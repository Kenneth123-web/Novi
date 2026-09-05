import SwiftUI

/// The note page. Full-bleed pictures, then the words, then the comments —
/// and a fixed bar at the bottom that never leaves, because on this screen the
/// three things a reader does (comment, like, save) have to be reachable from
/// wherever they stopped reading.
struct NoteDetailView: View {
    let note: Note
    @ObservedObject var chrome: Chrome

    @Environment(\.dismiss) private var dismiss
    @State private var page = 0
    @State private var liked = false
    @State private var collected = false
    @State private var following = false

    private let tagInk = Color(hex: 0x39587F)

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    gallery
                    words
                    Rectangle().fill(NV.hairline).frame(height: 6).opacity(0.55)
                    comments
                }
            }
            .scrollIndicators(.hidden)
            actionBar
        }
        .background(NV.surface)
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        // The bar belongs to the feed, not to a note. Written here rather than
        // derived from the navigation path, so it is correct however the page
        // was reached and restores itself by symmetry on the way out.
        .onAppear { chrome.barHidden = true }
        .onDisappear { chrome.barHidden = false }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(NV.ink)
            }

            Avatar(name: note.author.name, size: 30)
            Text(note.author.name)
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(NV.ink)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button {
                withAnimation(.easeOut(duration: 0.18)) { following.toggle() }
            } label: {
                // "Following (button)" is a manual catalog key: English reuses
                // the word "Following" for the feed lane, but Chinese splits
                // the two into 关注 and 已关注.
                Text(following ? "Following (button)".localized : "Follow".localized)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(following ? NV.inkFaint : .white)
                    .frame(width: 58, height: 28)
                    .background {
                        if following {
                            Capsule().stroke(NV.hairline, lineWidth: 1)
                        } else {
                            Capsule().fill(NV.red)
                        }
                    }
            }
            .buttonStyle(.plain)

            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(NV.ink)
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(NV.surface)
        .hairline()
    }

    // MARK: Pictures

    private var gallery: some View {
        GeometryReader { g in
            let h = g.size.width / max(0.5, note.ratio)
            ZStack(alignment: .bottom) {
                TabView(selection: $page) {
                    ForEach(0..<note.photos, id: \.self) { i in
                        CoverArt(seed: "\(note.coverSeed)-\(i)")
                            .frame(width: g.size.width, height: h)
                            .clipped()
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(width: g.size.width, height: h)

                if note.photos > 1 {
                    HStack(spacing: 5) {
                        ForEach(0..<note.photos, id: \.self) { i in
                            Circle()
                                .fill(i == page ? Color.white : Color.white.opacity(0.45))
                                .frame(width: 5.5, height: 5.5)
                        }
                    }
                    .padding(.bottom, 12)
                }
            }
            .frame(width: g.size.width, height: h)
        }
        .aspectRatio(max(0.5, note.ratio), contentMode: .fit)
    }

    // MARK: Words

    private var words: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(note.title)
                .font(.system(size: 17.5, weight: .semibold))
                .foregroundStyle(NV.ink)
                .fixedSize(horizontal: false, vertical: true)

            if !note.body.isEmpty {
                Text(note.body)
                    .font(.system(size: 15))
                    .foregroundStyle(NV.ink)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !note.tags.isEmpty {
                FlowRow(spacing: 8, lineSpacing: 6) {
                    ForEach(note.tags, id: \.self) { t in
                        Text("#" + t)
                            .font(.system(size: 14.5))
                            .foregroundStyle(tagInk)
                    }
                }
            }

            HStack(spacing: 6) {
                Text(note.postedAt)
                if let place = note.place {
                    Text(place)
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(NV.inkGhost)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 18)
    }

    // MARK: Comments

    private var comments: some View {
        let list = Fixtures.comments(for: note)
        return VStack(alignment: .leading, spacing: 0) {
            Text("%@ comments".localized(nv_count(note.comments)))
                .font(.system(size: 13))
                .foregroundStyle(NV.inkFaint)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

            ForEach(list) { c in
                CommentRow(comment: c, indent: 0)
                ForEach(c.replies) { r in
                    CommentRow(comment: r, indent: 40)
                }
            }

            Text("- No more comments -")
                .font(.system(size: 12))
                .foregroundStyle(NV.inkGhost)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
        }
    }

    // MARK: Bottom bar

    private var actionBar: some View {
        HStack(spacing: 16) {
            HStack {
                Text("Say something...")
                    .font(.system(size: 13.5))
                    .foregroundStyle(NV.inkGhost)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(NV.fill, in: Capsule())

            Counter(icon: liked ? "heart.fill" : "heart",
                    tint: liked ? NV.red : NV.ink,
                    value: note.likes + (liked ? 1 : 0)) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) { liked.toggle() }
            }
            Counter(icon: collected ? "star.fill" : "star",
                    tint: collected ? Color(hex: 0xFFB300) : NV.ink,
                    value: note.collects + (collected ? 1 : 0)) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) { collected.toggle() }
            }
            Counter(icon: "bubble.right", tint: NV.ink, value: note.comments) {}
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(NV.surface)
        .hairline(.top)
    }
}

private struct Counter: View {
    let icon: String
    let tint: Color
    let value: Int
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .light))
                    .foregroundStyle(tint)
                Text(nv_count(value))
                    .font(.system(size: 12.5))
                    .foregroundStyle(NV.inkSoft)
                    .monospacedDigit()
            }
        }
        .buttonStyle(.plain)
    }
}

private struct CommentRow: View {
    let comment: Comment
    let indent: CGFloat
    @State private var liked = false

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Avatar(name: comment.author.name, size: indent > 0 ? 24 : 30)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(comment.author.name)
                        .font(.system(size: 12.5))
                        .foregroundStyle(NV.inkFaint)
                    if comment.isAuthor {
                        Text("Author")
                            .font(.system(size: 9.5))
                            .foregroundStyle(NV.red)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(NV.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 3))
                    }
                }
                Text(comment.text)
                    .font(.system(size: 14.5))
                    .foregroundStyle(NV.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(comment.time)
                    .font(.system(size: 11))
                    .foregroundStyle(NV.inkGhost)
            }

            Spacer(minLength: 8)

            VStack(spacing: 2) {
                Image(systemName: liked ? "heart.fill" : "heart")
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(liked ? NV.red : NV.inkGhost)
                Text(nv_count(comment.likes + (liked ? 1 : 0)))
                    .font(.system(size: 11))
                    .foregroundStyle(NV.inkGhost)
                    .monospacedDigit()
            }
            .contentShape(.rect)
            .onTapGesture {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) { liked.toggle() }
            }
        }
        .padding(.leading, 16 + indent)
        .padding(.trailing, 16)
        .padding(.vertical, 9)
    }
}
