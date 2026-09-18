import Foundation

/// Who this copy of the app is, independent of who is signed in.
///
/// Two questions the app could not answer before, and both of them decided
/// which screen a new user landed on:
///
/// * **Is this a fresh install?** The keychain SURVIVES deleting the app, so
///   a reinstall found a live refresh token and skipped straight into
///   somebody's session. `UserDefaults` does not survive, which makes the
///   absence of a marker there the only reliable "this is a new install"
///   signal available on iOS.
/// * **Which install is this?** Skip-login used to share one developer row
///   across every device and every reinstall, so a brand-new app opened on
///   the previous tester's profile, feed and "continue where you left off"
///   card. The id below is sent with the skip so each install gets its own
///   account — empty the first time, and the same one on every later launch.
///
/// The id is a random UUID: it is not derived from the hardware, so it
/// identifies an install and nothing about the person holding it.
struct InstallIdentity {
    let id: String
    let isFreshInstall: Bool

    private static let markerKey = "novi.installMarker"
    private static let keychainService = "luke.novi.app.tokens"
    private static let keychainAccount = "novi.install"

    /// Resolved once, before anything reads the stored session.
    private(set) nonisolated(unsafe) static var current = InstallIdentity(id: "", isFreshInstall: false)

    @discardableResult
    static func bootstrap(forceFresh: Bool = false) -> InstallIdentity {
        let defaults = UserDefaults.standard
        let fresh = forceFresh || defaults.string(forKey: markerKey) == nil

        if fresh {
            // Credentials from a previous install are not this install's to
            // use. Cleared here rather than in the session layer so the purge
            // happens before the first keychain read, not after it.
            Keychain.delete(service: keychainService, account: "novi.session")
            Keychain.delete(service: keychainService, account: keychainAccount)
        }

        let id: String
        if let existing = Keychain.read(service: keychainService, account: keychainAccount),
           let text = String(data: existing, encoding: .utf8),
           !text.isEmpty {
            id = text
        } else {
            id = UUID().uuidString
            Keychain.write(Data(id.utf8), service: keychainService, account: keychainAccount)
        }

        defaults.set(id, forKey: markerKey)
        current = InstallIdentity(id: id, isFreshInstall: fresh)
        return current
    }
}
