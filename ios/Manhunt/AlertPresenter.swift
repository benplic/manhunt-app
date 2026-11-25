import Foundation
import Observation

/// Lower raw value wins the slot. See docs/superpowers/plans/2026-11-24-alert-noise.md.
enum AlertPriority: Int, Comparable, Sendable {
    /// Tag and out-of-bounds.
    case tagOrBounds = 1
    /// Safety: a player went dark.
    case safety = 2
    /// Ping flash.
    case ping = 3
    /// Live-update pill.
    case update = 4

    static func < (lhs: AlertPriority, rhs: AlertPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum LiveAlertKind: Equatable, Sendable {
    case update
    /// The full-screen ping flash. The role decides its tint and wording.
    case ping(PlayerRole)
}

struct LiveAlert: Equatable, Identifiable, Sendable {
    var id = UUID()
    var text: String
    var tone: String
    var priority: AlertPriority
    /// Subject plus type, for example `dark:<player id>`. The same key collapses to one entry.
    var subjectKey: String
    var createdAt: Date
    var kind: LiveAlertKind = .update
}

/// The queue rules, with no timers and no clock, so tests never sleep.
///
/// - One alert shows at a time, for `showDuration`.
/// - An alert of equal or lower priority than the one showing WAITS. It is never skipped.
/// - A higher-priority alert takes the slot at once, and jumps ahead of every lower-priority
///   alert in the queue. The interrupted alert returns to the front of its own tier and
///   later shows again for its full time.
/// - First in, first out within one priority.
/// - An alert nobody has seen is NEVER dropped (decided by the user, 2026-11-25). There is
///   no cap, no expiry, and no trim after the app was in the background. The only merge is
///   de-duplication by `subjectKey`: the same subject and type is one entry.
struct AlertQueue {
    static let showDuration: TimeInterval = 4

    struct Showing: Equatable {
        var alert: LiveAlert
        var shownAt: Date
        /// New for every showing, including a resumed one, so VoiceOver announces it again.
        var showID: Int
    }

    private(set) var current: Showing?
    private var waiting: [LiveAlert] = []
    private var showSeq = 0
    /// Set while the alert surface cannot be seen. Nothing times out or expires then.
    private var heldAt: Date?

    /// Alerts waiting for the slot, in the order they will be shown.
    var queued: [LiveAlert] { waiting }

    var isHeld: Bool { heldAt != nil }

    /// When `advance` should run next, or nil when nothing is showing or the queue is held.
    var nextWakeAt: Date? {
        guard heldAt == nil else { return nil }
        return current.map { $0.shownAt.addingTimeInterval(Self.showDuration) }
    }

    /// Nobody can see the alert surface (a map pick, the full-map lock, the app in the
    /// background). Alerts still arrive and queue, but the clock stops so none is used up
    /// unseen.
    mutating func hold(now: Date) {
        if heldAt == nil { heldAt = now }
    }

    /// The surface is visible again. The showing alert starts its 4 s over, with a new
    /// `showID` so VoiceOver announces it, because nobody saw it while it was held.
    @discardableResult
    mutating func release(now: Date) -> LiveAlert? {
        guard heldAt != nil else { return nil }
        heldAt = nil
        guard var showing = current else { return nil }
        showSeq += 1
        showing.shownAt = now
        showing.showID = showSeq
        current = showing
        return showing.alert
    }

    /// Returns the alert that took the slot because of this call, if any.
    @discardableResult
    mutating func enqueue(_ alert: LiveAlert, now: Date) -> LiveAlert? {
        if var showing = current, showing.alert.subjectKey == alert.subjectKey {
            // Already on screen: refresh its words, keep its timer.
            showing.alert.text = alert.text
            showing.alert.tone = alert.tone
            current = showing
            return nil
        }

        if let index = waiting.firstIndex(where: { $0.subjectKey == alert.subjectKey }) {
            if waiting[index].priority == alert.priority {
                waiting[index].text = alert.text
                waiting[index].tone = alert.tone
                return nil
            }
            waiting.remove(at: index)
        }

        guard let showing = current else {
            return show(alert, now: now)
        }

        if alert.priority < showing.alert.priority {
            requeueFront(showing.alert)
            return show(alert, now: now)
        }

        insertBack(alert)
        return nil
    }

    /// Call when the timer fires, or whenever the app wakes. Returns the newly shown alert.
    @discardableResult
    mutating func advance(now: Date) -> LiveAlert? {
        if heldAt != nil { return nil }
        if let showing = current, now.timeIntervalSince(showing.shownAt) < Self.showDuration {
            return nil
        }
        current = nil
        guard !waiting.isEmpty else { return nil }
        return show(waiting.removeFirst(), now: now)
    }

    mutating func reset() {
        current = nil
        waiting = []
        heldAt = nil
    }

    private mutating func show(_ alert: LiveAlert, now: Date) -> LiveAlert {
        showSeq += 1
        current = Showing(alert: alert, shownAt: now, showID: showSeq)
        return alert
    }

    /// Back to the front of its own tier, so it shows again before later arrivals.
    private mutating func requeueFront(_ alert: LiveAlert) {
        let index = waiting.firstIndex { $0.priority >= alert.priority } ?? waiting.count
        waiting.insert(alert, at: index)
    }

    /// Behind everything of the same or higher priority, ahead of anything lower.
    private mutating func insertBack(_ alert: LiveAlert) {
        var index = waiting.count
        while index > 0, waiting[index - 1].priority > alert.priority {
            index -= 1
        }
        waiting.insert(alert, at: index)
    }
}

/// When can the player actually see the alert pill? The presenter's clock runs only then,
/// so an alert is never used up unseen.
enum AlertSurface {
    /// - Parameters:
    ///   - floatingNoticeShown: the head-start chrome shows floating notices at all.
    ///   - mapPicking: a decoy or demo map pick replaces the pill with its own banner.
    ///   - coveredByModal: a full-page sheet (the tag scanner) or a blocking alert (leave
    ///     the hunt, "Play safely") sits over the pill. The medium-detent sheets leave the
    ///     top of the map visible, so they do not count.
    static func isVisible(floatingNoticeShown: Bool, mapPicking: Bool, coveredByModal: Bool) -> Bool {
        floatingNoticeShown && !mapPicking && !coveredByModal
    }
}

/// What the UI renders. Owns the 4 second timer. Time is injected, never read from
/// the wall clock inside the queue, so tests drive it with `advance(now:)`.
@MainActor
@Observable
final class AlertPresenter {
    private(set) var current: LiveAlert?
    /// Changes on every showing, including a resumed one. Use as the view identity.
    private(set) var showID = 0

    /// Fires when an alert takes the slot, new or resumed. The ping flash starts here, so
    /// it never plays while a higher-priority alert is on screen.
    @ObservationIgnored var onShow: ((LiveAlert) -> Void)?

    @ObservationIgnored private var queue = AlertQueue()
    @ObservationIgnored private var timer: Task<Void, Never>?
    /// The wake time the live timer was armed for. Re-arming for the same wake time would
    /// restart the 4 s, so an unrelated enqueue could keep one alert on screen forever.
    @ObservationIgnored private var armedWake: Date?
    /// How many times a timer was armed. Tests use it to prove an enqueue does not re-arm.
    @ObservationIgnored private(set) var timerArmCount = 0
    private let schedulesTimer: Bool
    @ObservationIgnored private var surfaceSuspended = false
    @ObservationIgnored private var appBackgrounded = false

    var queued: [LiveAlert] { queue.queued }

    /// `schedulesTimer: false` leaves timing to explicit `advance(now:)` calls (tests).
    init(schedulesTimer: Bool = true) {
        self.schedulesTimer = schedulesTimer
    }

    func enqueue(_ alert: LiveAlert, now: Date = Date()) {
        queue.enqueue(alert, now: now)
        publish(now: now)
    }

    func advance(now: Date = Date()) {
        queue.advance(now: now)
        publish(now: now)
    }

    /// True while the alert surface cannot be seen (a map pick, the full-map lock). The
    /// clock stops, alerts keep queueing, and the showing alert gets its full 4 s once the
    /// surface is visible again.
    func setSuspended(_ suspended: Bool, now: Date = Date()) {
        surfaceSuspended = suspended
        applyHold(now: now)
    }

    /// True while the app is in the background. Same effect as a hidden surface: nothing is
    /// used up or dropped while nobody can look.
    func setBackgrounded(_ backgrounded: Bool, now: Date = Date()) {
        appBackgrounded = backgrounded
        applyHold(now: now)
    }

    /// The clock runs only when the surface is visible AND the app is in the foreground.
    private func applyHold(now: Date) {
        if surfaceSuspended || appBackgrounded {
            queue.hold(now: now)
        } else {
            queue.release(now: now)
        }
        publish(now: now)
    }

    func reset() {
        timer?.cancel()
        timer = nil
        armedWake = nil
        surfaceSuspended = false
        appBackgrounded = false
        queue.reset()
        current = nil
    }

    private func publish(now: Date) {
        let previousShowID = showID
        current = queue.current?.alert
        showID = queue.current?.showID ?? previousShowID
        // While the surface is hidden nothing is on screen, so nothing flashes. `release`
        // gives the showing alert a new showID, which fires `onShow` once, when it is seen.
        if let alert = current, showID != previousShowID, !queue.isHeld {
            onShow?(alert)
        }
        schedule()
    }

    private func schedule() {
        guard schedulesTimer, let wake = queue.nextWakeAt, let shownAt = queue.current?.shownAt else {
            timer?.cancel()
            timer = nil
            armedWake = nil
            return
        }
        // Already armed for this exact wake time: leave it running. Re-arming would restart
        // the full 4 s from now, so a trickle of new events would starve the queue.
        if timer != nil, armedWake == wake { return }
        timer?.cancel()
        armedWake = wake
        timerArmCount += 1
        // The delay is always one show duration from when this alert took the slot, so a
        // synthetic `now` (previews, tests) schedules the same as a real one. On waking,
        // never advance to a time before the real clock: Task.sleep also counts time the
        // app spent suspended, and a stale time would give the next alert a stale start.
        let delay = max(0, wake.timeIntervalSince(shownAt))
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.timerFired(wake: wake)
        }
    }

    /// The armed timer ran out. Clear it first so `advance` can arm the next alert's timer.
    private func timerFired(wake: Date) {
        timer = nil
        armedWake = nil
        advance(now: max(wake, Date()))
    }
}
