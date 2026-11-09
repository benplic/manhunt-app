import Foundation

/// WebSocket for `/v1/games/{id}/ws`. Hello must go first. Ping every 15 s.
/// Reconnect backoff is 1, 2, 4, 8, then 15 s plus jitter. The first connect
/// waits up to 60 s so a waking host is survivable.
final class GameSocket: @unchecked Sendable {
    var onView: ((PlayerViewDTO) -> Void)?
    var onQR: ((String) -> Void)?
    var onEvent: ((BannerDTO) -> Void)?
    var onReconnect: ((Bool) -> Void)?
    var lastSeq: Int?

    private var task: URLSessionWebSocketTask?
    private var pingTask: Task<Void, Never>?
    private var runTask: Task<Void, Never>?
    private var stopped = false
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func connect(url: URL, token: String) {
        stopped = false
        runTask?.cancel()
        runTask = Task { [weak self] in
            await self?.run(url: url, token: token)
        }
    }

    func sendLocation(
        lat: Double,
        lon: Double,
        accuracyM: Double,
        flag: String = "normal",
        battery: Float? = nil
    ) {
        var data: [String: Any] = [
            "lat": lat,
            "lon": lon,
            "accuracy_m": accuracyM,
            "recorded_at": ISO8601DateFormatter().string(from: Date()),
            "flag": flag,
        ]
        if let battery {
            data["battery"] = battery
        }
        sendJSON(["type": "location", "data": data])
    }

    func disconnect() {
        stopped = true
        pingTask?.cancel()
        runTask?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func run(url: URL, token: String) async {
        var delay: TimeInterval = 1
        var first = true
        while !stopped, !Task.isCancelled {
            onReconnect?( !first )
            let ok = await open(url: url, token: token, timeout: first ? 60 : 15)
            first = false
            if stopped { return }
            if ok {
                delay = 1
                await listen()
            }
            if stopped { return }
            let jitter = Double.random(in: 0...0.4)
            try? await Task.sleep(nanoseconds: UInt64((delay + jitter) * 1_000_000_000))
            delay = delay >= 15 ? 15 : min(delay * 2, 15)
        }
    }

    private func open(url: URL, token: String, timeout: TimeInterval) async -> Bool {
        let ws = session.webSocketTask(with: url)
        task = ws
        ws.resume()
        var helloData: [String: Any] = ["token": token]
        if let lastSeq {
            helloData["last_seq"] = lastSeq
        }
        let hello: [String: Any] = ["type": "hello", "data": helloData]
        guard let data = try? JSONSerialization.data(withJSONObject: hello),
              let text = String(data: data, encoding: .utf8)
        else { return false }
        do {
            try await withTimeout(timeout) {
                try await ws.send(.string(text))
            }
            startPings()
            return true
        } catch {
            ws.cancel(with: .goingAway, reason: nil)
            return false
        }
    }

    private func listen() async {
        guard let task else { return }
        while !stopped, !Task.isCancelled {
            do {
                let message = try await task.receive()
                let data: Data
                switch message {
                case let .data(value): data = value
                case let .string(value): data = Data(value.utf8)
                @unknown default: continue
                }
                handle(data)
            } catch {
                break
            }
        }
        pingTask?.cancel()
    }

    private func handle(_ data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String
        else { return }
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
            if let dict = payload as? [String: Any] {
                let banner = BannerDTO(
                    bannerId: UUID(),
                    tone: dict["tone"] as? String ?? "info",
                    title: dict["type"] as? String ?? "event",
                    detail: dict["text"] as? String ?? "",
                    playerId: (dict["player_id"] as? String).flatMap(UUID.init)
                )
                if let seq = dict["seq"] as? Int { lastSeq = seq }
                onEvent?(banner)
            }
        default:
            break
        }
    }

    private func startPings() {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !(self?.stopped ?? true), !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                self?.sendJSON(["type": "ping", "data": [:]])
            }
        }
    }

    private func sendJSON(_ payload: [String: Any]) {
        guard let task,
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8)
        else { return }
        task.send(.string(text)) { _ in
            // TODO: surface send failures on the reconnecting banner.
        }
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
