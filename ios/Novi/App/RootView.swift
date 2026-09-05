import SwiftUI

struct RootView: View {
    @State private var tab: RootTab = Demo.tab
    @State private var composing = false

    /// Held as `@State` on a reference type, which stores it without
    /// subscribing to it — the whole point is that RootView must NOT re-run
    /// when the flag flips. The bar takes it as an `@ObservedObject` and is
    /// the only thing that watches it.
    @State private var chrome = Chrome()

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $tab) {
                HomeView(chrome: chrome)
                    .tag(RootTab.home)
                    .toolbar(.hidden, for: .tabBar)
                MarketView()
                    .tag(RootTab.market)
                    .toolbar(.hidden, for: .tabBar)
                MessagesView()
                    .tag(RootTab.messages)
                    .toolbar(.hidden, for: .tabBar)
                ProfileView()
                    .tag(RootTab.me)
                    .toolbar(.hidden, for: .tabBar)
            }

            TabBar(tab: $tab, chrome: chrome) { composing = true }
        }
        .ignoresSafeArea(.keyboard)
        .onAppear { if Demo.publish { composing = true } }
        .sheet(isPresented: $composing) {
            PublishSheet()
        }
    }
}
