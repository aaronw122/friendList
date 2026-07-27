import Foundation
import Security

/// Tiny Keychain wrapper for the rotating refresh token and the client id.
/// Accessibility is `AfterFirstUnlock` so a background refresh works without an
/// interactive unlock. Writes are delete-then-add so they're idempotent.
enum Keychain {
    static let service = "com.friendlist.app"

    enum Account {
        static let refreshToken = "spotify.refreshToken"
        static let clientID = "spotify.clientID"
    }

    @discardableResult
    static func set(_ value: String, account: String) -> Bool {
        delete(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    @discardableResult
    static func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Client-id change invalidates the stored tokens — clear them so we force
    /// a fresh authorization against the new app.
    static func clearTokens() {
        delete(account: Account.refreshToken)
    }
}
