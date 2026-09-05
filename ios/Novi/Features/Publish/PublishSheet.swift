import SwiftUI

/// The compose sheet. Three ways in, in the order they are actually used —
/// pictures first, because that is what the feed is made of, and text last.
/// The sheet says plainly that nothing is wired behind it rather than opening a
/// camera it cannot save from: a control that looks live and does nothing
/// teaches the reader that the rest of the screen might be fake too.
struct PublishSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Names and notes are English catalog keys; translated at the point of display.
    private let options: [(String, String, String)] = [
        ("photo.on.rectangle", "Photo post", "Up to 18 photos"),
        ("video", "Video", "Up to 15 minutes"),
        ("text.alignleft", "Text post", "No photos needed"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .font(.system(size: 15))
                    .foregroundStyle(NV.inkSoft)
                Spacer()
                Text("Post")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(NV.ink)
                Spacer()
                Text("Cancel").font(.system(size: 15)).opacity(0)
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
                            Text(name.localized)
                                .font(.system(size: 15.5, weight: .medium))
                                .foregroundStyle(NV.ink)
                            Text(note.localized)
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

            Text("This is an interface replica. Posting isn't wired up yet.")
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
