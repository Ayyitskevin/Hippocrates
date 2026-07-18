import SwiftData
import SwiftUI

/// I-013: a bounded recent-entries ledger. It resolves the pending-outcome gap
/// (flip acceptance once the recommendation's result is known), corrects
/// mistaken structured fields, and deletes bad entries with confirmation. It
/// offers no free text, no narrative, and no per-record notes.
struct RecentLedgerView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var items: [InterventionSummary] = []
    @State private var editingItem: InterventionSummary?
    @State private var pendingDeletion: InterventionSummary?
    @State private var failureText: String?

    var body: some View {
        List {
            if items.isEmpty {
                ContentUnavailableView(
                    "No interventions yet",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Recorded interventions appear here for quick outcome updates and corrections.")
                )
            }
            ForEach(items) { item in
                Button {
                    editingItem = item
                } label: {
                    LedgerRow(item: item)
                }
                .swipeActions(edge: .trailing) {
                    Button("Remove", role: .destructive) {
                        pendingDeletion = item
                    }
                }
                .swipeActions(edge: .leading) {
                    if item.acceptance != .accepted {
                        Button("Accept") {
                            setAcceptance(.accepted, for: item)
                        }
                        .tint(.green)
                    }
                    if item.acceptance != .rejected {
                        Button("Reject") {
                            setAcceptance(.rejected, for: item)
                        }
                        .tint(.orange)
                    }
                }
            }
        }
        .navigationTitle("Recent")
        .sheet(item: $editingItem, onDismiss: reload) { item in
            InterventionEditSheet(item: item)
        }
        .confirmationDialog(
            "Remove this intervention?",
            isPresented: deletionDialogBinding,
            presenting: pendingDeletion
        ) { item in
            Button("Remove permanently", role: .destructive) {
                deleteItem(item)
            }
            Button("Cancel", role: .cancel) {
            }
        } message: { _ in
            Text("This cannot be undone once confirmed.")
        }
        .alert("Could not update", isPresented: failureAlertBinding) {
            Button("OK", role: .cancel) {
            }
        } message: {
            Text(failureText ?? "Try again.")
        }
        .onAppear(perform: reload)
    }

    private var deletionDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { isPresented in
                if isPresented == false {
                    pendingDeletion = nil
                }
            }
        )
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

    private func reload() {
        do {
            items = try InterventionLedgerService.recent(in: modelContext)
        } catch {
            failureText = "The recent list could not be loaded."
        }
    }

    private func setAcceptance(_ acceptance: Acceptance, for item: InterventionSummary) {
        do {
            try InterventionLedgerService.setAcceptance(
                acceptance,
                forInterventionID: item.id,
                in: modelContext
            )
        } catch {
            failureText = "The outcome could not be updated."
        }
        reload()
    }

    private func deleteItem(_ item: InterventionSummary) {
        do {
            try InterventionLedgerService.deleteIntervention(id: item.id, in: modelContext)
        } catch {
            failureText = "The entry could not be removed."
        }
        reload()
    }
}

private struct LedgerRow: View {
    let item: InterventionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.typeLabel ?? "Unspecified type")
                    .font(.body)
                Spacer()
                Text(item.timestamp, format: .dateTime.month().day().hour().minute())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                if let drugClassLabel = item.drugClassLabel {
                    Text(drugClassLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                acceptanceBadge
            }
        }
    }

    /// Color is never the only signal: the badge always carries text.
    private var acceptanceBadge: some View {
        Text(AcceptanceDisplay.label(item.acceptance))
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.2), in: Capsule())
            .foregroundStyle(badgeColor)
    }

    private var badgeColor: Color {
        switch item.acceptance {
        case .accepted:
            return .green
        case .rejected:
            return .orange
        case .pending:
            return .blue
        case .notApplicable:
            return .gray
        }
    }
}

/// Structured-only edit surface: pickers and a numeric field. There is no text
/// field for narrative, preserving the no-free-text invariant on interventions.
private struct InterventionEditSheet: View {
    let item: InterventionSummary

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var typeOptions: [PickerOption] = []
    @State private var drugClassOptions: [PickerOption] = []
    @State private var serviceLineOptions: [PickerOption] = []

    @State private var selectedTypeID: UUID?
    @State private var selectedDrugClassID: UUID?
    @State private var selectedServiceLineID: UUID?
    @State private var acceptance: Acceptance
    @State private var minutesText: String
    @State private var hasCost: Bool
    @State private var dollars: Int
    @State private var failureText: String?

    init(item: InterventionSummary) {
        self.item = item
        _selectedTypeID = State(initialValue: item.typeID)
        _selectedDrugClassID = State(initialValue: item.drugClassID)
        _selectedServiceLineID = State(initialValue: item.serviceLineID)
        _acceptance = State(initialValue: item.acceptance)
        _minutesText = State(initialValue: item.minutesSpent.map(String.init) ?? "")
        _hasCost = State(initialValue: item.costAvoidanceCents != nil)
        // Whole-dollar editing; quotientAndRemainder keeps the source free of
        // bare slash tokens per the boundary parser rules.
        _dollars = State(
            initialValue: (item.costAvoidanceCents ?? 0).quotientAndRemainder(dividingBy: 100).quotient
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $selectedTypeID) {
                    Text("Unspecified").tag(UUID?.none)
                    ForEach(typeOptions) { option in
                        Text(option.label).tag(UUID?.some(option.id))
                    }
                }
                Picker("Drug class", selection: $selectedDrugClassID) {
                    Text("Unspecified").tag(UUID?.none)
                    ForEach(drugClassOptions) { option in
                        Text(option.label).tag(UUID?.some(option.id))
                    }
                }
                Picker("Service line", selection: $selectedServiceLineID) {
                    Text("None").tag(UUID?.none)
                    ForEach(serviceLineOptions) { option in
                        Text(option.label).tag(UUID?.some(option.id))
                    }
                }
                Picker("Outcome", selection: $acceptance) {
                    ForEach(AcceptanceDisplay.captureOrder, id: \.self) { value in
                        Text(AcceptanceDisplay.label(value)).tag(value)
                    }
                }
                HStack {
                    Text("Minutes")
                    Spacer()
                    TextField("Optional", text: $minutesText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                }
                Toggle("Set cost avoidance", isOn: $hasCost)
                if hasCost {
                    TextField("Whole dollars", value: $dollars, format: .number)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle("Edit intervention")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                }
            }
            .alert("Could not save", isPresented: failureAlertBinding) {
                Button("OK", role: .cancel) {
                }
            } message: {
                Text(failureText ?? "Try again.")
            }
            .onAppear(perform: reloadOptions)
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

    private func reloadOptions() {
        do {
            typeOptions = try TaxonomyService.allInterventionTypes(in: modelContext)
                .map { PickerOption(id: $0.id, label: $0.label) }
            drugClassOptions = try TaxonomyService.allDrugClasses(in: modelContext)
                .map { PickerOption(id: $0.id, label: $0.label) }
            serviceLineOptions = try TaxonomyService.allServiceLines(in: modelContext)
                .map { PickerOption(id: $0.id, label: $0.label) }
        } catch {
            failureText = "The categories could not be loaded."
        }
    }

    private func save() {
        guard let typeID = selectedTypeID, let drugClassID = selectedDrugClassID else {
            failureText = "Choose a type and a drug class."
            return
        }
        let minutes = Int(minutesText.trimmingCharacters(in: .whitespaces))
        let edit = InterventionEdit(
            typeID: typeID,
            drugClassID: drugClassID,
            serviceLineID: selectedServiceLineID,
            acceptance: acceptance,
            minutesSpent: minutes,
            costAvoidanceCents: hasCost ? dollars * 100 : nil
        )
        do {
            try InterventionLedgerService.apply(edit, toInterventionID: item.id, in: modelContext)
            dismiss()
        } catch {
            failureText = "The change could not be saved."
        }
    }
}
