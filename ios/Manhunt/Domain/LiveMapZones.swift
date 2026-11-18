import Foundation

/// Filters arena + spawn-lock zones for the live map.
enum LiveMapZones {
    /// Seeker spawn polygons stay on the map only during head start
    /// (including spawn-lock emphasis). After that they drop.
    static func visible(
        liveZones: [VisualZone],
        spawnZones: [VisualZone],
        phase: MatchPhase,
        emphasizeSpawn: Bool
    ) -> [VisualZone] {
        let showSpawn = phase == .headStart || emphasizeSpawn
        let base = liveZones.filter { zone in
            zone.kind != .spawn || showSpawn
        }
        guard showSpawn else { return base }
        let extras = spawnZones.filter { spawn in
            !base.contains { existing in
                existing.id == spawn.id
                    || (existing.kind == spawn.kind
                        && existing.points == spawn.points
                        && existing.radiusMeters == spawn.radiusMeters)
            }
        }
        return base + extras
    }
}
