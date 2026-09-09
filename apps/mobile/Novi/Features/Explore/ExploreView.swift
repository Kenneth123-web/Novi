import SwiftUI

/// Search as a learning search engine, not a post list.
///
/// A query returns the concept first, then videos, posts and discussions about
/// it. That order is the point: "Photosynthesis" is a thing to understand
/// before it is a list of links.
struct ExploreView: View {
    @ObservedObject var chrome: Chrome
    var onAsk: (AskSeed) -> Void

    @EnvironmentObject private var session: AppSession
    @State private var query = ""
    @State private var results: SearchResponseDTO?
    @State private var loading = false
    @State private var error: APIError?
    @State private var path = NavigationPath()
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: NV.Space.l) {
                    searchField

                    if loading {
                        loadingState
                    } else if let error {
                        NVErrorNote(message: error.message, retry: { runSearch(query) })
                    } else if let results {
                        resultsView(results)
                    } else {
                        browse
                    }
                    Spacer(minLength: 90)
                }
                .padding(.horizontal, NV.pageMargin)
                .padding(.top, NV.Space.s)
            }
            .background(NV.page)
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Explore")
            .navigationDestination(for: ContentDTO.self) { content in
                ContentDetailView(contentID: content.id, chrome: chrome, onAsk: onAsk)
            }
            .navigationDestination(for: RelatedConceptDTO.self) { concept in
                ConceptView(conceptID: concept.conceptID, fallbackName: concept.name,
                            chrome: chrome, onAsk: onAsk)
            }
            .navigationDestination(for: DiscussionDTO.self) { DiscussionView(discussion: $0) }
            .task {
                await session.loadSubjects()
                Demo.once("search") {
                    if let seeded = Demo.search {
                        query = seeded
                        runSearch(seeded)
                    }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: NV.Space.s) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(NV.inkTertiary)
            TextField("Search a concept, topic or question", text: $query)
                .font(NV.body)
                .focused($focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit { runSearch(query) }
                .onChange(of: query) { _, new in scheduleSearch(new) }
            if !query.isEmpty {
                Button {
                    query = ""
                    results = nil
                    error = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(NV.inkGhost)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, NV.Space.m)
        .frame(height: 46)
        .background(NV.surface, in: RoundedRectangle(cornerRadius: NV.Radius.control,
                                                     style: .continuous))
    }

    private var browse: some View {
        VStack(alignment: .leading, spacing: NV.Space.m) {
            NVSectionHeader(title: "Browse subjects")
            FlowRow(spacing: NV.Space.s, lineSpacing: NV.Space.s) {
                ForEach(session.subjects) { subject in
                    Button {
                        query = subject.name
                        runSearch(subject.name)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: subject.icon).font(.system(size: 12, weight: .medium))
                            Text(subject.name).font(NV.small.weight(.medium))
                        }
                        .foregroundStyle(NV.ink)
                        .padding(.horizontal, NV.Space.m)
                        .padding(.vertical, 10)
                        .cardSurface(NV.Radius.pill)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: NV.Space.m) {
            NVSkeleton(height: 92)
            NVSkeleton(height: 14, width: 100)
            HStack(spacing: NV.Space.m) {
                NVSkeleton(height: 150, width: 168)
                NVSkeleton(height: 150, width: 168)
            }
        }
    }

    @ViewBuilder
    private func resultsView(_ results: SearchResponseDTO) -> some View {
        if results.concept == nil && results.content.isEmpty && results.discussions.isEmpty {
            NVEmptyState(
                icon: "magnifyingglass",
                title: "Nothing for “\(results.query)”",
                message: "Try a different wording, or ask the tutor directly.",
                actionTitle: "Ask about this",
                action: { onAsk(AskSeed(question: results.query)) }
            )
            .padding(.top, NV.Space.section)
        } else {
            VStack(alignment: .leading, spacing: NV.Space.xl) {
                if let concept = results.concept { conceptCard(concept) }
                askCard(results.query)
                if !results.content.isEmpty { contentSection(results.content) }
                if !results.discussions.isEmpty { discussionSection(results.discussions) }
            }
        }
    }

    private func conceptCard(_ concept: SearchResponseDTO.SearchConcept) -> some View {
        NavigationLink(value: RelatedConceptDTO(
            name: concept.name, id: concept.id.uuidString, slug: concept.slug
        )) {
            VStack(alignment: .leading, spacing: NV.Space.s) {
                Text("CONCEPT").font(NV.caption).foregroundStyle(NV.spark)
                Text(concept.name).font(NV.h2).foregroundStyle(NV.ink)
                if let subject = concept.subjectName {
                    Text(subject).font(NV.small).foregroundStyle(NV.inkTertiary)
                }
                HStack(spacing: 5) {
                    Text("Open concept").font(NV.small.weight(.semibold))
                    Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(NV.spark)
                .padding(.top, 2)
            }
            .padding(NV.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NV.sparkSoft,
                        in: RoundedRectangle(cornerRadius: NV.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func askCard(_ query: String) -> some View {
        Button {
            onAsk(AskSeed(question: "Explain \(query)"))
        } label: {
            HStack(spacing: NV.Space.m) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(NV.spark, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ask about “\(query)”").font(NV.bodyStrong).foregroundStyle(NV.ink)
                        .lineLimit(1)
                    Text("Get an explanation at your level")
                        .font(NV.caption).foregroundStyle(NV.inkTertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(NV.inkGhost)
            }
            .padding(NV.Space.m)
            .frame(maxWidth: .infinity)
            .cardSurface(NV.Radius.control)
        }
        .buttonStyle(.plain)
    }

    private func contentSection(_ items: [ContentDTO]) -> some View {
        VStack(alignment: .leading, spacing: NV.Space.s) {
            Text("CONTENT").font(NV.caption).foregroundStyle(NV.inkTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: NV.Space.m) {
                    ForEach(items) { item in
                        NavigationLink(value: item) {
                            RailCard(content: item, onOpen: {}).allowsHitTesting(false)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private func discussionSection(_ items: [DiscussionDTO]) -> some View {
        VStack(alignment: .leading, spacing: NV.Space.s) {
            Text("DISCUSSIONS").font(NV.caption).foregroundStyle(NV.inkTertiary)
            ForEach(items) { discussion in
                NavigationLink(value: discussion) {
                    DiscussionRow(discussion: discussion)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Search

    /// Debounced. Search is cheap server-side but a request per keystroke
    /// still races: results for "der" can land after results for "deriv" and
    /// overwrite them.
    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = nil
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await search(trimmed)
        }
    }

    private func runSearch(_ text: String) {
        searchTask?.cancel()
        searchTask = Task { await search(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    private func search(_ text: String) async {
        guard text.count >= 2 else { return }
        loading = true
        error = nil
        do {
            let response: SearchResponseDTO = try await session.api.authed(
                .get, "search", query: ["q": text]
            )
            guard !Task.isCancelled else { return }
            results = response
            session.track("SEARCH")
        } catch let e as APIError {
            error = e
        } catch {
            self.error = APIError.transport(error)
        }
        loading = false
    }
}
