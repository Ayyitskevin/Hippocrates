import CoreTransferable
import SwiftData
import SwiftUI

/// Display names for the frozen DI vocabulary (P-006). Raw values are
/// persistence identifiers; these labels are presentation only.
enum DIDisplay {
    static func label(_ role: RequestorRole) -> String {
        switch role {
        case .resident: return "Resident"
        case .nurse: return "Nurse"
        case .attending: return "Attending"
        case .pharmacist: return "Pharmacist"
        case .student: return "Student"
        case .careTeam: return "Care team"
        case .other: return "Other"
        }
    }

    static func label(_ questionClass: DIQuestionClass) -> String {
        switch questionClass {
        case .dosing: return "Dosing"
        case .adverseEffect: return "Adverse effect"
        case .interaction: return "Interaction"
        case .compatibility: return "Compatibility"
        case .availability: return "Availability"
        case .administration: return "Administration"
        case .pregnancyLactation: return "Pregnancy and lactation"
        case .therapeutics: return "Therapeutics"
        case .toxicology: return "Toxicology"
        case .pharmacokinetics: return "Pharmacokinetics"
        case .other: return "Other"
        }
    }

    static func label(_ urgency: Urgency) -> String {
        switch urgency {
        case .routine: return "Routine"
        case .sameDay: return "Same day"
        case .stat: return "Stat"
        }
    }

    static func label(_ tier: SourceTier) -> String {
        switch tier {
        case .tertiary: return "Tertiary"
        case .secondary: return "Secondary"
        case .primary: return "Primary"
        case .guideline: return "Guideline"
        case .label: return "Product label"
        case .institutionPolicy: return "Institution policy"
        }
    }

    static func label(_ category: DeidentificationFinding.Category) -> String {
        switch category {
        case .phoneNumber: return "Phone number"
        case .date: return "Date"
        case .roomOrBed: return "Room or bed"
        case .ageOver89: return "Age over 89"
        case .medicalRecordNumber: return "Record number"
        }
    }

    static func fieldTitle(_ fieldName: String) -> String {
        switch fieldName {
        case "questionText": return "Question"
        case "background": return "Background"
        case "answerText": return "Answer"
        case "searchStrategy": return "Search strategy"
        case "citationTitle": return "Citation title"
        case "citationLocator": return "Citation locator"
        case "tag": return "Tag"
        default: return fieldName
        }
    }

    /// Badge text pairs with color everywhere; color is never the only signal.
    static func badgeText(_ state: FreshnessState) -> String {
        switch state {
        case .draft: return "Draft"
        case .green: return "Current"
        case .amber: return "Review due"
        case .red: return "Out of date"
        }
    }

    static func badgeColor(_ state: FreshnessState) -> Color {
        switch state {
        case .draft: return .blue
        case .green: return .green
        case .amber: return .orange
        case .red: return .red
        }
    }
}

/// The vault list: searchable, with the same freshness policy driving every
/// badge. Opening an amber or red record interposes the staleness interstitial
/// before any answer content, every time; dismissal is view-local only.
struct DIVaultView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var rows: [DIRowItem] = []
    @State private var portfolioText = ""
    @State private var searchText = ""
    @State private var editingQuestionID: UUID?
    @State private var staleCandidate: DIRowItem?
    @State private var isCreatingNew = false
    @State private var failureText: String?

    var body: some View {
        List {
            if rows.isEmpty {
                ContentUnavailableView(
                    "No drug information records yet",
                    systemImage: "books.vertical",
                    description: Text("Preserve a completed question and answer here. Every save is checked for patient identifiers first.")
                )
            }
            ForEach(rows) { row in
                Button {
                    open(row)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.title)
                            .lineLimit(2)
                        HStack(spacing: 8) {
                            Text(row.classLabel)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer()
                            freshnessBadge(row.freshness)
                        }
                    }
                }
            }
        }
        .navigationTitle("DI Vault")
        .searchable(text: $searchText, prompt: "Search questions and answers")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ShareLink(
                    item: PortfolioTransferable(text: portfolioText),
                    preview: SharePreview("DI portfolio")
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .accessibilityLabel("Share DI portfolio")
                }
                Button("Add") {
                    isCreatingNew = true
                }
            }
        }
        .sheet(isPresented: $isCreatingNew, onDismiss: reload) {
            DIQuestionEditorView(questionID: nil)
        }
        .sheet(item: editingIDBinding, onDismiss: reload) { identified in
            DIQuestionEditorView(questionID: identified.id)
        }
        .sheet(item: $staleCandidate) { row in
            StaleAnswerInterstitial(
                row: row,
                onReverify: {
                    reverify(row)
                },
                onViewAnyway: {
                    staleCandidate = nil
                    editingQuestionID = row.id
                }
            )
        }
        .alert("Could not load the vault", isPresented: failureAlertBinding) {
            Button("OK", role: .cancel) {
            }
        } message: {
            Text(failureText ?? "Try again.")
        }
        .onAppear(perform: reload)
        .onChange(of: searchText) {
            reload()
        }
    }

    private func freshnessBadge(_ state: FreshnessState) -> some View {
        Text(DIDisplay.badgeText(state))
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(DIDisplay.badgeColor(state).opacity(0.2), in: Capsule())
            .foregroundStyle(DIDisplay.badgeColor(state))
    }

    /// Amber and red records interpose the interstitial before their content,
    /// every presentation. Drafts and green records open directly.
    private func open(_ row: DIRowItem) {
        switch row.freshness {
        case .amber, .red:
            staleCandidate = row
        case .draft, .green:
            editingQuestionID = row.id
        }
    }

    private func reverify(_ row: DIRowItem) {
        do {
            try DIQuestionService.reverifyPreservingWindow(
                questionID: row.id,
                in: modelContext
            )
            staleCandidate = nil
            reload()
        } catch {
            staleCandidate = nil
            failureText = "The record could not be re-verified."
        }
    }

    private var editingIDBinding: Binding<IdentifiedID?> {
        Binding(
            get: { editingQuestionID.map(IdentifiedID.init) },
            set: { editingQuestionID = $0?.id }
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
            let now = Date.now
            rows = try DIQuestionService.search(searchText, in: modelContext).map { question in
                DIRowItem(
                    id: question.id,
                    title: question.questionText.isEmpty ? "Untitled question" : question.questionText,
                    classLabel: DIDisplay.label(question.questionClass),
                    freshness: FreshnessPolicy.state(
                        answeredAt: question.answeredAt,
                        verifiedOn: question.verifiedOn,
                        reviewAfter: question.reviewAfter,
                        now: now
                    ),
                    verifiedOn: question.verifiedOn
                )
            }
            portfolioText = DIPortfolio.document(
                questions: try DIQuestionService.allQuestions(in: modelContext).map { question in
                    PortfolioQuestion(
                        createdAt: question.createdAt,
                        answeredAt: question.answeredAt,
                        questionText: question.questionText,
                        background: question.background,
                        requestorLabel: DIDisplay.label(question.requestorRole),
                        classLabel: DIDisplay.label(question.questionClass),
                        urgencyLabel: DIDisplay.label(question.urgency),
                        searchStrategy: question.searchStrategy,
                        answerText: question.answerText,
                        citations: question.citations
                            .sorted { $0.accessedDate < $1.accessedDate }
                            .map { citation in
                                PortfolioCitation(
                                    tierLabel: DIDisplay.label(citation.tier),
                                    title: citation.title,
                                    locator: citation.locator,
                                    accessedDate: citation.accessedDate,
                                    urlText: citation.urlString
                                )
                            },
                        didFollowUp: question.didFollowUp,
                        verifiedOn: question.verifiedOn,
                        reviewAfter: question.reviewAfter
                    )
                }
            )
        } catch {
            failureText = "The record list could not be loaded."
        }
    }
}

/// The portfolio leaves the app only as app-owned plain-text bytes.
private struct PortfolioTransferable: Transferable {
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { transferable in
            Data(transferable.text.utf8)
        }
    }
}

private struct DIRowItem: Identifiable, Equatable {
    let id: UUID
    let title: String
    let classLabel: String
    let freshness: FreshnessState
    let verifiedOn: Date
}

private struct IdentifiedID: Identifiable, Equatable {
    let id: UUID
}

/// The staleness interstitial: it names the last verification date and offers
/// one-tap re-verification or a deliberate view-anyway. Dismissing it lasts
/// only for this presentation; the next open interposes again.
private struct StaleAnswerInterstitial: View {
    let row: DIRowItem
    let onReverify: () -> Void
    let onViewAnyway: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("This answer may be out of date")
                    .font(.title2)
                    .bold()
                HStack {
                    Text("Last verified")
                    Text(row.verifiedOn, format: .dateTime.year().month().day())
                        .bold()
                }
                Text("Drug information changes. Re-verify this answer against current references before relying on it, or view it knowing its review window has passed.")
                Button {
                    onReverify()
                } label: {
                    Text("I re-verified this answer today")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button("View without re-verifying") {
                    onViewAnyway()
                }
                Spacer()
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}
