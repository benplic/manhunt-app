import Foundation

enum PlayerRole: String, Codable, Hashable, CaseIterable {
    case hider
    case seeker
    case unassigned
}

enum RoleAssigner {
    static func assign<R: RandomNumberGenerator>(
        playerIDs: [UUID],
        hiderCount: Int,
        using rng: inout R
    ) -> [UUID: PlayerRole] {
        guard !playerIDs.isEmpty else { return [:] }
        var shuffled = playerIDs
        shuffled.shuffle(using: &rng)
        let hiders = max(0, min(hiderCount, shuffled.count))
        var assigned: [UUID: PlayerRole] = [:]
        for (index, id) in shuffled.enumerated() {
            assigned[id] = index < hiders ? .hider : .seeker
        }
        return assigned
    }
}
