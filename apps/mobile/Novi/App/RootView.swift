import SwiftUI

/// The three shells the app can be in, with the opening played over the top.
///
/// The intro is an OVERLAY rather than a fourth case, so the destination is
/// already laid out and rendered underneath while the animation runs. Fading
/// the overlay then reveals real content continuously, instead of exposing the
/// window's base colour for a frame while the next screen builds itself.
///
/// The gate is deliberately `introDone && phase != .launching`: whichever of
/// the animation and the stored-token check finishes last is what the user
/// waits for, and neither can skip ahead of the other.
struct RootView: View {
    @EnvironmentObject private var session: AppSession

    @State private var introDone = false

    private var ready: Bool {
        if case .launching = session.phase { return false }
        return introDone
    }

    var body: some View {
        ZStack {
            Group {
                switch session.phase {
                case .launching:
                    // Nothing behind the intro yet. Painted rather than empty
                    // so the fade has something to land on.
                    NV.page.ignoresSafeArea()
                case .signedOut:
                    AuthView()
                case .onboarding:
                    OnboardingView()
                case .ready:
                    MainTabs()
                }
            }
            .opacity(ready ? 1 : 0)

            if !introDone {
                LaunchIntroView { introDone = true }
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeOut(duration: 0.28), value: ready)
        .animation(.easeOut(duration: 0.25), value: session.phase)
        .task { await session.start() }
    }
}

struct MainTabs: View {
    @EnvironmentObject private var session: AppSession

    @State private var tab: RootTab = Demo.tab
    /// Held as `@State` on a reference type, which stores it without
    /// subscribing — this view must NOT re-run when the flag flips, because a
    /// body re-run here tears down whatever a nested stack has pushed.
    @State private var chrome = Chrome()

    /// Set when something elsewhere wants Ask opened with a question already
    /// in it — "I have a question" on a content page, or a concept tapped in
    /// the passport.
    @State private var askSeed: AskSeed?

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $tab) {
                HomeView(chrome: chrome, onAsk: openAsk)
                    .tag(RootTab.home)
                    .toolbar(.hidden, for: .tabBar)
                ExploreView(chrome: chrome, onAsk: openAsk)
                    .tag(RootTab.explore)
                    .toolbar(.hidden, for: .tabBar)
                AskView(seed: $askSeed, chrome: chrome)
                    .tag(RootTab.ask)
                    .toolbar(.hidden, for: .tabBar)
                PassportView(onAsk: openAsk)
                    .tag(RootTab.passport)
                    .toolbar(.hidden, for: .tabBar)
                ProfileView()
                    .tag(RootTab.profile)
                    .toolbar(.hidden, for: .tabBar)
            }

            TabBar(tab: $tab, chrome: chrome)
                // Only the bar ignores the keyboard. When the whole stack did,
                // the Ask composer could not rise either and the keyboard sat
                // straight on top of the one control the screen is for.
                .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .task {
            await session.loadSubjects()
            Demo.once("ask") {
                if let question = Demo.question {
                    openAsk(AskSeed(question: question))
                }
            }
        }
    }

    private func openAsk(_ seed: AskSeed) {
        askSeed = seed
        tab = .ask
    }
}

/// What a screen hands to Ask when it sends the learner there.
struct AskSeed: Equatable, Identifiable {
    var question: String = ""
    var contentID: UUID?
    var conceptID: UUID?
    var contentTitle: String?
    /// Submit immediately rather than waiting for the learner to tap send.
    var autoSubmit = true

    let id = UUID()
}
