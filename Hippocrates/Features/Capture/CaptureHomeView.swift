import SwiftUI

/// The capture-ready home. Ordinary launches land here directly (architecture:
/// no dashboard, no recurring welcome). Capture is the first tab; the recent
/// ledger and category settings are one tap away.
struct CaptureHomeView: View {
    var body: some View {
        TabView {
            Tab("Capture", systemImage: "plus.circle.fill") {
                CaptureView()
            }
            Tab("Recent", systemImage: "list.bullet.rectangle") {
                NavigationStack {
                    RecentLedgerView()
                }
            }
            Tab("Categories", systemImage: "slider.horizontal.3") {
                TaxonomySettingsView()
            }
        }
    }
}
