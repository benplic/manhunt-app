import Foundation

/// Maps battery and lifecycle into the location `flag` the server understands.
enum LocationFlag {
    /// Treat 5% and below as low. Negative levels (simulator) stay normal.
    static let lowBatteryThreshold: Float = 0.05

    static func choose(battery: Float, isFinal: Bool, wasLow: Bool) -> (flag: String, nowLow: Bool) {
        if isFinal {
            return ("final", wasLow)
        }
        let low = battery >= 0 && battery <= lowBatteryThreshold
        if low && !wasLow {
            return ("low_battery", true)
        }
        if !low {
            return ("normal", false)
        }
        // Still in the same low-battery dip; do not spam the safety banner.
        return ("normal", true)
    }
}

enum WakeCopy {
    static let message = "Waking the hunt server…"
}
