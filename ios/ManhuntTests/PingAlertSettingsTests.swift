import XCTest
@testable import Manhunt

final class PingAlertSettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "manhunt.tests.pingAlert.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testPingAlertTogglesDefaultOff() {
        // Quiet parks: chime and torch stay off until the player opts in.
        XCTAssertFalse(AppSettings.pingSoundEnabled(defaults: defaults))
        XCTAssertFalse(AppSettings.pingFlashlightEnabled(defaults: defaults))
    }

    func testPingAlertTogglesPersist() {
        AppSettings.setPingSoundEnabled(true, defaults: defaults)
        AppSettings.setPingFlashlightEnabled(true, defaults: defaults)
        XCTAssertTrue(AppSettings.pingSoundEnabled(defaults: defaults))
        XCTAssertTrue(AppSettings.pingFlashlightEnabled(defaults: defaults))

        AppSettings.setPingSoundEnabled(false, defaults: defaults)
        AppSettings.setPingFlashlightEnabled(false, defaults: defaults)
        XCTAssertFalse(AppSettings.pingSoundEnabled(defaults: defaults))
        XCTAssertFalse(AppSettings.pingFlashlightEnabled(defaults: defaults))
    }

    @MainActor
    func testPingDoesNotPlaySoundOrFlashTorchWhenTogglesOff() {
        let torch = RecordingTorch()
        let sound = RecordingPingSound()
        let store = AppStore(service: FakeGameService(), defaults: defaults, torch: torch, pingSound: sound)
        store.apply(Fixtures.liveView(elapsed: 59, nextReveal: 1, role: .seeker))
        store.apply(Fixtures.liveView(elapsed: 60, nextReveal: 60, role: .seeker))
        XCTAssertNotNil(store.pingPulse)
        XCTAssertEqual(sound.playCount, 0)
        XCTAssertTrue(torch.calls.isEmpty)
    }

    @MainActor
    func testPingPlaysSoundWhenEnabled() {
        AppSettings.setPingSoundEnabled(true, defaults: defaults)
        let torch = RecordingTorch()
        let sound = RecordingPingSound()
        let store = AppStore(service: FakeGameService(), defaults: defaults, torch: torch, pingSound: sound)
        XCTAssertTrue(store.pingSoundEnabled)
        store.apply(Fixtures.liveView(elapsed: 59, nextReveal: 1, role: .hider))
        store.apply(Fixtures.liveView(elapsed: 60, nextReveal: 60, role: .hider))
        XCTAssertEqual(sound.playCount, 1)
        XCTAssertTrue(torch.calls.isEmpty)
    }

    @MainActor
    func testPingFlashesTorchWhenEnabledAndLeavesManualOff() async {
        AppSettings.setPingFlashlightEnabled(true, defaults: defaults)
        let torch = RecordingTorch()
        let sound = RecordingPingSound()
        let store = AppStore(service: FakeGameService(), defaults: defaults, torch: torch, pingSound: sound)
        store.pingTorchFlashSeconds = 0.05
        XCTAssertTrue(store.pingFlashlightEnabled)
        store.apply(Fixtures.liveView(elapsed: 59, nextReveal: 1, role: .seeker))
        store.apply(Fixtures.liveView(elapsed: 60, nextReveal: 60, role: .seeker))
        XCTAssertEqual(sound.playCount, 0)
        XCTAssertEqual(torch.calls.first, true)
        let deadline = Date().addingTimeInterval(1)
        while store.flashlightOn && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(store.flashlightOn)
        XCTAssertEqual(torch.calls, [true, false])
    }

    @MainActor
    func testPingTorchFlashDoesNotTurnOffManualFlashlight() async {
        AppSettings.setPingFlashlightEnabled(true, defaults: defaults)
        let torch = RecordingTorch()
        let sound = RecordingPingSound()
        let store = AppStore(service: FakeGameService(), defaults: defaults, torch: torch, pingSound: sound)
        store.pingTorchFlashSeconds = 0.05
        store.toggleFlashlight()
        XCTAssertTrue(store.flashlightOn)
        let callsBeforePing = torch.calls
        store.apply(Fixtures.liveView(elapsed: 59, nextReveal: 1, role: .seeker))
        store.apply(Fixtures.liveView(elapsed: 60, nextReveal: 60, role: .seeker))
        try? await Task.sleep(for: .milliseconds(120))
        XCTAssertTrue(store.flashlightOn)
        XCTAssertEqual(torch.calls, callsBeforePing)
    }

    @MainActor
    func testManualFlashlightStillTogglesWithPingFlashlightPreferenceOn() {
        AppSettings.setPingFlashlightEnabled(true, defaults: defaults)
        let torch = RecordingTorch()
        let store = AppStore(
            service: FakeGameService(),
            defaults: defaults,
            torch: torch,
            pingSound: RecordingPingSound()
        )
        store.toggleFlashlight()
        XCTAssertTrue(store.flashlightOn)
        store.toggleFlashlight()
        XCTAssertFalse(store.flashlightOn)
        XCTAssertEqual(torch.calls, [true, false])
    }

    @MainActor
    func testStoreTogglesPersistThroughAppSettings() {
        let store = AppStore(
            service: FakeGameService(),
            defaults: defaults,
            torch: RecordingTorch(),
            pingSound: RecordingPingSound()
        )
        XCTAssertFalse(store.pingSoundEnabled)
        XCTAssertFalse(store.pingFlashlightEnabled)
        store.setPingSoundEnabled(true)
        store.setPingFlashlightEnabled(true)
        XCTAssertTrue(store.pingSoundEnabled)
        XCTAssertTrue(store.pingFlashlightEnabled)
        XCTAssertTrue(AppSettings.pingSoundEnabled(defaults: defaults))
        XCTAssertTrue(AppSettings.pingFlashlightEnabled(defaults: defaults))
    }
}

private final class RecordingTorch: TorchControlling {
    var isAvailable: Bool = true
    var calls: [Bool] = []
    var errorToThrow: Error?

    func setOn(_ on: Bool) throws {
        if let errorToThrow { throw errorToThrow }
        calls.append(on)
    }
}

private final class RecordingPingSound: PingSoundPlaying {
    var playCount = 0
    func play() { playCount += 1 }
}
