import SwiftUI

/// The passport as one tall image, for sending to someone who will look at it
/// in a chat and never open a link.
///
/// Deliberately NOT a screenshot of the Passport screen: that screen is a
/// scroll with a tab bar on it, so a capture shows a fraction of the record
/// and a lot of chrome. This lays out the whole thing at once — cover, every
/// stamp, every subject — drops the navigation, and is sized to be readable at
/// thumbnail size in a message list.
///
/// The idea is lifted from Travelers' trip poster. It earns its place here for
/// the same reason it did there: the app's most personal artefact is the one
/// thing a user would actually want to show somebody, and a link they have to
/// open is a link they do not open.
struct PassportPoster: View {
    let passport: PassportDTO
    let name: String

    /// Fixed width so the layout is identical whatever device renders it —
    /// a poster that reflows per screen is a screenshot with extra steps.
    static let width: CGFloat = 720

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 128, maximum: 200), spacing: NV.Space.l)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cover

            VStack(alignment: .leading, spacing: NV.Space.xl) {
                if !passport.stamps.isEmpty { stamps }
                if !passport.subjectCards.isEmpty { subjects }
                footer
            }
            .padding(.horizontal, NV.Space.xl)
            .padding(.vertical, NV.Space.xl)
        }
        .frame(width: Self.width)
        .background(NV.page)
    }

    private var cover: some View {
        VStack(alignment: .leading, spacing: NV.Space.l) {
            Text("LEARNING PASSPORT")
                .font(.system(size: 15, weight: .bold))
                .tracking(3.2)
                .foregroundStyle(.white.opacity(0.55))

            Text(name)
                .font(NV.font(52, .semibold))
                .tracking(NV.tracking(52))
                .foregroundStyle(.white)

            Rectangle().fill(.white.opacity(0.14)).frame(height: 1)

            HStack(spacing: 0) {
                posterStat("\(passport.conceptsCovered)", "CONCEPTS")
                posterStat("\(passport.conceptsLearned)", "LEARNED")
                posterStat("\(passport.subjects)", "SUBJECTS")
                posterStat("\(passport.sessions)", "SESSIONS")
            }
        }
        .padding(NV.Space.xl + NV.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    colors: [Color(hex: 0x24272E), NV.ink950, NV.ink900],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                Circle()
                    .strokeBorder(.white.opacity(0.07), lineWidth: 1.5)
                    .frame(width: 380, height: 380)
                    .offset(x: 110, y: -110)
                Circle()
                    .strokeBorder(.white.opacity(0.05), lineWidth: 1.5)
                    .frame(width: 280, height: 280)
                    .offset(x: 60, y: -60)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [NV.spark.opacity(0.42), NV.spark.opacity(0)],
                            center: .center, startRadius: 0, endRadius: 120
                        )
                    )
                    .frame(width: 240, height: 240)
                    .offset(x: 50, y: -20)
            }
        }
    }

    private func posterStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(NV.font(38, .semibold))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stamps: some View {
        VStack(alignment: .leading, spacing: NV.Space.m) {
            posterHeading("Stamps", "\(passport.stamps.count) earned")
            LazyVGrid(columns: columns, alignment: .leading, spacing: NV.Space.l) {
                ForEach(passport.stamps) { stamp in
                    StampBadge(
                        title: stamp.title,
                        subtitle: stamp.subtitle,
                        icon: stamp.icon,
                        tint: stamp.kind == "milestone" ? NV.warning : NV.spark
                    )
                }
            }
        }
    }

    private var subjects: some View {
        VStack(alignment: .leading, spacing: NV.Space.m) {
            posterHeading("Subjects", nil)
            VStack(spacing: NV.Space.m) {
                ForEach(passport.subjectCards) { card in
                    HStack(spacing: NV.Space.m) {
                        Image(systemName: card.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(NV.spark)
                            .frame(width: 26)
                        Text(card.name)
                            .font(NV.font(20, .semibold))
                            .foregroundStyle(NV.ink)
                            .frame(width: 190, alignment: .leading)
                        NVProgressBar(value: card.progress, tint: NV.ink900, height: 8)
                        Text("\(card.learned)/\(card.totalTouched)")
                            .font(NV.font(15, .medium))
                            .foregroundStyle(NV.inkTertiary)
                            .frame(width: 62, alignment: .trailing)
                    }
                    .padding(NV.Space.l)
                    .background(
                        NV.surface,
                        in: RoundedRectangle(cornerRadius: NV.Radius.hero, style: .continuous)
                    )
                }
            }
        }
    }

    private func posterHeading(_ title: String, _ trailing: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(NV.font(28, .semibold))
                .tracking(NV.tracking(28))
                .foregroundStyle(NV.ink)
            Spacer()
            if let trailing {
                Text(trailing).font(NV.font(16)).foregroundStyle(NV.inkTertiary)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: NV.Space.s) {
            BrandMark(progress: BrandMark.filled, size: 26)
            Text("Novi")
                .font(NV.font(19, .semibold))
                .foregroundStyle(NV.ink)
            Text("· The internet, as your classroom")
                .font(NV.font(15))
                .foregroundStyle(NV.inkTertiary)
            Spacer()
        }
        .padding(.top, NV.Space.s)
    }
}

/// Renders the poster to an image on demand.
///
/// `ImageRenderer` is main-actor only and its `uiImage` is nil until the view
/// has laid out, so this is a function rather than a computed property — the
/// caller awaits it and gets either an image or an honest nil.
@MainActor
enum PassportPosterRenderer {
    static func render(passport: PassportDTO, name: String) -> UIImage? {
        let renderer = ImageRenderer(content: PassportPoster(passport: passport, name: name))
        // 3x so the text is sharp when the recipient pinches into it. Higher
        // than the device scale on purpose: this image leaves the device and
        // gets viewed on things we do not control.
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage
    }
}
