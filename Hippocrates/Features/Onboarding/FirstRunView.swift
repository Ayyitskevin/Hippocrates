import SwiftData
import SwiftUI

/// The sanctioned pre-bootstrap gate: a responsibility notice (P-001) and the
/// explicit starter-taxonomy offer (P-003). It appears once; after completion
/// every ordinary launch goes directly to capture. Restore joins this gate in
/// a later milestone (I-003) and is shown disabled until then.
struct FirstRunView: View {
    private enum Step {
        case notice
        case starterOffer
    }

    @Environment(\.modelContext) private var modelContext
    @State private var step = Step.notice
    @State private var selectedTypeLabels = Set(StarterTaxonomy.interventionTypeLabels)
    @State private var selectedClassLabels = Set(StarterTaxonomy.drugClassLabels)
    @State private var selectedLineLabels = Set(StarterTaxonomy.serviceLineLabels)
    @State private var failureText: String?

    let onComplete: () -> Void

    var body: some View {
        switch step {
        case .notice:
            noticeView
        case .starterOffer:
            starterOfferView
        }
    }

    private var noticeView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Welcome to Hippocrates")
                    .font(.largeTitle)
                    .bold()
                Text("Hippocrates is a private, offline ledger of your own completed professional work: interventions you have already made and drug-information answers you have already written.")
                Text("It stores no patient identifiers, performs no clinical calculations, gives no recommendations, and never connects to a network. Your records stay on this device.")
                Text("You are responsible for following your institution's policies on personal devices and professional documentation. Hippocrates cannot verify hospital policy and is not a substitute for it.")
                Button {
                    step = .starterOffer
                } label: {
                    Text("I understand my responsibilities")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button("Restore from a backup") {
                }
                .disabled(true)
                Text("Restore becomes available in an upcoming build.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    private var starterOfferView: some View {
        NavigationStack {
            List {
                Section {
                    Text("These common starting categories are optional. Review them, switch off any you do not want, or start with empty lists and add your own later. Nothing is added without your choice here.")
                        .font(.callout)
                }
                Section("Intervention categories") {
                    ForEach(StarterTaxonomy.interventionTypeLabels, id: \.self) { label in
                        Toggle(label, isOn: toggleBinding(for: label, in: $selectedTypeLabels))
                    }
                }
                Section("Drug classes") {
                    ForEach(StarterTaxonomy.drugClassLabels, id: \.self) { label in
                        Toggle(label, isOn: toggleBinding(for: label, in: $selectedClassLabels))
                    }
                }
                Section("Service lines") {
                    ForEach(StarterTaxonomy.serviceLineLabels, id: \.self) { label in
                        Toggle(label, isOn: toggleBinding(for: label, in: $selectedLineLabels))
                    }
                }
                Section {
                    Button {
                        completeFirstRun(seedingSelection: true)
                    } label: {
                        Text("Add selected categories")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Start with empty lists") {
                        completeFirstRun(seedingSelection: false)
                    }
                }
            }
            .navigationTitle("Starting categories")
        }
        .alert(
            "Setup could not be completed",
            isPresented: failureAlertBinding
        ) {
            Button("OK", role: .cancel) {
            }
        } message: {
            Text(failureText ?? "Try again. If the problem continues, restart the app.")
        }
    }

    private var failureAlertBinding: Binding<Bool> {
        Binding(
            get: { failureText != nil },
            set: { isPresented in
                if isPresented == false {
                    failureText = nil
                }
            }
        )
    }

    private func toggleBinding(
        for label: String,
        in selection: Binding<Set<String>>
    ) -> Binding<Bool> {
        Binding(
            get: { selection.wrappedValue.contains(label) },
            set: { isOn in
                if isOn {
                    selection.wrappedValue.insert(label)
                } else {
                    selection.wrappedValue.remove(label)
                }
            }
        )
    }

    /// Creates the policy-neutral configuration row, then applies only the
    /// labels the user left selected. Order within each list is preserved.
    private func completeFirstRun(seedingSelection: Bool) {
        do {
            _ = try AppConfigService.fetchOrCreate(in: modelContext)
            if seedingSelection {
                try TaxonomyService.seedStarterTaxonomies(
                    interventionTypeLabels: StarterTaxonomy.interventionTypeLabels
                        .filter { selectedTypeLabels.contains($0) },
                    drugClassLabels: StarterTaxonomy.drugClassLabels
                        .filter { selectedClassLabels.contains($0) },
                    serviceLineLabels: StarterTaxonomy.serviceLineLabels
                        .filter { selectedLineLabels.contains($0) },
                    in: modelContext
                )
            }
            onComplete()
        } catch {
            failureText = "The starting configuration could not be saved. Try again."
        }
    }
}
