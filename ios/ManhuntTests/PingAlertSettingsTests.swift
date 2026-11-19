import XCTest
@testable import Manhunt

final class PingAlertSettingsTests: XCTestCase {
    @MainActor
    func testPingDoesNotPlaySoundOrFlashTorch() {
        let defaults = UserDefaults(suiteName: "ping-gone-\(UUID().uuidString)")!
        // Legacy opt-in keys may still be in defaults; they must no longer drive alerts.
        defaults.set(true, forKey: "manhunt.pingSoundEnabled")
        defaults.set(true, forKey: "manhunt.pingFlashlightEnabled")
        let torch = RecordingTorch()
        let store = AppStore(
            service: FakeGameService(),
            defaults: defaults,
            torch: torch
        )
        store.apply(Fixtures.liveView(elapsed: 59, nextReveal: 1, role: .seeker))
        store.apply(Fixtures.liveView(elapsed: 60, nextReveal: 60, role: .seeker))
        XCTAssertNotNil(store.pingPulse)
        XCTAssertEqual(torch.onCount, 0)
    }
}

private final class RecordingTorch: TorchControlling {
    var isAvailable: Bool = true
    var calls: [Bool] = []
    var errorToThrow: Error?
    var onCount: Int { calls.filter { $0 }.count }

    func setOn(_ on: Bool) throws {
        if let errorToThrow { throw errorToThrow }
        calls.append(on)
    }
}