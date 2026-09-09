import SwiftUI

/// Three drifting colour fields behind the launch and the welcome.
///
/// The opening is the only place in the app where the palette is allowed to
/// breathe, which is what makes it feel like an arrival rather than a screen.
/// Everywhere else the page is a flat near-white and the accent is rationed.
///
/// Positions are in unit space, so this lays out identically on every device
/// size — a blob pinned in points drifts off a small screen and sits in the
/// middle of a large one.
struct AuroraBackdrop: View {
    /// Held still under Reduce Motion. The gradient still reads; only the
    /// drift goes away.
    var animated = true
    var tints: [Color] = [NV.spark, NV.horizon, NV.ink200]
    /// How strongly the fields read. Loud behind a wordmark, quiet behind a
    /// form the user has to fill in.
    var strength: Double = 0.55

    @State private var drift = false

    private struct Blob {
        let size: CGFloat
        let start: CGPoint
        let end: CGPoint
        let period: Double
    }

    /// Positioned to FRAME the centre rather than flood the top. The first
    /// pass put the densest field behind the empty upper third, which read as
    /// a solid colour panel with a logo below it instead of light gathering
    /// around the mark.
    private let blobs: [Blob] = [
        Blob(size: 0.92, start: CGPoint(x: 0.08, y: 0.30),
             end: CGPoint(x: 0.26, y: 0.44), period: 12),
        Blob(size: 0.78, start: CGPoint(x: 0.94, y: 0.22),
             end: CGPoint(x: 0.78, y: 0.36), period: 15),
        Blob(size: 1.25, start: CGPoint(x: 0.52, y: 0.92),
             end: CGPoint(x: 0.34, y: 0.80), period: 18),
    ]

    var body: some View {
        GeometryReader { geo in
            let edge = max(geo.size.width, geo.size.height)
            ZStack {
                NV.page
                ForEach(Array(blobs.enumerated()), id: \.offset) { index, blob in
                    let colour = index < tints.count ? tints[index] : NV.ink200
                    let point = (animated && drift) ? blob.end : blob.start
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [colour.opacity(strength), colour.opacity(0)],
                                center: .center,
                                startRadius: 0,
                                endRadius: edge * blob.size / 2
                            )
                        )
                        .frame(width: edge * blob.size, height: edge * blob.size)
                        .position(x: geo.size.width * point.x, y: geo.size.height * point.y)
                        .animation(
                            .easeInOut(duration: blob.period).repeatForever(autoreverses: true),
                            value: drift
                        )
                }
            }
        }
        .ignoresSafeArea()
        .onAppear { if animated { drift = true } }
    }
}

/// The Novi mark: a concept graph that assembles itself.
///
/// The mark is the thesis, not decoration. The whole product is built on the
/// idea that scattered things connect into understanding, and the app's actual
/// data structure is a concept graph — so the mark draws scattered nodes and
/// then the edges between them. Anything more abstract would have been a
/// logo; this is the product's own shape.
///
/// `progress` is per-node so the caller drives the assembly beat by beat; the
/// edges follow their later endpoint, which is what makes the graph look like
/// it is being reasoned out rather than faded in.
struct BrandMark: View {
    /// 0...1 per node, in draw order.
    var progress: [Double]
    var size: CGFloat = 132
    var inkColour: Color = NV.ink900
    var accent: Color = NV.spark

    static let nodeCount = 6
    static let empty = Array(repeating: 0.0, count: nodeCount)
    static let filled = Array(repeating: 1.0, count: nodeCount)

    /// Unit-space positions. Node 0 is the hub and is drawn in the accent —
    /// the one point everything else connects through.
    private static let nodes: [CGPoint] = [
        CGPoint(x: 0.394, y: 0.439),   // hub
        CGPoint(x: 0.197, y: 0.727),
        CGPoint(x: 0.500, y: 0.167),
        CGPoint(x: 0.727, y: 0.561),
        CGPoint(x: 0.833, y: 0.273),
        CGPoint(x: 0.591, y: 0.818),
    ]

    private static let radii: [CGFloat] = [0.068, 0.042, 0.042, 0.049, 0.034, 0.034]

    /// (from, to). Each edge appears with its *later* node, so no line ever
    /// reaches toward a point that is not there yet.
    private static let edges: [(Int, Int)] = [
        (0, 1), (0, 2), (0, 3), (3, 4), (1, 5), (5, 3),
    ]

    private func amount(_ index: Int) -> Double {
        index < progress.count ? min(max(progress[index], 0), 1) : 0
    }

    var body: some View {
        Canvas { ctx, canvasSize in
            let s = min(canvasSize.width, canvasSize.height)
            func point(_ i: Int) -> CGPoint {
                CGPoint(x: Self.nodes[i].x * s, y: Self.nodes[i].y * s)
            }

            for (a, b) in Self.edges {
                let t = min(amount(a), amount(b))
                guard t > 0.01 else { continue }
                let from = point(a), to = point(b)
                let head = CGPoint(
                    x: from.x + (to.x - from.x) * t,
                    y: from.y + (to.y - from.y) * t
                )
                var path = Path()
                path.move(to: from)
                path.addLine(to: head)
                ctx.stroke(
                    path,
                    with: .color(inkColour.opacity(0.85)),
                    style: StrokeStyle(lineWidth: s * 0.012, lineCap: .round)
                )
            }

            for i in Self.nodes.indices {
                let t = amount(i)
                guard t > 0.01 else { continue }
                let r = Self.radii[i] * s * t
                let c = point(i)
                let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(i == 0 ? accent : inkColour))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
