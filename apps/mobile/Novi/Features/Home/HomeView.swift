import SwiftUI

/// The personalised feed.
///
/// Two columns of drawn covers, ranked server-side. The client does not
/// re-sort: the order IS the ranking, and a card's "why this?" line comes from
/// the same components that produced its position.
struct HomeView: View {
    @ObservedObject var chrome: Chrome
    var onAsk: (AskSeed) -> Void

    @EnvironmentObject private var session: AppSession
    @StateObject private var model = FeedModel()
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: NV.Space.l) {
                    greeting

                    if model.loading && model.items.isEmpty {
                        skeleton
                    } else if let error = model.error, model.items.isEmpty {
                        NVErrorNote(message: error.message, retry: { Task { await model.reload() } })
                            .padding(.horizontal, NV.gutter)
                    } else if model.items.isEmpty {
                        NVEmptyState(
                            icon: "square.stack.3d.up",
                            title: "Nothing here yet",
                            message: "Add a few more subjects and your feed will fill up.",
                            actionTitle: "Edit interests",
                            action: {}
                        )
                        .padding(.top, NV.Space.section)
                    } else {
                        feed
                    }
                }
                .padding(.bottom, 76)
            }
            .background(NV.page)
            .scrollIndicators(.hidden)
            .refreshable { await model.reload() }
            .navigationDestination(for: ContentDTO.self) { content in
                ContentDetailView(contentID: content.id, chrome: chrome, onAsk: onAsk)
            }
            .task {
                model.attach(session)
                await model.loadIfNeeded()
            }
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(timeOfDayGreeting)
                .font(NV.small)
                .foregroundStyle(NV.inkFaint)
            Text("For You")
                .font(NV.display)
                .foregroundStyle(NV.ink)
        }
        .padding(.horizontal, NV.gutter + 4)
        .padding(.top, NV.Space.s)
    }

    private var timeOfDayGreeting: String {
        let name = session.user?.displayName ?? ""
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good morning" : (hour < 18 ? "Good afternoon" : "Good evening")
        return name.isEmpty ? part : "\(part), \(name)"
    }

    private var feed: some View {
        Waterfall(
            items: model.items,
            spacing: NV.gutter,
            inset: NV.gutter,
            estimatedHeight: { item, width in ContentCard.height(for: item, width: width) }
        ) { item, _ in
            ContentCard(
                item: item,
                onOpen: { path.append(item.content) },
                onSave: { Task { await model.toggleSave(item) } }
            )
            .onAppear {
                // Paging from the card itself rather than a footer sentinel:
                // the sentinel only becomes visible after the user has already
                // hit the bottom, which is one scroll too late.
                Task { await model.loadMoreIfNeeded(after: item) }
            }
        }
    }

    private var skeleton: some View {
        HStack(alignment: .top, spacing: NV.gutter) {
            ForEach(0..<2, id: \.self) { column in
                VStack(spacing: NV.gutter) {
                    ForEach(0..<3, id: \.self) { row in
                        VStack(alignment: .leading, spacing: 8) {
                            NVSkeleton(height: column == 0 ? (row == 1 ? 150 : 210) : (row == 1 ? 220 : 160))
                            NVSkeleton(height: 12)
                            NVSkeleton(height: 12, width: 90)
                        }
                        .padding(9)
                        .cardSurface()
                    }
                }
            }
        }
        .padding(.horizontal, NV.gutter)
    }
}

/// Feed state. A class rather than `@State` because paging, refresh and the
/// optimistic save toggle all mutate the same list and have to stay ordered.
@MainActor
final class FeedModel: ObservableObject {
    @Published private(set) var items: [FeedItemDTO] = []
    @Published private(set) var loading = false
    @Published private(set) var error: APIError?

    private var session: AppSession?
    private var offset = 0
    private var hasMore = true
    private var loaded = false
    private let pageSize = 20

    func attach(_ session: AppSession) { self.session = session }

    func loadIfNeeded() async {
        guard !loaded else { return }
        await reload()
    }

    func reload() async {
        guard let session else { return }
        loading = true
        error = nil
        offset = 0
        hasMore = true
        do {
            let page: FeedResponseDTO = try await session.api.authed(
                .get, "feed", query: ["limit": "\(pageSize)", "offset": "0"]
            )
            items = page.items
            offset = page.items.count
            hasMore = page.hasMore
            loaded = true
        } catch let e as APIError {
            error = e
        } catch {
            self.error = APIError.transport(error)
        }
        loading = false
    }

    func loadMoreIfNeeded(after item: FeedItemDTO) async {
        guard hasMore, !loading, let session else { return }
        // Trigger three cards from the end, so the next page is usually there
        // before the user reaches it.
        guard let index = items.firstIndex(of: item), index >= items.count - 3 else { return }

        loading = true
        do {
            let page: FeedResponseDTO = try await session.api.authed(
                .get, "feed", query: ["limit": "\(pageSize)", "offset": "\(offset)"]
            )
            // The server excludes what has been seen, so a page can repeat an
            // item the client already holds if a VIEW landed between requests.
            let known = Set(items.map(\.id))
            items += page.items.filter { !known.contains($0.id) }
            offset += page.items.count
            hasMore = page.hasMore
        } catch {
            // A failed page is not worth an error banner over a working feed;
            // paging stops and a pull-to-refresh recovers it.
            hasMore = false
        }
        loading = false
    }

    func toggleSave(_ item: FeedItemDTO) async {
        guard let session, let index = items.firstIndex(of: item) else { return }
        let wasSaved = item.isSaved
        // Optimistic: the tap has to feel instant. Reverted below if the
        // request fails, so the icon never lies for longer than the round trip.
        items[index] = item.withSaved(!wasSaved)
        do {
            if wasSaved {
                _ = try await session.api.authed(
                    .delete, "content/\(item.content.id)/save", as: EmptyResponse.self
                )
            } else {
                _ = try await session.api.authed(
                    .post, "content/\(item.content.id)/save",
                    body: EmptyBody(), as: EmptyResponse.self
                )
            }
        } catch {
            items[index] = item.withSaved(wasSaved)
        }
    }
}

extension FeedItemDTO {
    /// The DTO is immutable by design (the server owns these fields), so an
    /// optimistic update rebuilds it rather than mutating in place.
    func withSaved(_ saved: Bool) -> FeedItemDTO {
        FeedItemDTO(content: content, score: score, reason: reason,
                    isSaved: saved, isLiked: isLiked)
    }
}
