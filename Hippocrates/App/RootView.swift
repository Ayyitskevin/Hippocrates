import SwiftUI

struct RootView: View {
    var body: some View {
        // Capture UI intentionally starts only after the empty taxonomies and
        // configuration decisions are reviewed. This is not a dashboard.
        Text("Configuration decisions are required before capture is enabled.")
            .font(.headline)
            .multilineTextAlignment(.center)
            .padding()
    }
}
