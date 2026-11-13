import Foundation

/// Keeps a pin moving between 1 Hz snapshots. Each new target starts a straight-line glide from
/// wherever the pin is drawn now, so it never snaps back and never overshoots. The display runs
/// about one snapshot behind the server, which is the price of never extrapolating.
struct PlayerGlide {
    static let minDuration: TimeInterval = 0.5
    static let maxDuration: TimeInterval = 1.25
    static let defaultDuration: TimeInterval = 1.0
    /// Longer jumps (role switch, demo skip) teleport instead of racing across the map.
    static let teleportMeters = 150.0

    private struct Track {
        var from: VisualPoint
        var to: VisualPoint
        var startedAt: Date
        var duration: TimeInterval
    }

    private var tracks: [String: Track] = [:]

    mutating func retarget(_ people: [VisualPlayer], now: Date) {
        var next: [String: Track] = [:]
        for person in people {
            guard let track = tracks[person.id] else {
                next[person.id] = Track(from: person.point, to: person.point, startedAt: now,
                                        duration: Self.defaultDuration)
                continue
            }
            if track.to == person.point {
                next[person.id] = track
                continue
            }
            let drawn = Self.position(of: track, at: now)
            let gap = ArenaGeometry.meters(
                from: GeoPoint(latitude: drawn.latitude, longitude: drawn.longitude),
                to: GeoPoint(latitude: person.point.latitude, longitude: person.point.longitude)
            )
            let observed = now.timeIntervalSince(track.startedAt)
            let duration = min(Self.maxDuration, max(Self.minDuration, observed))
            next[person.id] = gap > Self.teleportMeters
                ? Track(from: person.point, to: person.point, startedAt: now, duration: duration)
                : Track(from: drawn, to: person.point, startedAt: now, duration: duration)
        }
        tracks = next
    }

    func point(for id: String, at now: Date) -> VisualPoint? {
        tracks[id].map { Self.position(of: $0, at: now) }
    }

    func isSettled(at now: Date) -> Bool {
        tracks.values.allSatisfy { now.timeIntervalSince($0.startedAt) >= $0.duration }
    }

    private static func position(of track: Track, at now: Date) -> VisualPoint {
        let t = min(1, max(0, now.timeIntervalSince(track.startedAt) / track.duration))
        return VisualPoint(
            latitude: track.from.latitude + (track.to.latitude - track.from.latitude) * t,
            longitude: track.from.longitude + (track.to.longitude - track.from.longitude) * t
        )
    }
}
