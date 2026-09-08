import SwiftUI

/// One card in the waterfall: cover, up-to-two-line title, author, likes.
///
/// The order matters and is not negotiable — the picture is the reason anyone
/// stops, the title is the reason they tap, and the author is how they decide
/// whether to believe it. Putting the author above the title, which several
/// feed apps do, buries the only line that says what the note is about.
struct NoteCard: View {
    let note: Note
    let width: CGFloat
    var onOpen: () -> Void = {}

    @State private var liked = false

    static let titleFont = UIFont.systemFont(ofSize: 14.5, weight: .medium)
    private static let titleLeading: CGFloat = 3

    /// Must agree with the body below. A card that measures taller than it
    /// draws leaves a gap in its column; shorter, and the columns drift.
    static func height(_ note: Note, width: CGFloat) -> CGFloat {
        let cover = (width / max(0.4, note.ratio)).rounded()
        let lines = CGFloat(nv_lineCount(note.title, width: width - 20, font: titleFont))
        let title = lines * titleFont.lineHeight.rounded(.up) + (lines - 1) * titleLeading
        let badge: CGFloat = note.badge?.label != nil ? 21 : 0
        return cover + 9 + badge + title + 9 + 18 + 9
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                cover

                VStack(alignment: .leading, spacing: 0) {
                    if let label = note.badge?.label {
                        BadgeChip(kind: note.badge!, label: label)
                            .padding(.bottom, 5)
                    }

                    Text(note.title)
                        .font(Font(NoteCard.titleFont))
                        .foregroundStyle(NV.ink)
                        .lineSpacing(NoteCard.titleLeading)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    footer.padding(.top, 9)
                }
                .padding(.horizontal, 10)
                .padding(.top, 9)
                .padding(.bottom, 9)
            }
            .frame(width: width, alignment: .leading)
            .background(NV.surface)
            .clipShape(RoundedRectangle(cornerRadius: NV.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var cover: some View {
        CoverArt(seed: note.coverSeed)
            .frame(width: width, height: (width / max(0.4, note.ratio)).rounded())
            .clipped()
            .overlay(alignment: .center) {
                if note.badge == .video {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.95))
                        .frame(width: 30, height: 30)
                        .background(.black.opacity(0.22), in: Circle())
                        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                }
            }
            .overlay(alignment: .topLeading) {
                if note.badge == .live {
                    LiveFlag().padding(7)
                }
            }
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Avatar(name: note.author.name, size: 17)
            Text(note.author.name)
                .font(NV.meta())
                .foregroundStyle(NV.inkFaint)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 6)

            // A sibling of the card's own tap target, never nested inside it —
            // a Button inside a Button never receives its own taps.
            Image(systemName: liked ? "heart.fill" : "heart")
                .font(.system(size: 13.5, weight: liked ? .regular : .light))
                .foregroundStyle(liked ? NV.red : NV.inkFaint)
            Text(nv_count(note.likes + (liked ? 1 : 0)))
                .font(NV.meta())
                .foregroundStyle(NV.inkFaint)
                .monospacedDigit()
        }
        .frame(height: 18)
        .contentShape(.rect)
        .onTapGesture {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) { liked.toggle() }
        }
    }
}

/// 热点 / 直播中 — a red mark and a grey word. The mark carries the colour so
/// the word does not have to; a red label at 11pt beside a red heart at 13pt
/// puts two different reds in one row.
private struct BadgeChip: View {
    let kind: Note.Badge
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: kind == .hot ? "flame.fill" : "dot.radiowaves.left.and.right")
                .font(.system(size: 8.5))
                .foregroundStyle(.white)
                .frame(width: 14, height: 14)
                .background(NV.red, in: Circle())
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(NV.inkFaint)
        }
        .frame(height: 16)
    }
}

private struct LiveFlag: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 9, weight: .semibold))
            Text("直播中").font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 3.5)
        .background(NV.red.opacity(0.92), in: Capsule())
    }
}
