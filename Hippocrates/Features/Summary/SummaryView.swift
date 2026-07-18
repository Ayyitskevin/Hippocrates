import Charts
import CoreTransferable
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The CSV leaves the app only as app-owned bytes: a Transferable backed by
/// DataRepresentation. No file URL is created and no link preview can fetch.
struct InterventionCSVTransferable: Transferable {
    let csvText: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { transferable in
            Data(transferable.csvText.utf8)
        }
    }
}

/// Milestone 3: the manager-ready summary. A visible range control (P-004),
/// the I-007 acceptance rate with every count beside it, cost and time totals
/// honestly labeled, category breakdowns, a monthly chart, and CSV export.
struct SummaryView: View {
    @Environment(\.modelContext) private var modelContext
    /// P-004: the last range selection is remembered as app state.
    @AppStorage("summaryRangeChoice") private var rangeChoiceRawValue = SummaryRangeChoice.thisYear.rawValue

    @State private var statistics: SummaryStatistics?
    @State private var csvText = ""
    @State private var failureText: String?

    private var rangeChoice: SummaryRangeChoice {
        SummaryRangeChoice(rawValue: rangeChoiceRawValue) ?? .thisYear
    }

    var body: some View {
        List {
            Section {
                Picker("Range", selection: rangeChoiceBinding) {
                    ForEach(SummaryRangeChoice.allCases, id: \.self) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
            }

            if let statistics {
                totalsSection(statistics)
                acceptanceSection(statistics.acceptance)
                monthChartSection(statistics)
                breakdownSection(
                    title: "By intervention type",
                    counts: statistics.countsByType
                )
                breakdownSection(
                    title: "Top drug classes",
                    counts: Array(statistics.topDrugClasses.prefix(5))
                )
                breakdownSection(
                    title: "By service line",
                    counts: statistics.serviceLineBreakdown
                )
                exportSection
            }
        }
        .navigationTitle("Summary")
        .alert("Could not load the summary", isPresented: failureAlertBinding) {
            Button("OK", role: .cancel) {
            }
        } message: {
            Text(failureText ?? "Try again.")
        }
        .onAppear(perform: reload)
    }

    // MARK: Sections

    private func totalsSection(_ statistics: SummaryStatistics) -> some View {
        Section("Totals") {
            LabeledContent("Interventions") {
                Text(statistics.totalCount, format: .number)
            }
            if let costCents = statistics.costTotalCents {
                LabeledContent("Cost avoidance") {
                    Text(dollarsValue(fromCents: costCents), format: .currency(code: "USD"))
                }
                Text("Cost figures are the estimates you configured; they are not institutional accounting.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let minutes = statistics.minutesTotal {
                LabeledContent("Minutes recorded") {
                    Text(minutes, format: .number)
                }
            }
        }
    }

    private func acceptanceSection(_ breakdown: AcceptanceBreakdown) -> some View {
        Section("Acceptance") {
            if let permille = breakdown.ratePermille {
                LabeledContent("Acceptance rate") {
                    Text(SummaryEngine.permilleDisplayString(permille) + "%")
                }
                Text("Rate = accepted divided by accepted plus rejected. Pending and not-applicable records are excluded from the rate and shown below.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("No resolved interventions in this range yet. The rate appears once records are accepted or rejected.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Accepted") {
                Text(breakdown.accepted, format: .number)
            }
            LabeledContent("Rejected") {
                Text(breakdown.rejected, format: .number)
            }
            LabeledContent("Pending") {
                Text(breakdown.pending, format: .number)
            }
            LabeledContent("Not applicable") {
                Text(breakdown.notApplicable, format: .number)
            }
        }
    }

    private func monthChartSection(_ statistics: SummaryStatistics) -> some View {
        Section("By month") {
            if statistics.totalCount == 0 {
                Text("No interventions recorded in this range.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Chart(statistics.countsByMonth, id: \.monthKey) { month in
                    BarMark(
                        x: .value("Month", month.monthKey),
                        y: .value("Interventions", month.count)
                    )
                }
                .frame(height: 180)
                .accessibilityLabel("Bar chart of interventions per month")
            }
        }
    }

    private func breakdownSection(title: String, counts: [LabelCount]) -> some View {
        Section(title) {
            if counts.isEmpty {
                Text("Nothing recorded in this range.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(counts, id: \.label) { entry in
                LabeledContent(entry.label) {
                    Text(entry.count, format: .number)
                }
            }
        }
    }

    private var exportSection: some View {
        Section("Export") {
            ShareLink(
                item: InterventionCSVTransferable(csvText: csvText),
                preview: SharePreview("Intervention summary CSV")
            ) {
                Text("Share CSV")
            }
            Text("The CSV contains the selected range's interventions with UTC timestamps. Summary exports never update the backup reminder.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: State

    private var rangeChoiceBinding: Binding<SummaryRangeChoice> {
        Binding(
            get: { rangeChoice },
            set: { choice in
                rangeChoiceRawValue = choice.rawValue
                reload()
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

    /// Exact cents-to-dollars shift via a decimal exponent: no floating-point
    /// rounding and no division token.
    private func dollarsValue(fromCents cents: Int) -> Decimal {
        Decimal(sign: cents < 0 ? .minus : .plus, exponent: -2, significand: Decimal(abs(cents)))
    }

    private func reload() {
        do {
            let range = rangeChoice.range(now: .now, calendar: .current)
            let rows = try SummarySnapshotService.rows(in: range, from: modelContext)
            statistics = SummaryEngine.statistics(for: rows, in: range, calendar: .current)
            csvText = InterventionCSV.document(rows: rows)
        } catch {
            failureText = "The summary could not be loaded."
        }
    }
}
