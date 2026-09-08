import SwiftUI

/// Launch arguments, so every screen can be reached and screenshotted without
/// a GUI to tap in. `simctl` can launch and capture but cannot touch, so a
/// screen three taps deep is otherwise a screen nobody has actually looked at.
enum Demo {
    private static let d = UserDefaults.standard

    static var tab: RootTab {
        switch d.string(forKey: "demoTab") {
        case "explore": return .explore
        case "ask": return .ask
        case "passport": return .passport
        case "profile": return .profile
        default: return .home
        }
    }

    /// `-demoResetSession YES` — drop stored tokens before the phase is
    /// decided, so the sign-in screen is reachable on a simulator that has
    /// signed in before. The keychain survives a reinstall, so without this
    /// the auth screen cannot be reached at all.
    static var resetSession: Bool { d.bool(forKey: "demoResetSession") }

    /// `-demoEmail a@b.c -demoPassword ...` — sign in on launch against the
    /// real API. Not a fake phase override: a screenshot of a state the server
    /// cannot actually produce is not evidence of anything.
    static var credentials: (email: String, password: String)? {
        guard let email = d.string(forKey: "demoEmail"),
              let password = d.string(forKey: "demoPassword")
        else { return nil }
        return (email, password)
    }

    /// `-demoQuestion "why does a derivative represent slope"` — open Ask with
    /// the question already asked.
    static var question: String? { d.string(forKey: "demoQuestion") }

    /// `-demoSearch photosynthesis` — open Explore with results on screen.
    static var search: String? { d.string(forKey: "demoSearch") }

    /// Launch arguments live in UserDefaults for the whole process, so a
    /// `.task`-driven route re-fires every time its view reappears — i.e. on
    /// every back tap. A `static` flag, not `@State`, which a tab switch
    /// would reset.
    private static var fired = false
    static func once(_ body: () -> Void) {
        guard !fired else { return }
        fired = true
        body()
    }
}
