import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    /// I-012: the completed-first-run choice is app state, not clinical data,
    /// so it lives outside the SwiftData store and outside backups.
    @AppStorage("hasCompletedFirstRun") private var hasCompletedFirstRun = false
    @State private var bootstrapState = BootstrapState.firstRun
    @State private var isPresentingSettings = false

    var body: some View {
        Group {
            switch bootstrapState {
            case .firstRun:
                FirstRunView {
                    hasCompletedFirstRun = true
                    refreshBootstrapState()
                }
            case .setupNeeded:
                setupNeededView
            case .captureReady:
                CaptureHomeView()
            }
        }
        .onAppear(perform: refreshBootstrapState)
        .sheet(isPresented: $isPresentingSettings, onDismiss: refreshBootstrapState) {
            TaxonomySettingsView()
        }
    }

    private var setupNeededView: some View {
        VStack(spacing: 16) {
            Text("Capture needs categories")
                .font(.title2)
                .bold()
            Text("Recording an intervention requires at least one active intervention category and one active drug class. Add or reactivate them to continue.")
                .multilineTextAlignment(.center)
            Button("Edit categories") {
                isPresentingSettings = true
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    /// A fetch failure here surfaces as the setup screen rather than a crash;
    /// store-open failures themselves still fail loudly at app start.
    private func refreshBootstrapState() {
        let activeTypeCount = (try? TaxonomyService.allInterventionTypes(in: modelContext))?
            .filter(\.isActive)
            .count ?? 0
        let activeClassCount = (try? TaxonomyService.allDrugClasses(in: modelContext))?
            .filter(\.isActive)
            .count ?? 0
        bootstrapState = BootstrapPolicy.state(
            hasCompletedFirstRun: hasCompletedFirstRun,
            activeInterventionTypeCount: activeTypeCount,
            activeDrugClassCount: activeClassCount
        )
    }
}
