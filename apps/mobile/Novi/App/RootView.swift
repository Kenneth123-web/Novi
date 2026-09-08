import SwiftUI

/// The three shells the app can be in, and nothing else.
struct RootView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        Group {
            switch session.phase {
            case .launching: LaunchView()
            case .signedOut: AuthView()
            case .onboarding: OnboardingView()
            case .ready: MainTabs()
            }
        }
        .animation(.easeOut(duration: 0.25), value: session.phase)
        .task { await session.start() }
    }
}

/// Held for the moment it takes to check the stored token. Deliberately just
/// the wordmark: a spinner here flashes for 40ms on a warm launch and reads as
/// jank.
private struct LaunchView: View {
    var body: some View {
        ZStack {
            NV.surface.ignoresSafeArea()
            Text("Novi")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(NV.accent)
        }
    }
}

struct MainTabs: View {
    @EnvironmentObject private var session: AppSession

    @State private var tab: RootTab = Demo.tab
    /// Held as `@State` on a reference type, which stores it without
    /// subscribing — this view must NOT re-run when the flag flips, because a
    /// body re-run here tears down whatever a nested stack has pushed.
    @State private var chrome = Chrome()

    /// Set when something elsewhere wants the Ask tab opened with a question
    /// already in it — "I have a question" on a content page, or a concept
    /// tapped in the passport.
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
        }
        .ignoresSafeArea(.keyboard)
        .task {
            await session.loadSubjects()
            Demo.once {
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
