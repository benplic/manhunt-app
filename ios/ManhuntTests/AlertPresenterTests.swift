import XCTest
@testable import Manhunt

/// The queue is pure and takes `now`, so none of these tests sleep.
final class AlertPresenterTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 10_000)

    private func alert(
        _ key: String,
        _ priority: AlertPriority,
        text: String? = nil,
        kind: LiveAlertKind = .update
    ) -> LiveAlert {
        LiveAlert(
            text: text ?? key,
            tone: "info",
            priority: priority,
            subjectKey: key,
            createdAt: t0,
            kind: kind
        )
    }

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    /// Drain the queue the way the UI does: wait out each alert's 4 s, then advance.
    private func drain(_ queue: inout AlertQueue, from start: TimeInterval) -> [String] {
        var order: [String] = []
        var now = start
        while let showing = queue.current {
            order.append(showing.alert.subjectKey)
            now += AlertQueue.showDuration
            queue.advance(now: at(now))
        }
        return order
    }

    func testTheFirstAlertShowsImmediatelyForFourSeconds() {
        var queue = AlertQueue()
        queue.enqueue(alert("a", .ping), now: at(0))
        XCTAssertEqual(queue.current?.alert.subjectKey, "a")
        XCTAssertEqual(queue.nextWakeAt, at(4))
    }

    func testASameOrLowerPriorityAlertWaitsThenShowsAfterFourSeconds() {
        var queue = AlertQueue()
        queue.enqueue(alert("a", .ping), now: at(0))
        queue.enqueue(alert("b", .ping), now: at(1))
        XCTAssertEqual(queue.queued.map(\.subjectKey), ["b"])

        queue.advance(now: at(3.99))
        XCTAssertEqual(queue.current?.alert.subjectKey, "a")
        queue.advance(now: at(4))
        XCTAssertEqual(queue.current?.alert.subjectKey, "b")
        XCTAssertEqual(queue.current?.shownAt, at(4))
        XCTAssertTrue(queue.queued.isEmpty)
    }

    func testALowerPriorityAlertIsQueuedNotSkippedBehindAHigherOne() {
        var queue = AlertQueue()
        queue.enqueue(alert("tag", .tagOrBounds), now: at(0))
        queue.enqueue(alert("ping", .ping), now: at(0.5))
        queue.enqueue(alert("dark", .safety), now: at(0.6))

        XCTAssertEqual(queue.current?.alert.subjectKey, "tag")
        XCTAssertEqual(queue.queued.map(\.subjectKey), ["dark", "ping"])
        XCTAssertEqual(drain(&queue, from: 0), ["tag", "dark", "ping"])
    }

    func testALowerPriorityAlertSurvivesAStreamOfHigherPriorityOnes() {
        var queue = AlertQueue()
        queue.enqueue(alert("pill", .update), now: at(0))
        queue.enqueue(alert("tag-1", .tagOrBounds), now: at(0.1))
        queue.enqueue(alert("tag-2", .tagOrBounds), now: at(0.2))
        queue.enqueue(alert("tag-3", .tagOrBounds), now: at(0.3))

        XCTAssertEqual(drain(&queue, from: 0.3), ["tag-1", "tag-2", "tag-3", "pill"])
    }

    func testAHigherPriorityAlertTakesTheSlotAndTheInterruptedOneResumesWithFullTime() {
        var queue = AlertQueue()
        queue.enqueue(alert("ping", .ping), now: at(0))
        queue.enqueue(alert("tag", .tagOrBounds), now: at(1.5))

        XCTAssertEqual(queue.current?.alert.subjectKey, "tag")
        XCTAssertEqual(queue.queued.map(\.subjectKey), ["ping"])

        queue.advance(now: at(5.5))
        XCTAssertEqual(queue.current?.alert.subjectKey, "ping")
        XCTAssertEqual(queue.current?.shownAt, at(5.5))
        XCTAssertEqual(queue.nextWakeAt, at(9.5))
    }

    func testTheInterruptedAlertGoesToTheFrontOfItsOwnTier() {
        var queue = AlertQueue()
        queue.enqueue(alert("ping-a", .ping), now: at(0))
        queue.enqueue(alert("ping-b", .ping), now: at(0.1))
        queue.enqueue(alert("pill", .update), now: at(0.2))
        queue.enqueue(alert("tag", .tagOrBounds), now: at(0.3))

        XCTAssertEqual(queue.queued.map(\.subjectKey), ["ping-a", "ping-b", "pill"])
    }

    func testAnEqualPriorityAlertDoesNotInterrupt() {
        var queue = AlertQueue()
        queue.enqueue(alert("a", .tagOrBounds), now: at(0))
        queue.enqueue(alert("b", .tagOrBounds), now: at(0.1))
        XCTAssertEqual(queue.current?.alert.subjectKey, "a")
    }

    func testAResumedAlertGetsANewShowIDSoVoiceOverAnnouncesItAgain() {
        var queue = AlertQueue()
        queue.enqueue(alert("ping", .ping), now: at(0))
        let first = queue.current?.showID
        queue.enqueue(alert("tag", .tagOrBounds), now: at(0.1))
        queue.advance(now: at(4.1))
        XCTAssertEqual(queue.current?.alert.subjectKey, "ping")
        XCTAssertNotEqual(queue.current?.showID, first)
    }

    func testFirstInFirstOutWithinOnePriority() {
        var queue = AlertQueue()
        for key in ["a", "b", "c", "d"] {
            queue.enqueue(alert(key, .safety), now: at(0))
        }
        XCTAssertEqual(drain(&queue, from: 0), ["a", "b", "c", "d"])
    }

    func testDuplicatesCoalesceWithoutRestartingTheVisibleTimer() {
        var queue = AlertQueue()
        queue.enqueue(alert("dark:riley", .safety, text: "Riley went dark."), now: at(0))
        queue.enqueue(alert("dark:riley", .safety, text: "Riley went dark again."), now: at(2))
        XCTAssertTrue(queue.queued.isEmpty)
        XCTAssertEqual(queue.current?.shownAt, at(0))
        XCTAssertEqual(queue.current?.alert.text, "Riley went dark again.")
    }

    func testDuplicatesInsideTheQueueCollapseToOneEntry() {
        var queue = AlertQueue()
        queue.enqueue(alert("first", .tagOrBounds), now: at(0))
        for index in 0..<53 {
            queue.enqueue(alert("dark:riley", .safety, text: "dark \(index)"), now: at(Double(index) / 100))
        }
        XCTAssertEqual(queue.queued.map(\.subjectKey), ["dark:riley"])
        XCTAssertEqual(queue.queued.first?.text, "dark 52")
    }

    // Product rule (2026-11-25): never drop an alert the player has not seen.
    func testThereIsNoCapEveryQueuedAlertIsShownEventually() {
        var queue = AlertQueue()
        queue.enqueue(alert("showing", .tagOrBounds), now: at(0))
        for index in 0..<40 {
            queue.enqueue(alert("pill-\(index)", .update), now: at(1 + Double(index)))
        }
        queue.enqueue(alert("dark", .safety), now: at(100))

        XCTAssertEqual(queue.queued.count, 41)
        let order = drain(&queue, from: 100)
        XCTAssertEqual(order.count, 42)
        XCTAssertEqual(Array(order.prefix(2)), ["showing", "dark"], "higher priority jumps the queue")
        XCTAssertEqual(order.last, "pill-39")
    }

    func testAnAlertThatWaitsForTenMinutesIsStillShown() {
        var queue = AlertQueue()
        queue.enqueue(alert("long", .tagOrBounds), now: at(0))
        queue.enqueue(alert("old", .ping), now: at(1))
        queue.advance(now: at(600))
        XCTAssertEqual(queue.current?.alert.subjectKey, "old")
    }

    func testAHigherPriorityAlertJumpsAheadOfEverythingLowerInTheQueue() {
        var queue = AlertQueue()
        queue.enqueue(alert("showing", .safety), now: at(0))
        queue.enqueue(alert("pill", .update), now: at(1))
        queue.enqueue(alert("ping", .ping), now: at(2))
        queue.enqueue(alert("dark-2", .safety), now: at(3))
        queue.enqueue(alert("oob", .tagOrBounds), now: at(4))
        // The out-of-bounds alert takes the slot and the safety alert it interrupted
        // goes back to the front of its own tier, ahead of the second safety alert.
        XCTAssertEqual(queue.current?.alert.subjectKey, "oob")
        XCTAssertEqual(queue.queued.map(\.subjectKey), ["showing", "dark-2", "ping", "pill"])
    }

    // The app was in the background: nothing was seen, so nothing is used up or dropped.
    @MainActor
    func testBackgroundingStopsTheClockAndNothingIsLostOnReturn() {
        let presenter = AlertPresenter(schedulesTimer: false)
        presenter.enqueue(alert("now", .tagOrBounds), now: at(0))
        presenter.enqueue(alert("pill", .update), now: at(1))
        presenter.enqueue(alert("ping", .ping), now: at(2))
        presenter.enqueue(alert("dark", .safety), now: at(3))
        let before = presenter.showID

        presenter.setBackgrounded(true, now: at(5))
        presenter.advance(now: at(500))
        XCTAssertEqual(presenter.current?.subjectKey, "now")

        presenter.setBackgrounded(false, now: at(500))
        XCTAssertNotEqual(presenter.showID, before, "the alert nobody saw is announced again")
        var seen: [String] = []
        var clock = 500.0
        while let showing = presenter.current {
            seen.append(showing.subjectKey)
            clock += AlertQueue.showDuration
            presenter.advance(now: at(clock))
        }
        XCTAssertEqual(seen, ["now", "dark", "ping", "pill"])
    }

    // A hidden surface and a backgrounded app are independent reasons to stop the clock.
    @MainActor
    func testTheClockStaysStoppedUntilBothSurfaceAndAppAreVisible() {
        let presenter = AlertPresenter(schedulesTimer: false)
        presenter.enqueue(alert("a", .safety), now: at(0))
        presenter.setSuspended(true, now: at(1))
        presenter.setBackgrounded(true, now: at(2))

        presenter.setBackgrounded(false, now: at(10))
        presenter.advance(now: at(100))
        XCTAssertEqual(presenter.current?.subjectKey, "a", "surface is still hidden")

        presenter.setSuspended(false, now: at(100))
        presenter.advance(now: at(104))
        XCTAssertNil(presenter.current)
    }

    func testTenEventsInOneSecondAreShownOneAtATimeInPriorityOrder() {
        var queue = AlertQueue()
        let events: [(String, AlertPriority)] = [
            ("pill", .update), ("ping", .ping), ("dark:riley", .safety), ("dark:riley", .safety),
            ("tag:morgan", .tagOrBounds), ("ping", .ping), ("dark:casey", .safety),
            ("oob:jordan", .tagOrBounds), ("dark:riley", .safety), ("pill", .update),
        ]
        for (index, event) in events.enumerated() {
            queue.enqueue(alert(event.0, event.1), now: at(Double(index) / 10))
        }

        XCTAssertEqual(
            drain(&queue, from: 0.9),
            ["tag:morgan", "oob:jordan", "dark:riley", "dark:casey", "ping", "pill"]
        )
        XCTAssertNil(queue.current)
        XCTAssertTrue(queue.queued.isEmpty)
        XCTAssertNil(queue.nextWakeAt)
    }

    func testTheClockStopsWhileTheSurfaceIsHiddenSoNothingIsUsedUpUnseen() {
        var queue = AlertQueue()
        queue.enqueue(alert("tag", .tagOrBounds), now: at(0))
        queue.enqueue(alert("ping", .ping), now: at(0.1))

        queue.hold(now: at(1))
        XCTAssertNil(queue.nextWakeAt)
        XCTAssertNil(queue.advance(now: at(60)))
        XCTAssertEqual(queue.current?.alert.subjectKey, "tag")

        let firstShowID = queue.current?.showID
        queue.release(now: at(60))
        XCTAssertEqual(queue.current?.shownAt, at(60))
        XCTAssertEqual(queue.nextWakeAt, at(64))
        XCTAssertNotEqual(queue.current?.showID, firstShowID)

        queue.advance(now: at(64))
        // The ping was never dropped while the surface was hidden.
        XCTAssertEqual(queue.current?.alert.subjectKey, "ping")
    }

    func testAnAlertThatArrivesDuringAHoldStartsItsTimeOnRelease() {
        var queue = AlertQueue()
        queue.hold(now: at(0))
        queue.enqueue(alert("oob", .tagOrBounds), now: at(5))
        XCTAssertEqual(queue.current?.alert.subjectKey, "oob")
        XCTAssertNil(queue.nextWakeAt)

        queue.release(now: at(9))
        XCTAssertEqual(queue.current?.shownAt, at(9))
        XCTAssertEqual(queue.nextWakeAt, at(13))
    }

    @MainActor
    func testSuspendingThePresenterHoldsTheSlotAndResumingRestartsIt() {
        let presenter = AlertPresenter(schedulesTimer: false)
        presenter.enqueue(alert("dark", .safety), now: at(0))
        let before = presenter.showID

        presenter.setSuspended(true, now: at(1))
        presenter.advance(now: at(100))
        XCTAssertEqual(presenter.current?.subjectKey, "dark")

        presenter.setSuspended(false, now: at(100))
        XCTAssertNotEqual(presenter.showID, before)
        presenter.advance(now: at(103.9))
        XCTAssertEqual(presenter.current?.subjectKey, "dark")
        presenter.advance(now: at(104))
        XCTAssertNil(presenter.current)
    }

    @MainActor
    func testAWentDarkEventAndItsBannerShareOneKeySoTheyAreOneAlert() {
        let player = UUID()
        let eventKey = AppStore.alertSubjectKey(forEventType: "signal_lost", playerID: player, seq: 7)
        let bannerKey = AppStore.alertSubjectKey(forEventType: "signal_lost", playerID: player)
        XCTAssertEqual(eventKey, bannerKey)
        XCTAssertEqual(eventKey, "dark:\(player.uuidString)")

        var queue = AlertQueue()
        queue.enqueue(alert(eventKey, .safety, text: "Riley went dark."), now: at(0))
        queue.enqueue(alert(bannerKey, .safety, text: "Riley went dark. Last fix is on the map."), now: at(0.2))
        XCTAssertTrue(queue.queued.isEmpty)
    }

    @MainActor
    func testTwoEventsWithoutAPlayerNeverMerge() {
        let first = AppStore.alertSubjectKey(forEventType: "zone_warning", playerID: nil, seq: 1)
        let second = AppStore.alertSubjectKey(forEventType: "zone_warning", playerID: nil, seq: 2)
        XCTAssertNotEqual(first, second)
    }

    // Review finding: `schedule()` re-armed the 4 s timer on every enqueue, so a steady
    // trickle of events kept the visible alert on screen and starved the queue.
    @MainActor
    func testAnEnqueueMidSlotDoesNotRestartTheVisibleAlertsTimer() {
        let presenter = AlertPresenter(schedulesTimer: true)
        presenter.enqueue(alert("a", .safety), now: Date())
        XCTAssertEqual(presenter.timerArmCount, 1)

        presenter.enqueue(alert("b", .safety), now: Date())
        presenter.enqueue(alert("c", .ping), now: Date())
        presenter.enqueue(alert("a", .safety, text: "again"), now: Date())
        XCTAssertEqual(presenter.timerArmCount, 1, "the showing alert keeps its original timer")
        presenter.reset()
    }

    // Review finding: `onShow` (the ping flash and haptic) fired while the surface was
    // suspended, then fired again when `release` gave the alert a fresh showing.
    @MainActor
    func testOnShowWaitsForTheSurfaceAndFiresOnceNotTwice() {
        let presenter = AlertPresenter(schedulesTimer: false)
        var shown = 0
        presenter.onShow = { _ in shown += 1 }

        presenter.setSuspended(true, now: at(0))
        presenter.enqueue(alert("ping", .ping, kind: .ping(.hider)), now: at(1))
        XCTAssertEqual(shown, 0, "nothing flashes while the alert surface is hidden")

        presenter.setSuspended(false, now: at(5))
        XCTAssertEqual(shown, 1)
    }

    // A full-page sheet or a blocking alert hides the pill. Unseen alerts are never dropped,
    // so the clock stops there, as it already does for a map pick.
    func testTheAlertSurfaceIsHiddenByAMapPickAFullPageSheetOrABlockingAlert() {
        XCTAssertTrue(AlertSurface.isVisible(floatingNoticeShown: true, mapPicking: false, coveredByModal: false))
        XCTAssertFalse(AlertSurface.isVisible(floatingNoticeShown: false, mapPicking: false, coveredByModal: false))
        XCTAssertFalse(AlertSurface.isVisible(floatingNoticeShown: true, mapPicking: true, coveredByModal: false))
        XCTAssertFalse(AlertSurface.isVisible(floatingNoticeShown: true, mapPicking: false, coveredByModal: true))
    }

    func testAnEmptyQueueAdvancesCleanly() {
        var queue = AlertQueue()
        XCTAssertNil(queue.advance(now: at(1_000)))
        queue.enqueue(alert("a", .safety), now: at(0))
        queue.advance(now: at(4))
        XCTAssertNil(queue.current)
        XCTAssertNil(queue.nextWakeAt)
    }

    @MainActor
    func testThePresenterAnnouncesEveryShowingThroughOnShow() {
        let presenter = AlertPresenter(schedulesTimer: false)
        var shown: [String] = []
        presenter.onShow = { shown.append($0.subjectKey) }

        presenter.enqueue(alert("ping", .ping, kind: .ping(.hider)), now: at(0))
        presenter.enqueue(alert("tag", .tagOrBounds), now: at(1))
        presenter.advance(now: at(5))
        presenter.advance(now: at(9))

        XCTAssertEqual(shown, ["ping", "tag", "ping"])
        XCTAssertNil(presenter.current)
    }

    @MainActor
    func testCoalescingDoesNotAnnounceAgainOrChangeTheShowID() {
        let presenter = AlertPresenter(schedulesTimer: false)
        var shown = 0
        presenter.onShow = { _ in shown += 1 }

        presenter.enqueue(alert("dark:riley", .safety), now: at(0))
        let id = presenter.showID
        presenter.enqueue(alert("dark:riley", .safety, text: "again"), now: at(1))

        XCTAssertEqual(shown, 1)
        XCTAssertEqual(presenter.showID, id)
        XCTAssertEqual(presenter.current?.text, "again")
    }

    @MainActor
    func testResetClearsTheSlotAndTheQueue() {
        let presenter = AlertPresenter(schedulesTimer: false)
        presenter.enqueue(alert("a", .safety), now: at(0))
        presenter.enqueue(alert("b", .update), now: at(0))
        presenter.reset()
        XCTAssertNil(presenter.current)
        XCTAssertTrue(presenter.queued.isEmpty)
    }

    @MainActor
    func testTheEventPriorityMapping() {
        XCTAssertEqual(AppStore.alertPriority(forEventType: "tag"), .tagOrBounds)
        XCTAssertEqual(AppStore.alertPriority(forEventType: "out_of_bounds"), .tagOrBounds)
        XCTAssertEqual(AppStore.alertPriority(forEventType: "signal_lost"), .safety)
        XCTAssertEqual(AppStore.alertPriority(forEventType: "zone_warning"), .update)
    }
}
