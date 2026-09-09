import SwiftUI
import UIKit  // UIFont, to ask whether the bundled face registered

/// The Novi design system.
///
/// The structure is deliberately borrowed from Travelers: a long neutral ink
/// scale carries the hierarchy, one accent appears rarely, and the page is a
/// near-white that is not the card white. What it does NOT borrow is the
/// palette — sage and lime are Travelers' identity.
///
/// The rule that keeps this from looking like every other AI product: the
/// accent is not the button colour. Primary actions are near-black. Violet is
/// reserved for the three places where the product is doing something *for*
/// you — Ask, an active state, an earned stamp — which is what makes it read
/// as meaning rather than decoration.
enum NV {

    // MARK: Ink scale

    static let ink50 = Color(hex: 0xF6F6F8)
    static let ink100 = Color(hex: 0xECEEF1)
    static let ink200 = Color(hex: 0xDEE1E7)
    static let ink300 = Color(hex: 0xB0B5BF)
    static let ink400 = Color(hex: 0x868C97)
    static let ink500 = Color(hex: 0x6A707A)
    static let ink700 = Color(hex: 0x474C55)
    static let ink800 = Color(hex: 0x32363D)
    static let ink900 = Color(hex: 0x1B1E23)
    static let ink950 = Color(hex: 0x121418)

    // MARK: Accent

    /// The one accent. Ask, an active tab, a selected chip, an earned stamp —
    /// and nowhere else. A second accent, or this one on every button, and the
    /// whole "rare enough to mean something" effect is gone.
    static let spark = Color(hex: 0x5B4BFF)
    static let sparkDeep = Color(hex: 0x4938E8)
    static let sparkSoft = Color(hex: 0xEAE7FF)
    /// The aurora's companion field. Never used as an ink or a fill on its own.
    static let horizon = Color(hex: 0x2D6BFF)

    // MARK: Semantic

    static let page = ink50
    static let surface = Color.white
    /// Cards sit on the page; the page is not white, or the masonry collapses
    /// into one undifferentiated sheet.
    static let surfaceSoft = ink100

    static let ink = ink900
    static let inkSecondary = ink500
    static let inkTertiary = ink400
    static let inkGhost = ink300

    static let hairline = Color(red: 27 / 255, green: 30 / 255, blue: 35 / 255, opacity: 0.08)
    static let hairlineStrong = Color(red: 27 / 255, green: 30 / 255, blue: 35 / 255, opacity: 0.16)
    static let fill = ink100
    static let track = ink100

    static let success = Color(hex: 0x0F9D58)
    static let warning = Color(hex: 0xE0850C)
    static let error = Color(hex: 0xD93A45)

    /// The mastery ladder, weak to strong. Every concept row and passport card
    /// reads this ramp, so it is defined once.
    static func mastery(_ state: String) -> Color {
        switch state {
        case "mastered": return success
        case "learned": return Color(hex: 0x35B37E)
        case "practiced": return spark
        case "explored": return Color(hex: 0x8E86FF)
        case "viewed": return Color(hex: 0xB9B4FF)
        default: return inkGhost
        }
    }

    // MARK: Metrics

    /// Two densities, on purpose.
    ///
    /// ARRIVAL screens — launch, sign-in, onboarding, the passport cover —
    /// have nothing to scan, so they run at the page margin and the type goes
    /// large. BROWSE screens — the feed, search results, saved — exist to get
    /// as much real content in front of the eye as it will hold, so they drop
    /// to the gutter and the card title falls a step. Rednote's grid is the
    /// reference for the second number: at a 21pt margin a two-column feed
    /// wastes about a sixth of the screen on nothing.
    static let pageMargin: CGFloat = 21
    static let gutter: CGFloat = 8

    /// The tab bar is drawn as an overlay above the tab content, so anything a
    /// screen pins to the bottom edge has to clear it explicitly. Defined once
    /// because getting it wrong hides a control completely rather than just
    /// misaligning it.
    static let tabBarHeight: CGFloat = 62

    /// Fibonacci. The integer approximation of φ, so the spacing scale and
    /// the type scale are the same system expressed two ways.
    enum Space {
        static let xs: CGFloat = 5
        static let s: CGFloat = 8
        static let m: CGFloat = 13
        static let l: CGFloat = 21
        static let xl: CGFloat = 34
        static let xxl: CGFloat = 55
        static let section: CGFloat = 55
    }

    /// Also Fibonacci. `card` is deliberately smaller than it was: at an 8pt
    /// gutter a 21pt radius eats most of the gap between two cards and the
    /// grid stops reading as a grid.
    enum Radius {
        static let hero: CGFloat = 21
        static let card: CGFloat = 13
        static let control: CGFloat = 13
        static let thumb: CGFloat = 13
        static let sheet: CGFloat = 34
        static let pill: CGFloat = 999
    }

    // MARK: Type
    //
    // Instrument Sans is bundled (SIL Open Font License). `Font.custom` falls
    // back to the system face silently if registration ever fails, so the app
    // degrades to a different typeface rather than crashing — but the ramp
    // would shift, so `fontIsAvailable` lets a debug build notice.

    private static let family = "Instrument Sans"

    static var fontIsAvailable: Bool {
        UIFont(name: family, size: 12) != nil
    }

    /// The golden ratio, and the type scale built on it.
    ///
    /// `size(n) = 15 × φ^(n/6)`. Sixths rather than whole steps because a full
    /// φ jump between adjacent sizes is far too coarse for a UI ramp — but
    /// every SIXTH step is still an exact golden multiple of the body size, so
    /// 15 → 24.27 → 39.27 are φ, φ² apart. The scale is genuinely golden at
    /// the intervals that carry the hierarchy, and usable in between.
    ///
    /// Spacing is Fibonacci (5, 8, 13, 21, 34, 55), which is the integer
    /// approximation of the same ratio — so type and space agree without
    /// either being bent to fit the other.
    static let phi: CGFloat = 1.618_033_988_749_895
    static let typeBase: CGFloat = 15

    static func size(_ step: CGFloat) -> CGFloat {
        typeBase * pow(phi, step / 6)
    }

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(family, size: size).weight(weight)
    }

    /// A step on the scale, as a font.
    static func step(_ n: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        font(size(n), weight)
    }

    /// Named steps. The number beside each is what the scale returns.
    static func display(_ n: CGFloat = 12, _ weight: Font.Weight = .semibold) -> Font {
        step(n, weight)
    }

    static var hero: Font { step(16, .semibold) }        // 54.12 — wordmark
    static var h1: Font { step(8, .semibold) }           // 28.49
    static var h1Small: Font { step(6, .semibold) }      // 24.27 = 15φ
    static var h2: Font { step(4, .semibold) }           // 20.67
    static var h3: Font { step(2, .semibold) }           // 17.61
    static var body: Font { step(0) }                    // 15.00
    static var bodyStrong: Font { step(0, .medium) }
    static var small: Font { step(-2) }                  // 12.78
    static var smallStrong: Font { step(-2, .medium) }
    static var caption: Font { step(-4, .medium) }       // 10.88

    /// The feed card's own step. Kept named because `ContentCard.height`
    /// computes its estimate from this exact value and the masonry breaks if
    /// the two drift apart.
    static let cardTitleSize: CGFloat = size(-1)         // 13.84
    static var cardTitle: Font { font(cardTitleSize, .medium) }
    static var cardMeta: Font { step(-4) }

    /// Optical tracking. Large type set at default tracking looks loose, and
    /// small type set tight closes up — so the correction is a curve, not a
    /// constant: negative above the body size, slightly positive below it.
    static func tracking(_ size: CGFloat) -> CGFloat {
        size >= typeBase ? size * -0.028 : size * 0.008
    }
}

// MARK: - Primitives

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

    /// The card surface: white, rounded, and lifted by two shadows rather than
    /// one. A single soft shadow reads as blur; a tight contact shadow plus a
    /// wide ambient one is what makes a card look like it is resting on the
    /// page rather than floating above a photograph of it.
    func cardSurface(_ radius: CGFloat = NV.Radius.card) -> some View {
        background(NV.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: NV.ink900.opacity(0.04), radius: 1, x: 0, y: 1)
            .shadow(color: NV.ink900.opacity(0.05), radius: 12, x: 0, y: 8)
    }

    /// A flat surface with a drawn edge — for controls and rows, where a
    /// shadow on every element would turn the page into a pile.
    func edgedSurface(_ radius: CGFloat = NV.Radius.control) -> some View {
        background(NV.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(NV.hairline, lineWidth: 1)
            }
    }

    /// A step on the golden scale, with its optical tracking applied.
    /// Takes a STEP, not a point size — the whole point of the scale is that
    /// no screen picks its own numbers.
    func displayStyle(_ step: CGFloat, weight: Font.Weight = .semibold) -> some View {
        let size = NV.size(step)
        return font(NV.font(size, weight))
            .tracking(NV.tracking(size))
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

func nv_duration(_ seconds: Int) -> String {
    let m = seconds / 60, s = seconds % 60
    return String(format: "%d:%02d", m, s)
}
