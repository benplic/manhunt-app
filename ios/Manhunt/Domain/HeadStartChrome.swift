import Foundation

/// What a seeker sees during head start. `locked_map` covers the map.
/// `spawn_zone` leaves the map up and strokes the spawn polygon.
enum HeadStartChrome {
    enum Kind: Equatable {
        case fullMap
        case spawnZone
        case none
    }

    static func kind(phase: MatchPhase, role: PlayerRole, seekerLock: String?) -> Kind {
        guard phase == .headStart, role == .seeker else { return .none }
        if seekerLock == "spawn_zone" { return .spawnZone }
        return .fullMap
    }
}
