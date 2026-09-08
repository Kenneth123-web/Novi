import Foundation
import OSLog
import Security

/// Where the refresh token lives.
///
/// Keychain, not `UserDefaults`: a refresh token is a long-lived bearer
/// credential, and `UserDefaults` is a plist in the app container that any
/// device backup carries away in the clear.
///
/// `AfterFirstUnlockThisDeviceOnly` — "after first unlock" so a background
/// refresh works with the screen locked, "this device only" so the token is
/// not restored onto a different phone from an iCloud backup.
struct TokenStore {
    private let service: String
    private let account = "novi.session"

    init(service: String = "luke.novi.app.tokens") {
        self.service = service
    }

    struct Stored: Codable, Equatable {
        var accessToken: String
        var refreshToken: String
        /// Absolute, not a duration: a stored duration says nothing after the
        /// app has been closed for a week.
        var accessExpiresAt: Date

        /// Treated as expired 30s early, so a token cannot lapse between the
        /// check here and the request arriving at the server.
        var isAccessValid: Bool { accessExpiresAt.timeIntervalSinceNow > 30 }
    }

    func load() -> Stored? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return try? JSONDecoder().decode(Stored.self, from: data)
    }

    private static let log = Logger(subsystem: "luke.novi.app", category: "keychain")

    /// Returns false when the credential was NOT persisted.
    ///
    /// Every failure is logged with its OSStatus. This returned `false`
    /// silently once already — an unsigned simulator build has no keychain
    /// entitlement, so every write failed and the app asked the user to sign
    /// in again on every launch, with nothing anywhere saying why.
    @discardableResult
    func save(_ stored: Stored) -> Bool {
        guard let data = try? JSONEncoder().encode(stored) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        // Update-then-add, not delete-then-add: deleting first leaves a window
        // where a concurrent read finds nothing and signs the user out.
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return true }
        if status != errSecItemNotFound {
            Self.log.error("keychain update failed: \(status)")
            return false
        }
        let added = SecItemAdd(query.merging(attributes) { a, _ in a } as CFDictionary, nil)
        if added != errSecSuccess {
            Self.log.error("keychain add failed: \(added)")
            return false
        }
        return true
    }

    func clear() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
    }
}
