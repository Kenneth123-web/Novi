import SwiftUI

@main
struct NoviApp: App {
    @StateObject private var language = LanguageStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                // The reproduction is of the light app. A dark variant is a
                // second palette to keep honest, and there is nothing to check
                // it against yet.
                .preferredColorScheme(.light)
                .tint(NV.red)
                .environmentObject(language)
                // In-app language wins over the iPhone's: Settings → Language
                // writes the store, and the whole tree follows that locale.
                // Arabic also flips the layout direction.
                .environment(\.locale, Locale(identifier: AppLocalization.localeIdentifier(for: language.resolvedCode)))
                .environment(\.layoutDirection, AppLocalization.layoutDirection(for: language.resolvedCode))
        }
    }
}
