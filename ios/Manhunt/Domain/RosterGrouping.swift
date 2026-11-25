import Foundation

/// Leaderboard grouping: Seekers, Hiders, and (lobby only) players with no team yet.
/// Rank is overall and survives grouping, so a hider ranked 2nd still shows "2".
/// Roles already reach every viewer in the roster rows, so this widens nothing.
/// Mirror of web/src/game/roster.ts.
enum RosterGrouping {
    enum SectionID: String, Equatable {
        case seekers, hiders, unassigned

        var title: String {
            switch self {
            case .seekers: "Seekers"
            case .hiders: "Hiders"
            case .unassigned: "Not on a team yet"
            }
        }
    }

    struct Row: Equatable, Identifiable {
        var player: PlayerDTO
        var rank: Int
        var points: Int
        /// A hider who was tagged and now hunts. Shown with a small "tagged" marker.
        var tagged: Bool
        var id: UUID { player.playerId }
    }

    struct Section: Equatable, Identifiable {
        var id: SectionID
        var rows: [Row]
        var title: String { id.title }
    }

    static func points(of player: PlayerDTO) -> Int {
        player.pointsEarned ?? player.points ?? 0
    }

    private static func section(for role: PlayerRole) -> SectionID {
        switch role {
        case .seeker: .seekers
        case .hider: .hiders
        case .unassigned: .unassigned
        }
    }

    /// Competition ranking: equal points share a rank and the next rank skips ("1, 1, 3").
    static func rank(_ players: [PlayerDTO]) -> [Row] {
        let sorted = players.sorted { left, right in
            let difference = points(of: left) - points(of: right)
            if difference != 0 { return difference > 0 }
            // Explicit tie-break so rows do not shuffle between refreshes.
            return left.playerId.uuidString.lowercased() < right.playerId.uuidString.lowercased()
        }
        var rows: [Row] = []
        for (index, player) in sorted.enumerated() {
            let earned = points(of: player)
            var rank = index + 1
            if let previous = rows.last, previous.points == earned {
                rank = previous.rank
            }
            rows.append(
                Row(
                    player: player,
                    rank: rank,
                    points: earned,
                    tagged: player.convertedFromHider && player.role == .seeker
                )
            )
        }
        return rows
    }

    /// Empty sections are dropped, so a lobby with nobody unassigned shows two headers.
    static func group(_ players: [PlayerDTO]) -> [Section] {
        let ranked = rank(players)
        return [SectionID.seekers, .hiders, .unassigned].compactMap { id in
            let rows = ranked.filter { section(for: $0.player.role) == id }
            return rows.isEmpty ? nil : Section(id: id, rows: rows)
        }
    }

    static func statusNote(_ status: PlayerStatus) -> String? {
        switch status {
        case .eliminated: "Out"
        case .signalLost: "Dark"
        case .active: nil
        }
    }
}
