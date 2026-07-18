import Foundation
import SwiftData

/// Main-actor snapshot into pure summary rows. Every export begins here:
/// models are flattened to Sendable values, and all aggregation and
/// formatting below happens on those values, never on live models.
@MainActor
enum SummarySnapshotService {
    static func rows(
        in range: SummaryDateRange,
        from context: ModelContext
    ) throws -> [SummaryInputRow] {
        try context.fetch(FetchDescriptor<Intervention>())
            .filter { range.contains($0.timestamp) }
            .map { intervention in
                SummaryInputRow(
                    timestamp: intervention.timestamp,
                    typeLabel: intervention.type?.label,
                    drugClassLabel: intervention.drugClass?.label,
                    serviceLineLabel: intervention.serviceLine?.label,
                    acceptance: intervention.acceptance,
                    costAvoidanceCents: intervention.costAvoidanceCents,
                    minutesSpent: intervention.minutesSpent
                )
            }
    }
}
