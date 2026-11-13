import XCTest
@testable import Manhunt

final class SmoothClockTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    func testLeadGrowsWithTheRateAndStopsAtOneTick() {
        XCTAssertEqual(ClockLead.seconds(rate: 1, anchoredAt: t0, now: t0.addingTimeInterval(0.4)), 0.4, accuracy: 1e-9)
        XCTAssertEqual(ClockLead.seconds(rate: 1, anchoredAt: t0, now: t0.addingTimeInterval(9)), 1.0, accuracy: 1e-9)
        XCTAssertEqual(ClockLead.seconds(rate: 5, anchoredAt: t0, now: t0.addingTimeInterval(9)), 5.0, accuracy: 1e-9)
        XCTAssertEqual(ClockLead.seconds(rate: 0, anchoredAt: t0, now: t0.addingTimeInterval(0.4)), 0)
        XCTAssertEqual(ClockLead.seconds(rate: 1, anchoredAt: t0, now: t0.addingTimeInterval(-3)), 0)
    }

    func testRateIsZeroUnlessTheMatchClockRuns() {
        XCTAssertEqual(ClockLead.rate(snapshot: nil, paused: false), 0)
        XCTAssertEqual(ClockLead.rate(snapshot: Fixtures.liveView(phase: .active), paused: false), 1)
        XCTAssertEqual(ClockLead.rate(snapshot: Fixtures.liveView(phase: .active), paused: true), 0)
        XCTAssertEqual(ClockLead.rate(snapshot: Fixtures.liveView(phase: .lobby), paused: false), 0)
        XCTAssertEqual(ClockLead.rate(snapshot: Fixtures.liveView(phase: .ended), paused: false), 0)
        var held = Fixtures.liveView(phase: .headStart)
        held.spawnLock = SpawnLockDTO(outside: false, zones: [], holding: true)
        XCTAssertEqual(ClockLead.rate(snapshot: held, paused: false), 0)
        var demo = Fixtures.liveView(phase: .active)
        demo.demo = DemoDTO(speed: 5, lobbyHold: false, seekerLock: "spawn_zone",
                            controlsEnabled: true, virtualLocation: nil, bots: [])
        XCTAssertEqual(ClockLead.rate(snapshot: demo, paused: false), 5)
    }

    func testAnchorMovesOnlyWhenTheServerClockMoves() {
        let tick = Fixtures.liveView(elapsed: 10)
        let later = t0.addingTimeInterval(0.6)
        XCTAssertEqual(ClockLead.anchor(previous: nil, previousAnchor: nil, next: tick, now: t0), t0)
        // A demo action reply carries the same game second and must not rewind the countdown.
        XCTAssertEqual(ClockLead.anchor(previous: tick, previousAnchor: t0, next: tick, now: later), t0)
        XCTAssertEqual(ClockLead.anchor(previous: tick, previousAnchor: t0,
                                        next: Fixtures.liveView(elapsed: 11), now: later), later)
        XCTAssertEqual(ClockLead.anchor(previous: tick, previousAnchor: t0,
                                        next: Fixtures.liveView(phase: .paused, elapsed: 10), now: later), later)
    }

    func testPhaseClockCountsDownBetweenSnapshots() {
        let view = Fixtures.liveView(
            elapsed: 100, timeLimitRemaining: 900, nextReveal: 12,
            zone: ZoneTimerDTO(radiusM: 310, nextRadiusM: 259, shrinksInS: 42, intervalS: 60)
        )
        let us = Locale(identifier: "en_US")
        XCTAssertEqual(PhaseClock(snapshot: view, paused: false, locale: us).primaryClock, "15:00")
        let half = PhaseClock(snapshot: view, paused: false, locale: us, leadS: 0.5)
        XCTAssertEqual(half.primaryClock, "15:00")
        XCTAssertEqual(half.primaryProgress, 1 - 899.5 / 1800, accuracy: 1e-9)
        XCTAssertEqual(half.pingProgress, 1 - 11.5 / 60, accuracy: 1e-9)
        let full = PhaseClock(snapshot: view, paused: false, locale: us, leadS: 1.0)
        XCTAssertEqual(full.primaryClock, "14:59")
        XCTAssertEqual(full.pingClock, "0:11")
        XCTAssertEqual(full.zoneLine, "Zone 0.19 mi → 850 ft in 0:41")
        XCTAssertGreaterThan(full.primaryProgress, half.primaryProgress)
    }

    @MainActor
    func testApplyKeepsTheAnchorForAnOutOfCycleView() {
        let store = AppStore.makePreview()
        store.apply(Fixtures.liveView(elapsed: 10), now: t0)
        store.apply(Fixtures.liveView(elapsed: 10), now: t0.addingTimeInterval(0.6))
        XCTAssertEqual(store.match?.clockAnchorAt, t0)
        store.apply(Fixtures.liveView(elapsed: 11), now: t0.addingTimeInterval(1.0))
        XCTAssertEqual(store.match?.clockAnchorAt, t0.addingTimeInterval(1.0))
    }
}
