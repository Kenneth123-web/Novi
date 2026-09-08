import SwiftUI

enum RootTab: Int, Hashable, CaseIterable {
    case home, explore, ask, passport, profile

    var title: String {
        switch self {
        case .home: return "Home"
        case .explore: return "Explore"
        case .ask: return "Ask"
        case .passport: return "Passport"
        case .profile: return "Profile"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .explore: return "safari"
        case .ask: return "sparkles"
        case .passport: return "checkmark.seal"
        case .profile: return "person"
        }
    }

    var filledIcon: String {
        switch self {
        case .home: return "house.fill"
        case .explore: return "safari.fill"
        case .ask: return "sparkles"
        case .passport: return "checkmark.seal.fill"
        case .profile: return "person.fill"
        }
    }
}

/// Navigation-timed chrome, on an object of its own so ONLY the bar observes
/// it. Anything above the navigation stacks that subscribes to a published
/// change re-runs its body, and a body re-run at the root tears down whatever
/// page a nested stack has pushed.
final class Chrome: ObservableObject {
    @Published var barHidden = false
}

/// Five tabs, with Ask raised into the bar as the one shape on it.
///
/// Ask is the product's centre — the loop is feed, question, understanding,
/// discovery — so it gets the position the eye and thumb both land on, and the
/// only accent-coloured element in the chrome.
struct TabBar: View {
    @Binding var tab: RootTab
    @ObservedObject var chrome: Chrome

    var body: some View {
        HStack(spacing: 0) {
            item(.home)
            item(.explore)
            askButton
            item(.passport)
            item(.profile)
        }
        .padding(.horizontal, NV.Space.s)
        .frame(height: NV.tabBarHeight - 2)
        .padding(.bottom, 2)
        .background {
            NV.surface
                .hairline(.top)
                .ignoresSafeArea(edges: .bottom)
        }
        .opacity(chrome.barHidden ? 0 : 1)
        // A fully transparent bar still takes touches; this is not UIKit's
        // `alpha: 0`.
        .allowsHitTesting(!chrome.barHidden)
        .animation(.easeOut(duration: 0.16), value: chrome.barHidden)
    }

    private var askButton: some View {
        Button {
            tab = .ask
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 32)
                    .background(
                        LinearGradient(
                            colors: [NV.accent, NV.accentDeep],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                    )
                Text(RootTab.ask.title)
                    .font(.system(size: 10, weight: tab == .ask ? .semibold : .medium))
                    .foregroundStyle(tab == .ask ? NV.accent : NV.inkFaint)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func item(_ t: RootTab) -> some View {
        let on = tab == t
        return Button {
            tab = t
        } label: {
            VStack(spacing: 4) {
                Image(systemName: on ? t.filledIcon : t.icon)
                    .font(.system(size: 18, weight: on ? .semibold : .regular))
                Text(t.title)
                    .font(.system(size: 10, weight: on ? .semibold : .medium))
            }
            .foregroundStyle(on ? NV.ink : NV.inkFaint)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
