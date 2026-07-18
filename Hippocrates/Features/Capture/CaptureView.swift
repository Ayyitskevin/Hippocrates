import SwiftData
import SwiftUI

/// Five-second, no-typing capture. The three required taps are
/// type -> drug class -> acceptance; the third tap saves immediately. Optional
/// fields (I-008) live in a collapsed strip and never add a required tap.
struct CaptureView: View {
    private enum Stage {
        case type
        case drugClass
        case acceptance
    }

    @Environment(\.modelContext) private var modelContext

    @State private var stage = Stage.type
    @State private var typeOptions: [PickerOption] = []
    @State private var drugClassOptions: [PickerOption] = []
    @State private var serviceLineOptions: [PickerOption] = []

    @State private var selectedType: PickerOption?
    @State private var selectedDrugClass: PickerOption?

    // Optional strip selections persist across the tap path and apply at save.
    @State private var showsOptional = false
    @State private var selectedServiceLineID: UUID?
    @State private var minutesText = ""

    @State private var snackbar: CaptureSnackbar?
    @State private var snackbarTask: Task<Void, Never>?
    @State private var saveCount = 0
    @State private var failureText: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            optionalStrip
            Divider()
            stageContent
        }
        .sensoryFeedback(.impact(weight: .light), trigger: saveCount)
        .overlay(alignment: .bottom) {
            if let snackbar {
                undoSnackbar(snackbar)
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

    // MARK: Header

    private var header: some View {
        VStack(spacing: 4) {
            Text(stageTitle)
                .font(.headline)
            HStack(spacing: 6) {
                stageDot(isFilled: selectedType != nil)
                stageDot(isFilled: selectedDrugClass != nil)
                stageDot(isFilled: false)
            }
            if selectedType != nil || selectedDrugClass != nil {
                Button("Start over", action: resetDraft)
                    .font(.footnote)
            }
        }
        .padding(.vertical, 12)
    }

    private func stageDot(isFilled: Bool) -> some View {
        Circle()
            .fill(isFilled ? Color.accentColor : Color.secondary.opacity(0.3))
            .frame(width: 8, height: 8)
    }

    private var stageTitle: String {
        switch stage {
        case .type:
            return "Choose an intervention type"
        case .drugClass:
            return "Choose a drug class"
        case .acceptance:
            return "Record the outcome"
        }
    }

    // MARK: Optional strip (I-008)

    private var optionalStrip: some View {
        DisclosureGroup(isExpanded: $showsOptional) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Service line", selection: $selectedServiceLineID) {
                    Text("None").tag(UUID?.none)
                    ForEach(serviceLineOptions) { option in
                        Text(option.label).tag(UUID?.some(option.id))
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
            }
            .padding(.top, 4)
        } label: {
            Text("Optional details")
                .font(.subheadline)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: Stage content

    @ViewBuilder
    private var stageContent: some View {
        switch stage {
        case .type:
            optionGrid(typeOptions, emptyMessage: "Add an intervention category in Categories first.") { option in
                selectedType = option
                stage = .drugClass
            }
        case .drugClass:
            optionGrid(drugClassOptions, emptyMessage: "Add a drug class in Categories first.") { option in
                selectedDrugClass = option
                stage = .acceptance
            }
        case .acceptance:
            acceptanceButtons
        }
    }

    private func optionGrid(
        _ options: [PickerOption],
        emptyMessage: String,
        onSelect: @escaping (PickerOption) -> Void
    ) -> some View {
        Group {
            if options.isEmpty {
                ContentUnavailableView("No categories", systemImage: "tray", description: Text(emptyMessage))
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 150), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(options) { option in
                            Button {
                                onSelect(option)
                            } label: {
                                Text(option.label)
                                    .frame(maxWidth: .infinity, minHeight: 64)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private var acceptanceButtons: some View {
        VStack(spacing: 12) {
            ForEach(AcceptanceDisplay.captureOrder, id: \.self) { acceptance in
                Button {
                    save(acceptance: acceptance)
                } label: {
                    Text(AcceptanceDisplay.label(acceptance))
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    // MARK: Undo snackbar

    private func undoSnackbar(_ snackbar: CaptureSnackbar) -> some View {
        HStack {
            Text(snackbar.message)
                .foregroundStyle(.white)
            Spacer()
            Button("Undo") {
                undo(snackbar)
            }
            .foregroundStyle(.white)
            .bold()
        }
        .padding()
        .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
        .padding()
    }

    // MARK: Actions

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
            typeOptions = try InterventionCaptureService.rankedActiveTypes(in: modelContext)
                .map { PickerOption(id: $0.id, label: $0.label) }
            drugClassOptions = try TaxonomyService.allDrugClasses(in: modelContext)
                .filter(\.isActive)
                .map { PickerOption(id: $0.id, label: $0.label) }
            serviceLineOptions = try TaxonomyService.allServiceLines(in: modelContext)
                .filter(\.isActive)
                .map { PickerOption(id: $0.id, label: $0.label) }
        } catch {
            failureText = "The categories could not be loaded."
        }
    }

    private func save(acceptance: Acceptance) {
        guard let type = selectedType, let drugClass = selectedDrugClass else {
            return
        }
        let minutes = Int(minutesText.trimmingCharacters(in: .whitespaces))
        let draft = CaptureDraft(
            typeID: type.id,
            drugClassID: drugClass.id,
            acceptance: acceptance,
            serviceLineID: selectedServiceLineID,
            minutesSpent: minutes
        )
        do {
            let intervention = try InterventionCaptureService.record(draft, in: modelContext)
            saveCount += 1
            presentSnackbar(for: intervention.id)
            resetDraft()
            reloadOptions()
        } catch {
            failureText = "The intervention could not be saved."
        }
    }

    private func presentSnackbar(for id: UUID) {
        snackbarTask?.cancel()
        snackbar = CaptureSnackbar(interventionID: id, message: "Saved")
        snackbarTask = Task {
            try? await Task.sleep(for: .seconds(5))
            if Task.isCancelled == false {
                snackbar = nil
            }
        }
    }

    private func undo(_ snackbar: CaptureSnackbar) {
        snackbarTask?.cancel()
        do {
            try InterventionLedgerService.deleteIntervention(id: snackbar.interventionID, in: modelContext)
        } catch {
            failureText = "The entry could not be removed."
        }
        self.snackbar = nil
        reloadOptions()
    }

    private func resetDraft() {
        stage = .type
        selectedType = nil
        selectedDrugClass = nil
    }
}

/// The snackbar retains only the inserted UUID and a display message. Undo
/// looks up that exact intervention through the ledger service.
private struct CaptureSnackbar: Equatable {
    let interventionID: UUID
    let message: String
}
