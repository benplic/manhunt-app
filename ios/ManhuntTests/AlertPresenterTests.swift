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

    func testTheQueueIsCappedAtEightAndDropsTheOldestLowestPriority() {
        var queue = AlertQueue()
        queue.enqueue(alert("showing", .tagOrBounds), now: at(0))
        queue.enqueue(alert("pill-old", .update), now: at(1))
        queue.enqueue(alert("pill-new", .update), now: at(2))
        for index in 0..<(AlertQueue.capacity - 2) {
            queue.enqueue(alert("ping-\(index)", .ping), now: at(3 + Double(index)))
        }
        XCTAssertEqual(queue.queued.count, AlertQueue.capacity)

        queue.enqueue(alert("dark", .safety), now: at(100))

        XCTAssertEqual(queue.queued.count, AlertQueue.capacity)
        let keys = queue.queued.map(\.subjectKey)
        XCTAssertFalse(keys.contains("pill-old"))
        XCTAssertTrue(keys.contains("pill-new"))
        XCTAssertEqual(keys.first, "dark")
    }

    func testAnAlertThatWaitedOverThirtySecondsIsDropped() {
        var queue = AlertQueue()
        queue.enqueue(alert("long", .tagOrBounds), now: at(0))
        queue.enqueue(alert("stale", .ping), now: at(1))
        queue.enqueue(alert("fresh", .ping), now: at(25))

        queue.advance(now: at(31.5))
        XCTAssertEqual(queue.current?.alert.subjectKey, "fresh")
    }

    func testAnAlertThatWaitedExactlyThirtySecondsIsKept() {
        var queue = AlertQueue()
        queue.enqueue(alert("long", .tagOrBounds), now: at(0))
        queue.enqueue(alert("edge", .ping), now: at(0))
        queue.advance(now: at(30))
        XCTAssertEqual(queue.current?.alert.subjectKey, "edge")
    }

    func testBackgroundReturnKeepsOnlyTheThreeHighestPriority() {
        var queue = AlertQueue()
        queue.enqueue(alert("now", .tagOrBounds), now: at(0))
        queue.enqueue(alert("pill", .update), now: at(1))
        queue.enqueue(alert("ping", .ping), now: at(2))
        queue.enqueue(alert("dark", .safety), now: at(3))
        queue.enqueue(alert("oob", .tagOrBounds), now: at(4))
        queue.enqueue(alert("ping-2", .ping), now: at(5))

        queue.resumeFromBackground(now: at(10))

        XCTAssertEqual(queue.current?.alert.subjectKey, "oob")
        XCTAssertEqual(queue.queued.map(\.subjectKey), ["dark", "ping"])
        XCTAssertEqual(drain(&queue, from: 10), ["oob", "dark", "ping"])
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
        // The ping waited about 1 s of visible time, not 60 s, so it did not expire.
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
