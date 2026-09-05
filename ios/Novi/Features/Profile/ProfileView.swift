import SwiftUI

/// 我. A banner, the identity block, the three counts, then the same waterfall
/// again under 笔记 / 收藏 / 赞过.
///
/// The counts are printed with their labels below rather than beside, because
/// "获赞与收藏" is five characters and no inline label row survives that at any
/// width worth having.
struct ProfileView: View {
    private let me = Fixtures.me
    @State private var tab = 0
    @State private var settings = Demo.settings
    /// English catalog keys; translated at the point of display.
    private let tabs = ["Notes", "Saved", "Liked"]

    private var notes: [Note] {
        switch tab {
        case 1: return Array(Fixtures.discover.prefix(6))
        case 2: return Array(Fixtures.nearby.prefix(4))
        default: return Array(Fixtures.following.prefix(5))
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                banner
                VStack(spacing: 0) {
                    identity
                    stats
                    actions
                }
                .background(NV.surface)
                lane
                grid
            }
        }
        .scrollIndicators(.hidden)
        .background(NV.page)
        .ignoresSafeArea(edges: .top)
        .sheet(isPresented: $settings) {
            SettingsSheet()
        }
    }

    private var banner: some View {
        CoverArt(seed: "banner-" + me.id)
            .frame(height: 190)
            .clipped()
            .overlay(alignment: .top) {
                LinearGradient(colors: [.black.opacity(0.18), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 90)
            }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 18) {
                    Image(systemName: "line.3.horizontal")
                    Button { settings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
                .font(.system(size: 19, weight: .light))
                .foregroundStyle(.white)
                .padding(.trailing, 18)
                .padding(.top, 58)
            }
    }

    private var identity: some View {
        HStack(alignment: .top, spacing: 14) {
            Avatar(name: me.name, size: 76)
                .overlay(Circle().stroke(.white, lineWidth: 3))
                .offset(y: -34)
                .padding(.bottom, -34)

            VStack(alignment: .leading, spacing: 6) {
                Text(me.name)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(NV.ink)
                Text("Novi ID: %@".localized(me.noviID))
                    .font(.system(size: 12))
                    .foregroundStyle(NV.inkFaint)
            }
            .padding(.top, 4)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private var stats: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(me.bio.isEmpty ? "No bio yet".localized : me.bio)
                .font(.system(size: 13.5))
                .foregroundStyle(NV.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 26) {
                count(me.following, "Following")
                count(me.followers, "Followers")
                count(me.liked, "Likes & saves")
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private func count(_ n: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(nv_count(n))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(NV.ink)
                .monospacedDigit()
            Text(label.localized)
                .font(.system(size: 11.5))
                .foregroundStyle(NV.inkFaint)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Text("Edit profile")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(NV.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(Capsule().stroke(NV.hairline, lineWidth: 1))

            Text("Share")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(NV.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(Capsule().stroke(NV.hairline, lineWidth: 1))

            Image(systemName: "person.badge.plus")
                .font(.system(size: 14))
                .foregroundStyle(NV.ink)
                .frame(width: 46, height: 32)
                .background(Capsule().stroke(NV.hairline, lineWidth: 1))
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }

    private var lane: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { i, name in
                VStack(spacing: 5) {
                    Text(name.localized)
                        .font(.system(size: 14.5, weight: i == tab ? .semibold : .regular))
                        .foregroundStyle(i == tab ? NV.ink : NV.inkFaint)
                    Capsule()
                        .fill(i == tab ? NV.ink : .clear)
                        .frame(width: 18, height: 2.5)
                }
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.18)) { tab = i }
                }
            }
        }
        .padding(.vertical, 10)
        .background(NV.surface)
        .hairline()
    }

    private var grid: some View {
        Waterfall(
            items: notes,
            estimatedHeight: { note, w in NoteCard.height(note, width: w) }
        ) { note, w in
            NoteCard(note: note, width: w)
        }
        .padding(.horizontal, NV.gutter)
        .padding(.top, NV.gutter)
        .padding(.bottom, 96)
    }
}
