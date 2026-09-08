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

    private struct QuizTarget: Identifiable {
        let id: UUID
        let name: String
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

    private func cover(_ passport: PassportDTO) -> some View {
        VStack(alignment: .leading, spacing: NV.Space.l) {
            VStack(alignment: .leading, spacing: 2) {
                Text("LEARNING PASSPORT")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(0.75))
                Text(session.user?.displayName ?? "")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
            }

            HStack(spacing: 0) {
                stat("\(passport.conceptsCovered)", "Concepts")
                stat("\(passport.conceptsLearned)", "Learned")
                stat("\(passport.subjects)", "Subjects")
                stat("\(passport.sessions)", "Sessions")
            }
        }
        .padding(NV.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [NV.accent, NV.accentDeep],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: NV.Radius.sheet, style: .continuous)
        )
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 21, weight: .bold)).foregroundStyle(.white)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
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
                            tint: stamp.kind == "milestone" ? NV.warning : NV.accent
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
                            .foregroundStyle(NV.accent)
                        Text(card.name).font(NV.h3).foregroundStyle(NV.ink)
                        Spacer(minLength: 0)
                        Text("\(card.learned)/\(card.totalTouched)")
                            .font(NV.caption).foregroundStyle(NV.inkFaint)
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
                        .foregroundStyle(NV.accent)
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
