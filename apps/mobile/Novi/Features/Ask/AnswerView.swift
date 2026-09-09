import SwiftUI

/// The structured answer, rendered as sections.
///
/// The server returns JSON with named parts rather than one block of prose,
/// which is what lets this be a designed page instead of a wall of text. Any
/// section the model omitted is simply skipped — a missing "why it works" is
/// a shorter answer, not a broken one.
struct AnswerView: View {
    let answer: AskResponseDTO
    let askedQuestion: String
    var onOpen: (ContentDTO) -> Void
    var onFollowUp: (String) -> Void
    var onConcept: (RelatedConceptDTO) -> Void
    var onDiscussion: (DiscussionDTO) -> Void

    private var e: ExplanationDTO { answer.explanation }

    var body: some View {
        VStack(alignment: .leading, spacing: NV.Space.xl) {
            question
            explanation
            if !answer.watch.isEmpty || !answer.read.isEmpty || !answer.discuss.isEmpty
                || !answer.relatedConcepts.isEmpty {
                exploreHeader
            }
            if !answer.watch.isEmpty { rail("Watch", "play.rectangle", answer.watch) }
            if !answer.read.isEmpty { rail("Read", "doc.text", answer.read) }
            if !answer.discuss.isEmpty { discussions }
            if !answer.relatedConcepts.isEmpty { related }
        }
    }

    private var question: some View {
        VStack(alignment: .leading, spacing: NV.Space.xs) {
            if !e.concept.isEmpty {
                NVTag(text: e.concept, icon: "lightbulb", tint: NV.spark)
            }
            Text(askedQuestion)
                .font(NV.h2)
                .foregroundStyle(NV.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: NV.Space.l) {
            if !e.summary.isEmpty {
                Text(e.summary)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(NV.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(NV.Space.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NV.sparkSoft,
                                in: RoundedRectangle(cornerRadius: NV.Radius.card,
                                                     style: .continuous))
            }

            section("Explanation", "text.alignleft", e.simpleExplanation)
            section("Why it works", "gearshape", e.whyItWorks)
            section("Example", "function", e.example, mono: true)
            section(
                "Common misconception", "exclamationmark.triangle", e.commonMisconception,
                tint: NV.warning
            )
        }
    }

    @ViewBuilder
    private func section(
        _ title: String, _ icon: String, _ text: String,
        mono: Bool = false, tint: Color = NV.inkTertiary
    ) -> some View {
        if !text.isEmpty {
            VStack(alignment: .leading, spacing: NV.Space.s) {
                HStack(spacing: 6) {
                    Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                    Text(title.uppercased()).font(NV.caption)
                }
                .foregroundStyle(tint)

                Text(text)
                    .font(mono ? .system(size: 14.5, design: .monospaced) : NV.body)
                    .foregroundStyle(NV.ink)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(NV.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    private var exploreHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Explore this concept")
                .font(NV.h2)
                .foregroundStyle(NV.ink)
            Text("Where this idea shows up, and what people argue about")
                .font(NV.small)
                .foregroundStyle(NV.inkTertiary)
        }
        .padding(.top, NV.Space.s)
    }

    private func rail(_ title: String, _ icon: String, _ items: [ContentDTO]) -> some View {
        VStack(alignment: .leading, spacing: NV.Space.s) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                Text(title.uppercased()).font(NV.caption)
            }
            .foregroundStyle(NV.inkTertiary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: NV.Space.m) {
                    ForEach(items) { item in
                        RailCard(content: item) { onOpen(item) }
                    }
                }
                // The rail is inset by the page padding, but scrolls edge to
                // edge so a card is never clipped mid-swipe.
                .padding(.horizontal, 1)
            }
        }
    }

    private var discussions: some View {
        VStack(alignment: .leading, spacing: NV.Space.s) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 11, weight: .semibold))
                Text("DISCUSS").font(NV.caption)
            }
            .foregroundStyle(NV.inkTertiary)

            VStack(spacing: NV.Space.s) {
                ForEach(answer.discuss) { discussion in
                    Button { onDiscussion(discussion) } label: {
                        DiscussionRow(discussion: discussion)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var related: some View {
        VStack(alignment: .leading, spacing: NV.Space.s) {
            HStack(spacing: 6) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 11, weight: .semibold))
                Text("RELATED CONCEPTS").font(NV.caption)
            }
            .foregroundStyle(NV.inkTertiary)

            FlowRow(spacing: NV.Space.s, lineSpacing: NV.Space.s) {
                ForEach(answer.relatedConcepts) { concept in
                    if concept.conceptID != nil {
                        Button { onConcept(concept) } label: {
                            conceptChip(concept.name, tappable: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        // Named by the model but absent from our graph. Still
                        // part of the answer, so it is shown — just not as a
                        // link to a page that does not exist.
                        conceptChip(concept.name, tappable: false)
                    }
                }
            }

            Button {
                onFollowUp("How do these concepts connect to \(e.concept.isEmpty ? "this" : e.concept)?")
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 12, weight: .semibold))
                    Text("How do these connect?").font(NV.small.weight(.semibold))
                }
                .foregroundStyle(NV.spark)
                .padding(.top, NV.Space.xs)
            }
            .buttonStyle(.plain)
        }
    }

    private func conceptChip(_ name: String, tappable: Bool) -> some View {
        HStack(spacing: 5) {
            Text(name).font(NV.small.weight(.medium))
            if tappable {
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
            }
        }
        .foregroundStyle(tappable ? NV.spark : NV.inkTertiary)
        .padding(.horizontal, NV.Space.m)
        .padding(.vertical, 8)
        .background(tappable ? NV.sparkSoft : NV.fill, in: Capsule())
    }
}

/// A landscape card for the horizontal rails.
struct RailCard: View {
    let content: ContentDTO
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                CoverArt(seed: content.coverSeed)
                    .frame(width: 168, height: 100)
                    .clipped()
                    .overlay(alignment: .topLeading) {
                        if content.isSample {
                            NVTag(text: "Sample", tint: NV.ink.opacity(0.55), filled: true)
                                .padding(5)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if let seconds = content.durationSeconds {
                            Text(nv_duration(seconds))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(.black.opacity(0.45), in: Capsule())
                                .padding(5)
                        }
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(content.title)
                        .font(NV.small.weight(.medium))
                        .foregroundStyle(NV.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 4) {
                        Text(content.platform.capitalized)
                        Text("·")
                        Text(nv_count(content.likes))
                    }
                    .font(NV.caption)
                    .foregroundStyle(NV.inkTertiary)
                }
                .padding(9)
                // Fixed height so the row of cards has one baseline; a
                // two-line title next to a one-line title would otherwise
                // leave the metadata at two different heights.
                .frame(width: 168, height: 62, alignment: .topLeading)
            }
            .frame(width: 168)
            .cardSurface(NV.Radius.control)
        }
        .buttonStyle(.plain)
    }
}

struct DiscussionRow: View {
    let discussion: DiscussionDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                NVTag(text: discussion.community, icon: "person.2", tint: NV.spark)
                Spacer(minLength: 0)
                Label(nv_count(discussion.upvotes), systemImage: "arrow.up")
                    .font(NV.caption)
                    .foregroundStyle(NV.inkTertiary)
                Label(nv_count(discussion.commentCount), systemImage: "bubble.left")
                    .font(NV.caption)
                    .foregroundStyle(NV.inkTertiary)
            }
            Text(discussion.title)
                .font(NV.bodyStrong)
                .foregroundStyle(NV.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(discussion.body)
                .font(NV.small)
                .foregroundStyle(NV.inkSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(NV.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(NV.Radius.control)
    }
}
