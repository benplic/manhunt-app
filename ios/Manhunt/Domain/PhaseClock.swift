import Foundation

/// View-model for the live game countdown and progress HUD.
struct PhaseClock: Equatable {
    var primaryLabel: String
    var primaryClock: String
    var primaryProgress: Double
    var pingClock: String?
    var pingProgress: Double
    var zoneLine: String?
    var zoneImminent: Bool

    init(snapshot: PlayerViewDTO?, paused: Bool, locale: Locale = .current, leadS: Double = 0) {
        guard let snapshot else {
            primaryLabel = paused ? "Paused" : "Time left"
            primaryClock = "30:00"
            primaryProgress = 0
            pingClock = "1:00"
            pingProgress = 0
            zoneLine = nil
            zoneImminent = false
            return
        }
        let timers = snapshot.timers
        if paused {
            primaryLabel = "Paused"
        } else {
            switch snapshot.phase {
            case .headStart: primaryLabel = "Head start"
            case .active: primaryLabel = "Time left"
            case .paused: primaryLabel = "Paused"
            case .ended: primaryLabel = "Ended"
            case .lobby: primaryLabel = "Lobby"
            }
        }

        if snapshot.phase == .headStart {
            let remaining = snapshot.phaseRemainingS ?? 0
            let total = max(1, timers?.headStartS ?? max(1, remaining))
            let left = Self.left(remaining, leadS)
            primaryClock = Self.clock(Int(left.rounded(.up)))
            if snapshot.spawnLock?.holding == true, !paused {
                // The number on screen is the countdown that has not started.
                primaryLabel = "Waiting"
                primaryProgress = 0
            } else {
                primaryProgress = Self.clampProgress(1.0 - left / Double(total))
            }
        } else {
            let remaining = snapshot.timeLimitRemainingS ?? 0
            let total = max(1, timers?.timeLimitS ?? max(1, remaining))
            if let timeLimitRemainingS = snapshot.timeLimitRemainingS {
                let left = Self.left(timeLimitRemainingS, leadS)
                primaryClock = Self.clock(Int(left.rounded(.up)))
                primaryProgress = Self.clampProgress(1.0 - left / Double(total))
            } else {
                primaryClock = "--:--"
                primaryProgress = 0
            }
        }

        if let nextPing = timers?.nextRevealInS,
           let interval = timers?.revealIntervalS,
           interval > 0 {
            let left = Self.left(nextPing, leadS)
            pingClock = Self.clock(Int(left.rounded(.up)))
            pingProgress = Self.clampProgress(1.0 - left / Double(interval))
        } else {
            pingClock = nil
            pingProgress = 0
        }

        if let zone = timers?.zone {
            let currentText = Self.formatDistance(zone.radiusM, locale: locale)
            if let nextRadius = zone.nextRadiusM, let shrinksIn = zone.shrinksInS {
                let nextText = Self.formatDistance(nextRadius, locale: locale)
                let left = Self.left(shrinksIn, leadS)
                if left <= 60 {
                    zoneLine = "Zone \(currentText) → \(nextText) in \(Self.clock(Int(left.rounded(.up))))"
                    zoneImminent = true
                } else {
                    zoneLine = "Zone \(currentText) · shrinks in \(Self.clock(Int(left.rounded(.up))))"
                    zoneImminent = false
                }
            } else {
                zoneLine = "Zone \(currentText) · final size"
                zoneImminent = false
            }
        } else {
            zoneLine = nil
            zoneImminent = false
        }
    }

    static func formatDistance(_ meters: Double, locale: Locale = .current) -> String {
        if locale.measurementSystem == .us {
            let feet = meters * 3.28084
            if feet < 1000 {
                return "\(Int(feet.rounded())) ft"
            }
            let miles = meters / 1609.344
            return String(format: "%.2f mi", miles)
        }
        if meters < 1000 {
            return "\(Int(meters.rounded())) m"
        }
        return String(format: "%.2f km", meters / 1000.0)
    }

    static func clock(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }

    private static func left(_ seconds: Int, _ lead: Double) -> Double {
        max(0, Double(seconds) - lead)
    }

    private static func clampProgress(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }
}
