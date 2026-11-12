import Foundation

/// Primary action card in the live dock, keyed on server `phase` rather than `situation`
/// so an out-of-bounds warning during head start never reveals the tag button early.
enum DockChrome: Equatable {
    case headStartWaiting(title: String, subtitle: String)
    case activeTagging
    case activeHider

    static func state(phase: MatchPhase, role: VisualRole, remainingS: Int?) -> DockChrome {
        guard phase == .headStart else {
            return role == .hider ? .activeHider : .activeTagging
        }
        let clock = PhaseClock.clock(remainingS ?? 0)
        if role == .hider {
            return .headStartWaiting(
                title: "Hide!",
                subtitle: "Seekers are released in \(clock)"
            )
        }
        return .headStartWaiting(
            title: "Hiders are hiding",
            subtitle: "You're out in \(clock)"
        )
    }
}
