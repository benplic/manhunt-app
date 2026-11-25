import Foundation

/// How fresh a player's last location fix is, as 0 to 4 bars.
///
/// This is FRESHNESS, not radio signal: the server never sees RSSI, only when the last fix
/// was recorded. Keep the word "fix" in every label so nobody reads it as signal strength.
/// Thresholds match stale map pins: stale means older than 2 ping intervals, measured in
/// wall-clock time from the fix's own `at` timestamp, never from game seconds.
/// Mirror of web/src/game/fixFreshness.ts. Keep the two in lockstep.
enum FixFreshness {
    struct Reading: Equatable {
        var bars: Int
        /// Spoken label, for example "Last fix 40 seconds ago".
        var label: String
        /// Wall-clock age in seconds, or nil when there is no fix to age.
        var ageSeconds: Double?
    }

    /// Used when the match has no ping interval (reveals off). Shared with map pin staleness.
    static let defaultPingIntervalS = PinStaleness.defaultPingIntervalS

    static func pingInterval(timers: TimersDTO?) -> Int {
        for candidate in [timers?.revealIntervalS, timers?.seekerRevealIntervalS] {
            if let value = candidate, value > 0 { return value }
        }
        return defaultPingIntervalS
    }

    static func describeAge(_ seconds: Double) -> String {
        let whole = max(0, Int(seconds.rounded(.down)))
        func plural(_ n: Int, _ unit: String) -> String { "\(n) \(unit)\(n == 1 ? "" : "s")" }
        if whole < 60 { return plural(whole, "second") }
        if whole < 3600 { return plural(whole / 60, "minute") }
        return plural(whole / 3600, "hour")
    }

    /// The server sends `location: nil` both for "hidden from you" and "no fix yet", so the
    /// client decides which one a nil means. Hidden players draw nothing, never zero bars.
    static func viewerExpectsFix(
        viewerID: UUID,
        viewerRole: PlayerRole,
        viewerStatus: PlayerStatus,
        playerID: UUID,
        playerRole: PlayerRole,
        phase: MatchPhase
    ) -> Bool {
        if phase == .lobby { return false }
        if playerID == viewerID { return true }
        if viewerStatus == .eliminated { return false }
        return playerRole != .unassigned && playerRole == viewerRole
    }

    /// Server timestamps come from Python `isoformat()`, which omits the fraction when it is
    /// exactly zero. Try both shapes.
    static func parse(_ iso: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: iso) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: iso)
    }

    /// Returns nil when nothing should be drawn (the viewer may not see this player's fix).
    static func reading(
        location: LocationDTO?,
        status: PlayerStatus,
        expectsFix: Bool,
        pingIntervalS: Int,
        now: Date
    ) -> Reading? {
        guard let location else {
            guard expectsFix else { return nil }
            if status == .signalLost {
                return Reading(bars: 1, label: "Signal lost, no fix on record", ageSeconds: nil)
            }
            return Reading(bars: 0, label: "No fix yet", ageSeconds: nil)
        }
        guard let fixAt = parse(location.at) else {
            return Reading(bars: 0, label: "No fix yet", ageSeconds: nil)
        }
        // A phone clock a little behind the server gives negative ages. Clamp to "just now".
        let age = max(0, now.timeIntervalSince(fixAt))
        let described = describeAge(age)

        if status == .signalLost || location.kind == "last_known" {
            return Reading(bars: 1, label: "Signal lost, last fix \(described) ago", ageSeconds: age)
        }
        let interval = PinStaleness.effectiveIntervalS(pingIntervalS)
        let label = "Last fix \(described) ago"
        let bars = PinStaleness.barsForAge(age, intervalS: interval, signalLost: false)
        if bars == 2 {
            return Reading(bars: 2, label: "Stale fix, \(described) old", ageSeconds: age)
        }
        return Reading(bars: bars, label: label, ageSeconds: age)
    }
}
