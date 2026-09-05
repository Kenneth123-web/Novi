import SwiftUI

/// The whole app is drawn from these values. Xiaohongshu's look is not a
/// palette so much as a *ratio*: one saturated red against a page that is
/// almost entirely neutral, and type that carries the hierarchy instead of
/// colour. Anything that adds a second accent breaks the impression.
enum NV {

    // MARK: Colour

    /// The one accent. Used for the active-tab underline, the compose button,
    /// badges, and a liked heart — and nowhere else.
    static let red = Color(hex: 0xFF2442)
    static let redDeep = Color(hex: 0xF01C39)

    /// Page behind the cards. Not white: the cards are white, and a white page
    /// under white cards collapses the masonry into one undifferentiated sheet.
    static let page = Color(hex: 0xF7F7F7)
    static let surface = Color.white

    /// Type ramp. XHS never runs body copy at pure black.
    static let ink = Color(hex: 0x333333)
    static let inkSoft = Color(hex: 0x666666)
    static let inkFaint = Color(hex: 0x999999)
    static let inkGhost = Color(hex: 0xBBBBBB)

    static let hairline = Color(hex: 0xEBEBEB)
    static let fill = Color(hex: 0xF2F2F2)

    // MARK: Metrics

    /// Feed geometry. The gutter is the same on the outside as it is between
    /// the columns, which is what makes the two columns read as one grid
    /// rather than as two lists.
    static let gutter: CGFloat = 6
    static let cardRadius: CGFloat = 8

    // MARK: Type

    static func title(_ size: CGFloat = 14.5) -> Font { .system(size: size, weight: .medium) }
    static func meta(_ size: CGFloat = 11.5) -> Font { .system(size: size, weight: .regular) }
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
    /// A 1-physical-pixel rule. `Divider()` is 1pt, which is three device
    /// pixels on a 3× screen and reads as a drawn line rather than a seam.
    func hairline(_ edge: Edge.Set = .bottom, color: Color = NV.hairline) -> some View {
        overlay(alignment: edge == .top ? .top : .bottom) {
            color.frame(height: 1 / UIScreen.main.scale)
        }
    }
}

/// Counts are printed the way the app prints them: 999 stays 999, 1000 becomes
/// 1.0万. 万 is a Chinese unit — in any other language the same count prints as
/// 10.0k, because showing 万 to a reader of English is showing them a wall, not
/// a number. Rounding down is deliberate — a card claiming more likes than the
/// note has is the one number on screen that would be false.
func nv_count(_ n: Int) -> String {
    switch AppLocalization.code {
    case "zh-Hans", "zh-Hant":
        if n < 10_000 { return "\(n)" }
        let w = Double(n) / 10_000
        let unit = AppLocalization.code == "zh-Hant" ? "萬" : "万"
        return String(format: w >= 100 ? "%.0f%@" : "%.1f%@", w, unit)
    default:
        if n < 1_000 { return "\(n)" }
        if n < 1_000_000 {
            let k = Double(n) / 1_000
            return String(format: k >= 100 ? "%.0fk" : "%.1fk", k)
        }
        let m = Double(n) / 1_000_000
        return String(format: m >= 100 ? "%.0fM" : "%.1fM", m)
    }
}
