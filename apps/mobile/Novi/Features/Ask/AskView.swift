import SwiftUI

/// Ask a question, get an explanation, then keep going.
///
/// The page deliberately does not end when the answer does. Below the
/// explanation are the videos, posts, discussions and adjacent concepts that
/// the answer opens up — the loop the whole product is built around is
/// question, understanding, discovery, deeper understanding.
struct AskView: View {
    @Binding var seed: AskSeed?
    @ObservedObject var chrome: Chrome

    @EnvironmentObject private var session: AppSession
    @StateObject private var model = AskModel()
    @State private var draft = ""
    @State private var path = NavigationPath()
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: NV.Space.xl) {
                        if let answer = model.answer {
                            AnswerView(
                                answer: answer,
                                askedQuestion: model.askedQuestion,
                                onOpen: { path.append($0) },
                                onFollowUp: { ask($0) },
                                onConcept: { concept in path.append(concept) },
                                onDiscussion: { path.append($0) }
                            )
                            .id("answer")
                        } else if model.loading {
                            loadingState
                        } else if let error = model.error {
                            errorState(error)
                        } else {
                            emptyState
                        }
                    }
                    .padding(.horizontal, NV.pageMargin)
                    .padding(.top, NV.Space.m)
                    .padding(.bottom, NV.Space.section)
                }
                .scrollIndicators(.hidden)
                .onChange(of: model.answer) { _, new in
                    guard new != nil else { return }
                    withAnimation { proxy.scrollTo("answer", anchor: .top) }
                }
            }
            .background(NV.page)
            .safeAreaInset(edge: .bottom) { composer }
            .navigationTitle("Ask")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ContentDTO.self) { content in
                ContentDetailView(contentID: content.id, chrome: chrome, onAsk: { seed = $0 })
            }
            .navigationDestination(for: RelatedConceptDTO.self) { concept in
                ConceptView(
                    conceptID: concept.conceptID,
                    fallbackName: concept.name,
                    chrome: chrome,
                    onAsk: { seed = $0 }
                )
            }
            .navigationDestination(for: DiscussionDTO.self) { discussion in
                DiscussionView(discussion: discussion)
            }
            .task {
                model.attach(session)
                consumeSeed()
            }
            .onChange(of: seed) { _, _ in consumeSeed() }
        }
    }

    // MARK: States

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: NV.Space.xl) {
            VStack(alignment: .leading, spacing: NV.Space.s) {
                Text("What are you stuck on?")
                    .font(NV.h1)
                    .foregroundStyle(NV.ink)
                Text("Ask in your own words. Half-formed is fine.")
                    .font(NV.small)
                    .foregroundStyle(NV.inkTertiary)
            }
            .padding(.top, NV.Space.xl)

            VStack(alignment: .leading, spacing: NV.Space.s) {
                Text("TRY").font(NV.caption).foregroundStyle(NV.inkGhost)
                ForEach(Self.suggestions, id: \.self) { suggestion in
                    Button {
                        draft = suggestion
                        inputFocused = true
                    } label: {
                        HStack {
                            Text(suggestion).font(NV.body).foregroundStyle(NV.ink)
                            Spacer(minLength: NV.Space.s)
                            Image(systemName: "arrow.up.left")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(NV.inkGhost)
                        }
                        .padding(NV.Space.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardSurface(NV.Radius.control)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private static let suggestions = [
        "Why does a derivative represent slope?",
        "Explain photosynthesis simply",
        "What is Big-O notation actually measuring?",
        "How is momentum different from force?",
    ]

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: NV.Space.l) {
            if !model.askedQuestion.isEmpty {
                Text(model.askedQuestion)
                    .font(NV.h2)
                    .foregroundStyle(NV.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Skeleton in the shape of the answer, so the wait reads as the
            // page arriving rather than the app hanging.
            VStack(alignment: .leading, spacing: NV.Space.m) {
                NVSkeleton(height: 18, width: 140)
                NVSkeleton(height: 13)
                NVSkeleton(height: 13)
                NVSkeleton(height: 13, width: 220)
            }
            .padding(NV.Space.l)
            .cardSurface()
            HStack(spacing: NV.Space.s) {
                ProgressView().controlSize(.small)
                Text("Thinking it through…").font(NV.small).foregroundStyle(NV.inkTertiary)
            }
        }
        .padding(.top, NV.Space.l)
    }

    private func errorState(_ error: APIError) -> some View {
        VStack(alignment: .leading, spacing: NV.Space.l) {
            if !model.askedQuestion.isEmpty {
                Text(model.askedQuestion)
                    .font(NV.h2).foregroundStyle(NV.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if error.isAIUnavailable {
                // The tutor being down is not the app being broken, and the
                // difference is worth stating: everything else still works.
                VStack(alignment: .leading, spacing: NV.Space.m) {
                    HStack(spacing: NV.Space.s) {
                        Image(systemName: "sparkles")
                            .foregroundStyle(NV.warning)
                        Text("The tutor is offline")
                            .font(NV.h3).foregroundStyle(NV.ink)
                    }
                    Text(error.message)
                        .font(NV.small).foregroundStyle(NV.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Search and your feed still work — you can look the topic up while this comes back.")
                        .font(NV.small).foregroundStyle(NV.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: NV.Space.s) {
                        NVButton(title: "Try again", kind: .secondary) {
                            ask(model.askedQuestion)
                        }
                    }
                }
                .padding(NV.Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NV.warning.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: NV.Radius.card, style: .continuous))
            } else {
                NVErrorNote(message: error.message, retry: { ask(model.askedQuestion) })
            }
        }
        .padding(.top, NV.Space.l)
    }

    // MARK: Composer

    private var composer: some View {
        VStack(spacing: NV.Space.s) {
            if model.answer != nil {
                // Follow-up modes, which are the cheapest way to go deeper:
                // the learner does not have to think of the next question.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: NV.Space.s) {
                        ForEach(AskModel.Mode.allCases, id: \.self) { mode in
                            Button {
                                model.mode = mode
                                ask(model.askedQuestion, mode: mode)
                            } label: {
                                Text(mode.label)
                                    .font(NV.small.weight(.medium))
                                    .foregroundStyle(NV.ink)
                                    .padding(.horizontal, NV.Space.m)
                                    .padding(.vertical, 7)
                                    .background(NV.surface, in: Capsule())
                                    .overlay(Capsule().stroke(NV.hairline, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, NV.pageMargin)
                }
            }

            HStack(spacing: NV.Space.s) {
                TextField("Ask anything…", text: $draft, axis: .vertical)
                    .font(NV.body)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .padding(.horizontal, NV.Space.m)
                    .padding(.vertical, 11)
                    .background(NV.fill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                Button {
                    ask(draft)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(canSend ? NV.spark : NV.inkGhost, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .animation(.easeOut(duration: 0.15), value: canSend)
            }
            .padding(.horizontal, NV.pageMargin)
        }
        .padding(.top, NV.Space.m)
        // Clears the tab bar, which is an overlay: without this the composer
        // is drawn underneath it and the Ask screen has no visible input.
        .padding(.bottom, NV.tabBarHeight + NV.Space.s)
        .background(.regularMaterial)
        .overlay(alignment: .top) { NV.hairline.frame(height: 0.5) }
    }

    private var canSend: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 && !model.loading
    }

    // MARK: Actions

    private func consumeSeed() {
        guard let current = seed else { return }
        seed = nil
        if current.autoSubmit, !current.question.isEmpty {
            ask(current.question, contentID: current.contentID, conceptID: current.conceptID)
        } else {
            draft = current.question
            inputFocused = true
        }
    }

    private func ask(
        _ question: String,
        mode: AskModel.Mode = .explain,
        contentID: UUID? = nil,
        conceptID: UUID? = nil
    ) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return }
        draft = ""
        inputFocused = false
        Task {
            await model.ask(trimmed, mode: mode, contentID: contentID, conceptID: conceptID)
        }
    }
}

@MainActor
final class AskModel: ObservableObject {
    enum Mode: String, CaseIterable {
        case explain, simple, eli10, deeper, example, compare

        var label: String {
            switch self {
            case .explain: return "Explain"
            case .simple: return "Simpler"
            case .eli10: return "Like I'm 10"
            case .deeper: return "Go deeper"
            case .example: return "Give an example"
            case .compare: return "Compare"
            }
        }
    }

    @Published private(set) var answer: AskResponseDTO?
    @Published private(set) var askedQuestion = ""
    @Published private(set) var loading = false
    @Published private(set) var error: APIError?
    @Published var mode: Mode = .explain

    private var session: AppSession?

    func attach(_ session: AppSession) { self.session = session }

    func ask(_ question: String, mode: Mode, contentID: UUID?, conceptID: UUID?) async {
        guard let session else { return }
        askedQuestion = question
        loading = true
        error = nil
        // The previous answer is cleared so the skeleton is what is on screen;
        // leaving the old one up while a new question loads reads as the app
        // having ignored the tap.
        answer = nil
        do {
            let response: AskResponseDTO = try await session.api.authed(
                .post, "ask",
                body: AskBody(
                    question: question,
                    mode: mode.rawValue,
                    contentId: contentID?.uuidString,
                    conceptId: conceptID?.uuidString
                )
            )
            answer = response
        } catch let e as APIError {
            error = e
        } catch {
            self.error = APIError.transport(error)
        }
        loading = false
    }
}
