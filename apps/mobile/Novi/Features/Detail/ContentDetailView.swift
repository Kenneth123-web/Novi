import SwiftUI

/// A content page, with the question button as its most prominent control.
///
/// "I have a question" is the hinge of the whole product: it is the moment a
/// passive scroll becomes learning, so it gets the accent, the width and the
/// position under the thumb.
struct ContentDetailView: View {
    let contentID: UUID
    @ObservedObject var chrome: Chrome
    var onAsk: (AskSeed) -> Void

    @EnvironmentObject private var session: AppSession
    @State private var detail: ContentDetailDTO?
    @State private var error: APIError?
    @State private var saved = false
    @State private var liked = false
    @State private var openedAt = Date()

    var body: some View {
        ScrollView {
            if let detail {
                VStack(alignment: .leading, spacing: NV.Space.l) {
                    cover(detail.content)
                    header(detail.content)
                    askButton(detail)
                    if !detail.content.description.isEmpty {
                        Text(detail.content.description)
                            .font(NV.body)
                            .foregroundStyle(NV.inkSoft)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, NV.Space.l)
                    }
                    if !detail.concepts.isEmpty { concepts(detail) }
                    if !detail.related.isEmpty { related(detail) }
                    Spacer(minLength: 90)
                }
            } else if let error {
                NVErrorNote(message: error.message, retry: { Task { await load() } })
                    .padding(NV.Space.l)
            } else {
                skeleton
            }
        }
        .background(NV.page)
        .scrollIndicators(.hidden)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: NV.Space.l) {
                    Button { toggleLike() } label: {
                        Image(systemName: liked ? "heart.fill" : "heart")
                            .foregroundStyle(liked ? NV.error : NV.ink)
                    }
                    Button { toggleSave() } label: {
                        Image(systemName: saved ? "bookmark.fill" : "bookmark")
                            .foregroundStyle(saved ? NV.accent : NV.ink)
                    }
                }
            }
        }
        .task { await load() }
        .onDisappear {
            // Dwell time is the single most informative signal collected: a
            // like is one bit, time-on-page is a measurement.
            let seconds = Int(Date().timeIntervalSince(openedAt))
            session.track("VIEW", contentID: contentID, dwellSeconds: seconds)
        }
    }

    private func cover(_ content: ContentDTO) -> some View {
        CoverArt(seed: content.coverSeed)
            .frame(height: 240)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 6) {
                    NVTag(text: content.platform.capitalized, tint: .white.opacity(0.9), filled: false)
                        .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
                    if content.isSample {
                        NVTag(text: "Sample content", tint: NV.ink.opacity(0.6), filled: true)
                    }
                }
                .padding(NV.Space.m)
            }
    }

    private func header(_ content: ContentDTO) -> some View {
        VStack(alignment: .leading, spacing: NV.Space.s) {
            Text(content.title)
                .font(NV.h1)
                .foregroundStyle(NV.ink)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: NV.Space.s) {
                Avatar(name: content.creator, size: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text(content.creator).font(NV.small.weight(.medium)).foregroundStyle(NV.ink)
                    HStack(spacing: 4) {
                        Text(nv_count(content.likes) + " likes")
                        Text("·")
                        Text(content.topic)
                    }
                    .font(NV.caption)
                    .foregroundStyle(NV.inkFaint)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, NV.Space.l)
    }

    private func askButton(_ detail: ContentDetailDTO) -> some View {
        VStack(spacing: NV.Space.s) {
            NVButton(title: "I have a question", icon: "sparkles") {
                onAsk(
                    AskSeed(
                        question: "",
                        contentID: detail.content.id,
                        conceptID: detail.concepts.first?.id,
                        contentTitle: detail.content.title,
                        // Not auto-submitted: the learner has a specific thing
                        // they are stuck on, and guessing it for them would
                        // answer a question they did not ask.
                        autoSubmit: false
                    )
                )
            }
            if let concept = detail.concepts.first {
                Button {
                    onAsk(
                        AskSeed(
                            question: "Explain \(concept.name) simply",
                            contentID: detail.content.id,
                            conceptID: concept.id
                        )
                    )
                } label: {
                    Text("or explain \(concept.name) simply")
                        .font(NV.small)
                        .foregroundStyle(NV.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, NV.Space.l)
    }

    private func concepts(_ detail: ContentDetailDTO) -> some View {
        VStack(alignment: .leading, spacing: NV.Space.s) {
            Text("CONCEPTS IN THIS").font(NV.caption).foregroundStyle(NV.inkFaint)
            FlowRow(spacing: NV.Space.s, lineSpacing: NV.Space.s) {
                ForEach(detail.concepts) { concept in
                    NavigationLink(value: RelatedConceptDTO(
                        name: concept.name, id: concept.id.uuidString, slug: concept.slug
                    )) {
                        HStack(spacing: 5) {
                            Text(concept.name).font(NV.small.weight(.medium))
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(NV.accent)
                        .padding(.horizontal, NV.Space.m)
                        .padding(.vertical, 8)
                        .background(NV.accentSoft, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, NV.Space.l)
    }

    private func related(_ detail: ContentDetailDTO) -> some View {
        VStack(alignment: .leading, spacing: NV.Space.s) {
            Text("MORE ON THIS").font(NV.caption).foregroundStyle(NV.inkFaint)
                .padding(.horizontal, NV.Space.l)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: NV.Space.m) {
                    ForEach(detail.related) { item in
                        NavigationLink(value: item) {
                            RailCard(content: item, onOpen: {})
                                .allowsHitTesting(false)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, NV.Space.l)
            }
        }
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: NV.Space.l) {
            NVSkeleton(height: 240)
            VStack(alignment: .leading, spacing: NV.Space.s) {
                NVSkeleton(height: 22)
                NVSkeleton(height: 22, width: 200)
                NVSkeleton(height: 14, width: 140)
            }
            .padding(.horizontal, NV.Space.l)
            NVSkeleton(height: 50).padding(.horizontal, NV.Space.l)
        }
    }

    private func load() async {
        do {
            let response: ContentDetailDTO = try await session.api.authed(
                .get, "content/\(contentID)"
            )
            detail = response
            saved = response.isSaved
            liked = response.isLiked
            openedAt = Date()
        } catch let e as APIError {
            error = e
        } catch {
            self.error = APIError.transport(error)
        }
    }

    private func toggleSave() {
        let wasSaved = saved
        saved.toggle()   // optimistic; the tap has to feel instant
        Task {
            do {
                if wasSaved {
                    _ = try await session.api.authed(
                        .delete, "content/\(contentID)/save", as: EmptyResponse.self)
                } else {
                    _ = try await session.api.authed(
                        .post, "content/\(contentID)/save",
                        body: EmptyBody(), as: EmptyResponse.self)
                }
            } catch {
                saved = wasSaved
            }
        }
    }

    private func toggleLike() {
        let wasLiked = liked
        liked.toggle()
        Task {
            do {
                if wasLiked {
                    _ = try await session.api.authed(
                        .delete, "content/\(contentID)/like", as: EmptyResponse.self)
                } else {
                    _ = try await session.api.authed(
                        .post, "content/\(contentID)/like", as: EmptyResponse.self)
                }
            } catch {
                liked = wasLiked
            }
        }
    }
}
