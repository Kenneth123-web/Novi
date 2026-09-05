import SwiftUI

enum RootTab: Int, Hashable {
    case home, market, messages, me
}

/// Navigation-timed chrome, on an object of its own so that ONLY the tab bar
/// observes it. Anything above the navigation stacks that subscribes to a
/// published change re-runs its body, and a body re-run at the root tears down
/// whatever page a nested stack has pushed.
final class Chrome: ObservableObject {
    @Published var barHidden = false
}

/// Text tabs, not icons. That is the single most recognisable thing about this
/// bar, and it is a real decision rather than a saving: five glyphs would have
/// to be learned, where five words are read. It costs the bar its ability to
/// shrink, which is why the compose button is the only shape on it.
struct TabBar: View {
    @Binding var tab: RootTab
    @ObservedObject var chrome: Chrome
    var onCompose: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            item(.home, "Home")
            item(.market, "Market")

            Button(action: onCompose) {
                Image(systemName: "plus")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 30)
                    .background(NV.red, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            item(.messages, "Messages", badge: 60)
            item(.me, "Me")
        }
        .padding(.horizontal, 8)
        .frame(height: 50)
        .padding(.bottom, 2)
        .background {
            NV.surface
                .hairline(.top)
                .ignoresSafeArea(edges: .bottom)
        }
        .opacity(chrome.barHidden ? 0 : 1)
        // An invisible bar still takes touches.
        .allowsHitTesting(!chrome.barHidden)
        .animation(.easeOut(duration: 0.16), value: chrome.barHidden)
    }

    private func item(_ t: RootTab, _ label: String, badge: Int = 0) -> some View {
        let on = tab == t
        return Button {
            tab = t
        } label: {
            Text(label.localized)
                .font(.system(size: on ? 17 : 15.5, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? NV.ink : NV.inkFaint)
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text(badge > 99 ? "99+" : "\(badge)")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, badge > 9 ? 4 : 0)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(NV.red, in: Capsule())
                            .overlay(Capsule().stroke(.white, lineWidth: 1.5))
                            .offset(x: 15, y: -10)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
