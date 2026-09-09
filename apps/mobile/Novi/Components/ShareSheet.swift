import SwiftUI
import UIKit

/// `UIActivityViewController`, wrapped.
///
/// SwiftUI's `ShareLink` wants a `Transferable`, and a freshly rendered
/// `UIImage` that exists only in memory is easier to hand to UIKit directly
/// than to wrap in a transfer representation for one call site.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
