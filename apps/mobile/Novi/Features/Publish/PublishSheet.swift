import SwiftUI

/// The compose sheet. Three ways in, in the order they are actually used —
/// pictures first, because that is what the feed is made of, and text last.
/// The sheet says plainly that nothing is wired behind it rather than opening a
/// camera it cannot save from: a control that looks live and does nothing
/// teaches the reader that the rest of the screen might be fake too.
struct PublishSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let options: [(String, String, String)] = [
        ("photo.on.rectangle", "图文", "最多 18 张图片"),
        ("video", "视频", "最长 15 分钟"),
        ("text.alignleft", "文字", "只写字也可以"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("取消") { dismiss() }
                    .font(.system(size: 15))
                    .foregroundStyle(NV.inkSoft)
                Spacer()
                Text("发布")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(NV.ink)
                Spacer()
                Text("取消").font(.system(size: 15)).opacity(0)
            }
            .padding(.horizontal, 18)
            .frame(height: 52)
            .hairline()

            VStack(spacing: 0) {
                ForEach(options, id: \.1) { icon, name, note in
                    HStack(spacing: 14) {
                        Image(systemName: icon)
                            .font(.system(size: 19, weight: .light))
                            .foregroundStyle(NV.ink)
                            .frame(width: 42, height: 42)
                            .background(NV.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(name)
                                .font(.system(size: 15.5, weight: .medium))
                                .foregroundStyle(NV.ink)
                            Text(note)
                                .font(.system(size: 12))
                                .foregroundStyle(NV.inkFaint)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(NV.inkGhost)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
            }
            .padding(.top, 10)

            Text("这是界面复刻，发布还没有接后端。")
                .font(.system(size: 12))
                .foregroundStyle(NV.inkGhost)
                .padding(.top, 18)

            Spacer()
        }
        .background(NV.surface)
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
    }
}
