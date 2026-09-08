import SwiftUI

/// Covers and avatars are DRAWN, not fetched.
///
/// The content store holds no images yet, and the two honest ways to fill that
/// hole are a grey rectangle or a generated one. A grey rectangle reads as a
/// broken image, and a screen full of them says nothing about whether the
/// layout works. So every cover is a deterministic function of the item's id:
/// the same item draws the same picture on every launch and every device,
/// which is what lets the masonry read as a stable grid rather than as noise.
///
/// Nothing here calls `Date()` or `random()`. Either would re-roll the picture
/// on every scroll frame.
struct Seeded {
    private var state: UInt64

    init(_ seed: String) {
        var h: UInt64 = 0xcbf29ce484222325
        for b in seed.utf8 {
            h = (h ^ UInt64(b)) &* 0x100000001b3
        }
        state = h | 1
    }

    mutating func next() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state % 1_000_000) / 1_000_000
    }

    mutating func inRange(_ lo: Double, _ hi: Double) -> Double {
        lo + next() * (hi - lo)
    }

    mutating func pick<T>(_ xs: [T]) -> T {
        xs[Int(next() * Double(xs.count)) % xs.count]
    }
}

/// Muted, photographic pairs — dawn, moss, terracotta, slate. Saturated pairs
/// look like a colour picker; these look like something was photographed.
private let palettes: [[UInt32]] = [
    [0xE8D5C4, 0xC9A88A], [0xD6E4E5, 0x9BB8C4], [0xE4D9F0, 0xB3A0CC],
    [0xF0DFD8, 0xD5A79A], [0xDCE8D5, 0xA3BC8F], [0xF2E3C6, 0xD9BE86],
    [0xD8DEE9, 0x8FA0B8], [0xF0D9DE, 0xCC96A6], [0xE0E7E3, 0x9DB3AA],
    [0xEDE3D3, 0xBFA184], [0xD4E2EA, 0x89A6BC], [0xEAD9E8, 0xB08FA8],
    [0xE6E9D8, 0xAEB88C], [0xF4E0D0, 0xDFA98C], [0xDBD9EC, 0x9A96C4],
    [0xE9E2DA, 0xB5A695],
]

struct CoverArt: View {
    let seed: String

    var body: some View {
        Canvas { ctx, size in
            var rng = Seeded(seed)
            let pair = rng.pick(palettes)
            let top = Color(hex: pair[0])
            let bottom = Color(hex: pair[1])
            let angle = rng.next()

            ctx.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .linearGradient(
                    Gradient(colors: [top, bottom]),
                    startPoint: CGPoint(x: size.width * angle, y: 0),
                    endPoint: CGPoint(x: size.width * (1 - angle), y: size.height)
                )
            )

            // A ground plane, about half the time. This is what stops the set
            // reading as sixteen frosted rectangles: a photograph almost always
            // has a horizon or a table edge somewhere, and one soft division
            // across the frame is enough to imply it.
            if rng.next() > 0.45 {
                let y = size.height * rng.inRange(0.45, 0.82)
                var ground = ctx
                ground.addFilter(.blur(radius: size.height * rng.inRange(0.01, 0.05)))
                ground.fill(
                    Path(CGRect(x: -20, y: y, width: size.width + 40, height: size.height - y + 20)),
                    with: .linearGradient(
                        Gradient(colors: [
                            bottom.opacity(0.0),
                            Color(hex: pair[1]).opacity(rng.inRange(0.55, 0.9)),
                        ]),
                        startPoint: CGPoint(x: 0, y: y),
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )
            }

            // One near-focus form — the "subject". Blurred far less than the
            // rest, so the frame has a plane of interest instead of being
            // uniformly soft.
            let sr = rng.inRange(0.18, 0.40) * size.width
            let sx = rng.inRange(0.15, 0.85) * size.width
            let sy = rng.inRange(0.20, 0.75) * size.height
            var subject = ctx
            subject.addFilter(.blur(radius: sr * rng.inRange(0.08, 0.20)))
            subject.fill(
                Path(ellipseIn: CGRect(x: sx - sr, y: sy - sr * rng.inRange(0.7, 1.3),
                                       width: sr * 2, height: sr * 2)),
                with: .color((rng.next() > 0.45 ? Color.white : Color.black)
                    .opacity(rng.inRange(0.10, 0.26)))
            )

            // Two or three soft forms behind it. Enough to suggest a
            // background; more and it starts to look like a pattern.
            let blobs = Int(rng.inRange(2, 3.99))
            for i in 0..<blobs {
                let r = rng.inRange(0.22, 0.62) * size.width
                let cx = rng.inRange(-0.1, 1.1) * size.width
                let cy = rng.inRange(0.05, 1.0) * size.height
                let shade = rng.next() > 0.5 ? Color.white : Color.black
                let alpha = rng.inRange(0.06, 0.18) * (i == 0 ? 1.4 : 1)
                var blob = ctx
                blob.addFilter(.blur(radius: r * 0.42))
                blob.fill(
                    Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                    with: .color(shade.opacity(alpha))
                )
            }

            // A light from one corner. Photographs have a direction; flat
            // gradients do not.
            ctx.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .radialGradient(
                    Gradient(colors: [.white.opacity(0.30), .clear]),
                    center: CGPoint(x: size.width * rng.next(), y: size.height * rng.inRange(0, 0.4)),
                    startRadius: 0,
                    endRadius: size.width * 0.9
                )
            )
        }
        .background(NV.fill)
        .drawingGroup()
    }
}

/// Avatars follow the same rule, plus the one true thing we hold about the
/// person: the first character of the name they chose.
struct Avatar: View {
    let name: String
    var size: CGFloat = 16

    var body: some View {
        var rng = Seeded("avatar-" + name)
        let pair = rng.pick(palettes)
        return Circle()
            .fill(
                LinearGradient(
                    colors: [Color(hex: pair[0]), Color(hex: pair[1])],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay {
                Text(String(name.prefix(1)))
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }
    }
}
