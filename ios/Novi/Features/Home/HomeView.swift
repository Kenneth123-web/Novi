import SwiftUI

enum HomeTab: Int, CaseIterable, Hashable {
    case following, discover, nearby

    /// English catalog keys; translated at the point of display.
    var title: String {
        switch self {
        case .following: return "Following"
        case .discover: return "Discover"
        case .nearby: return "Nearby"
        }
    }

    var notes: [Note] {
        switch self {
        case .following: return Fixtures.following
        case .discover: return Fixtures.discover
        case .nearby: return Fixtures.nearby
        }
    }
}

struct HomeView: View {
    @ObservedObject var chrome: Chrome

    @State private var tab: HomeTab = .discover
    @State private var path = NavigationPath()
    @Namespace private var underline

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                TopBar(tab: $tab, underline: underline)

                // Paged, because the three lanes are swiped between in the
                // real app and the underline has to be able to follow a
                // half-finished drag. A switch statement cannot be dragged.
                TabView(selection: $tab) {
                    ForEach(HomeTab.allCases, id: \.self) { t in
                        Feed(notes: t.notes, lane: t) { note in
                            path.append(note)
                        }
                        .tag(t)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .background(NV.page)
            .navigationDestination(for: Note.self) { note in
                NoteDetailView(note: note, chrome: chrome)
            }
            .task {
                Demo.once {
                    if let lane = Demo.lane { tab = lane }
                    if let note = Demo.note { path.append(note) }
                }
            }
        }
    }
}

// MARK: - The bar

private struct TopBar: View {
    @Binding var tab: HomeTab
    let underline: Namespace.ID

    var body: some View {
        ZStack {
            HStack {
                Image(systemName: "bubble.left")
                    .font(.system(size: 21, weight: .light))
                    .foregroundStyle(NV.ink)
                Spacer()
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(NV.ink)
            }
            .padding(.horizontal, 18)

            HStack(spacing: 20) {
                ForEach(HomeTab.allCases, id: \.self) { t in
                    TabItem(
                        tab: t,
                        selected: tab == t,
                        badge: t == .following ? 11 : 0,
                        underline: underline
                    )
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.22)) { tab = t }
                    }
                }
            }
        }
        .frame(height: 44)
        .background(NV.surface)
    }
}

private struct TabItem: View {
    let tab: HomeTab
    let selected: Bool
    let badge: Int
    let underline: Namespace.ID

    var body: some View {
        VStack(spacing: 4) {
            Text(tab.title.localized)
                // Weight AND size change together. Weight alone is too quiet
                // between 中文 glyphs, which have no ascenders to thicken.
                .font(.system(size: selected ? 18 : 16, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? NV.ink : NV.inkFaint)
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text("\(badge)")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, badge > 9 ? 4 : 0)
                            .frame(minWidth: 15, minHeight: 15)
                            .background(NV.red, in: Capsule())
                            .overlay(Capsule().stroke(.white, lineWidth: 1.5))
                            .offset(x: 12, y: -9)
                    }
                }

            Group {
                if selected {
                    Capsule()
                        .fill(NV.red)
                        .matchedGeometryEffect(id: "home-underline", in: underline)
                        .frame(width: 17, height: 3)
                } else {
                    Color.clear.frame(width: 17, height: 3)
                }
            }
        }
        .frame(height: 34)
        .contentShape(.rect)
    }
}

// MARK: - The feed

private struct Feed: View {
    let notes: [Note]
    let lane: HomeTab
    let open: (Note) -> Void

    @State private var refreshed = false

    var body: some View {
        ScrollView {
            Waterfall(
                items: notes,
                estimatedHeight: { note, w in NoteCard.height(note, width: w) }
            ) { note, w in
                NoteCard(note: note, width: w) { open(note) }
            }
            .padding(.horizontal, NV.gutter)
            .padding(.top, NV.gutter)

            Text("- That's everything -")
                .font(.system(size: 12))
                .foregroundStyle(NV.inkGhost)
                .frame(maxWidth: .infinity)
                .padding(.top, 22)
                // Clears the tab bar. The bar is opaque and sits on top of the
                // scroll view, so the last row would otherwise end underneath it.
                .padding(.bottom, 96)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            try? await Task.sleep(nanoseconds: 700_000_000)
            refreshed = true
        }
        .background(NV.page)
    }
}
