import Foundation

enum PlayerRole: String, Codable, Hashable, CaseIterable {
    case hider
    case seeker
    case unassigned
}

enum RoleAssigner {
    static func assign<R: RandomNumberGenerator>(
        playerIDs: [UUID],
        seekerCount: Int,
        using rng: inout R
    ) -> [UUID: PlayerRole] {
        guard !playerIDs.isEmpty else { return [:] }
        var shuffled = playerIDs
        shuffled.shuffle(using: &rng)
        let seekers = max(0, min(seekerCount, shuffled.count))
        var assigned: [UUID: PlayerRole] = [:]
        for (index, id) in shuffled.enumerated() {
            assigned[id] = index < seekers ? .seeker : .hider
        }
        return assigned
    }
}
