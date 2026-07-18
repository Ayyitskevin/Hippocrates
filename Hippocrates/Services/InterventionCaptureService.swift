import Foundation
import SwiftData

/// The three required selections plus the reviewed optional fields (I-008).
/// This is an ephemeral value; the third required tap turns it into one
/// persisted `Intervention`. Optional fields default to unset and never add a
/// required tap to type -> class -> acceptance.
struct CaptureDraft: Equatable, Sendable {
    var typeID: UUID
    var drugClassID: UUID
    var acceptance: Acceptance
    var serviceLineID: UUID?
    var minutesSpent: Int?
    /// An explicit per-capture override. `nil` means "use the type's configured
    /// default snapshot"; it does not mean zero.
    var costAvoidanceCentsOverride: Int?

    init(
        typeID: UUID,
        drugClassID: UUID,
        acceptance: Acceptance,
        serviceLineID: UUID? = nil,
        minutesSpent: Int? = nil,
        costAvoidanceCentsOverride: Int? = nil
    ) {
        self.typeID = typeID
        self.drugClassID = drugClassID
        self.acceptance = acceptance
        self.serviceLineID = serviceLineID
        self.minutesSpent = minutesSpent
        self.costAvoidanceCentsOverride = costAvoidanceCentsOverride
    }
}

enum InterventionCaptureError: Error, Equatable {
    case unknownType(UUID)
    case unknownDrugClass(UUID)
    case unknownServiceLine(UUID)
    case negativeMinutes(Int)
    case negativeCostAvoidanceCents(Int)
}

/// Records interventions from a completed capture draft. Cost avoidance is
/// snapshotted from the selected type at record time (A-013): the intervention
/// keeps its own optional value, so later editing the type's default never
/// rewrites past records, and unknown stays distinct from explicit zero.
@MainActor
enum InterventionCaptureService {
    @discardableResult
    static func record(
        _ draft: CaptureDraft,
        at timestamp: Date = .now,
        in context: ModelContext
    ) throws -> Intervention {
        guard let type = try interventionType(draft.typeID, in: context) else {
            throw InterventionCaptureError.unknownType(draft.typeID)
        }
        guard let drugClass = try drugClass(draft.drugClassID, in: context) else {
            throw InterventionCaptureError.unknownDrugClass(draft.drugClassID)
        }

        var serviceLine: ServiceLine?
        if let serviceLineID = draft.serviceLineID {
            guard let resolved = try self.serviceLine(serviceLineID, in: context) else {
                throw InterventionCaptureError.unknownServiceLine(serviceLineID)
            }
            serviceLine = resolved
        }

        if let minutes = draft.minutesSpent, minutes < 0 {
            throw InterventionCaptureError.negativeMinutes(minutes)
        }

        // The override, when present, wins; otherwise the type's configured
        // default is snapshotted. Both may legitimately be nil.
        let costSnapshot = draft.costAvoidanceCentsOverride ?? type.defaultCostAvoidanceCents
        if let cost = costSnapshot, cost < 0 {
            throw InterventionCaptureError.negativeCostAvoidanceCents(cost)
        }

        let intervention = Intervention(
            timestamp: timestamp,
            type: type,
            drugClass: drugClass,
            serviceLine: serviceLine,
            acceptance: draft.acceptance,
            costAvoidanceCents: costSnapshot,
            minutesSpent: draft.minutesSpent
        )
        context.insert(intervention)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return intervention
    }

    static func rankedActiveTypes(in context: ModelContext, recentWindow: Int = 50) throws -> [InterventionType] {
        let activeTypes = try TaxonomyService.allInterventionTypes(in: context).filter(\.isActive)
        let rankableTypes = activeTypes.map {
            RankableType(id: $0.id, sortOrder: $0.sortOrder, label: $0.label)
        }
        let recent = try recentInterventions(limit: recentWindow, in: context)
        let usage = recent.compactMap { intervention -> TypeUsage? in
            guard let typeID = intervention.type?.id else { return nil }
            return TypeUsage(typeID: typeID, usedAt: intervention.timestamp)
        }
        let order = FrecencyRanking.rank(types: rankableTypes, recentUsage: usage)
        let byID = Dictionary(uniqueKeysWithValues: activeTypes.map { ($0.id, $0) })
        return order.compactMap { byID[$0.id] }
    }

    private static func recentInterventions(limit: Int, in context: ModelContext) throws -> [Intervention] {
        var descriptor = FetchDescriptor<Intervention>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
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
}
