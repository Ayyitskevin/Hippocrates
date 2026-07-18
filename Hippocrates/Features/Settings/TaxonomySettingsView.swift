import SwiftData
import SwiftUI

/// Entry screen for the three taxonomy editors. All mutation flows through
/// TaxonomyService; these views hold value snapshots and never touch models.
struct TaxonomySettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Categories are generic department terms used to classify interventions. Never put patient details, room numbers, or case specifics in a category name.")
                        .font(.callout)
                }
                NavigationLink("Intervention categories") {
                    InterventionTypeEditorView()
                }
                NavigationLink("Drug classes") {
                    DrugClassEditorView()
                }
                NavigationLink("Service lines") {
                    ServiceLineEditorView()
                }
            }
            .navigationTitle("Categories")
        }
    }
}

// MARK: - Per-model wrappers

struct InterventionTypeEditorView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TaxonomyEditorView(
            configuration: TaxonomyEditorConfiguration(
                title: "Intervention categories",
                supportsCostDefault: true
            ),
            actions: TaxonomyEditorActions(
                loadItems: {
                    try TaxonomyService.allInterventionTypes(in: modelContext).map { row in
                        TaxonomyRowItem(
                            id: row.id,
                            label: row.label,
                            isActive: row.isActive,
                            wholeDollarDefault: row.defaultCostAvoidanceCents
                                .map(wholeDollars(fromCents:))
                        )
                    }
                },
                addItem: { label, dollars in
                    try TaxonomyService.addInterventionType(
                        label: label,
                        defaultCostAvoidanceCents: dollars.map(cents(fromWholeDollars:)),
                        in: modelContext
                    )
                },
                renameItem: { id, label in
                    guard let row = try interventionType(id) else { return }
                    try TaxonomyService.renameInterventionType(row, to: label, in: modelContext)
                },
                setItemActive: { id, isActive in
                    guard let row = try interventionType(id) else { return }
                    try TaxonomyService.setInterventionTypeActive(isActive, on: row, in: modelContext)
                },
                setItemCostDefault: { id, dollars in
                    guard let row = try interventionType(id) else { return }
                    try TaxonomyService.setDefaultCostAvoidanceCents(
                        dollars.map(cents(fromWholeDollars:)),
                        on: row,
                        in: modelContext
                    )
                },
                deleteItem: { id in
                    guard let row = try interventionType(id) else { return }
                    try TaxonomyService.deleteInterventionType(row, in: modelContext)
                },
                reorderItems: { ids in
                    try TaxonomyService.reorderInterventionTypes(ids, in: modelContext)
                }
            )
        )
    }

    private func interventionType(_ id: UUID) throws -> InterventionType? {
        try TaxonomyService.allInterventionTypes(in: modelContext).first { $0.id == id }
    }
}

struct DrugClassEditorView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TaxonomyEditorView(
            configuration: TaxonomyEditorConfiguration(
                title: "Drug classes",
                supportsCostDefault: false
            ),
            actions: TaxonomyEditorActions(
                loadItems: {
                    try TaxonomyService.allDrugClasses(in: modelContext).map { row in
                        TaxonomyRowItem(
                            id: row.id,
                            label: row.label,
                            isActive: row.isActive,
                            wholeDollarDefault: nil
                        )
                    }
                },
                addItem: { label, _ in
                    try TaxonomyService.addDrugClass(label: label, in: modelContext)
                },
                renameItem: { id, label in
                    guard let row = try drugClass(id) else { return }
                    try TaxonomyService.renameDrugClass(row, to: label, in: modelContext)
                },
                setItemActive: { id, isActive in
                    guard let row = try drugClass(id) else { return }
                    try TaxonomyService.setDrugClassActive(isActive, on: row, in: modelContext)
                },
                setItemCostDefault: { _, _ in
                },
                deleteItem: { id in
                    guard let row = try drugClass(id) else { return }
                    try TaxonomyService.deleteDrugClass(row, in: modelContext)
                },
                reorderItems: { ids in
                    try TaxonomyService.reorderDrugClasses(ids, in: modelContext)
                }
            )
        )
    }

    private func drugClass(_ id: UUID) throws -> DrugClass? {
        try TaxonomyService.allDrugClasses(in: modelContext).first { $0.id == id }
    }
}

struct ServiceLineEditorView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TaxonomyEditorView(
            configuration: TaxonomyEditorConfiguration(
                title: "Service lines",
                supportsCostDefault: false
            ),
            actions: TaxonomyEditorActions(
                loadItems: {
                    try TaxonomyService.allServiceLines(in: modelContext).map { row in
                        TaxonomyRowItem(
                            id: row.id,
                            label: row.label,
                            isActive: row.isActive,
                            wholeDollarDefault: nil
                        )
                    }
                },
                addItem: { label, _ in
                    try TaxonomyService.addServiceLine(label: label, in: modelContext)
                },
                renameItem: { id, label in
                    guard let row = try serviceLine(id) else { return }
                    try TaxonomyService.renameServiceLine(row, to: label, in: modelContext)
                },
                setItemActive: { id, isActive in
                    guard let row = try serviceLine(id) else { return }
                    try TaxonomyService.setServiceLineActive(isActive, on: row, in: modelContext)
                },
                setItemCostDefault: { _, _ in
                },
                deleteItem: { id in
                    guard let row = try serviceLine(id) else { return }
                    try TaxonomyService.deleteServiceLine(row, in: modelContext)
                },
                reorderItems: { ids in
                    try TaxonomyService.reorderServiceLines(ids, in: modelContext)
                }
            )
        )
    }

    private func serviceLine(_ id: UUID) throws -> ServiceLine? {
        try TaxonomyService.allServiceLines(in: modelContext).first { $0.id == id }
    }
}

// MARK: - Shared editor

/// Value snapshot of one taxonomy row. Editing routes back through the
/// service by UUID; the list never holds live model references.
private struct TaxonomyRowItem: Identifiable, Equatable {
    let id: UUID
    var label: String
    var isActive: Bool
    var wholeDollarDefault: Int?
}

private struct TaxonomyEditorConfiguration {
    var title: String
    var supportsCostDefault: Bool
}

private struct TaxonomyEditorActions {
    var loadItems: @MainActor () throws -> [TaxonomyRowItem]
    var addItem: @MainActor (String, Int?) throws -> Void
    var renameItem: @MainActor (UUID, String) throws -> Void
    var setItemActive: @MainActor (UUID, Bool) throws -> Void
    var setItemCostDefault: @MainActor (UUID, Int?) throws -> Void
    var deleteItem: @MainActor (UUID) throws -> Void
    var reorderItems: @MainActor ([UUID]) throws -> Void
}

private struct TaxonomyEditorView: View {
    let configuration: TaxonomyEditorConfiguration
    let actions: TaxonomyEditorActions

    @State private var items: [TaxonomyRowItem] = []
    @State private var editingItem: TaxonomyRowItem?
    @State private var isAddingItem = false
    @State private var pendingDeletion: TaxonomyRowItem?
    @State private var failureText: String?

    var body: some View {
        List {
            ForEach(items) { item in
                Button {
                    editingItem = item
                } label: {
                    rowLabel(item)
                }
                .swipeActions(edge: .trailing) {
                    Button("Remove", role: .destructive) {
                        pendingDeletion = item
                    }
                    if item.isActive {
                        Button("Deactivate") {
                            setActive(false, for: item)
                        }
                    } else {
                        Button("Activate") {
                            setActive(true, for: item)
                        }
                    }
                }
            }
            .onMove(perform: moveItems)
        }
        .navigationTitle(configuration.title)
        .toolbar {
            EditButton()
            Button("Add") {
                isAddingItem = true
            }
        }
        .sheet(item: $editingItem, onDismiss: reload) { item in
            TaxonomyRowEditorSheet(
                title: "Edit",
                supportsCostDefault: configuration.supportsCostDefault,
                initialLabel: item.label,
                initialDollars: item.wholeDollarDefault,
                onSave: { label, dollars in
                    try actions.renameItem(item.id, label)
                    if configuration.supportsCostDefault {
                        try actions.setItemCostDefault(item.id, dollars)
                    }
                }
            )
        }
        .sheet(isPresented: $isAddingItem, onDismiss: reload) {
            TaxonomyRowEditorSheet(
                title: "Add",
                supportsCostDefault: configuration.supportsCostDefault,
                initialLabel: "",
                initialDollars: nil,
                onSave: { label, dollars in
                    try actions.addItem(label, dollars)
                }
            )
        }
        .confirmationDialog(
            "Remove this item?",
            isPresented: deletionDialogBinding,
            presenting: pendingDeletion
        ) { item in
            Button("Remove permanently", role: .destructive) {
                deleteItem(item)
            }
            Button("Cancel", role: .cancel) {
            }
        } message: { _ in
            Text("Removal only works for items no intervention has used. Items in use can be deactivated instead.")
        }
        .alert("The change could not be saved", isPresented: failureAlertBinding) {
            Button("OK", role: .cancel) {
            }
        } message: {
            Text(failureText ?? "Try again.")
        }
        .onAppear(perform: reload)
    }

    private func rowLabel(_ item: TaxonomyRowItem) -> some View {
        HStack {
            Text(item.label)
                .foregroundStyle(item.isActive ? Color.primary : Color.secondary)
            Spacer()
            if item.isActive == false {
                Text("Inactive")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let dollars = item.wholeDollarDefault {
                Text(dollars, format: .currency(code: "USD"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
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
            items = try actions.loadItems()
        } catch {
            failureText = message(for: error)
        }
    }

    private func setActive(_ isActive: Bool, for item: TaxonomyRowItem) {
        do {
            try actions.setItemActive(item.id, isActive)
        } catch {
            failureText = message(for: error)
        }
        reload()
    }

    private func deleteItem(_ item: TaxonomyRowItem) {
        do {
            try actions.deleteItem(item.id)
        } catch {
            failureText = message(for: error)
        }
        reload()
    }

    private func moveItems(fromOffsets source: IndexSet, toOffset destination: Int) {
        var reordered = items
        reordered.move(fromOffsets: source, toOffset: destination)
        do {
            try actions.reorderItems(reordered.map(\.id))
        } catch {
            failureText = message(for: error)
        }
        reload()
    }
}

private struct TaxonomyRowEditorSheet: View {
    let title: String
    let supportsCostDefault: Bool
    let initialLabel: String
    let initialDollars: Int?
    let onSave: @MainActor (String, Int?) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var hasCostDefault: Bool
    @State private var dollars: Int
    @State private var failureText: String?

    init(
        title: String,
        supportsCostDefault: Bool,
        initialLabel: String,
        initialDollars: Int?,
        onSave: @escaping @MainActor (String, Int?) throws -> Void
    ) {
        self.title = title
        self.supportsCostDefault = supportsCostDefault
        self.initialLabel = initialLabel
        self.initialDollars = initialDollars
        self.onSave = onSave
        _label = State(initialValue: initialLabel)
        _hasCostDefault = State(initialValue: initialDollars != nil)
        _dollars = State(initialValue: initialDollars ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $label)
                if supportsCostDefault {
                    Toggle("Set estimated cost avoidance", isOn: $hasCostDefault)
                    if hasCostDefault {
                        TextField("Whole dollars", value: $dollars, format: .number)
                            .keyboardType(.numberPad)
                        Text("An unset value means your institution has not assigned one. Zero is a real value and is kept distinct.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(title)
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
            .alert("The change could not be saved", isPresented: failureAlertBinding) {
                Button("OK", role: .cancel) {
                }
            } message: {
                Text(failureText ?? "Try again.")
            }
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

    private func save() {
        do {
            try onSave(label, hasCostDefault ? dollars : nil)
            dismiss()
        } catch {
            failureText = message(for: error)
        }
    }
}

// MARK: - Shared helpers

/// Cost defaults are stored as integer cents (A-013); the editor works in
/// whole dollars for v1. A backup-imported value with odd cents displays its
/// whole-dollar portion here while the stored cents remain exact.
private func wholeDollars(fromCents storedCents: Int) -> Int {
    storedCents.quotientAndRemainder(dividingBy: 100).quotient
}

private func cents(fromWholeDollars dollars: Int) -> Int {
    dollars * 100
}

private func message(for error: any Error) -> String {
    guard let serviceError = error as? TaxonomyServiceError else {
        return "The change could not be saved. Try again."
    }
    switch serviceError {
    case .invalidLabel:
        return "Enter a single-line name."
    case .labelTooLong:
        return "Names are limited to 60 characters."
    case .duplicateLabel:
        return "An item with this name already exists."
    case .negativeCostAvoidanceCents:
        return "Cost avoidance cannot be negative."
    case .rowIsReferenced:
        return "This item is used by recorded interventions. Deactivate it instead of removing it."
    case .reorderMustIncludeEveryRow:
        return "The list changed while reordering. Try again."
    case .starterSeedRequiresEmptyTaxonomies:
        return "Starting categories can only be added to empty lists."
    }
}
