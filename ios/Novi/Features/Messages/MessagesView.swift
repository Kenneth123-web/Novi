import SwiftUI

/// 消息. Three aggregate rows across the top — likes, follows, mentions — then
/// the actual conversations. The aggregates come first because they are what
/// the badge on the tab is usually counting; putting them below the chat list
/// would make the number on the bar refer to something the reader has to scroll
/// to find.
struct MessagesView: View {
    private let buckets: [(String, String, Color, Int)] = [
        ("赞和收藏", "heart.fill", Color(hex: 0xFF6B81), 42),
        ("新增关注", "person.fill.badge.plus", Color(hex: 0x6FA8F5), 11),
        ("评论和@", "bubble.left.fill", Color(hex: 0xFFB055), 7),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                HStack(spacing: 0) {
                    ForEach(buckets, id: \.0) { name, icon, tint, count in
                        VStack(spacing: 8) {
                            Image(systemName: icon)
                                .font(.system(size: 20))
                                .foregroundStyle(.white)
                                .frame(width: 48, height: 48)
                                .background(tint, in: Circle())
                                .overlay(alignment: .topTrailing) {
                                    if count > 0 {
                                        Text("\(count)")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 5)
                                            .frame(minWidth: 18, minHeight: 18)
                                            .background(NV.red, in: Capsule())
                                            .overlay(Capsule().stroke(.white, lineWidth: 1.5))
                                            .offset(x: 6, y: -4)
                                    }
                                }
                            Text(name)
                                .font(.system(size: 12.5))
                                .foregroundStyle(NV.inkSoft)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 20)

                Rectangle().fill(NV.hairline).frame(height: 6).opacity(0.55)

                LazyVStack(spacing: 0) {
                    ForEach(Fixtures.threads) { t in
                        ThreadRow(thread: t)
                    }
                }
                .padding(.bottom, 96)
            }
            .scrollIndicators(.hidden)
        }
        .background(NV.surface)
    }

    private var header: some View {
        ZStack {
            Text("消息")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(NV.ink)
            HStack {
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(NV.ink)
            }
            .padding(.horizontal, 18)
        }
        .frame(height: 44)
        .background(NV.surface)
    }
}

private struct ThreadRow: View {
    let thread: MessageThread

    var body: some View {
        HStack(spacing: 12) {
            Avatar(name: thread.author.name, size: 46)
                .overlay(alignment: .topTrailing) {
                    if thread.unread > 0 {
                        Text("\(thread.unread)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 17, minHeight: 17)
                            .background(NV.red, in: Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 1.5))
                            .offset(x: 4, y: -2)
                    }
                }

            VStack(alignment: .leading, spacing: 5) {
                Text(thread.author.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(NV.ink)
                Text(thread.preview)
                    .font(.system(size: 13))
                    .foregroundStyle(NV.inkFaint)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(thread.time)
                .font(.system(size: 11.5))
                .foregroundStyle(NV.inkGhost)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(.rect)
    }
}
