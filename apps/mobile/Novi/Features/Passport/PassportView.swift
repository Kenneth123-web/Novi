import SwiftUI

/// The Learning Passport — the record of what the learner has actually done.
///
/// Styled as a document rather than a dashboard: a header block with the
/// counts, then a stamp collection, then a page per subject. It is the one
/// screen meant to be worth opening for its own sake.
struct PassportView: View {
    var onAsk: (AskSeed) -> Void

    @EnvironmentObject private var session: AppSession
    @StateObject private var chrome = Chrome()
    @State private var passport: PassportDTO?
    @State private var error: APIError?
    @State private var path = NavigationPath()
    @State private var quizConcept: QuizTarget?
    @State private var poster: PosterImage?
    @State private var rendering = false

    private struct QuizTarget: Identifiable {
        let id: UUID
        let name: String
    }

    /// `ShareLink` needs something `Identifiable` to drive a sheet, and a bare
    /// `UIImage` is not.
    private struct PosterImage: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: NV.Space.xl) {
                    if let passport {
                        cover(passport)
                        if !passport.stamps.isEmpty { stamps(passport) }
                        if passport.subjectCards.isEmpty {
                            NVEmptyState(
                                icon: "checkmark.seal",
                                title: "No stamps yet",
                                message: "Open a concept, ask a question, or take a quiz — everything you learn lands here.",
                                actionTitle: "Ask something",
                                action: { onAsk(AskSeed(question: "", autoSubmit: false)) }
                            )
                            .padding(.top, NV.Space.xl)
                        } else {
                            subjects(passport)
                        }
                    } else if let error {
                        NVErrorNote(message: error.message, retry: { Task { await load() } })
                    } else {
                        skeleton
                    }
                    Spacer(minLength: 90)
                }
                .padding(.horizontal, NV.Space.l)
                .padding(.top, NV.Space.s)
            }
            .background(NV.page)
            .scrollIndicators(.hidden)
            .refreshable { await load() }
            .navigationTitle("Passport")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        makePoster()
                    } label: {
                        if rendering {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(NV.ink)
                        }
                    }
                    .disabled(passport == nil || rendering)
                }
            }
            .sheet(item: $poster) { item in
                ShareSheet(items: [item.image])
            }
            .navigationDestination(for: RelatedConceptDTO.self) { concept in
                ConceptView(conceptID: concept.conceptID, fallbackName: concept.name,
                            chrome: chrome, onAsk: onAsk)
            }
            .sheet(item: $quizConcept) { target in
                QuizView(conceptID: target.id, conceptName: target.name)
            }
            .task { await load() }
        }
    }

    /// The cover reads as a document, not a dashboard.
    ///
    /// Deep ink rather than the accent: a full-bleed violet panel is a
    /// dashboard header, and this is meant to be the one screen worth opening
    /// for its own sake. The concentric rules are the guilloché a real
    /// passport prints to make itself hard to forge — here they are just what
    /// stops a dark rectangle from looking like an empty state.
    private func cover(_ passport: PassportDTO) -> some View {
        VStack(alignment: .leading, spacing: NV.Space.l) {
            VStack(alignment: .leading, spacing: NV.Space.xs) {
                Text("LEARNING PASSPORT")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2.0)
                    .foregroundStyle(.white.opacity(0.52))
                Text(session.user?.displayName ?? "")
                    .displayStyle(8)
                    .foregroundStyle(.white)
            }

            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(height: 1)

            HStack(spacing: 0) {
                stat("\(passport.conceptsCovered)", "CONCEPTS")
                stat("\(passport.conceptsLearned)", "LEARNED")
                stat("\(passport.subjects)", "SUBJECTS")
                stat("\(passport.sessions)", "SESSIONS")
            }
        }
        .padding(NV.Space.xl - 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    colors: [Color(hex: 0x24272E), NV.ink950, NV.ink900],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )

                // Guilloché. Clipped by the card's own shape below, so the
                // rings can run off the corner instead of being tucked inside
                // it — a ring that stops short of the edge reads as a sticker.
                Circle()
                    .strokeBorder(.white.opacity(0.07), lineWidth: 1)
                    .frame(width: 210, height: 210)
                    .offset(x: 50, y: -50)
                Circle()
                    .strokeBorder(.white.opacity(0.05), lineWidth: 1)
                    .frame(width: 160, height: 160)
                    .offset(x: 24, y: -24)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [NV.spark.opacity(0.40), NV.spark.opacity(0)],
                            center: .center, startRadius: 0, endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)
                    .offset(x: 24, y: -8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: NV.Radius.hero, style: .continuous))
        .shadow(color: NV.ink900.opacity(0.18), radius: 20, x: 0, y: 10)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(NV.step(5, .semibold))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.50))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stamps(_ passport: PassportDTO) -> some View {
        VStack(alignment: .leading, spacing: NV.Space.m) {
            NVSectionHeader(title: "Stamps", subtitle: "\(passport.stamps.count) earned")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: NV.Space.m) {
                    ForEach(passport.stamps) { stamp in
                        StampBadge(
                            title: stamp.title,
                            subtitle: stamp.subtitle,
                            icon: stamp.icon,
                            tint: stamp.kind == "milestone" ? NV.warning : NV.spark
                        )
                    }
                }
                .padding(.vertical, NV.Space.s)
                .padding(.horizontal, 2)
            }
        }
    }

    private func subjects(_ passport: PassportDTO) -> some View {
        VStack(alignment: .leading, spacing: NV.Space.m) {
            NVSectionHeader(title: "Subjects")
            ForEach(passport.subjectCards) { card in
                VStack(alignment: .leading, spacing: NV.Space.m) {
                    HStack(spacing: NV.Space.s) {
                        Image(systemName: card.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(NV.spark)
                        Text(card.name).font(NV.h3).foregroundStyle(NV.ink)
                        Spacer(minLength: 0)
                        Text("\(card.learned)/\(card.totalTouched)")
                            .font(NV.caption).foregroundStyle(NV.inkTertiary)
                    }

                    NVProgressBar(value: card.progress)

                    VStack(spacing: 0) {
                        ForEach(card.concepts) { concept in
                            conceptRow(concept)
                        }
                    }
                }
                .padding(NV.Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
            }
        }
    }

    private func conceptRow(_ concept: PassportConceptDTO) -> some View {
        HStack(spacing: NV.Space.s) {
            Image(systemName: iconFor(concept.mastery))
                .font(.system(size: 13))
                .foregroundStyle(NV.mastery(concept.mastery))
                .frame(width: 18)

            NavigationLink(value: RelatedConceptDTO(
                name: concept.name, id: concept.id, slug: concept.slug
            )) {
                Text(concept.name)
                    .font(NV.small)
                    .foregroundStyle(NV.ink)
            }
            .buttonStyle(.plain)

            Spacer(minLength: NV.Space.s)

            Text(concept.mastery.capitalized)
                .font(NV.caption)
                .foregroundStyle(NV.mastery(concept.mastery))

            // The next action is on the row, so improving a weak concept never
            // requires navigating away to find the button.
            if concept.mastery != "mastered", let id = concept.conceptID {
                Button {
                    quizConcept = QuizTarget(id: id, name: concept.name)
                } label: {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(NV.spark)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 7)
        .hairline(.bottom, color: NV.hairline.opacity(0.6))
    }

    private func iconFor(_ mastery: String) -> String {
        switch mastery {
        case "mastered": return "seal.fill"
        case "learned": return "checkmark.seal.fill"
        case "practiced": return "checkmark.circle.fill"
        case "explored": return "circle.lefthalf.filled"
        case "viewed": return "circle.dotted"
        default: return "circle"
        }
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: NV.Space.l) {
            NVSkeleton(height: 128)
            NVSkeleton(height: 16, width: 120)
            NVSkeleton(height: 96)
            NVSkeleton(height: 140)
        }
    }

    /// Renders on a detached task hop so the button's spinner actually paints
    /// before the render begins. `ImageRenderer` is synchronous and main-actor
    /// only, so without yielding first the UI freezes on the tap and the
    /// spinner is never seen.
    private func makePoster() {
        guard let passport, !rendering else { return }
        rendering = true
        Task {
            await Task.yield()
            let image = PassportPosterRenderer.render(
                passport: passport,
                name: session.user?.displayName ?? "Novi learner"
            )
            rendering = false
            if let image { poster = PosterImage(image: image) }
        }
    }

    private func load() async {
        do {
            passport = try await session.api.authed(.get, "passport", as: PassportDTO.self)
            error = nil
        } catch let e as APIError {
            error = e
        } catch {
            self.error = APIError.transport(error)
        }
    }
}
