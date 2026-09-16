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

    /// `-demoSkipLogin YES` — `POST /auth/dev-skip` against the real API and
    /// land in the product as the reserved developer account. A screenshot of
    /// a state the server cannot produce is not evidence of anything.
    static var skipLogin: Bool { d.bool(forKey: "demoSkipLogin") }

    /// `-demoQuestion "why does a derivative represent slope"` — open Ask with
    /// the question already asked.
    static var question: String? { d.string(forKey: "demoQuestion") }

    /// `-demoSearch photosynthesis` — open Explore with results on screen.
    static var search: String? { d.string(forKey: "demoSearch") }

    /// `-demoHoldIntro YES` — run the opening and then STOP on its finished
    /// frame instead of handing off. The sequence is under two seconds, which
    /// is shorter than a `simctl` screenshot round trip, so without this the
    /// opening is the one screen that cannot be captured.
    static var holdIntro: Bool { d.bool(forKey: "demoHoldIntro") }

    /// `-demoSkipIntro YES` — go straight past the opening animation.
    /// Without it every automated screenshot catches the intro rather than
    /// the screen it was aimed at.
    static var skipIntro: Bool { d.bool(forKey: "demoSkipIntro") }

    /// Launch arguments live in UserDefaults for the whole process, so a
    /// `.task`-driven route re-fires every time its view reappears — i.e. on
    /// every back tap. `static`, not `@State`, which a tab switch would reset.
    ///
    /// Keyed, because there is more than one of these. A single shared latch
    /// meant whichever screen's `.task` ran first consumed it and the other
    /// never fired at all — `-demoSearch` and `-demoQuestion` could not both
    /// work, and neither could be relied on alone.
    private static var fired: Set<String> = []
    static func once(_ key: String, _ body: () -> Void) {
        guard !fired.contains(key) else { return }
        fired.insert(key)
        body()
    }
}
