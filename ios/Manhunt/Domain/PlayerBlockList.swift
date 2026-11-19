import Foundation

/// One locally blocked player. Names are the last known display name at block time.
struct BlockedPlayerEntry: Codable, Equatable, Identifiable {
    var id: String { playerId }
    var playerId: String
    var displayName: String
}

/// Confirmation payload before calling `AppStore.blockPlayer`.
struct PendingBlock: Identifiable, Equatable {
    var id: String
    var name: String
}

/// Locally blocked player ids (device-only; not synced to the server).
/// When in-game chat lands, messages from blocked ids must be hidden here too.
struct PlayerBlockList {
    private static let storageKey = "manhunt.blockedPlayerIds"
    private static let entriesKey = "manhunt.blockedPlayerEntries"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isBlocked(_ playerID: String) -> Bool {
        entries.contains { $0.playerId == playerID }
    }

    /// Stable public label: `Blocked Player #1`, `#2`, … by sorted id order.
    func anonymizedName(for playerID: String) -> String? {
        let ordered = entries.map(\.playerId).sorted()
        guard let index = ordered.firstIndex(of: playerID) else { return nil }
        return "Blocked Player #\(index + 1)"
    }

    /// Display name for lists/map: anonymized if blocked, otherwise `fallback`.
    func displayName(for playerID: String, fallback: String) -> String {
        anonymizedName(for: playerID) ?? fallback
    }

    var entries: [BlockedPlayerEntry] {
        migrateIfNeeded()
        guard let data = defaults.data(forKey: Self.entriesKey),
              let decoded = try? JSONDecoder().decode([BlockedPlayerEntry].self, from: data)
        else { return [] }
        return decoded
    }

    mutating func block(_ playerID: String, displayName: String) {
        var next = entries.filter { $0.playerId != playerID }
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        next.append(
            BlockedPlayerEntry(
                playerId: playerID,
                displayName: trimmed.isEmpty ? "Player" : trimmed
            )
        )
        save(next)
    }

    mutating func unblock(_ playerID: String) {
        save(entries.filter { $0.playerId != playerID })
    }

    private func save(_ next: [BlockedPlayerEntry]) {
        if let data = try? JSONEncoder().encode(next) {
            defaults.set(data, forKey: Self.entriesKey)
        }
        // Keep legacy id array in sync for older builds / tests mid-migration.
        defaults.set(next.map(\.playerId), forKey: Self.storageKey)
    }

    private func migrateIfNeeded() {
        if defaults.data(forKey: Self.entriesKey) != nil { return }
        let legacy = defaults.stringArray(forKey: Self.storageKey) ?? []
        guard !legacy.isEmpty else { return }
        let migrated = legacy.map {
            BlockedPlayerEntry(playerId: $0, displayName: "Player")
        }
        if let data = try? JSONEncoder().encode(migrated) {
            defaults.set(data, forKey: Self.entriesKey)
        }
    }
}

enum PlayerReportMail {
    static func url(gameID: UUID, playerID: UUID, displayName: String, supportEmail: String?) -> URL? {
        guard let supportEmail, !supportEmail.isEmpty else { return nil }
        let body = """
        game_id: \(gameID.uuidString)
        player_id: \(playerID.uuidString)
        display_name: \(displayName)
        """
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Manhunt player report"),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }
}
