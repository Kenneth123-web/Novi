import SwiftUI

/// A card in the masonry.
///
/// `height(for:width:)` MUST agree with what `body` actually draws. Measured
/// taller than drawn and the column shows a gap; shorter and the two columns
/// drift out of alignment as you scroll. Change one and you change the other.
struct ContentCard: View {
    let item: FeedItemDTO
    var onOpen: () -> Void
    var onSave: () -> Void

    private var content: ContentDTO { item.content }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                cover
                VStack(alignment: .leading, spacing: 6) {
                    Text(content.title)
                        .font(NV.cardTitle)
                        .foregroundStyle(NV.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    footer
                }
                .padding(.horizontal, 9)
                .padding(.top, 8)
                .padding(.bottom, 9)
            }
            .background(NV.surface)
            .clipShape(RoundedRectangle(cornerRadius: NV.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var cover: some View {
        CoverArt(seed: content.coverSeed)
            .aspectRatio(content.thumbnailRatio, contentMode: .fill)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(alignment: .topLeading) {
                // The one place the app admits what this content is. A
                // placeholder that looks ingested makes the product look
                // finished when the hardest part has not been built.
                if content.isSample {
                    NVTag(text: "Sample", tint: NV.ink.opacity(0.55), filled: true)
                        .padding(6)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if content.mediaKind == "video", let seconds = content.durationSeconds {
                    HStack(spacing: 3) {
                        Image(systemName: "play.fill").font(.system(size: 8, weight: .bold))
                        Text(nv_duration(seconds)).font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(6)
                }
            }
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Avatar(name: content.creator, size: 15)
            Text(content.creator)
                .font(NV.cardMeta)
                .foregroundStyle(NV.inkFaint)
                .lineLimit(1)
            Spacer(minLength: 2)
            // The heart is the count's label; the bookmark is a control. They
            // were adjacent with one number between them, which read as
            // "590 saves" when it is the like count.
            HStack(spacing: 2) {
                Image(systemName: "heart")
                    .font(.system(size: 10, weight: .medium))
                Text(nv_count(content.likes))
                    .font(NV.cardMeta)
            }
            .foregroundStyle(NV.inkFaint)

            Button(action: onSave) {
                Image(systemName: item.isSaved ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(item.isSaved ? NV.accent : NV.inkFaint)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Height

    /// The masonry places a card before it can measure one, so the estimate
    /// has to be computed rather than observed.
    static func height(for item: FeedItemDTO, width: CGFloat) -> CGFloat {
        let content = item.content
        let cover = width / max(0.4, CGFloat(content.thumbnailRatio))

        // Title lines via boundingRect, not characters ÷ width. Mixed Latin,
        // CJK and digits have no single character width, and being wrong by
        // one line is a visible step in the column.
        let titleWidth = width - 18
        let font = UIFont.systemFont(ofSize: 14.5, weight: .medium)
        let bounds = (content.title as NSString).boundingRect(
            with: CGSize(width: titleWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        let lineHeight = font.lineHeight
        let lines = min(2, max(1, Int(ceil(bounds.height / lineHeight))))

        //  8 top padding + title + 6 gap + 15 footer + 9 bottom padding
        return cover + 8 + lineHeight * CGFloat(lines) + 6 + 15 + 9
    }
}
