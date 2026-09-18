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
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: NV.Space.m) {
                    header

                    if let item = model.continueItem {
                        continueStrip(item)
                    }

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

    /// The header. Display type, a generous margin, and no chrome — the
    /// screen opens on the learner's name and their own momentum rather than
    /// on a toolbar.
    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(dayLabel)
                .font(NV.small)
                .foregroundStyle(NV.inkTertiary)

            HStack(alignment: .lastTextBaseline) {
                Text(greetingTitle)
                    .displayStyle(8)
                    .foregroundStyle(NV.ink)
                Spacer(minLength: NV.Space.s)
                if model.streak > 1 { streakChip }
            }
        }
        .padding(.horizontal, NV.pageMargin)
        .padding(.top, NV.Space.xs)
    }

    private var dayLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f.string(from: Date())
    }

    private var greetingTitle: String {
        // "For you" is the section, not a greeting. The name goes in the line
        // above so the display step stays a constant width and does not jump
        // between a two-letter name and a twelve-letter one.
        "For you"
    }

    private var streakChip: some View {
        HStack(spacing: 5) {
            Image(systemName: "flame.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NV.spark)
            Text("\(model.streak) day streak")
                .font(NV.caption)
                .foregroundStyle(NV.ink)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .edgedSurface(NV.Radius.pill)
    }

    /// Pick up where you left off. One wide card above the grid, because the
    /// single most useful thing on this screen is the thing the learner was
    /// already part-way through — and a masonry gives nothing priority.
    @ViewBuilder
    private func continueStrip(_ item: ContinueItem) -> some View {
        Button {
            onAsk(AskSeed(question: "Explain \(item.name)", conceptID: item.id))
        } label: {
            HStack(spacing: NV.Space.m) {
                ZStack {
                    RoundedRectangle(cornerRadius: NV.Radius.thumb, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [NV.spark, NV.horizon],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text("CONTINUE")
                        .font(NV.step(-4, .bold))
                        .tracking(0.8)
                        .foregroundStyle(NV.spark)
                    Text(item.name)
                        .font(NV.bodyStrong)
                        .foregroundStyle(NV.ink)
                        .lineLimit(1)
                    HStack(spacing: NV.Space.s) {
                        NVProgressBar(value: item.progress, tint: NV.ink900, height: 5)
                        Text(item.mastery.capitalized)
                            .font(NV.cardMeta)
                            .foregroundStyle(NV.inkTertiary)
                            .fixedSize()
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(NV.Space.l)
            .cardSurface(NV.Radius.hero)
        }
        .buttonStyle(.plain)
        // The grid's margin, not the header's: this card sits directly above
        // the columns and a different inset reads as a misalignment.
        .padding(.horizontal, NV.gutter)
    }

    private var feed: some View {
        Waterfall(
            items: model.items,
            spacing: NV.gutter,
            inset: NV.gutter,
            estimatedHeight: { item, width in
                ContentCard.height(for: item, width: width, typeSize: typeSize)
            }
        ) { item, width in
            ContentCard(
                item: item,
                width: width,
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
/// What the learner was part-way through.
struct ContinueItem: Equatable {
    let id: UUID
    let name: String
    let mastery: String
    let progress: Double
}

@MainActor
final class FeedModel: ObservableObject {
    @Published private(set) var items: [FeedItemDTO] = []
    @Published private(set) var loading = false
    @Published private(set) var error: APIError?
    @Published private(set) var streak = 0
    @Published private(set) var continueItem: ContinueItem?

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
        // Fired alongside the feed rather than before it: the header can
        // arrive a moment late, but the grid is what the screen is for.
        Task { await loadHeader() }
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

    /// Streak and "continue", both derived from endpoints that already exist.
    ///
    /// Neither needs a new route: a streak is consecutive days in the activity
    /// history, and the thing to continue is the most recently touched concept
    /// that is not finished yet. Adding server fields for two numbers the
    /// client can count would have been the wrong trade.
    private func loadHeader() async {
        guard let session else { return }

        if let history: [HistoryDayDTO] = try? await session.api.authed(
            .get, "me/history", query: ["days": "60"]
        ) {
            streak = Self.streakLength(from: history)
        }

        guard let passport: PassportDTO = try? await session.api.authed(.get, "passport") else {
            return
        }
        // Ordered weak-to-strong, so "continue" offers the concept with the
        // most left to do rather than the one nearest the finish.
        //
        // `discovered` is excluded: the server writes that row when a concept
        // merely appears in the feed, so including it invented a "pick up
        // where you left off" card for a learner who has not opened anything.
        // No history, no card.
        let ladder = ["discovered", "viewed", "explored", "practiced", "learned", "mastered"]
        let started = ladder.firstIndex(of: "viewed")!
        let candidates = passport.subjectCards
            .flatMap(\.concepts)
            .compactMap { concept -> ContinueItem? in
                guard let id = concept.conceptID,
                      let rank = ladder.firstIndex(of: concept.mastery),
                      rank >= started, concept.mastery != "mastered"
                else { return nil }
                return ContinueItem(
                    id: id,
                    name: concept.name,
                    mastery: concept.mastery,
                    progress: Double(rank) / Double(ladder.count - 1)
                )
            }
        continueItem = candidates.max { $0.progress < $1.progress }
    }

    /// Consecutive days with activity, counting back from today.
    ///
    /// Today missing does not break a streak — it is not over yet — but
    /// yesterday missing does. Without that allowance the streak reads zero
    /// every morning until the learner opens something.
    static func streakLength(from history: [HistoryDayDTO], now: Date = Date()) -> Int {
        let calendar = Calendar.current
        let active = Set(history.filter {
            $0.content + $0.questions + $0.quizzes + $0.concepts > 0
        }.map { calendar.startOfDay(for: $0.date) })
        guard !active.isEmpty else { return 0 }

        var day = calendar.startOfDay(for: now)
        if !active.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else {
                return 0
            }
            day = yesterday
        }

        var count = 0
        while active.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
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
