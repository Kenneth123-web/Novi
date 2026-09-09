import SwiftUI

/// A community thread, with translation and an AI summary.
///
/// The point of this screen is that a Reddit thread becomes a learning
/// resource rather than a social feed: what people agree on, where they
/// genuinely differ, and which misunderstandings show up in the replies.
struct DiscussionView: View {
    let discussion: DiscussionDTO

    @EnvironmentObject private var session: AppSession
    @State private var summary: SummaryDTO?
    @State private var translation: TranslationDTO?
    @State private var showingTranslation = false
    @State private var busy: Busy?
    @State private var error: APIError?

    private enum Busy { case summary, translation }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NV.Space.l) {
                header
                actions
                if let error { NVErrorNote(message: error.message, tint: NV.warning) }
                if let summary { summaryCard(summary) }
                body(for: discussion)
                comments
                Spacer(minLength: 90)
            }
            .padding(.horizontal, NV.pageMargin)
            .padding(.top, NV.Space.m)
        }
        .background(NV.page)
        .scrollIndicators(.hidden)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            summary = discussion.summary
            translation = discussion.translation
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: NV.Space.s) {
            HStack(spacing: 6) {
                NVTag(text: discussion.community, icon: "person.2", tint: NV.spark)
                if discussion.isSample {
                    NVTag(text: "Sample", tint: NV.inkTertiary)
                }
                Spacer(minLength: 0)
                Label(nv_count(discussion.upvotes), systemImage: "arrow.up")
                    .font(NV.caption).foregroundStyle(NV.inkTertiary)
            }
            Text(displayTitle)
                .font(NV.h2)
                .foregroundStyle(NV.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Posted by \(discussion.author)")
                .font(NV.caption)
                .foregroundStyle(NV.inkTertiary)
        }
    }

    private var actions: some View {
        HStack(spacing: NV.Space.s) {
            Button { Task { await summarise() } } label: {
                pill("Summarise", "sparkles", loading: busy == .summary)
            }
            .buttonStyle(.plain)
            .disabled(busy != nil)

            Button { Task { await translate() } } label: {
                pill(
                    showingTranslation ? "Show original" : "Translate",
                    "character.bubble",
                    loading: busy == .translation
                )
            }
            .buttonStyle(.plain)
            .disabled(busy != nil)

            Spacer(minLength: 0)
        }
    }

    private func pill(_ title: String, _ icon: String, loading: Bool) -> some View {
        HStack(spacing: 6) {
            if loading {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold))
            }
            Text(title).font(NV.small.weight(.medium))
        }
        .foregroundStyle(NV.spark)
        .padding(.horizontal, NV.Space.m)
        .padding(.vertical, 9)
        .background(NV.sparkSoft, in: Capsule())
    }

    private func summaryCard(_ summary: SummaryDTO) -> some View {
        VStack(alignment: .leading, spacing: NV.Space.m) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 11, weight: .semibold))
                Text("WHAT THIS THREAD SAYS").font(NV.caption)
            }
            .foregroundStyle(NV.spark)

            bullets("Main ideas", summary.mainIdeas)
            bullets("What people agree on", summary.agreement)
            bullets("Where they differ", summary.disagreement)
            bullets("Common mistakes", summary.commonMistakes, tint: NV.warning)
            bullets("Useful resources", summary.usefulResources)
        }
        .padding(NV.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    @ViewBuilder
    private func bullets(_ title: String, _ items: [String]?, tint: Color = NV.inkTertiary) -> some View {
        if let items, !items.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(NV.caption).foregroundStyle(tint)
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 7) {
                        Circle().fill(tint.opacity(0.5)).frame(width: 4, height: 4).padding(.top, 7)
                        Text(item)
                            .font(NV.small)
                            .foregroundStyle(NV.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func body(for discussion: DiscussionDTO) -> some View {
        VStack(alignment: .leading, spacing: NV.Space.s) {
            Text(displayBody)
                .font(NV.body)
                .foregroundStyle(NV.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            if showingTranslation {
                // Saying which text is on screen matters: a translated thread
                // presented as the original hides that a machine rewrote it.
                Text("Translated by AI")
                    .font(NV.caption)
                    .foregroundStyle(NV.inkGhost)
            }
        }
        .padding(NV.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var comments: some View {
        VStack(alignment: .leading, spacing: NV.Space.s) {
            Text("\(discussion.comments.count) REPLIES")
                .font(NV.caption).foregroundStyle(NV.inkTertiary)

            ForEach(Array(discussion.comments.enumerated()), id: \.element.id) { index, comment in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Avatar(name: comment.author, size: 18)
                        Text(comment.author).font(NV.caption).foregroundStyle(NV.inkSecondary)
                        Spacer(minLength: 0)
                        Label(nv_count(comment.upvotes), systemImage: "arrow.up")
                            .font(NV.caption).foregroundStyle(NV.inkTertiary)
                    }
                    Text(commentText(at: index, fallback: comment.body))
                        .font(NV.small)
                        .foregroundStyle(NV.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(NV.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface(NV.Radius.control)
            }
        }
    }

    // MARK: Text selection

    private var displayTitle: String {
        showingTranslation ? (translation?.title ?? discussion.title) : discussion.title
    }

    private var displayBody: String {
        showingTranslation ? (translation?.body ?? discussion.body) : discussion.body
    }

    /// Translated comments are only used when the server returned exactly as
    /// many as there are originals. A mismatched list would attribute one
    /// person's words to another, so the original is shown instead.
    private func commentText(at index: Int, fallback: String) -> String {
        guard showingTranslation,
              let translated = translation?.comments,
              translated.count == discussion.comments.count
        else { return fallback }
        return translated[index]
    }

    // MARK: Actions

    private func summarise() async {
        busy = .summary
        error = nil
        do {
            summary = try await session.api.authed(
                .post, "discussions/\(discussion.id)/summarize", as: SummaryDTO.self
            )
        } catch let e as APIError {
            error = e
        } catch {
            self.error = APIError.transport(error)
        }
        busy = nil
    }

    private func translate() async {
        if translation != nil {
            showingTranslation.toggle()
            return
        }
        busy = .translation
        error = nil
        do {
            translation = try await session.api.authed(
                .post, "discussions/\(discussion.id)/translate",
                body: TranslateBody(translateTo: "English"),
                as: TranslationDTO.self
            )
            showingTranslation = true
        } catch let e as APIError {
            error = e
        } catch {
            self.error = APIError.transport(error)
        }
        busy = nil
    }
}
