import SwiftUI

@main
struct NoviApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                // The reproduction is of the light app. A dark variant is a
                // second palette to keep honest, and there is nothing to check
                // it against yet.
                .preferredColorScheme(.light)
                .tint(NV.red)
        }
    }
}
