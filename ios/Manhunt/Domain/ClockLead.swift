import Foundation

/// Extrapolates the 1 Hz server snapshots so countdowns move every frame.
enum ClockLead {
    /// One server tick. Past this the clock holds and waits for the next snapshot, so a late
    /// snapshot never makes the display run backwards.
    static let maxWallSeconds: TimeInterval = 1.0

    /// Game seconds per wall second. Zero whenever the match clock is not running.
    static func rate(snapshot: PlayerViewDTO?, paused: Bool) -> Double {
        guard let snapshot, !paused else { return 0 }
        switch snapshot.phase {
        case .lobby, .paused, .ended: return 0
        case .headStart, .active: break
        }
        if snapshot.spawnLock?.holding == true { return 0 }
        return Double(max(1, snapshot.demo?.speed ?? 1))
    }

    /// Game seconds elapsed since the snapshot arrived, capped at one tick.
    static func seconds(rate: Double, anchoredAt: Date, now: Date) -> Double {
        guard rate > 0 else { return 0 }
        let raw = max(0, now.timeIntervalSince(anchoredAt))
        // Sub-millisecond bins: `addingTimeInterval(0.4)` is not exact in IEEE-754 wall time.
        let wall = min((raw * 1000).rounded() / 1000, maxWallSeconds)
        return wall * rate
    }

    /// New anchor time for an incoming view. Re-anchor only when the server clock moved.
    static func anchor(previous: PlayerViewDTO?, previousAnchor: Date?, next: PlayerViewDTO, now: Date) -> Date {
        guard let previous, let previousAnchor else { return now }
        let sameClock = previous.gameElapsedS == next.gameElapsedS
            && previous.phase == next.phase
            && previous.spawnLock?.holding == next.spawnLock?.holding
            && previous.demo?.speed == next.demo?.speed
        return sameClock ? previousAnchor : now
    }
}
