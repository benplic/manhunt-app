import XCTest
@testable import Manhunt

/// Scriptable stand-in for `NWPathMonitor`.
private final class FakePathObserver: NetworkPathObserving {
    var onChange: ((NetworkPathState) -> Void)?
    private(set) var startCount = 0
    private(set) var cancelCount = 0

    func start() { startCount += 1 }
    func cancel() { cancelCount += 1 }
    func emit(_ state: NetworkPathState) { onChange?(state) }
}

private let wifi = NetworkPathState(isSatisfied: true, interface: "wifi")
private let cellular = NetworkPathState(isSatisfied: true, interface: "cellular")
private let offline = NetworkPathState(isSatisfied: false, interface: nil)

final class GameSocketHealthTests: XCTestCase {
    /// Nothing listens on port 9, so connect attempts fail at once and the run loop retries.
    private let unreachable = URL(string: "ws://127.0.0.1:9/v1/games/test/ws")!

    private func makeSocket(_ observer: FakePathObserver) -> GameSocket {
        let socket = GameSocket(pathObserver: observer)
        socket.triggerDebounce = 0.02
        return socket
    }

    private func settle(_ seconds: TimeInterval = 0.25) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// Polls instead of sleeping a fixed time: a refused connect takes longer on a loaded CI runner.
    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    // MARK: hello

    func testHelloCarriesTheClientBlockAndKeepsLastSeq() {
        let socket = GameSocket(pathObserver: FakePathObserver())
        socket.clientInfo = ["platform": "ios", "app_version": "1.2 (3)", "os_version": "18.4"]
        socket.lastSeq = 7

        let hello = socket.helloFrame(token: "tok")

        XCTAssertEqual(hello["type"] as? String, "hello")
        let data = hello["data"] as? [String: Any]
        XCTAssertEqual(data?["token"] as? String, "tok")
        XCTAssertEqual(data?["last_seq"] as? Int, 7)
        XCTAssertEqual(data?["client"] as? [String: String], socket.clientInfo)
    }

    func testDefaultClientInfoNamesThePlatform() {
        let info = GameSocket.defaultClientInfo()
        XCTAssertEqual(info["platform"], "ios")
        XCTAssertFalse(info["app_version"]?.isEmpty ?? true)
        XCTAssertFalse(info["os_version"]?.isEmpty ?? true)
    }

    // MARK: resend after welcome

    func testWelcomeResendsTheLatestFixAsNormal() throws {
        let socket = GameSocket(pathObserver: FakePathObserver())
        var frames: [[String: Any]] = []
        socket.frameSink = { frames.append($0) }

        socket.sendLocation(lat: 1, lon: 2, accuracyM: 5, flag: "reset")
        socket.sendLocation(lat: 3, lon: 4, accuracyM: 6, flag: "final", battery: 0.5)
        frames.removeAll()

        socket.handle(Data(#"{"type":"welcome","data":{}}"#.utf8))

        XCTAssertEqual(frames.count, 1)
        let data = try XCTUnwrap(frames.first?["data"] as? [String: Any])
        XCTAssertEqual(frames.first?["type"] as? String, "location")
        XCTAssertEqual(data["lat"] as? Double, 3)
        XCTAssertEqual(data["lon"] as? Double, 4)
        XCTAssertEqual(data["accuracy_m"] as? Double, 6)
        // A replayed one-off flag would repeat its action.
        XCTAssertEqual(data["flag"] as? String, "normal")
    }

    func testWelcomeSendsNothingWhenThereIsNoFixYet() {
        let socket = GameSocket(pathObserver: FakePathObserver())
        var frames: [[String: Any]] = []
        socket.frameSink = { frames.append($0) }

        socket.handle(Data(#"{"type":"welcome","data":{}}"#.utf8))

        XCTAssertTrue(frames.isEmpty)
    }

    func testAFixOlderThanTheLimitIsNotResent() {
        let socket = GameSocket(pathObserver: FakePathObserver())
        socket.resendMaxAge = -1
        var frames: [[String: Any]] = []
        socket.frameSink = { frames.append($0) }
        socket.sendLocation(lat: 1, lon: 2, accuracyM: 5)
        frames.removeAll()

        socket.handle(Data(#"{"type":"welcome","data":{}}"#.utf8))

        XCTAssertTrue(frames.isEmpty)
    }

    // MARK: health

    func testHealthTracksWelcomeAndTheLastMessage() {
        let socket = GameSocket(pathObserver: FakePathObserver())
        XCTAssertEqual(socket.health().lastMessageAt, nil)
        XCTAssertFalse(socket.health().connected)

        socket.handle(Data(#"{"type":"welcome","data":{}}"#.utf8))
        let first = socket.health()
        XCTAssertTrue(first.connected)
        XCTAssertNotNil(first.lastMessageAt)

        socket.handle(Data(#"{"type":"pong","data":{}}"#.utf8))
        XCTAssertGreaterThanOrEqual(socket.health().lastMessageAt ?? .distantPast, first.lastMessageAt ?? .distantFuture)
    }

    func testHealthReportsNoNetworkFromThePathObserver() async {
        let observer = FakePathObserver()
        let socket = makeSocket(observer)
        socket.connect(url: unreachable, token: "tok")
        observer.emit(wifi)
        observer.emit(offline)

        XCTAssertFalse(socket.health().networkAvailable)
        socket.disconnect()
    }

    func testFailuresAccumulateWhileFlappingAndResetAfterAStableConnection() async {
        let socket = makeSocket(FakePathObserver())
        socket.stableAfter = 0.05
        socket.connect(url: unreachable, token: "tok")
        await waitUntil { socket.health().failureStreak >= 1 }
        XCTAssertGreaterThanOrEqual(socket.health().failureStreak, 1)

        socket.handle(Data(#"{"type":"welcome","data":{}}"#.utf8))
        await waitUntil { socket.health().failureStreak == 0 }

        XCTAssertEqual(socket.health().failureStreak, 0)
        socket.disconnect()
    }

    // MARK: half-open watchdog

    func testASilentWelcomedSocketIsDroppedAndReconnected() async {
        let observer = FakePathObserver()
        let socket = makeSocket(observer)
        socket.silenceLimit = 20
        socket.connect(url: unreachable, token: "tok")
        socket.handle(Data(#"{"type":"welcome","data":{}}"#.utf8))

        let forced = socket.reconnectIfSilent(now: Date().addingTimeInterval(30))
        await settle()

        XCTAssertTrue(forced)
        XCTAssertEqual(socket.triggeredReconnects, 1)
        XCTAssertFalse(socket.health().connected)
        socket.disconnect()
    }

    func testASocketThatJustHeardFromTheServerIsLeftAlone() {
        let socket = makeSocket(FakePathObserver())
        socket.handle(Data(#"{"type":"welcome","data":{}}"#.utf8))

        XCTAssertFalse(socket.reconnectIfSilent(now: Date().addingTimeInterval(5)))
        XCTAssertEqual(socket.triggeredReconnects, 0)
    }

    func testASocketThatNeverWelcomedIsNotTreatedAsSilent() {
        let socket = makeSocket(FakePathObserver())

        XCTAssertFalse(socket.reconnectIfSilent(now: Date().addingTimeInterval(300)))
    }

    // MARK: path triggers

    func testTheFirstPathReportIsABaselineNotATrigger() async {
        let observer = FakePathObserver()
        let socket = makeSocket(observer)
        socket.connect(url: unreachable, token: "tok")

        observer.emit(wifi)
        await settle()

        XCTAssertEqual(socket.triggeredReconnects, 0)
        XCTAssertEqual(observer.startCount, 1)
        socket.disconnect()
    }

    func testSwitchingFromWifiToCellularReconnectsAtOnce() async {
        let observer = FakePathObserver()
        let socket = makeSocket(observer)
        socket.connect(url: unreachable, token: "tok")
        observer.emit(wifi)

        observer.emit(cellular)
        await settle()

        XCTAssertEqual(socket.triggeredReconnects, 1)
        socket.disconnect()
    }

    func testTheNetworkReturningAfterAirplaneModeReconnects() async {
        let observer = FakePathObserver()
        let socket = makeSocket(observer)
        socket.connect(url: unreachable, token: "tok")
        observer.emit(wifi)
        observer.emit(offline)
        await settle()
        XCTAssertEqual(socket.triggeredReconnects, 0, "losing the network is not a trigger")

        observer.emit(wifi)
        await settle()

        XCTAssertEqual(socket.triggeredReconnects, 1)
        socket.disconnect()
    }

    func testARepeatOfTheSamePathDoesNothing() async {
        let observer = FakePathObserver()
        let socket = makeSocket(observer)
        socket.connect(url: unreachable, token: "tok")
        observer.emit(wifi)

        observer.emit(wifi)
        await settle()

        XCTAssertEqual(socket.triggeredReconnects, 0)
        socket.disconnect()
    }

    func testAStormOfPathChangesCollapsesIntoOneReconnect() async {
        let observer = FakePathObserver()
        let socket = makeSocket(observer)
        socket.triggerDebounce = 0.1
        socket.connect(url: unreachable, token: "tok")
        observer.emit(wifi)

        for _ in 0..<5 {
            observer.emit(cellular)
            observer.emit(wifi)
        }
        await settle(0.4)

        XCTAssertEqual(socket.triggeredReconnects, 1)
        socket.disconnect()
    }

    func testNoTriggerReconnectsAfterAHostRemove() async {
        let observer = FakePathObserver()
        let socket = makeSocket(observer)
        var removed = 0
        socket.onRemoved = { removed += 1 }
        socket.connect(url: unreachable, token: "tok")
        observer.emit(wifi)

        socket.handle(Data(#"{"type":"removed","data":{"reason":"host_removed"}}"#.utf8))
        observer.emit(cellular)
        socket.requestReconnect()
        await settle()

        XCTAssertTrue(socket.isStopped)
        XCTAssertEqual(removed, 1)
        XCTAssertEqual(socket.triggeredReconnects, 0)
    }

    func testDisconnectStopsPathObservation() {
        let observer = FakePathObserver()
        let socket = makeSocket(observer)
        socket.connect(url: unreachable, token: "tok")

        socket.disconnect()

        XCTAssertEqual(observer.cancelCount, 1)
        XCTAssertTrue(socket.isStopped)
    }
}
