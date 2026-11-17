import Foundation
import Security

/// Session JWTs live in the keychain, never UserDefaults.
struct KeychainStore {
    var service: String = "app.manhunt.ios"
    var accessAccount: String = "session"
    var refreshAccount: String = "refresh"
    var installationAccount: String = "installation"

    func saveToken(_ token: String) throws {
        try save(token, account: accessAccount)
    }

    func saveRefreshToken(_ token: String) throws {
        try save(token, account: refreshAccount)
    }

    func saveInstallationID(_ id: String) throws {
        try save(id, account: installationAccount)
    }

    func readToken() -> String? {
        read(account: accessAccount)
    }

    func readRefreshToken() -> String? {
        read(account: refreshAccount)
    }

    func readInstallationID() -> String? {
        read(account: installationAccount)
    }

    func deleteToken() {
        delete(account: accessAccount)
        delete(account: refreshAccount)
    }

    private func save(_ token: String, account: String) throws {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        // This device only, so an encrypted backup restore cannot clone the install id.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ServiceError(code: .internal, message: "Could not save the session.")
        }
    }

    private func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
