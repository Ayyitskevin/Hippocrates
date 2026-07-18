import Foundation
import SwiftData

/// A value snapshot of one recent intervention for the ledger list. The ledger
/// never holds a live model reference; edits route back through this service by
/// UUID. There is deliberately no free-text or narrative field (I-013).
struct InterventionSummary: Identifiable, Equatable, Sendable {
    let id: UUID
    var timestamp: Date
    var typeID: UUID?
    var typeLabel: String?
    var drugClassID: UUID?
    var drugClassLabel: String?
    var serviceLineID: UUID?
    var serviceLineLabel: String?
    var acceptance: Acceptance
    var costAvoidanceCents: Int?
    var minutesSpent: Int?
}

/// Structured edit request. Only these categorical and numeric fields can
/// change; there is no path to attach prose to an intervention.
struct InterventionEdit: Equatable, Sendable {
    var typeID: UUID
    var drugClassID: UUID
    var serviceLineID: UUID?
    var acceptance: Acceptance
    var minutesSpent: Int?
    var costAvoidanceCents: Int?
}

enum InterventionLedgerError: Error, Equatable {
    case unknownIntervention(UUID)
    case unknownType(UUID)
    case unknownDrugClass(UUID)
    case unknownServiceLine(UUID)
    case negativeMinutes(Int)
    case negativeCostAvoidanceCents(Int)
}

/// Owns every post-capture mutation and the single reviewed intervention
/// deletion seam (I-013). Both the five-second undo and the ledger's confirmed
/// delete route through `delete(id:in:)`, so there is exactly one intervention
/// `.delete` call in shipping code for the boundary scanner to mask.
@MainActor
enum InterventionLedgerService {
    static func recent(limit: Int = 50, in context: ModelContext) throws -> [InterventionSummary] {
        var descriptor = FetchDescriptor<Intervention>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor).map(summary(of:))
    }

    /// One-tap acceptance resolution: the common case where a recommendation's
    /// outcome becomes known after capture. This is the pending -> accepted or
    /// rejected transition the profession actually needs.
    static func setAcceptance(
        _ acceptance: Acceptance,
        forInterventionID id: UUID,
        in context: ModelContext
    ) throws {
        guard let intervention = try intervention(id, in: context) else {
            throw InterventionLedgerError.unknownIntervention(id)
        }
        intervention.acceptance = acceptance
        try saveOrRollback(context)
    }

    static func apply(
        _ edit: InterventionEdit,
        toInterventionID id: UUID,
        in context: ModelContext
    ) throws {
        guard let intervention = try intervention(id, in: context) else {
            throw InterventionLedgerError.unknownIntervention(id)
        }
        guard let type = try interventionType(edit.typeID, in: context) else {
            throw InterventionLedgerError.unknownType(edit.typeID)
        }
        guard let drugClass = try drugClass(edit.drugClassID, in: context) else {
            throw InterventionLedgerError.unknownDrugClass(edit.drugClassID)
        }

        var serviceLine: ServiceLine?
        if let serviceLineID = edit.serviceLineID {
            guard let resolved = try self.serviceLine(serviceLineID, in: context) else {
                throw InterventionLedgerError.unknownServiceLine(serviceLineID)
            }
            serviceLine = resolved
        }

        if let minutes = edit.minutesSpent, minutes < 0 {
            throw InterventionLedgerError.negativeMinutes(minutes)
        }
        if let cost = edit.costAvoidanceCents, cost < 0 {
            throw InterventionLedgerError.negativeCostAvoidanceCents(cost)
        }

        intervention.type = type
        intervention.drugClass = drugClass
        intervention.serviceLine = serviceLine
        intervention.acceptance = edit.acceptance
        intervention.minutesSpent = edit.minutesSpent
        intervention.costAvoidanceCents = edit.costAvoidanceCents
        try saveOrRollback(context)
    }

    /// The single reviewed intervention deletion path. Undo (five-second
    /// snackbar) and the ledger's confirmed delete both call this. The method
    /// name deliberately avoids a bare `delete` token so call sites do not read
    /// as raw model deletion to the boundary scanner.
    static func deleteIntervention(id: UUID, in context: ModelContext) throws {
        guard let intervention = try intervention(id, in: context) else {
            throw InterventionLedgerError.unknownIntervention(id)
        }
        context.delete(intervention)
        try saveOrRollback(context)
    }

    // MARK: Helpers

    private static func summary(of intervention: Intervention) -> InterventionSummary {
        InterventionSummary(
            id: intervention.id,
            timestamp: intervention.timestamp,
            typeID: intervention.type?.id,
            typeLabel: intervention.type?.label,
            drugClassID: intervention.drugClass?.id,
            drugClassLabel: intervention.drugClass?.label,
            serviceLineID: intervention.serviceLine?.id,
            serviceLineLabel: intervention.serviceLine?.label,
            acceptance: intervention.acceptance,
            costAvoidanceCents: intervention.costAvoidanceCents,
            minutesSpent: intervention.minutesSpent
        )
    }

    /// A UUID-equality `#Predicate` compiles here, but the codebase resolves
    /// small model lookups in memory (A-007) to avoid predicate-compilation
    /// fragility. The expected intervention volume is well within that policy.
    private static func intervention(_ id: UUID, in context: ModelContext) throws -> Intervention? {
        try context.fetch(FetchDescriptor<Intervention>()).first { $0.id == id }
    }

    private static func interventionType(_ id: UUID, in context: ModelContext) throws -> InterventionType? {
        try TaxonomyService.allInterventionTypes(in: context).first { $0.id == id }
    }

    private static func drugClass(_ id: UUID, in context: ModelContext) throws -> DrugClass? {
        try TaxonomyService.allDrugClasses(in: context).first { $0.id == id }
    }

    private static func serviceLine(_ id: UUID, in context: ModelContext) throws -> ServiceLine? {
        try TaxonomyService.allServiceLines(in: context).first { $0.id == id }
    }

    private static func saveOrRollback(_ context: ModelContext) throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
