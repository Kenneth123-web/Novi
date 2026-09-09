import SwiftUI

/// The controls every screen is built from. Written once, because the
/// alternative — each screen rolling its own button — is how two screens stop
/// looking like the same app.

struct NVButton: View {
    enum Kind { case primary, accent, secondary, quiet }

    let title: String
    var icon: String?
    var kind: Kind = .primary
    var loading = false
    var enabled = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // The label stays in the layout while loading, so the button
                // does not change width under the user's finger.
                HStack(spacing: NV.Space.s) {
                    if let icon { Image(systemName: icon).font(.system(size: 15, weight: .semibold)) }
                    Text(title)
                }
                .opacity(loading ? 0 : 1)

                if loading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(kind == .secondary || kind == .quiet ? NV.ink : .white)
                }
            }
            .font(NV.h3)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(background, in: RoundedRectangle(cornerRadius: NV.Radius.control,
                                                         style: .continuous))
            .overlay {
                if kind == .secondary {
                    RoundedRectangle(cornerRadius: NV.Radius.control, style: .continuous)
                        .stroke(NV.hairline, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!enabled || loading)
        .animation(.easeOut(duration: 0.15), value: loading)
        .animation(.easeOut(duration: 0.15), value: enabled)
    }

    /// Disabled is its own pair of colours, not the enabled pair at reduced
    /// opacity. A translucent button reads as a pale button with pale text on
    /// it: it fails contrast and still looks pressable.
    private var foreground: Color {
        guard enabled else { return NV.inkGhost }
        switch kind {
        case .primary, .accent: return .white
        case .secondary: return NV.ink
        case .quiet: return NV.spark
        }
    }

    /// Primary is near-black, not the accent. The accent is reserved for the
    /// places the product is doing something for you — Ask, an active state,
    /// an earned stamp — and putting it on every button is exactly what makes
    /// an accent stop meaning anything.
    private var background: Color {
        guard enabled else { return kind == .quiet ? .clear : NV.fill }
        switch kind {
        case .primary: return NV.ink900
        case .accent: return NV.spark
        case .secondary: return NV.surface
        case .quiet: return .clear
        }
    }
}

struct NVField: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""
    var secure = false
    var error: String?
    var contentType: UITextContentType?
    var keyboard: UIKeyboardType = .default
    var submitLabel: SubmitLabel = .next
    var onSubmit: () -> Void = {}

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: NV.Space.xs) {
            Text(title)
                .font(NV.caption)
                .foregroundStyle(NV.inkTertiary)

            Group {
                if secure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .font(NV.body)
            .foregroundStyle(NV.ink)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textContentType(contentType)
            .keyboardType(keyboard)
            .submitLabel(submitLabel)
            .focused($focused)
            .onSubmit(onSubmit)
            .padding(.horizontal, NV.Space.l - 2)
            .frame(height: 52)
            // White with a drawn edge, not a grey fill. A fill has no edge of
            // its own, so on any tinted backdrop it stops reading as a control
            // at all — which is what happened over the sign-in aurora.
            .background(NV.surface, in: RoundedRectangle(cornerRadius: NV.Radius.control,
                                                         style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: NV.Radius.control, style: .continuous)
                    .strokeBorder(strokeColour, lineWidth: focused || error != nil ? 1.5 : 1)
            }

            // The row appears only when there is a message. An empty 16pt gap
            // under every field reads as a layout bug on a form with five.
            if let error {
                Text(error)
                    .font(NV.caption)
                    .foregroundStyle(NV.error)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: error)
        .animation(.easeOut(duration: 0.15), value: focused)
    }

    private var strokeColour: Color {
        if error != nil { return NV.error.opacity(0.7) }
        return focused ? NV.spark.opacity(0.55) : NV.hairline
    }
}

/// Multi-select chip. The selected state is a fill, not a border: across a
/// twenty-chip grid a 1pt outline is not a state you can see at a glance.
struct NVChip: View {
    let text: String
    var icon: String?
    let selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 12, weight: .medium))
                }
                Text(text).font(selected ? NV.bodyStrong : NV.body)
            }
            .foregroundStyle(selected ? .white : NV.ink)
            .padding(.horizontal, NV.Space.l)
            .padding(.vertical, 10)
            .background(selected ? NV.spark : NV.fill,
                        in: RoundedRectangle(cornerRadius: NV.Radius.pill, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: selected)
    }
}

/// A small non-interactive label: a platform, a concept, a mastery state.
struct NVTag: View {
    let text: String
    var icon: String?
    var tint: Color = NV.inkSecondary
    var filled = false

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 9.5, weight: .semibold)) }
            Text(text).font(NV.caption)
        }
        .foregroundStyle(filled ? .white : tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            filled ? tint : tint.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
    }
}

/// Inline, non-blocking error. An alert would take the user out of whatever
/// they were doing to fix.
struct NVErrorNote: View {
    let message: String
    var icon: String = "exclamationmark.circle.fill"
    var tint: Color = NV.error
    var retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: NV.Space.s) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(tint)
            Text(message)
                .font(NV.small)
                .foregroundStyle(NV.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let retry {
                Button("Retry", action: retry)
                    .font(NV.small.weight(.semibold))
                    .foregroundStyle(tint)
            }
        }
        .padding(NV.Space.m)
        .background(tint.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: NV.Radius.control, style: .continuous))
    }
}

/// Every major screen needs one. An empty list with nothing in it is the most
/// common way an app looks broken.
struct NVEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: NV.Space.m) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(NV.inkGhost)
            Text(title)
                .font(NV.h3)
                .foregroundStyle(NV.ink)
            Text(message)
                .font(NV.small)
                .foregroundStyle(NV.inkTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(NV.bodyStrong)
                    .foregroundStyle(NV.spark)
                    .padding(.top, NV.Space.xs)
            }
        }
        .padding(.horizontal, NV.Space.section)
        .frame(maxWidth: .infinity)
    }
}

/// Segmented progress. Preferred over a percentage because onboarding's honest
/// promise is "five questions", and a bar at 40% does not say how many are left.
struct NVStepBar: View {
    let step: Int
    let total: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? NV.spark : NV.track)
                    .frame(height: 3)
            }
        }
        .animation(.easeOut(duration: 0.2), value: step)
        .accessibilityElement()
        .accessibilityLabel("Step \(step + 1) of \(total)")
    }
}

struct NVProgressBar: View {
    let value: Double
    var tint: Color = NV.spark
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(NV.track)
                Capsule()
                    .fill(tint)
                    // Clamped: a value outside 0...1 would draw past the track.
                    .frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.3), value: value)
    }
}

/// Section header used across Home, Ask and Passport.
struct NVSectionHeader: View {
    let title: String
    var subtitle: String?
    var action: (title: String, run: () -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(NV.h2).foregroundStyle(NV.ink)
                if let subtitle {
                    Text(subtitle).font(NV.small).foregroundStyle(NV.inkTertiary)
                }
            }
            Spacer(minLength: NV.Space.s)
            if let action {
                Button(action.title, action: action.run)
                    .font(NV.small.weight(.semibold))
                    .foregroundStyle(NV.spark)
            }
        }
    }
}

/// Placeholder shimmer. Shown instead of a spinner wherever the shape of what
/// is loading is already known — it makes the wait feel like the page arriving
/// rather than the app hanging.
struct NVSkeleton: View {
    var height: CGFloat = 14
    var width: CGFloat? = nil
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(NV.fill)
            .frame(width: width, height: height)
            .overlay {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, NV.surface.opacity(0.85), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.5)
                    .offset(x: phase * geo.size.width * 1.5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .onAppear {
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}
