import SwiftUI

/// A concept page: what it is, what to do about it, and where it leads.
///
/// This is the node of the "rabbit hole". Every concept offers three exits —
/// ask, quiz, or the next concept — so the learner is never at a dead end.
struct ConceptView: View {
    let conceptID: UUID?
    let fallbackName: String
    @ObservedObject var chrome: Chrome
    var onAsk: (AskSeed) -> Void

    @EnvironmentObject private var session: AppSession
    @State private var detail: ConceptDetailDTO?
    @State private var error: APIError?
    @State private var quizPresented = false
    @State private var markingLearned = false
    @State private var learnedMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NV.Space.l) {
                header
                actions
                if let error { NVErrorNote(message: error.message) }
                if let learnedMessage {
                    NVErrorNote(
                        message: learnedMessage,
                        icon: "checkmark.circle.fill",
                        tint: NV.success
                    )
                }
                if let next = detail?.next, !next.isEmpty { whereNext(next) }
                Spacer(minLength: 90)
            }
            .padding(.horizontal, NV.pageMargin)
            .padding(.top, NV.Space.m)
        }
        .background(NV.page)
        .scrollIndicators(.hidden)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $quizPresented) {
            if let concept = detail?.concept {
                QuizView(conceptID: concept.id, conceptName: concept.name)
            }
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: NV.Space.s) {
            if let subject = detail?.subject {
                NVTag(text: subject.name, icon: subject.icon, tint: NV.spark)
            }
            Text(detail?.concept.name ?? fallbackName)
                .font(NV.h1)
                .foregroundStyle(NV.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let difficulty = detail?.concept.difficulty {
                HStack(spacing: 4) {
                    ForEach(1...5, id: \.self) { level in
                        Capsule()
                            .fill(level <= difficulty ? NV.spark : NV.track)
                            .frame(width: 18, height: 3)
                    }
                    Text(difficultyLabel(difficulty))
                        .font(NV.caption)
                        .foregroundStyle(NV.inkTertiary)
                        .padding(.leading, 4)
                }
            }
        }
    }

    private func difficultyLabel(_ level: Int) -> String {
        ["", "Foundational", "Introductory", "Intermediate", "Advanced", "Expert"][
            min(max(level, 1), 5)
        ]
    }

    private var actions: some View {
        VStack(spacing: NV.Space.s) {
            NVButton(title: "Explain this to me", icon: "sparkles") {
                onAsk(
                    AskSeed(
                        question: "Explain \(detail?.concept.name ?? fallbackName)",
                        conceptID: detail?.concept.id
                    )
                )
            }
            HStack(spacing: NV.Space.s) {
                NVButton(title: "Quiz me", icon: "checkmark.circle", kind: .secondary,
                         enabled: detail != nil) {
                    quizPresented = true
                }
                NVButton(
                    title: learnedMessage == nil ? "I know this" : "Marked learned",
                    icon: learnedMessage == nil ? "checkmark.seal" : "checkmark.seal.fill",
                    kind: .secondary,
                    loading: markingLearned,
                    enabled: detail != nil && learnedMessage == nil
                ) {
                    Task { await markLearned() }
                }
            }
        }
    }

    private func whereNext(_ next: [ConceptDTO]) -> some View {
        VStack(alignment: .leading, spacing: NV.Space.s) {
            Text("WHERE THIS LEADS").font(NV.caption).foregroundStyle(NV.inkTertiary)
            ForEach(next) { concept in
                NavigationLink(value: RelatedConceptDTO(
                    name: concept.name, id: concept.id.uuidString, slug: concept.slug
                )) {
                    HStack(spacing: NV.Space.m) {
                        Text("\(concept.difficulty)")
                            .font(NV.caption.weight(.bold))
                            .foregroundStyle(NV.spark)
                            .frame(width: 26, height: 26)
                            .background(NV.sparkSoft, in: Circle())
                        Text(concept.name).font(NV.bodyStrong).foregroundStyle(NV.ink)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(NV.inkGhost)
                    }
                    .padding(NV.Space.m)
                    .frame(maxWidth: .infinity)
                    .cardSurface(NV.Radius.control)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func load() async {
        guard let conceptID else { return }
        do {
            detail = try await session.api.authed(
                .get, "concepts/\(conceptID)", as: ConceptDetailDTO.self
            )
            session.track("CONCEPT_OPEN", conceptID: conceptID)
        } catch let e as APIError {
            error = e
        } catch {
            self.error = APIError.transport(error)
        }
    }

    private func markLearned() async {
        guard let concept = detail?.concept else { return }
        markingLearned = true
        error = nil
        do {
            let _: EmptyResponse = try await session.api.authed(
                .post, "passport/learn",
                body: MarkLearnedBody(conceptId: concept.id.uuidString),
                as: EmptyResponse.self
            )
            learnedMessage = "Added to your passport."
        } catch let e as APIError {
            error = e
        } catch {
            self.error = APIError.transport(error)
        }
        markingLearned = false
    }
}
