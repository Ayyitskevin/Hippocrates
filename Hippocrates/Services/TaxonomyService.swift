import Foundation
import SwiftData

enum TaxonomyServiceError: Error, Equatable {
    case invalidLabel
    case labelTooLong(limit: Int)
    case duplicateLabel(normalizedLabel: String)
    case negativeCostAvoidanceCents(Int)
    case rowIsReferenced(rowID: UUID)
    case reorderMustIncludeEveryRow
    case starterSeedRequiresEmptyTaxonomies
}

/// I-004: labels are generic department categories, never record-specific
/// prose. The mechanical constraints are single-line and bounded length;
/// editor UI carries the purpose guidance. An immutable file-scope constant
/// stays readable from nonisolated validation under strict concurrency.
private let taxonomyLabelCharacterLimit = 60

/// Owns every shipping mutation of the three editable taxonomies. Views never
/// insert, rename, reorder, deactivate, or delete a taxonomy row directly;
/// one main-actor service keeps validation, save, and rollback behavior
/// identical across the three models.
@MainActor
enum TaxonomyService {
    nonisolated static var labelCharacterLimit: Int { taxonomyLabelCharacterLimit }

    // MARK: Validation

    nonisolated static func normalizedLabel(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw TaxonomyServiceError.invalidLabel
        }
        guard trimmed.contains(where: { $0.isNewline }) == false else {
            throw TaxonomyServiceError.invalidLabel
        }
        guard trimmed.count <= labelCharacterLimit else {
            throw TaxonomyServiceError.labelTooLong(limit: labelCharacterLimit)
        }
        return trimmed
    }

    /// P-002 keeps unknown distinct from an explicit zero: `nil` is valid and
    /// means no institutional value is configured.
    nonisolated static func validate(costAvoidanceCents: Int?) throws {
        if let costAvoidanceCents, costAvoidanceCents < 0 {
            throw TaxonomyServiceError.negativeCostAvoidanceCents(costAvoidanceCents)
        }
    }

    // MARK: Intervention types

    /// Rows are returned in the deterministic editor order: configured
    /// `sortOrder`, then case-insensitive label as the stable tie-breaker.
    static func allInterventionTypes(in context: ModelContext) throws -> [InterventionType] {
        try context.fetch(FetchDescriptor<InterventionType>()).sorted {
            orderedBefore($0.sortOrder, $0.label, $1.sortOrder, $1.label)
        }
    }

    @discardableResult
    static func addInterventionType(
        label rawLabel: String,
        defaultCostAvoidanceCents: Int? = nil,
        in context: ModelContext
    ) throws -> InterventionType {
        let label = try normalizedLabel(rawLabel)
        try validate(costAvoidanceCents: defaultCostAvoidanceCents)
        let existing = try allInterventionTypes(in: context)
        try requireUniqueLabel(label, among: existing.map(\.label))
        let row = InterventionType(
            label: label,
            defaultCostAvoidanceCents: defaultCostAvoidanceCents,
            isActive: true,
            sortOrder: nextSortOrder(after: existing.map(\.sortOrder))
        )
        context.insert(row)
        try saveOrRollback(context)
        return row
    }

    static func renameInterventionType(
        _ row: InterventionType,
        to rawLabel: String,
        in context: ModelContext
    ) throws {
        let label = try normalizedLabel(rawLabel)
        let others = try allInterventionTypes(in: context).filter { $0.id != row.id }
        try requireUniqueLabel(label, among: others.map(\.label))
        row.label = label
        try saveOrRollback(context)
    }

    static func setDefaultCostAvoidanceCents(
        _ cents: Int?,
        on row: InterventionType,
        in context: ModelContext
    ) throws {
        try validate(costAvoidanceCents: cents)
        row.defaultCostAvoidanceCents = cents
        try saveOrRollback(context)
    }

    static func setInterventionTypeActive(
        _ isActive: Bool,
        on row: InterventionType,
        in context: ModelContext
    ) throws {
        row.isActive = isActive
        try saveOrRollback(context)
    }

    static func reorderInterventionTypes(
        _ orderedIDs: [UUID],
        in context: ModelContext
    ) throws {
        let rows = try allInterventionTypes(in: context)
        let positions = try orderPositions(orderedIDs, matching: rows.map(\.id))
        for row in rows {
            row.sortOrder = positions[row.id] ?? row.sortOrder
        }
        try saveOrRollback(context)
    }

    static func deleteInterventionType(
        _ row: InterventionType,
        in context: ModelContext
    ) throws {
        let isReferenced = try allInterventions(in: context)
            .contains { $0.type?.id == row.id }
        guard isReferenced == false else {
            throw TaxonomyServiceError.rowIsReferenced(rowID: row.id)
        }
        try deleteUnreferencedRow(row, in: context)
    }

    // MARK: Drug classes

    static func allDrugClasses(in context: ModelContext) throws -> [DrugClass] {
        try context.fetch(FetchDescriptor<DrugClass>()).sorted {
            orderedBefore($0.sortOrder, $0.label, $1.sortOrder, $1.label)
        }
    }

    @discardableResult
    static func addDrugClass(
        label rawLabel: String,
        in context: ModelContext
    ) throws -> DrugClass {
        let label = try normalizedLabel(rawLabel)
        let existing = try allDrugClasses(in: context)
        try requireUniqueLabel(label, among: existing.map(\.label))
        let row = DrugClass(
            label: label,
            isActive: true,
            sortOrder: nextSortOrder(after: existing.map(\.sortOrder))
        )
        context.insert(row)
        try saveOrRollback(context)
        return row
    }

    static func renameDrugClass(
        _ row: DrugClass,
        to rawLabel: String,
        in context: ModelContext
    ) throws {
        let label = try normalizedLabel(rawLabel)
        let others = try allDrugClasses(in: context).filter { $0.id != row.id }
        try requireUniqueLabel(label, among: others.map(\.label))
        row.label = label
        try saveOrRollback(context)
    }

    static func setDrugClassActive(
        _ isActive: Bool,
        on row: DrugClass,
        in context: ModelContext
    ) throws {
        row.isActive = isActive
        try saveOrRollback(context)
    }

    static func reorderDrugClasses(
        _ orderedIDs: [UUID],
        in context: ModelContext
    ) throws {
        let rows = try allDrugClasses(in: context)
        let positions = try orderPositions(orderedIDs, matching: rows.map(\.id))
        for row in rows {
            row.sortOrder = positions[row.id] ?? row.sortOrder
        }
        try saveOrRollback(context)
    }

    static func deleteDrugClass(
        _ row: DrugClass,
        in context: ModelContext
    ) throws {
        let isReferenced = try allInterventions(in: context)
            .contains { $0.drugClass?.id == row.id }
        guard isReferenced == false else {
            throw TaxonomyServiceError.rowIsReferenced(rowID: row.id)
        }
        try deleteUnreferencedRow(row, in: context)
    }

    // MARK: Service lines

    static func allServiceLines(in context: ModelContext) throws -> [ServiceLine] {
        try context.fetch(FetchDescriptor<ServiceLine>()).sorted {
            orderedBefore($0.sortOrder, $0.label, $1.sortOrder, $1.label)
        }
    }

    @discardableResult
    static func addServiceLine(
        label rawLabel: String,
        in context: ModelContext
    ) throws -> ServiceLine {
        let label = try normalizedLabel(rawLabel)
        let existing = try allServiceLines(in: context)
        try requireUniqueLabel(label, among: existing.map(\.label))
        let row = ServiceLine(
            label: label,
            isActive: true,
            sortOrder: nextSortOrder(after: existing.map(\.sortOrder))
        )
        context.insert(row)
        try saveOrRollback(context)
        return row
    }

    static func renameServiceLine(
        _ row: ServiceLine,
        to rawLabel: String,
        in context: ModelContext
    ) throws {
        let label = try normalizedLabel(rawLabel)
        let others = try allServiceLines(in: context).filter { $0.id != row.id }
        try requireUniqueLabel(label, among: others.map(\.label))
        row.label = label
        try saveOrRollback(context)
    }

    static func setServiceLineActive(
        _ isActive: Bool,
        on row: ServiceLine,
        in context: ModelContext
    ) throws {
        row.isActive = isActive
        try saveOrRollback(context)
    }

    static func reorderServiceLines(
        _ orderedIDs: [UUID],
        in context: ModelContext
    ) throws {
        let rows = try allServiceLines(in: context)
        let positions = try orderPositions(orderedIDs, matching: rows.map(\.id))
        for row in rows {
            row.sortOrder = positions[row.id] ?? row.sortOrder
        }
        try saveOrRollback(context)
    }

    static func deleteServiceLine(
        _ row: ServiceLine,
        in context: ModelContext
    ) throws {
        let isReferenced = try allInterventions(in: context)
            .contains { $0.serviceLine?.id == row.id }
        guard isReferenced == false else {
            throw TaxonomyServiceError.rowIsReferenced(rowID: row.id)
        }
        try deleteUnreferencedRow(row, in: context)
    }

    // MARK: Starter set

    /// P-003: applies the explicitly accepted starter labels to a store whose
    /// taxonomies are all empty. Anything else is a real configuration and is
    /// never merged over; the caller routes edits through the ordinary paths.
    static func seedStarterTaxonomies(
        interventionTypeLabels: [String],
        drugClassLabels: [String],
        serviceLineLabels: [String],
        in context: ModelContext
    ) throws {
        let existingTypes = try context.fetch(FetchDescriptor<InterventionType>())
        let existingClasses = try context.fetch(FetchDescriptor<DrugClass>())
        let existingLines = try context.fetch(FetchDescriptor<ServiceLine>())
        guard existingTypes.isEmpty, existingClasses.isEmpty, existingLines.isEmpty else {
            throw TaxonomyServiceError.starterSeedRequiresEmptyTaxonomies
        }

        let typeLabels = try normalizedUniqueLabels(interventionTypeLabels)
        let classLabels = try normalizedUniqueLabels(drugClassLabels)
        let lineLabels = try normalizedUniqueLabels(serviceLineLabels)

        for (index, label) in typeLabels.enumerated() {
            context.insert(InterventionType(label: label, isActive: true, sortOrder: index))
        }
        for (index, label) in classLabels.enumerated() {
            context.insert(DrugClass(label: label, isActive: true, sortOrder: index))
        }
        for (index, label) in lineLabels.enumerated() {
            context.insert(ServiceLine(label: label, isActive: true, sortOrder: index))
        }
        try saveOrRollback(context)
    }

    // MARK: Shared helpers

    private nonisolated static func orderedBefore(
        _ leftOrder: Int,
        _ leftLabel: String,
        _ rightOrder: Int,
        _ rightLabel: String
    ) -> Bool {
        if leftOrder != rightOrder {
            return leftOrder < rightOrder
        }
        return leftLabel.lowercased() < rightLabel.lowercased()
    }

    /// The reference check fetches the full intervention set and filters in
    /// memory. This mirrors A-007: the expected volume is small, and it avoids
    /// optional-relationship predicate compilation risk.
    private static func allInterventions(in context: ModelContext) throws -> [Intervention] {
        try context.fetch(FetchDescriptor<Intervention>())
    }

    private nonisolated static func nextSortOrder(after existingOrders: [Int]) -> Int {
        (existingOrders.max() ?? -1) + 1
    }

    private nonisolated static func requireUniqueLabel(
        _ label: String,
        among existingLabels: [String]
    ) throws {
        let normalized = label.lowercased()
        let collides = existingLabels.contains { $0.lowercased() == normalized }
        guard collides == false else {
            throw TaxonomyServiceError.duplicateLabel(normalizedLabel: normalized)
        }
    }

    private nonisolated static func normalizedUniqueLabels(_ rawLabels: [String]) throws -> [String] {
        var seen: Set<String> = []
        var labels: [String] = []
        for raw in rawLabels {
            let label = try normalizedLabel(raw)
            let key = label.lowercased()
            guard seen.contains(key) == false else {
                throw TaxonomyServiceError.duplicateLabel(normalizedLabel: key)
            }
            seen.insert(key)
            labels.append(label)
        }
        return labels
    }

    private nonisolated static func orderPositions(
        _ orderedIDs: [UUID],
        matching rowIDs: [UUID]
    ) throws -> [UUID: Int] {
        guard
            orderedIDs.count == rowIDs.count,
            Set(orderedIDs).count == orderedIDs.count,
            Set(orderedIDs) == Set(rowIDs)
        else {
            throw TaxonomyServiceError.reorderMustIncludeEveryRow
        }
        var positions: [UUID: Int] = [:]
        for (index, id) in orderedIDs.enumerated() {
            positions[id] = index
        }
        return positions
    }

    /// Milestone 1 permits hard deletion only for never-referenced rows; every
    /// referenced row is soft-deactivated instead so historical interventions
    /// keep their categories. This is the one reviewed shipping deletion seam
    /// the boundary scanner masks; keep the delete call on its own exact line.
    private static func deleteUnreferencedRow(
        _ row: any PersistentModel,
        in context: ModelContext
    ) throws {
        context.delete(row)
        try saveOrRollback(context)
    }

    /// The context was consistent before each single-operation mutation, so
    /// rollback discards only the change owned by that operation.
    private static func saveOrRollback(_ context: ModelContext) throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
