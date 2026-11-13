import Foundation

/// Primary action card in the live dock, keyed on server `phase` rather than `situation`
/// so an out-of-bounds warning during head start never reveals the tag button early.
enum DockChrome: Equatable {
    case headStartWaiting(title: String, subtitle: String)
    case activeTagging
    case activeHider

    static func state(
        phase: MatchPhase,
        role: VisualRole,
        remainingS: Int?,
        spawnHolding: Bool = false,
        seekerOutsideSpawn: Bool = false
    ) -> DockChrome {
        guard phase == .headStart else {
            return role == .hider ? .activeHider : .activeTagging
        }
        if spawnHolding {
            if role == .hider {
                return .headStartWaiting(
                    title: "Hide!",
                    subtitle: "Head start starts when seekers are in spawn"
                )
            }
            if seekerOutsideSpawn {
                return .headStartWaiting(
                    title: "Get in the spawn zone",
                    subtitle: "The countdown starts when every seeker is inside"
                )
            }
            return .headStartWaiting(
                title: "Waiting on seekers",
                subtitle: "The countdown starts when every seeker is inside"
            )
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
