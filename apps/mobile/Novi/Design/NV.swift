import SwiftUI

/// Every colour, space, radius and type step in the app.
///
/// One accent against a page that is almost entirely neutral. The hierarchy is
/// carried by type and spacing rather than by colour, which is what keeps a
/// content feed from looking like a dashboard — and what makes the single
/// accent mean something when it does appear.
enum NV {

    // MARK: Colour

    /// The one accent: the Ask button, an active tab, a selected chip, an
    /// earned stamp. Adding a second accent loses the whole impression.
    static let accent = Color(hex: 0x5B4BFF)
    static let accentDeep = Color(hex: 0x4938E8)
    static let accentSoft = Color(hex: 0xEEECFF)

    /// The page sits behind the cards. Not white: the cards are white, and
    /// white cards on a white page collapse the masonry into one flat sheet.
    static let page = Color(hex: 0xF6F6F8)
    static let surface = Color.white
    static let surfaceRaised = Color(hex: 0xFBFBFD)

    /// Type ramp. Body copy never runs at pure black — it vibrates against
    /// white and makes long explanations tiring to read.
    static let ink = Color(hex: 0x1A1A1F)
    static let inkSoft = Color(hex: 0x5A5A66)
    static let inkFaint = Color(hex: 0x8E8E9A)
    static let inkGhost = Color(hex: 0xC2C2CC)

    static let hairline = Color(hex: 0xE9E9EF)
    static let fill = Color(hex: 0xF1F1F5)
    static let track = Color(hex: 0xEAEAF0)

    /// Status. Never decorative — only on something that actually succeeded,
    /// warned, or failed.
    static let success = Color(hex: 0x18A957)
    static let warning = Color(hex: 0xE0850C)
    static let error = Color(hex: 0xE0323C)

    /// The mastery ladder, weak to strong. The learner sees this ramp on every
    /// concept row and every passport card, so it is defined once.
    static func mastery(_ state: String) -> Color {
        switch state {
        case "mastered": return Color(hex: 0x0F9D58)
        case "learned": return Color(hex: 0x35B37E)
        case "practiced": return Color(hex: 0x5B4BFF)
        case "explored": return Color(hex: 0x8E86FF)
        case "viewed": return Color(hex: 0xB9B4FF)
        default: return inkGhost
        }
    }

    // MARK: Metrics

    /// Feed geometry. The outside gutter matches the one between columns,
    /// which is what makes two columns read as one grid instead of two lists.
    static let gutter: CGFloat = 10

    /// The tab bar is drawn as an overlay above the tab content, so anything a
    /// screen pins to the bottom edge has to clear it explicitly. Defined once
    /// because getting it wrong hides a control completely rather than just
    /// misaligning it — which is exactly what happened to the Ask composer.
    static let tabBarHeight: CGFloat = 56

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let section: CGFloat = 40
    }

    enum Radius {
        static let card: CGFloat = 14
        static let control: CGFloat = 12
        static let chip: CGFloat = 999
        static let sheet: CGFloat = 24
    }

    // MARK: Type

    /// Seven steps. A heading that invents its own size is the fastest way for
    /// two screens to stop looking like the same product.
    static let display = Font.system(size: 32, weight: .bold)
    static let h1 = Font.system(size: 25, weight: .bold)
    static let h2 = Font.system(size: 20, weight: .semibold)
    static let h3 = Font.system(size: 16.5, weight: .semibold)
    static let body = Font.system(size: 15, weight: .regular)
    static let bodyStrong = Font.system(size: 15, weight: .medium)
    static let small = Font.system(size: 13, weight: .regular)
    static let caption = Font.system(size: 11.5, weight: .medium)

    /// The feed card's own sizes. Kept separate from the ramp because
    /// `ContentCard.height` computes its estimate from these exact values, and
    /// the masonry breaks if the two drift apart.
    static let cardTitle = Font.system(size: 14.5, weight: .medium)
    static let cardMeta = Font.system(size: 11.5, weight: .regular)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

extension View {
    /// A one-physical-pixel rule. `Divider()` is 1pt, which is three device
    /// pixels on a 3x screen and reads as a drawn line rather than a seam.
    func hairline(_ edge: Edge.Set = .bottom, color: Color = NV.hairline) -> some View {
        overlay(alignment: edge == .top ? .top : .bottom) {
            color.frame(height: 1 / UIScreen.main.scale)
        }
    }

    func cardSurface(_ radius: CGFloat = NV.Radius.card) -> some View {
        background(NV.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Counts print the way a feed prints them: 999 stays 999, 1000 becomes 1.0K.
/// Rounding down is deliberate — a card claiming more likes than the item has
/// is the one number on screen that would be false.
func nv_count(_ n: Int) -> String {
    if n < 1_000 { return "\(n)" }
    if n < 1_000_000 {
        let k = Double(n) / 1_000
        return String(format: k >= 100 ? "%.0fK" : "%.1fK", k)
    }
    return String(format: "%.1fM", Double(n) / 1_000_000)
}

/// Seconds as the duration badge on a video card.
func nv_duration(_ seconds: Int) -> String {
    let m = seconds / 60, s = seconds % 60
    return String(format: "%d:%02d", m, s)
}
