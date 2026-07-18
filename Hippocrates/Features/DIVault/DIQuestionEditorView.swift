import SwiftData
import SwiftUI

/// The structured DI editor. All text lives in form values; nothing reaches
/// the store until DIQuestionService's gate passes. The review sheet blocks
/// every save that carries unacknowledged findings, and acknowledgements last
/// only for the current attempt.
struct DIQuestionEditorView: View {
    let questionID: UUID?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var values = DIDraftValues()
    @State private var savedQuestionID: UUID?
    @State private var isDraft = true
    @State private var createdAt = Date.now
    @State private var pendingFindings: [DeidentificationFinding]?
    @State private var acknowledgments: [DeidentificationAcknowledgment] = []
    @State private var editingCitation: DICitationValues?
    @State private var isAnswering = false
    @State private var failureText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Question") {
                    TextEditor(text: $values.questionText)
                        .frame(minHeight: 70)
                }
                Section("De-identified background") {
                    TextEditor(text: $values.background)
                        .frame(minHeight: 70)
                    Text("Describe the clinical context without names, record numbers, exact dates, rooms, or ages over 89. Every save is scanned.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Classification") {
                    Picker("Requestor", selection: $values.requestorRole) {
                        ForEach(RequestorRole.allCases, id: \.self) { role in
                            Text(DIDisplay.label(role)).tag(role)
                        }
                    }
                    Picker("Question class", selection: $values.questionClass) {
                        ForEach(DIQuestionClass.allCases, id: \.self) { questionClass in
                            Text(DIDisplay.label(questionClass)).tag(questionClass)
                        }
                    }
                    Picker("Urgency", selection: $values.urgency) {
                        ForEach(Urgency.allCases, id: \.self) { urgency in
                            Text(DIDisplay.label(urgency)).tag(urgency)
                        }
                    }
                }
                Section("Search strategy") {
                    TextEditor(text: $values.searchStrategy)
                        .frame(minHeight: 70)
                }
                Section("Answer") {
                    TextEditor(text: $values.answerText)
                        .frame(minHeight: 100)
                }
                citationsSection
                Section {
                    Toggle("Follow-up completed", isOn: $values.didFollowUp)
                }
                if savedQuestionID != nil, isDraft {
                    Section {
                        Button("Mark as answered") {
                            isAnswering = true
                        }
                        Text("Answering sets the verification date and starts this record's review clock.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(savedQuestionID == nil ? "New DI record" : "DI record")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        attemptSave()
                    }
                }
            }
            .sheet(item: findingsBinding) { pending in
                DeidentificationReviewSheet(
                    findings: pending.findings,
                    onAcknowledge: { finding in
                        acknowledgments.append(
                            DeidentificationAcknowledgment(
                                fieldName: finding.fieldName,
                                matchedText: finding.matchedText
                            )
                        )
                        pendingFindings = nil
                        attemptSave()
                    },
                    onReturnToEditing: {
                        pendingFindings = nil
                    }
                )
            }
            .sheet(item: $editingCitation) { citation in
                DICitationEditorSheet(
                    citation: citation,
                    onSave: { updated in
                        if let index = values.citations.firstIndex(where: { $0.id == updated.id }) {
                            values.citations[index] = updated
                        } else {
                            values.citations.append(updated)
                        }
                    }
                )
            }
            .sheet(isPresented: $isAnswering) {
                DIAnswerSheet(createdAt: createdAt) { verifiedOn, months in
                    markAnswered(verifiedOn: verifiedOn, months: months)
                }
            }
            .alert("Could not save", isPresented: failureAlertBinding) {
                Button("OK", role: .cancel) {
                }
            } message: {
                Text(failureText ?? "Try again.")
            }
            .onAppear(perform: load)
        }
    }

    private var citationsSection: some View {
        Section("References") {
            ForEach(values.citations) { citation in
                Button {
                    editingCitation = citation
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(citation.title.isEmpty ? "Untitled reference" : citation.title)
                            .lineLimit(1)
                        Text(DIDisplay.label(citation.tier))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button("Remove", role: .destructive) {
                        values.citations.removeAll { $0.id == citation.id }
                    }
                }
            }
            Button("Add reference") {
                editingCitation = DICitationValues()
            }
        }
    }

    // MARK: State plumbing

    private var findingsBinding: Binding<PendingFindings?> {
        Binding(
            get: { pendingFindings.map(PendingFindings.init) },
            set: { pendingFindings = $0?.findings }
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

    private func load() {
        savedQuestionID = questionID
        guard let questionID else {
            return
        }
        do {
            guard let question = try DIQuestionService.question(questionID, in: modelContext) else {
                failureText = "This record could not be found."
                return
            }
            values = DIQuestionService.values(of: question)
            isDraft = question.answeredAt == nil
            createdAt = question.createdAt
        } catch {
            failureText = "This record could not be loaded."
        }
    }

    /// Editing any guarded text invalidates acknowledgements automatically:
    /// the service rescans on every attempt and only exact field-and-text
    /// matches from this attempt clear a finding.
    private func attemptSave() {
        do {
            let question = try DIQuestionService.save(
                values,
                questionID: savedQuestionID,
                acknowledging: acknowledgments,
                in: modelContext
            )
            savedQuestionID = question.id
            createdAt = question.createdAt
            acknowledgments = []
            dismiss()
        } catch DIQuestionServiceError.identifierFindingsRequireReview(let findings) {
            pendingFindings = findings
        } catch DIQuestionServiceError.citationTitleRequired {
            failureText = "Every reference needs a title."
        } catch DIQuestionServiceError.citationFieldTooLong {
            failureText = "Reference fields are single-line, up to 200 characters."
        } catch {
            failureText = "The record could not be saved."
        }
    }

    private func markAnswered(verifiedOn: Date, months: Int) {
        guard let savedQuestionID else {
            return
        }
        do {
            try DIQuestionService.markAnswered(
                questionID: savedQuestionID,
                verifiedOn: verifiedOn,
                stalenessMonths: months,
                in: modelContext
            )
            isDraft = false
            dismiss()
        } catch DIQuestionServiceError.verificationMustFollowCreation {
            failureText = "The verification date must come after this record was created."
        } catch {
            failureText = "The record could not be marked answered."
        }
    }
}

private struct PendingFindings: Identifiable, Equatable {
    let findings: [DeidentificationFinding]

    /// Identity reflects the exact finding set, so a retry that produces a
    /// different set re-presents the sheet with fresh content.
    var id: String {
        findings
            .map { $0.fieldName + ":" + String($0.location) + ":" + $0.matchedText }
            .joined(separator: "|")
    }
}

/// The blocking review: every finding needs a disposition. "Not an
/// identifier" acknowledges exactly one finding for this attempt and retries;
/// "Return to editing" leaves everything unsaved for correction. Nothing is
/// silently scrubbed and nothing is permanently ignored.
private struct DeidentificationReviewSheet: View {
    let findings: [DeidentificationFinding]
    let onAcknowledge: (DeidentificationFinding) -> Void
    let onReturnToEditing: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("These look like patient identifiers. Remove them, or confirm each one is not an identifier. Saving is blocked until every item is resolved.")
                        .font(.callout)
                }
                ForEach(Array(findings.enumerated()), id: \.offset) { _, finding in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(DIDisplay.label(finding.category))
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2), in: Capsule())
                                .foregroundStyle(.orange)
                            Spacer()
                            Text(DIDisplay.fieldTitle(finding.fieldName))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Text(finding.matchedText)
                            .font(.body.monospaced())
                        Button("Not an identifier") {
                            onAcknowledge(finding)
                        }
                        .font(.footnote)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Review required")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Return to editing") {
                        onReturnToEditing()
                    }
                }
            }
            .interactiveDismissDisabled()
        }
    }
}

private struct DICitationEditorSheet: View {
    @State var citation: DICitationValues
    let onSave: (DICitationValues) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Source tier", selection: $citation.tier) {
                    ForEach(SourceTier.allCases, id: \.self) { tier in
                        Text(DIDisplay.label(tier)).tag(tier)
                    }
                }
                TextField("Title", text: $citation.title)
                TextField("Locator (edition, section, page)", text: $citation.locator)
                DatePicker("Accessed", selection: $citation.accessedDate, displayedComponents: .date)
                TextField("Address (plain text, optional)", text: $urlText)
                    .textInputAutocapitalization(.never)
                Text("References stay plain text. The app never opens links.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Reference")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        var updated = citation
                        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.urlString = trimmed.isEmpty ? nil : trimmed
                        onSave(updated)
                        dismiss()
                    }
                }
            }
            .onAppear {
                urlText = citation.urlString ?? ""
            }
        }
    }
}

/// Answering asks for the verification date and the review interval. The
/// stored P-005 choice, once made, is offered as the default; a custom
/// interval affects this record only (A-006).
private struct DIAnswerSheet: View {
    let createdAt: Date
    let onConfirm: (Date, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var verifiedOn = Date.now
    @State private var months = 12
    @State private var hasStoredChoice = false

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(
                    "Verified on",
                    selection: $verifiedOn,
                    in: createdAt...Date.distantFuture
                )
                Picker("Review interval", selection: $months) {
                    Text("6 months").tag(6)
                    Text("12 months").tag(12)
                    Text("18 months").tag(18)
                    Text("24 months").tag(24)
                }
                if hasStoredChoice == false {
                    Text("This first choice becomes your default review interval. Each record keeps the interval it was answered with.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Mark answered")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        onConfirm(verifiedOn, months)
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let configuration = try? AppConfigService.existing(in: modelContext),
                   let stored = configuration.stalenessIntervalMonths {
                    months = stored
                    hasStoredChoice = true
                }
            }
        }
    }
}
