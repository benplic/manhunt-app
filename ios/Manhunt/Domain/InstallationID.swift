import Foundation

/// Stable per-install identity for Play / dev auth before Sign in with Apple.
enum InstallationID {
    private static let defaultsKey = "manhunt.installation_id"

    static func current(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: defaultsKey), !existing.isEmpty {
            return existing
        }
        let created = UUID().uuidString
        defaults.set(created, forKey: defaultsKey)
        return created
    }
}
