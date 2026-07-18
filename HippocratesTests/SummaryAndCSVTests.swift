import Foundation
import SwiftData
import XCTest

@testable import Hippocrates

@MainActor
final class SummaryAndCSVTests: XCTestCase {
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return utcCalendar.date(from: components) ?? Date(timeIntervalSinceReferenceDate: 0)
    }

    private func row(
        _ timestamp: Date,
        type: String? = "Renal dose adjustment",
        drugClass: String? = "Antimicrobials",
        line: String? = nil,
        acceptance: Acceptance = .accepted,
        cost: Int? = nil,
        minutes: Int? = nil
    ) -> SummaryInputRow {
        SummaryInputRow(
            timestamp: timestamp,
            typeLabel: type,
            drugClassLabel: drugClass,
            serviceLineLabel: line,
            acceptance: acceptance,
            costAvoidanceCents: cost,
            minutesSpent: minutes
        )
    }

    // MARK: Permille (I-007 rate math)

    func testPermilleIsNilWithoutResolvedRecords() {
        XCTAssertNil(SummaryEngine.permille(0, of: 0))
        let breakdown = AcceptanceBreakdown(accepted: 0, rejected: 0, pending: 4, notApplicable: 1)
        XCTAssertNil(breakdown.ratePermille)
        XCTAssertEqual(breakdown.resolvedDenominator, 0)
    }

    func testPermilleRoundsHalfUp() {
        XCTAssertEqual(SummaryEngine.permille(2, of: 3), 667)
        XCTAssertEqual(SummaryEngine.permille(1, of: 3), 333)
        XCTAssertEqual(SummaryEngine.permille(1, of: 2), 500)
        XCTAssertEqual(SummaryEngine.permille(3, of: 3), 1000)
        XCTAssertEqual(SummaryEngine.permille(0, of: 5), 0)
    }

    func testPermilleDisplayString() {
        XCTAssertEqual(SummaryEngine.permilleDisplayString(667), "66.7")
        XCTAssertEqual(SummaryEngine.permilleDisplayString(1000), "100.0")
        XCTAssertEqual(SummaryEngine.permilleDisplayString(0), "0.0")
        XCTAssertEqual(SummaryEngine.permilleDisplayString(5), "0.5")
    }

    // MARK: Date range

    func testCalendarYearRangeIsHalfOpen() {
        let range = SummaryDateRange.calendarYear(
            containing: date(2026, 7, 18),
            calendar: utcCalendar
        )
        XCTAssertTrue(range.contains(date(2026, 1, 1, hour: 0)))
        XCTAssertTrue(range.contains(date(2026, 12, 31)))
        XCTAssertFalse(range.contains(date(2025, 12, 31)))
        XCTAssertFalse(range.contains(utcCalendar.date(from: DateComponents(year: 2027, month: 1, day: 1, hour: 0)) ?? .distantFuture))
    }

    // MARK: Statistics

    func testStatisticsAggregatesWithDenominatorRule() {
        let range = SummaryDateRange.calendarYear(containing: date(2026, 6, 1), calendar: utcCalendar)
        let rows = [
            row(date(2026, 1, 10), acceptance: .accepted, cost: 5_000, minutes: 10),
            row(date(2026, 1, 20), acceptance: .accepted),
            row(date(2026, 2, 5), type: "IV to PO conversion", acceptance: .rejected, cost: 0),
            row(date(2026, 3, 1), acceptance: .pending),
            row(date(2026, 3, 2), acceptance: .notApplicable),
            row(date(2025, 12, 31), acceptance: .accepted),
        ]

        let stats = SummaryEngine.statistics(for: rows, in: range, calendar: utcCalendar)
        XCTAssertEqual(stats.totalCount, 5)
        XCTAssertEqual(stats.acceptance.accepted, 2)
        XCTAssertEqual(stats.acceptance.rejected, 1)
        XCTAssertEqual(stats.acceptance.pending, 1)
        XCTAssertEqual(stats.acceptance.notApplicable, 1)
        // I-007: 2 of 3 resolved records accepted.
        XCTAssertEqual(stats.acceptance.ratePermille, 667)
        // Cost total sums only rows carrying a value; zero remains real.
        XCTAssertEqual(stats.costTotalCents, 5_000)
        XCTAssertEqual(stats.minutesTotal, 10)
        XCTAssertEqual(stats.countsByType.first?.label, "Renal dose adjustment")
        XCTAssertEqual(stats.countsByType.first?.count, 4)
        XCTAssertEqual(stats.serviceLineBreakdown.first?.label, "Unassigned")
    }

    func testStatisticsCostIsNilWhenNoRowCarriesValue() {
        let range = SummaryDateRange.calendarYear(containing: date(2026, 6, 1), calendar: utcCalendar)
        let rows = [
            row(date(2026, 1, 10)),
            row(date(2026, 2, 10)),
        ]
        let stats = SummaryEngine.statistics(for: rows, in: range, calendar: utcCalendar)
        XCTAssertNil(stats.costTotalCents)
        XCTAssertNil(stats.minutesTotal)
    }

    func testStatisticsCostZeroIsDistinctFromNil() {
        let range = SummaryDateRange.calendarYear(containing: date(2026, 6, 1), calendar: utcCalendar)
        let rows = [row(date(2026, 1, 10), cost: 0)]
        let stats = SummaryEngine.statistics(for: rows, in: range, calendar: utcCalendar)
        XCTAssertEqual(stats.costTotalCents, 0)
    }

    func testMonthSequenceIncludesZeroCountMonths() {
        let range = SummaryDateRange.calendarYear(containing: date(2026, 6, 1), calendar: utcCalendar)
        let rows = [
            row(date(2026, 1, 10)),
            row(date(2026, 3, 10)),
        ]
        let stats = SummaryEngine.statistics(for: rows, in: range, calendar: utcCalendar)
        XCTAssertEqual(stats.countsByMonth.count, 12)
        XCTAssertEqual(stats.countsByMonth.first?.monthKey, "2026-01")
        XCTAssertEqual(stats.countsByMonth.first?.count, 1)
        XCTAssertEqual(stats.countsByMonth[1].monthKey, "2026-02")
        XCTAssertEqual(stats.countsByMonth[1].count, 0)
        XCTAssertEqual(stats.countsByMonth.last?.monthKey, "2026-12")
    }

    func testRangeChoiceMapping() {
        let now = date(2026, 7, 18)
        let thisYear = SummaryRangeChoice.thisYear.range(now: now, calendar: utcCalendar)
        XCTAssertTrue(thisYear.contains(date(2026, 1, 1, hour: 0)))
        XCTAssertFalse(thisYear.contains(date(2025, 12, 31)))

        let lastYear = SummaryRangeChoice.lastYear.range(now: now, calendar: utcCalendar)
        XCTAssertTrue(lastYear.contains(date(2025, 6, 15)))
        XCTAssertFalse(lastYear.contains(date(2026, 1, 15)))

        let allTime = SummaryRangeChoice.allTime.range(now: now, calendar: utcCalendar)
        XCTAssertTrue(allTime.contains(date(1990, 1, 1)))
        XCTAssertTrue(allTime.contains(date(2090, 1, 1)))
    }

    func testAllTimeStatisticsBucketMonthsAcrossDataSpanOnly() {
        let allTime = SummaryRangeChoice.allTime.range(now: date(2026, 7, 18), calendar: utcCalendar)
        let rows = [
            row(date(2025, 11, 10)),
            row(date(2026, 2, 10)),
        ]
        let stats = SummaryEngine.statistics(for: rows, in: allTime, calendar: utcCalendar)
        XCTAssertEqual(
            stats.countsByMonth.map(\.monthKey),
            ["2025-11", "2025-12", "2026-01", "2026-02"]
        )
        XCTAssertEqual(stats.countsByMonth.first?.count, 1)
        XCTAssertEqual(stats.countsByMonth.last?.count, 1)

        let emptyStats = SummaryEngine.statistics(for: [], in: allTime, calendar: utcCalendar)
        XCTAssertTrue(emptyStats.countsByMonth.isEmpty)
    }

    // MARK: CSV formatting

    func testCSVQuotingAndInjectionNeutralization() {
        XCTAssertEqual(InterventionCSV.textField("Plain label"), "Plain label")
        XCTAssertEqual(InterventionCSV.textField("Comma, label"), "\"Comma, label\"")
        XCTAssertEqual(InterventionCSV.textField("Has \"quotes\""), "\"Has \"\"quotes\"\"\"")
        XCTAssertEqual(InterventionCSV.textField("=SUM(A1:A9)"), "'=SUM(A1:A9)")
        XCTAssertEqual(InterventionCSV.textField("+positive"), "'+positive")
        XCTAssertEqual(InterventionCSV.textField("-negative"), "'-negative")
        XCTAssertEqual(InterventionCSV.textField("@command"), "'@command")
        XCTAssertEqual(InterventionCSV.textField("'=already quoted"), "'=already quoted")
    }

    func testCSVDocumentIsDeterministicWithExactBytes() {
        let first = row(
            date(2026, 1, 10),
            type: "Renal dose adjustment",
            drugClass: "Antimicrobials",
            line: "Critical care",
            acceptance: .accepted,
            cost: 5_000,
            minutes: 10
        )
        let second = row(
            date(2026, 2, 5),
            type: "IV, then PO",
            drugClass: "Analgesics",
            line: nil,
            acceptance: .pending,
            cost: nil,
            minutes: nil
        )

        let expected = InterventionCSV.header
            + "\r\n"
            + "2026-01-10T12:00:00Z,Renal dose adjustment,Antimicrobials,Critical care,accepted,5000,10"
            + "\r\n"
            + "2026-02-05T12:00:00Z,\"IV, then PO\",Analgesics,,pending,,"
            + "\r\n"

        // Input order must not matter.
        XCTAssertEqual(InterventionCSV.document(rows: [second, first]), expected)
        XCTAssertEqual(InterventionCSV.document(rows: [first, second]), expected)
    }

    func testCSVEmptyDocumentIsHeaderOnly() {
        XCTAssertEqual(
            InterventionCSV.document(rows: []),
            InterventionCSV.header + "\r\n"
        )
    }

    // MARK: Snapshot service

    func testSnapshotServiceFlattensAndFiltersRange() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let type = try TaxonomyService.addInterventionType(label: "Renal dose adjustment", in: context)
        let drugClass = try TaxonomyService.addDrugClass(label: "Antimicrobials", in: context)

        let inside = date(2026, 5, 1)
        let outside = date(2025, 5, 1)
        try InterventionCaptureService.record(
            CaptureDraft(typeID: type.id, drugClassID: drugClass.id, acceptance: .accepted),
            at: inside,
            in: context
        )
        try InterventionCaptureService.record(
            CaptureDraft(typeID: type.id, drugClassID: drugClass.id, acceptance: .accepted),
            at: outside,
            in: context
        )

        let range = SummaryDateRange.calendarYear(containing: date(2026, 6, 1), calendar: utcCalendar)
        let rows = try SummarySnapshotService.rows(in: range, from: context)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.typeLabel, "Renal dose adjustment")
        XCTAssertEqual(rows.first?.drugClassLabel, "Antimicrobials")
        XCTAssertEqual(rows.first?.acceptance, .accepted)
    }
}
