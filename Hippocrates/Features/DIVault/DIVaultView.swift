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
}

/// One row per DI record: drafts labeled plainly, answered records dated.
/// Freshness badges join this list in the next milestone.
struct DIVaultView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var rows: [DIRowItem] = []
    @State private var editingQuestionID: UUID?
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
                    editingQuestionID = row.id
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.title)
                            .lineLimit(2)
                        HStack(spacing: 8) {
                            Text(row.classLabel)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if row.isDraft {
                                Text("Draft")
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.2), in: Capsule())
                                    .foregroundStyle(.blue)
                            } else if let answeredAt = row.answeredAt {
                                Text(answeredAt, format: .dateTime.year().month().day())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("DI Vault")
        .toolbar {
            Button("Add") {
                isCreatingNew = true
            }
        }
        .sheet(isPresented: $isCreatingNew, onDismiss: reload) {
            DIQuestionEditorView(questionID: nil)
        }
        .sheet(item: editingIDBinding, onDismiss: reload) { identified in
            DIQuestionEditorView(questionID: identified.id)
        }
        .alert("Could not load the vault", isPresented: failureAlertBinding) {
            Button("OK", role: .cancel) {
            }
        } message: {
            Text(failureText ?? "Try again.")
        }
        .onAppear(perform: reload)
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
            rows = try DIQuestionService.allQuestions(in: modelContext).map { question in
                DIRowItem(
                    id: question.id,
                    title: question.questionText.isEmpty ? "Untitled question" : question.questionText,
                    classLabel: DIDisplay.label(question.questionClass),
                    isDraft: question.answeredAt == nil,
                    answeredAt: question.answeredAt
                )
            }
        } catch {
            failureText = "The record list could not be loaded."
        }
    }
}

private struct DIRowItem: Identifiable, Equatable {
    let id: UUID
    let title: String
    let classLabel: String
    let isDraft: Bool
    let answeredAt: Date?
}

private struct IdentifiedID: Identifiable, Equatable {
    let id: UUID
}
