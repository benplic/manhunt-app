import Foundation

/// Stable per-install identity for Play / dev auth before Sign in with Apple.
/// Keychain-first so a UserDefaults backup restore cannot clone one phone onto another.
enum InstallationID {
    private static let defaultsKey = "manhunt.installation_id"

    /// Production path: Keychain, then migrate any legacy UserDefaults value, else mint.
    static func current(keychain: KeychainStore = KeychainStore()) -> String {
        if let existing = keychain.readInstallationID(), !existing.isEmpty {
            return existing
        }
        // One-time migrate from an older UserDefaults install id if present.
        let defaults = UserDefaults.standard
        if let legacy = defaults.string(forKey: defaultsKey), !legacy.isEmpty {
            try? keychain.saveInstallationID(legacy)
            defaults.removeObject(forKey: defaultsKey)
            return legacy
        }
        let created = UUID().uuidString
        try? keychain.saveInstallationID(created)
        return created
    }

    /// Test double: keeps identity in an isolated UserDefaults suite (no Keychain).
    static func current(defaults: UserDefaults) -> String {
        if let existing = defaults.string(forKey: defaultsKey), !existing.isEmpty {
            return existing
        }
        let created = UUID().uuidString
        defaults.set(created, forKey: defaultsKey)
        return created
    }
}
