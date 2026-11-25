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
/// - A higher-priority alert takes the slot at once. The interrupted alert returns to the
///   front of its own tier and later shows again for its full time.
/// - First in, first out within one priority.
/// - Bounded: `capacity`, `expiry` for alerts that waited too long, and de-duplication by
///   `subjectKey`.
struct AlertQueue {
    static let showDuration: TimeInterval = 4
    static let capacity = 8
    // TODO: confirm the 30 s expiry with the user (open question in the plan).
    static let expiry: TimeInterval = 30
    static let backgroundKeep = 3

    struct Showing: Equatable {
        var alert: LiveAlert
        var shownAt: Date
        /// New for every showing, including a resumed one, so VoiceOver announces it again.
        var showID: Int
    }

    private struct Waiting {
        var alert: LiveAlert
        var queuedAt: Date
    }

    private(set) var current: Showing?
    private var waiting: [Waiting] = []
    private var showSeq = 0
    /// Set while the alert surface cannot be seen. Nothing times out or expires then.
    private var heldAt: Date?

    /// Alerts waiting for the slot, in the order they will be shown.
    var queued: [LiveAlert] { waiting.map(\.alert) }

    var isHeld: Bool { heldAt != nil }

    /// When `advance` should run next, or nil when nothing is showing or the queue is held.
    var nextWakeAt: Date? {
        guard heldAt == nil else { return nil }
        return current.map { $0.shownAt.addingTimeInterval(Self.showDuration) }
    }

    /// The surface is hidden (a map pick, the full-map lock). Alerts still arrive and
    /// queue, but the clock stops so nobody loses one they never saw.
    mutating func hold(now: Date) {
        if heldAt == nil { heldAt = now }
    }

    /// The surface is visible again. The showing alert starts its 4 s over, with a new
    /// `showID` so VoiceOver announces it, and waiting time does not count the hold.
    @discardableResult
    mutating func release(now: Date) -> LiveAlert? {
        guard let held = heldAt else { return nil }
        heldAt = nil
        let heldFor = now.timeIntervalSince(held)
        for index in waiting.indices {
            waiting[index].queuedAt = waiting[index].queuedAt.addingTimeInterval(heldFor)
        }
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

        if let index = waiting.firstIndex(where: { $0.alert.subjectKey == alert.subjectKey }) {
            if waiting[index].alert.priority == alert.priority {
                waiting[index].alert.text = alert.text
                waiting[index].alert.tone = alert.tone
                return nil
            }
            waiting.remove(at: index)
        }

        guard let showing = current else {
            return show(alert, now: now)
        }

        if alert.priority < showing.alert.priority {
            requeueFront(showing.alert, now: now)
            enforceCapacity()
            return show(alert, now: now)
        }

        insertBack(Waiting(alert: alert, queuedAt: now))
        enforceCapacity()
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
        waiting.removeAll { now.timeIntervalSince($0.queuedAt) > Self.expiry }
        guard !waiting.isEmpty else { return nil }
        return show(waiting.removeFirst().alert, now: now)
    }

    /// After the app was in the background: forget stale news, keep the few best alerts.
    @discardableResult
    mutating func resumeFromBackground(now: Date) -> LiveAlert? {
        waiting.removeAll { now.timeIntervalSince($0.queuedAt) > Self.expiry }
        if waiting.count > Self.backgroundKeep {
            waiting.removeLast(waiting.count - Self.backgroundKeep)
        }
        return advance(now: now)
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

    /// Back to the front of its own tier. It waits from now, with a full 4 s ahead.
    private mutating func requeueFront(_ alert: LiveAlert, now: Date) {
        let entry = Waiting(alert: alert, queuedAt: now)
        let index = waiting.firstIndex { $0.alert.priority >= alert.priority } ?? waiting.count
        waiting.insert(entry, at: index)
    }

    private mutating func insertBack(_ entry: Waiting) {
        var index = waiting.count
        while index > 0, waiting[index - 1].alert.priority > entry.alert.priority {
            index -= 1
        }
        waiting.insert(entry, at: index)
    }

    /// Over capacity: drop the oldest entry of the lowest priority.
    private mutating func enforceCapacity() {
        while waiting.count > Self.capacity {
            guard let lowest = waiting.map(\.alert.priority).max(),
                  let victim = waiting.firstIndex(where: { $0.alert.priority == lowest })
            else { return }
            waiting.remove(at: victim)
        }
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
    private let schedulesTimer: Bool

    var queued: [LiveAlert] { queue.queued }

    /// `schedulesTimer: false` leaves expiry to explicit `advance(now:)` calls (tests).
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

    func resumeFromBackground(now: Date = Date()) {
        queue.resumeFromBackground(now: now)
        publish(now: now)
    }

    /// True while the alert surface cannot be seen. The clock stops, alerts keep queueing,
    /// and the showing alert gets its full 4 s once the surface is visible again.
    func setSuspended(_ suspended: Bool, now: Date = Date()) {
        if suspended {
            queue.hold(now: now)
        } else {
            queue.release(now: now)
        }
        publish(now: now)
    }

    func reset() {
        timer?.cancel()
        timer = nil
        queue.reset()
        current = nil
    }

    private func publish(now: Date) {
        let previousShowID = showID
        current = queue.current?.alert
        showID = queue.current?.showID ?? previousShowID
        if let alert = current, showID != previousShowID {
            onShow?(alert)
        }
        schedule()
    }

    private func schedule() {
        timer?.cancel()
        timer = nil
        guard schedulesTimer, let wake = queue.nextWakeAt, let shownAt = queue.current?.shownAt else {
            return
        }
        // The delay is always one show duration from when this alert took the slot, so a
        // synthetic `now` (previews, tests) schedules the same as a real one. On waking,
        // never advance to a time before the real clock: Task.sleep also counts time the
        // app spent suspended, and a stale time would give the next alert a stale start.
        let delay = max(0, wake.timeIntervalSince(shownAt))
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.advance(now: max(wake, Date()))
        }
    }
}
