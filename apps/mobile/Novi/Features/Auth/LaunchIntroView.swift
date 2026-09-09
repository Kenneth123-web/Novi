import SwiftUI

/// The opening.
///
/// Six nodes appear one at a time and the edges between them draw themselves,
/// then the wordmark wipes in. The mark is the product's own data structure —
/// scattered things connecting — so the animation is the thesis rather than a
/// logo reveal.
///
/// Timings follow the launch-animation convention: the mark is legible at
/// ~0.9s and the whole thing hands off at ~2.0s. Longer than that and it stops
/// being an introduction and starts being a wait. Tapping anywhere skips it,
/// and Reduce Motion collapses it to a still frame with a short hold.
struct LaunchIntroView: View {
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var nodes = BrandMark.empty
    @State private var markScale: CGFloat = 0.92
    @State private var haloScale: CGFloat = 0.55
    @State private var haloOpacity: Double = 0
    @State private var wordReveal: CGFloat = 0
    @State private var wordLift: CGFloat = 14
    @State private var taglineOpacity: Double = 0
    @State private var exiting = false
    @State private var finished = false

    /// One place to tune the sequence. Seconds from appear.
    private enum Beat {
        static let firstNode = 0.05
        static let nodeStagger = 0.085
        static let nodeDraw = 0.62
        static let lockIn = 0.80
        static let wordmark = 0.94
        static let tagline = 1.20
        // The wipe finishes around 1.5. Exit shortly after rather than holding
        // a finished frame: this plays on every launch, so dead time at the end
        // is the most expensive time in the sequence.
        static let exit = 1.70
        static let handoff = 2.00

        static let staticHold = 0.75
        static let staticHandoff = 1.05
    }

    private let markSize: CGFloat = 132

    var body: some View {
        ZStack {
            AuroraBackdrop(animated: !reduceMotion, strength: 0.62)

            VStack(spacing: NV.Space.xl) {
                mark
                VStack(spacing: 10) {
                    wordmark
                    Text("The internet, as your classroom")
                        .font(NV.body)
                        .foregroundStyle(NV.inkSecondary)
                        .opacity(taglineOpacity)
                }
            }
            .padding(.horizontal, NV.pageMargin)
            .padding(.bottom, NV.Space.section)
        }
        // Full-window from frame 0. A content-sized first pass interpolates
        // into a full-screen stretch as the system launch screen lifts.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NV.page)
        .ignoresSafeArea()
        // The destination is already rendered underneath, so fading the whole
        // overlay reveals real content continuously instead of exposing the
        // window's white base for a frame.
        .opacity(exiting ? 0 : 1)
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .accessibilityElement()
        .accessibilityLabel("Novi")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double tap to skip")
        .task { await run() }
    }

    private var mark: some View {
        ZStack {
            // A single outward pulse at the moment the graph closes — the
            // "it connected" beat. One ring, once; a repeating pulse would
            // turn the mark into a loading spinner.
            Circle()
                .strokeBorder(NV.spark.opacity(0.45), lineWidth: 1.5)
                .frame(width: markSize * 1.16, height: markSize * 1.16)
                .scaleEffect(haloScale)
                .opacity(haloOpacity)

            BrandMark(progress: nodes, size: markSize)
        }
        .scaleEffect(markScale)
    }

    private var wordmark: some View {
        Text("Novi")
            .displayStyle(52, weight: .semibold)
            .foregroundStyle(NV.ink)
            // Wiped in behind a soft edge rather than animated per letter:
            // splitting the word into characters drops the kerning, which at
            // display size is immediately visible.
            .mask(alignment: .leading) {
                GeometryReader { geo in
                    Rectangle()
                        // Extended past BOTH edges. The lead-in keeps the blur
                        // off the first letter; the 1.35 overshoot carries the
                        // travelling edge clear of the last one, which
                        // otherwise finishes half-dissolved — a pale streak
                        // through the "i" that looks like a rendering fault.
                        .frame(width: 40 + geo.size.width * wordReveal * 1.35)
                        .offset(x: -40)
                        .blur(radius: 7)
                }
            }
            .offset(y: wordLift)
            .opacity(wordReveal > 0 ? 1 : 0)
    }

    private func run() async {
        if Demo.skipIntro {
            finish()
            return
        }

        guard !reduceMotion else {
            nodes = BrandMark.filled
            markScale = 1
            wordReveal = 1
            wordLift = 0
            taglineOpacity = 1
            guard await sleep(Beat.staticHold) else { return }
            withAnimation(.easeOut(duration: 0.28)) { exiting = true }
            guard await sleep(Beat.staticHandoff - Beat.staticHold) else { return }
            finish()
            return
        }

        // Each node on its own clock. The stagger is what makes them read as
        // separate ideas arriving rather than one logo appearing.
        for index in 0..<BrandMark.nodeCount {
            let delay = Beat.firstNode + Double(index) * Beat.nodeStagger
            withAnimation(
                .spring(response: Beat.nodeDraw, dampingFraction: 0.76).delay(delay)
            ) {
                nodes[index] = 1
            }
        }
        withAnimation(.spring(response: 0.9, dampingFraction: 0.85).delay(Beat.firstNode)) {
            markScale = 1
        }

        guard await sleep(Beat.lockIn) else { return }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.5)) { markScale = 1.035 }
        withAnimation(.easeOut(duration: 0.7)) {
            haloScale = 1.5
            haloOpacity = 0.9
        }
        withAnimation(.easeOut(duration: 0.45).delay(0.25)) { haloOpacity = 0 }

        guard await sleep(Beat.wordmark - Beat.lockIn) else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) { markScale = 1 }
        withAnimation(.easeOut(duration: 0.55)) { wordReveal = 1 }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) { wordLift = 0 }

        guard await sleep(Beat.tagline - Beat.wordmark) else { return }
        withAnimation(.easeOut(duration: 0.45)) { taglineOpacity = 1 }

        if Demo.holdIntro { return }

        guard await sleep(Beat.exit - Beat.tagline) else { return }
        withAnimation(.easeIn(duration: 0.3)) { exiting = true }

        guard await sleep(Beat.handoff - Beat.exit) else { return }
        finish()
    }

    /// `try? await Task.sleep` returns normally when cancelled, so every caller
    /// would run its next beat immediately on teardown. Reporting cancellation
    /// lets `run()` fall out instead.
    private func sleep(_ seconds: Double) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return true
        } catch {
            return false
        }
    }

    /// Idempotent: tap-to-skip and the timeline both land here.
    private func finish() {
        guard !finished else { return }
        finished = true
        onFinished()
    }
}
