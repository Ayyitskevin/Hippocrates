import Foundation

/// A half-open interval: `start` is included, `end` is excluded. Using the
/// next period's first instant as `end` avoids end-of-day boundary ambiguity.
struct SummaryDateRange: Equatable, Sendable {
    let start: Date
    let end: Date

    func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }

    /// P-004: the summary's initial state is the calendar year containing
    /// `date` in the supplied calendar. The user can always change the range.
    static func calendarYear(containing date: Date, calendar: Calendar) -> SummaryDateRange {
        let year = calendar.component(.year, from: date)
        var startComponents = DateComponents()
        startComponents.year = year
        startComponents.month = 1
        startComponents.day = 1
        var endComponents = DateComponents()
        endComponents.year = year + 1
        endComponents.month = 1
        endComponents.day = 1
        let start = calendar.date(from: startComponents) ?? date
        let end = calendar.date(from: endComponents) ?? date
        return SummaryDateRange(start: start, end: end)
    }
}

/// P-004: the visible range control's choices. Raw values persist the user's
/// last selection in app storage; they are UI state, not clinical data.
enum SummaryRangeChoice: Int, CaseIterable, Sendable {
    case thisYear = 0
    case lastYear = 1
    case allTime = 2

    var title: String {
        switch self {
        case .thisYear:
            return "This year"
        case .lastYear:
            return "Last year"
        case .allTime:
            return "All time"
        }
    }

    func range(now: Date, calendar: Calendar) -> SummaryDateRange {
        switch self {
        case .thisYear:
            return SummaryDateRange.calendarYear(containing: now, calendar: calendar)
        case .lastYear:
            let previous = calendar.date(byAdding: .year, value: -1, to: now) ?? now
            return SummaryDateRange.calendarYear(containing: previous, calendar: calendar)
        case .allTime:
            return SummaryDateRange(start: .distantPast, end: .distantFuture)
        }
    }
}

/// One intervention flattened to summary-relevant values. Snapshots are taken
/// on the main actor; everything below this line is pure and Sendable.
struct SummaryInputRow: Equatable, Sendable {
    let timestamp: Date
    let typeLabel: String?
    let drugClassLabel: String?
    let serviceLineLabel: String?
    let acceptance: Acceptance
    let costAvoidanceCents: Int?
    let minutesSpent: Int?
}

/// I-007: the acceptance rate's denominator is accepted + rejected only.
/// Pending and not-applicable records are excluded from the denominator and
/// always displayed beside the rate, never silently dropped.
struct AcceptanceBreakdown: Equatable, Sendable {
    let accepted: Int
    let rejected: Int
    let pending: Int
    let notApplicable: Int

    var resolvedDenominator: Int {
        accepted + rejected
    }

    /// Rate in permille (667 = 66.7 percent), nil when nothing is resolved.
    var ratePermille: Int? {
        SummaryEngine.permille(accepted, of: resolvedDenominator)
    }
}

struct LabelCount: Equatable, Sendable {
    let label: String
    let count: Int
}

/// `monthKey` is "YYYY-MM" in the summary calendar, zero-padded, so keys sort
/// lexically in chronological order.
struct MonthCount: Equatable, Sendable {
    let monthKey: String
    let count: Int
}

struct SummaryStatistics: Equatable, Sendable {
    let range: SummaryDateRange
    let totalCount: Int
    let acceptance: AcceptanceBreakdown
    let countsByType: [LabelCount]
    let countsByMonth: [MonthCount]
    let topDrugClasses: [LabelCount]
    let serviceLineBreakdown: [LabelCount]
    /// nil means no included row carried a value (P-002 keeps unknown distinct
    /// from zero); an explicit zero total means rows summed to zero.
    let costTotalCents: Int?
    let minutesTotal: Int?
}

/// Pure aggregation. Deterministic for identical inputs: every list has an
/// explicit sort with a stable tie-breaker.
enum SummaryEngine {
    static let unspecifiedTypeLabel = "Unspecified"
    static let unassignedServiceLineLabel = "Unassigned"

    static func statistics(
        for rows: [SummaryInputRow],
        in range: SummaryDateRange,
        calendar: Calendar
    ) -> SummaryStatistics {
        let included = rows.filter { range.contains($0.timestamp) }

        var accepted = 0
        var rejected = 0
        var pending = 0
        var notApplicable = 0
        var typeCounts: [String: Int] = [:]
        var classCounts: [String: Int] = [:]
        var lineCounts: [String: Int] = [:]
        var monthCounts: [String: Int] = [:]
        var costTotal: Int?
        var minutesTotal: Int?

        for row in included {
            switch row.acceptance {
            case .accepted:
                accepted += 1
            case .rejected:
                rejected += 1
            case .pending:
                pending += 1
            case .notApplicable:
                notApplicable += 1
            }
            typeCounts[row.typeLabel ?? unspecifiedTypeLabel, default: 0] += 1
            classCounts[row.drugClassLabel ?? unspecifiedTypeLabel, default: 0] += 1
            lineCounts[row.serviceLineLabel ?? unassignedServiceLineLabel, default: 0] += 1
            monthCounts[monthKey(for: row.timestamp, calendar: calendar), default: 0] += 1
            if let cost = row.costAvoidanceCents {
                costTotal = (costTotal ?? 0) + cost
            }
            if let minutes = row.minutesSpent {
                minutesTotal = (minutesTotal ?? 0) + minutes
            }
        }

        // An unbounded range (all time) buckets months across the actual data
        // span; a bounded range keeps its full month axis including zero
        // months. Iterating distantPast..distantFuture is never attempted.
        let monthAxisRange: SummaryDateRange
        if range.start == .distantPast || range.end == .distantFuture {
            if let earliest = included.map(\.timestamp).min(),
               let latest = included.map(\.timestamp).max() {
                monthAxisRange = SummaryDateRange(start: earliest, end: latest.addingTimeInterval(1))
            } else {
                monthAxisRange = SummaryDateRange(start: range.start, end: range.start)
            }
        } else {
            monthAxisRange = range
        }

        return SummaryStatistics(
            range: range,
            totalCount: included.count,
            acceptance: AcceptanceBreakdown(
                accepted: accepted,
                rejected: rejected,
                pending: pending,
                notApplicable: notApplicable
            ),
            countsByType: sortedLabelCounts(typeCounts),
            countsByMonth: monthSequence(in: monthAxisRange, calendar: calendar).map { key in
                MonthCount(monthKey: key, count: monthCounts[key, default: 0])
            },
            topDrugClasses: sortedLabelCounts(classCounts),
            serviceLineBreakdown: sortedLabelCounts(lineCounts),
            costTotalCents: costTotal,
            minutesTotal: minutesTotal
        )
    }

    /// Integer permille with half-up rounding, computed without a division
    /// operator token (the boundary parser closes bare slashes).
    static func permille(_ numerator: Int, of denominator: Int) -> Int? {
        guard denominator > 0 else {
            return nil
        }
        let half = denominator.quotientAndRemainder(dividingBy: 2).quotient
        return (numerator * 1000 + half).quotientAndRemainder(dividingBy: denominator).quotient
    }

    /// 667 becomes "66.7"; 1000 becomes "100.0".
    static func permilleDisplayString(_ permille: Int) -> String {
        let split = permille.quotientAndRemainder(dividingBy: 10)
        return String(split.quotient) + "." + String(split.remainder)
    }

    /// Every month intersecting the range appears, including zero-count
    /// months, so charts and tables keep continuous axes.
    static func monthSequence(in range: SummaryDateRange, calendar: Calendar) -> [String] {
        guard range.start < range.end else {
            return []
        }
        var keys: [String] = []
        var components = calendar.dateComponents([.year, .month], from: range.start)
        components.day = 1
        var cursor = calendar.date(from: components) ?? range.start
        while cursor < range.end {
            keys.append(monthKey(for: cursor, calendar: calendar))
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else {
                break
            }
            cursor = next
        }
        return keys
    }

    static func monthKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        return String(format: "%04d-%02d", year, month)
    }

    private static func sortedLabelCounts(_ counts: [String: Int]) -> [LabelCount] {
        counts
            .map { LabelCount(label: $0.key, count: $0.value) }
            .sorted { left, right in
                if left.count != right.count {
                    return left.count > right.count
                }
                return left.label.lowercased() < right.label.lowercased()
            }
    }
}
