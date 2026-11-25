import Foundation

/// Wall-clock freshness thresholds shared by fix bars and live map pins.
/// Stale means older than `staleAfterIntervals` ping intervals — the same rule as 2 fix bars.
/// Mirror: web/src/map/pinStaleness.ts. Keep the two in lockstep.
enum PinStaleness {
    /// Fixes older than this many reveal/ping intervals read as stale on the map and in the HUD.
    static let staleAfterIntervals = 2

    static let defaultPingIntervalS = 60

    static func effectiveIntervalS(_ pingIntervalS: Int) -> Double {
        let value = pingIntervalS > 0 ? pingIntervalS : defaultPingIntervalS
        return Double(value)
    }

    /// Bar count for a fix age. Matches `FixFreshness.reading` except when there is no fix (0 bars).
    static func barsForAge(_ ageS: Double, intervalS: Double, signalLost: Bool) -> Int {
        if signalLost {
            return 1
        }
        if ageS <= intervalS { return 4 }
        if ageS <= intervalS * Double(staleAfterIntervals) { return 3 }
        return 2
    }

    /// Map pin translucency paired with fix bars so a dim pin matches the leaderboard meter.
    static func pinOpacity(forBars bars: Int) -> Double {
        switch bars {
        case 4: 1
        case 3: 0.88
        case 2: 0.5
        case 1: 0.45
        default: 0.4
        }
    }

    static func pinOpacity(
        fixAt: Date?,
        fixKind: String?,
        status: PlayerStatus,
        pingIntervalS: Int,
        now: Date
    ) -> Double {
        guard let fixAt else {
            return pinOpacity(forBars: 0)
        }
        let age = max(0, now.timeIntervalSince(fixAt))
        let lost = status == .signalLost || fixKind == "last_known"
        let bars = barsForAge(age, intervalS: effectiveIntervalS(pingIntervalS), signalLost: lost)
        return pinOpacity(forBars: bars)
    }
}