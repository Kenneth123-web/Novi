import SwiftUI

@main
struct NoviApp: App {
    @StateObject private var session = AppSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                // Light only for now. A dark variant is a second palette to
                // keep honest, and every screen would need checking against it.
                .preferredColorScheme(.light)
                .tint(NV.spark)
        }
    }
}
