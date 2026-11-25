import Foundation

/// WebSocket for `/v1/games/{id}/ws`. Hello must go first. Ping every 15 s.
///
/// Reconnect backoff is 1, 2, 4, 8, then 15 s plus jitter. The first connect waits up to
/// 60 s so a waking host is survivable. Three things shorten that wait:
/// - A network path change (Wi-Fi to cellular, or the network returning) reconnects at once
///   and restarts the backoff at 1 s.
/// - The backoff only restarts after a connection stayed up for `stableAfter`, so a socket
///   that flaps keeps backing off instead of hammering the server.
/// - After `welcome` the newest known location fix is sent immediately, so the server does
///   not wait for the next GPS callback to know where this phone is.
///
/// TODO: consider a 10 s backoff cap after measuring (see the connection-health plan).
final class GameSocket: @unchecked Sendable {
    var onView: ((PlayerViewDTO) -> Void)?
    var onQR: ((String) -> Void)?
    var onEvent: ((LiveEventDTO) -> Void)?
    var onReconnect: ((Bool) -> Void)?
    var onSendFailure: ((String) -> Void)?
    /// Host kicked this phone. Stops reconnect; the store routes home.
    var onRemoved: (() -> Void)?
    var lastSeq: Int?
    /// True after disconnect or a host remove / 4403 close.
    private(set) var isStopped = false

    /// Sent in `hello` so the server log can group disconnects by platform and build.
    /// Coarse values only: no device identifiers.
    var clientInfo: [String: String] = GameSocket.defaultClientInfo()
    /// Tests shorten these so nothing sleeps for real seconds.
    var stableAfter: TimeInterval = 10
    var triggerDebounce: TimeInterval = 0.3
    /// A fix older than this is not re-sent after a reconnect. TODO: tune with playtest data.
    var resendMaxAge: TimeInterval = 60
    /// The server sends a view every second and answers every ping, so a welcomed socket
    /// silent this long is half-open. Must exceed the 15 s ping interval.
    var silenceLimit: TimeInterval = 20
    /// When set, frames go here instead of the socket. Tests only.
    var frameSink: (([String: Any]) -> Void)?
    /// How many times a network-path trigger forced an immediate reconnect. Tests only.
    private(set) var triggeredReconnects = 0

    private struct Fix {
        var lat: Double
        var lon: Double
        var accuracyM: Double
        var battery: Float?
        var at: Date
    }

    // Guards the fields below. Network callbacks, the run loop, and UI calls all touch them.
    private let lock = NSLock()
    private var task: URLSessionWebSocketTask?
    private var pingTask: Task<Void, Never>?
    private var runTask: Task<Void, Never>?
    private var stableTask: Task<Void, Never>?
    private var triggerTask: Task<Void, Never>?
    private var connection: (url: URL, token: String)?
    private var generation = 0
    private var backoff: TimeInterval = 1
    private var failureStreak = 0
    private var welcomed = false
    private var lastMessageAt: Date?
    /// When hello went out, until `welcome` arrives. Catches a hello lost on a dead path.
    private var openedAt: Date?
    private var lastFix: Fix?
    private var lastPath: NetworkPathState?
    private var gameID: UUID?
    private let session: URLSession
    private let pathObserver: NetworkPathObserving

    init(session: URLSession = .shared, pathObserver: NetworkPathObserving = SystemPathObserver()) {
        self.session = session
        self.pathObserver = pathObserver
    }

    static func defaultClientInfo() -> [String: String] {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return [
            "platform": "ios",
            "app_version": build.map { "\(version) (\($0))" } ?? version,
            "os_version": "\(os.majorVersion).\(os.minorVersion)",
        ]
    }

    func beginGame(_ gameID: UUID) {
        guard self.gameID != gameID else { return }
        self.gameID = gameID
        lastSeq = nil
    }

    func connect(url: URL, token: String) {
        // The store connects once from the lobby and again when the hunt goes live. Close the
        // previous socket first: cancelling only the run task leaves the old URLSession
        // socket open, and the server would keep a zombie handler until TCP gives up.
        let previous = locked { () -> (URLSessionWebSocketTask?, Task<Void, Never>?, Task<Void, Never>?) in
            let old = (task, pingTask, stableTask)
            task = nil
            pingTask = nil
            stableTask = nil
            openedAt = nil
            return old
        }
        previous.1?.cancel()
        previous.2?.cancel()
        previous.0?.cancel(with: .goingAway, reason: nil)
        isStopped = false
        locked {
            connection = (url, token)
            backoff = 1
            failureStreak = 0
            welcomed = false
            lastMessageAt = nil
            lastPath = nil
        }
        pathObserver.onChange = { [weak self] state in self?.handlePath(state) }
        pathObserver.start()
        launchRun(first: true)
    }

    func sendLocation(
        lat: Double,
        lon: Double,
        accuracyM: Double,
        flag: String = "normal",
        battery: Float? = nil
    ) {
        let now = Date()
        // Kept even while offline: the newest fix is what a reconnect re-sends.
        locked { lastFix = Fix(lat: lat, lon: lon, accuracyM: accuracyM, battery: battery, at: now) }
        sendJSON(locationFrame(lat: lat, lon: lon, accuracyM: accuracyM, flag: flag, battery: battery, at: now))
    }

    func disconnect() {
        isStopped = true
        pathObserver.cancel()
        let tasks: [Task<Void, Never>?] = locked {
            generation += 1
            welcomed = false
            lastPath = nil
            lastFix = nil
            let all = [pingTask, runTask, stableTask, triggerTask]
            pingTask = nil
            runTask = nil
            stableTask = nil
            triggerTask = nil
            return all
        }
        tasks.forEach { $0?.cancel() }
        let current = locked { () -> URLSessionWebSocketTask? in
            let value = task
            task = nil
            return value
        }
        current?.cancel(with: .goingAway, reason: nil)
    }

    /// Applies a server close code. 4403 means not a member — do not reconnect.
    func noteServerClosed(code: Int) {
        if code == 4403 {
            markRemoved()
        }
    }

    /// Snapshot for the four-bar meter. Cheap enough to read every second.
    func health() -> SocketHealth {
        locked {
            SocketHealth(
                connected: welcomed,
                failureStreak: failureStreak,
                lastMessageAt: lastMessageAt,
                networkAvailable: lastPath?.isSatisfied ?? true
            )
        }
    }

    /// Half-open watchdog: drops and reconnects a welcomed socket that has gone silent.
    /// Called from the ping loop and when the app returns to the foreground.
    /// Returns true when it forced a reconnect.
    @discardableResult
    func reconnectIfSilent(now: Date = Date()) -> Bool {
        let silent = locked { () -> Bool in
            if welcomed, let last = lastMessageAt {
                return now.timeIntervalSince(last) > silenceLimit
            }
            if !welcomed, let opened = openedAt {
                return now.timeIntervalSince(opened) > silenceLimit
            }
            return false
        }
        guard silent, !isStopped else { return false }
        locked { failureStreak += 1 }
        reconnectNow()
        return true
    }

    // MARK: Network path and reconnect triggers

    /// First report is the baseline; later ones that regain or switch the network reconnect.
    func handlePath(_ state: NetworkPathState) {
        let previous = locked { () -> NetworkPathState? in
            let old = lastPath
            lastPath = state
            return old
        }
        guard !isStopped, let previous, state.isSatisfied else { return }
        let regained = !previous.isSatisfied
        let switchedInterface = previous.interface != state.interface
        if regained || switchedInterface {
            requestReconnect()
        }
    }

    /// Several triggers at once (a path flap, a close) collapse into one reconnect.
    func requestReconnect() {
        guard !isStopped else { return }
        let debounce = triggerDebounce
        locked {
            guard triggerTask == nil else { return }
            triggerTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(debounce * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.locked { self?.triggerTask = nil }
                self?.reconnectNow()
            }
        }
    }

    private func reconnectNow() {
        // A host remove or membership close sets `isStopped`; no trigger may undo that.
        guard !isStopped, locked({ self.connection != nil }) else { return }
        let old = locked { () -> (URLSessionWebSocketTask?, Task<Void, Never>?, Task<Void, Never>?) in
            backoff = 1
            welcomed = false
            openedAt = nil
            triggeredReconnects += 1
            let current = (task, pingTask, stableTask)
            task = nil
            pingTask = nil
            stableTask = nil
            return current
        }
        old.1?.cancel()
        old.2?.cancel()
        old.0?.cancel(with: .goingAway, reason: nil)
        launchRun(first: false)
    }

    // MARK: Run loop

    private func launchRun(first: Bool) {
        let (gen, previous) = locked { () -> (Int, Task<Void, Never>?) in
            generation += 1
            let old = runTask
            runTask = nil
            return (generation, old)
        }
        previous?.cancel()
        let newTask: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            await self.run(generation: gen, first: first)
        }
        locked { runTask = newTask }
    }

    private func isCurrent(_ gen: Int) -> Bool {
        locked { generation == gen } && !isStopped && !Task.isCancelled
    }

    private func run(generation gen: Int, first initial: Bool) async {
        var first = initial
        while isCurrent(gen) {
            guard let target = locked({ self.connection }) else { return }
            onReconnect?(!first)
            let ws = await open(url: target.url, token: target.token, timeout: first ? 60 : 15, generation: gen)
            first = false
            guard isCurrent(gen) else { return }
            if let ws {
                await listen(ws, generation: gen)
            }
            guard isCurrent(gen) else { return }
            noteDrop()
            let delay = takeBackoff()
            let jitter = Double.random(in: 0...0.4)
            try? await Task.sleep(nanoseconds: UInt64((delay + jitter) * 1_000_000_000))
        }
    }

    private func takeBackoff() -> TimeInterval {
        locked {
            let delay = backoff
            backoff = delay >= 15 ? 15 : min(delay * 2, 15)
            return delay
        }
    }

    private func noteDrop() {
        let stable = locked { () -> Task<Void, Never>? in
            failureStreak += 1
            welcomed = false
            openedAt = nil
            let old = stableTask
            stableTask = nil
            return old
        }
        stable?.cancel()
    }

    /// Opens the socket and sends hello. Returns the live task, or nil when it failed.
    private func open(url: URL, token: String, timeout: TimeInterval, generation gen: Int) async -> URLSessionWebSocketTask? {
        let ws = session.webSocketTask(with: url)
        guard locked({ () -> Bool in
            guard generation == gen else { return false }
            task = ws
            return true
        }) else { return nil }
        ws.resume()
        let hello = helloFrame(token: token)
        guard let data = try? JSONSerialization.data(withJSONObject: hello),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        do {
            try await withTimeout(timeout) {
                try await ws.send(.string(text))
            }
            locked { openedAt = Date() }
            startPings()
            return ws
        } catch {
            ws.cancel(with: .goingAway, reason: nil)
            return nil
        }
    }

    /// First frame on every connection. `client` is optional for the server, so an old
    /// server that ignores it keeps working.
    func helloFrame(token: String) -> [String: Any] {
        var helloData: [String: Any] = ["token": token, "client": clientInfo]
        if let lastSeq {
            helloData["last_seq"] = lastSeq
        }
        return ["type": "hello", "data": helloData]
    }

    private func listen(_ ws: URLSessionWebSocketTask, generation gen: Int) async {
        while isCurrent(gen) {
            do {
                let message = try await ws.receive()
                let data: Data
                switch message {
                case let .data(value): data = value
                case let .string(value): data = Data(value.utf8)
                @unknown default: continue
                }
                handle(data)
            } catch {
                noteServerClosed(code: ws.closeCode.rawValue)
                break
            }
        }
        // Only the connection that is still current owns the ping task.
        if isCurrent(gen) {
            locked { pingTask }?.cancel()
        }
    }

    func handle(_ data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String
        else { return }
        locked { lastMessageAt = Date() }
        let payload = obj["data"]
        let payloadData = payload.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        switch type {
        case "view":
            if let payloadData, let view = try? JSONDecoder().decode(PlayerViewDTO.self, from: payloadData) {
                onView?(view)
            }
        case "qr_token":
            if let dict = payload as? [String: Any], let token = dict["token"] as? String {
                onQR?(token)
            }
        case "event":
            if let payloadData,
               let event = try? JSONDecoder().decode(LiveEventDTO.self, from: payloadData),
               lastSeq.map({ event.seq > $0 }) ?? true
            {
                lastSeq = event.seq
                onEvent?(event)
            }
        case "welcome":
            noteWelcome()
        case "removed":
            markRemoved()
        default:
            break
        }
    }

    private func noteWelcome() {
        let stable = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.stableAfter * 1_000_000_000))
            guard !Task.isCancelled else { return }
            // A connection that stayed up: the next drop starts the backoff over at 1 s.
            self.locked {
                self.failureStreak = 0
                self.backoff = 1
            }
        }
        let previous = locked { () -> Task<Void, Never>? in
            welcomed = true
            openedAt = nil
            let old = stableTask
            stableTask = stable
            return old
        }
        previous?.cancel()
        resendLatestFix()
    }

    private func resendLatestFix() {
        guard let fix = locked({ lastFix }), Date().timeIntervalSince(fix.at) <= resendMaxAge else {
            return
        }
        // Always "normal": a replayed `reset` or `final` flag would repeat a one-off action.
        sendJSON(locationFrame(lat: fix.lat, lon: fix.lon, accuracyM: fix.accuracyM, flag: "normal", battery: fix.battery, at: fix.at))
    }

    private func locationFrame(
        lat: Double,
        lon: Double,
        accuracyM: Double,
        flag: String,
        battery: Float?,
        at: Date
    ) -> [String: Any] {
        var data: [String: Any] = [
            "lat": lat,
            "lon": lon,
            "accuracy_m": accuracyM,
            "recorded_at": ISO8601DateFormatter().string(from: at),
            "flag": flag,
        ]
        if let battery {
            data["battery"] = battery
        }
        return ["type": "location", "data": data]
    }

    private func markRemoved() {
        guard !isStopped else { return }
        isStopped = true
        pathObserver.cancel()
        let tasks: [Task<Void, Never>?] = locked {
            generation += 1
            welcomed = false
            let all = [pingTask, runTask, stableTask, triggerTask]
            pingTask = nil
            runTask = nil
            stableTask = nil
            triggerTask = nil
            return all
        }
        tasks.forEach { $0?.cancel() }
        onRemoved?()
    }

    private func startPings() {
        let ping = Task { [weak self] in
            while !(self?.isStopped ?? true), !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled else { return }
                if self?.reconnectIfSilent() == true { return }
                self?.sendJSON(["type": "ping", "data": [:]])
            }
        }
        let previous = locked { () -> Task<Void, Never>? in
            let old = pingTask
            pingTask = ping
            return old
        }
        previous?.cancel()
    }

    private func sendJSON(_ payload: [String: Any]) {
        if let frameSink {
            frameSink(payload)
            return
        }
        guard let socketTask = locked({ self.task }),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8)
        else { return }
        socketTask.send(.string(text)) { [weak self] error in
            if let error {
                self?.onSendFailure?(error.localizedDescription)
            }
        }
    }

    @discardableResult
    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private func withTimeout<T>(_ seconds: TimeInterval, _ work: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await work() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw ServiceError(code: .internal, message: "Timed out waiting for the hunt server.")
        }
        guard let result = try await group.next() else {
            throw ServiceError(code: .internal, message: "Timed out waiting for the hunt server.")
        }
        group.cancelAll()
        return result
    }
}
