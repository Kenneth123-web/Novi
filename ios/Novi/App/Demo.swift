import SwiftUI

/// Launch arguments, so every screen can be reached and screenshotted without
/// a Simulator GUI to tap in. `xcrun simctl` can launch and capture but cannot
/// touch, so a screen that is three taps deep is otherwise unverifiable on this
/// machine — and an unverified screen is one nobody has actually looked at.
enum Demo {
    private static let d = UserDefaults.standard

    static var tab: RootTab {
        switch d.string(forKey: "demoTab") {
        case "market": return .market
        case "messages": return .messages
        case "me": return .me
        default: return .home
        }
    }

    static var lane: HomeTab? {
        switch d.string(forKey: "demoLane") {
        case "following": return .following
        case "nearby": return .nearby
        case "discover": return .discover
        default: return nil
        }
    }

    /// `-demoNote n5`, or `-demoNote first` for whichever note leads the lane.
    static var note: Note? {
        guard let id = d.string(forKey: "demoNote") else { return nil }
        let all = Fixtures.discover + Fixtures.following + Fixtures.nearby
        if id == "first" { return all.first }
        return all.first { $0.id == id }
    }

    static var publish: Bool { d.bool(forKey: "demoPublish") }

    /// `-demoSettings YES` opens the profile's settings sheet — the language
    /// picker lives there, and a sheet is otherwise unreachable for simctl.
    static var settings: Bool { d.bool(forKey: "demoSettings") }

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
