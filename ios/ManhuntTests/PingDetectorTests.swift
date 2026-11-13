import XCTest
@testable import Manhunt

final class PingDetectorTests: XCTestCase {
    func testCountdownWrapIsAPing() {
        let before = Fixtures.liveView(elapsed: 59, nextReveal: 1)
        let after = Fixtures.liveView(elapsed: 60, nextReveal: 60)
        XCTAssertTrue(PingDetector.didPing(previous: before, next: after))
    }

    func testOrdinaryCountdownIsNotAPing() {
        let before = Fixtures.liveView(elapsed: 30, nextReveal: 30)
        let after = Fixtures.liveView(elapsed: 31, nextReveal: 29)
        XCTAssertFalse(PingDetector.didPing(previous: before, next: after))
    }

    func testTenTimesSpeedStillPingsWhenTheWrapHidesInsideOneSnapshot() {
        let before = Fixtures.liveView(elapsed: 56, nextReveal: 4)
        let after = Fixtures.liveView(elapsed: 66, nextReveal: 54)
        XCTAssertTrue(PingDetector.didPing(previous: before, next: after))
    }

    func testForcedRevealPingsOnTheTickThatFiresNotOnTheReply() {
        let before = Fixtures.liveView(elapsed: 20, nextReveal: 40)
        let reply = Fixtures.liveView(elapsed: 20, nextReveal: 0)
        XCTAssertFalse(PingDetector.didPing(previous: before, next: reply))
        let fired = Fixtures.liveView(elapsed: 21, nextReveal: 60)
        XCTAssertTrue(PingDetector.didPing(previous: reply, next: fired))
    }

    func testNoPingWithoutAHistoryATimerOrALiveClock() {
        let view = Fixtures.liveView(elapsed: 60, nextReveal: 60)
        XCTAssertFalse(PingDetector.didPing(previous: nil, next: view))
        let noTimer = Fixtures.liveView(elapsed: 61, nextReveal: nil)
        XCTAssertFalse(PingDetector.didPing(previous: view, next: noTimer))
        let paused = Fixtures.liveView(phase: .paused, elapsed: 60, nextReveal: 60)
        XCTAssertFalse(PingDetector.didPing(previous: Fixtures.liveView(elapsed: 60, nextReveal: 1), next: paused))
        let lobby = Fixtures.liveView(phase: .lobby, elapsed: 0, nextReveal: 60)
        XCTAssertFalse(PingDetector.didPing(previous: lobby, next: lobby))
    }

    @MainActor
    func testApplyRaisesAPulseForTheViewersRole() {
        let store = AppStore.makePreview()
        store.apply(Fixtures.liveView(elapsed: 59, nextReveal: 1, role: .hider))
        XCTAssertNil(store.pingPulse)
        store.apply(Fixtures.liveView(elapsed: 60, nextReveal: 60, role: .hider))
        XCTAssertEqual(store.pingPulse?.role, .hider)
    }
}
