import Foundation

/// Locally blocked player ids (device-only; not synced to the server).
struct PlayerBlockList {
    private static let storageKey = "manhunt.blockedPlayerIds"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isBlocked(_ playerID: String) -> Bool {
        ids.contains(playerID)
    }

    mutating func block(_ playerID: String) {
        var next = ids
        next.insert(playerID)
        defaults.set(Array(next), forKey: Self.storageKey)
    }

    private var ids: Set<String> {
        Set(defaults.stringArray(forKey: Self.storageKey) ?? [])
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