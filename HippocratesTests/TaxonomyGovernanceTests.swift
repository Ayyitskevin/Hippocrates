import Foundation
import SwiftData
import XCTest

@testable import Hippocrates

@MainActor
final class TaxonomyGovernanceTests: XCTestCase {
    // MARK: Label validation

    func testNormalizedLabelTrimsWhitespace() throws {
        let label = try TaxonomyService.normalizedLabel("  Renal dose adjustment  ")
        XCTAssertEqual(label, "Renal dose adjustment")
    }

    func testNormalizedLabelRejectsEmptyAndMultiline() {
        XCTAssertThrowsError(try TaxonomyService.normalizedLabel("   ")) { error in
            XCTAssertEqual(error as? TaxonomyServiceError, .invalidLabel)
        }
        XCTAssertThrowsError(try TaxonomyService.normalizedLabel("Room\n412")) { error in
            XCTAssertEqual(error as? TaxonomyServiceError, .invalidLabel)
        }
    }

    func testNormalizedLabelRejectsOversizedLabel() {
        let oversized = String(repeating: "a", count: 61)
        XCTAssertThrowsError(try TaxonomyService.normalizedLabel(oversized)) { error in
            XCTAssertEqual(error as? TaxonomyServiceError, .labelTooLong(limit: 60))
        }
    }

    // MARK: Add, rename, and cost defaults

    func testAddInterventionTypeAssignsSequentialSortOrder() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext

        try TaxonomyService.addInterventionType(label: "Renal dose adjustment", in: context)
        try TaxonomyService.addInterventionType(label: "IV to PO conversion", in: context)
        try TaxonomyService.addInterventionType(label: "Dose optimization", in: context)

        let rows = try TaxonomyService.allInterventionTypes(in: context)
        XCTAssertEqual(rows.map(\.sortOrder), [0, 1, 2])
        XCTAssertEqual(
            rows.map(\.label),
            ["Renal dose adjustment", "IV to PO conversion", "Dose optimization"]
        )
        XCTAssertFalse(context.hasChanges)
    }

    func testDuplicateLabelIsRejectedCaseInsensitively() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext

        try TaxonomyService.addInterventionType(label: "Renal dose adjustment", in: context)
        XCTAssertThrowsError(
            try TaxonomyService.addInterventionType(label: "renal DOSE adjustment", in: context)
        ) { error in
            XCTAssertEqual(
                error as? TaxonomyServiceError,
                .duplicateLabel(normalizedLabel: "renal dose adjustment")
            )
        }
        XCTAssertEqual(try TaxonomyService.allInterventionTypes(in: context).count, 1)
    }

    func testRenamePreservesIdentityAndRejectsCollision() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext

        let first = try TaxonomyService.addInterventionType(label: "Dose optimization", in: context)
        let second = try TaxonomyService.addInterventionType(label: "Patient education", in: context)
        let firstID = first.id

        try TaxonomyService.renameInterventionType(first, to: "Dose adjustment", in: context)
        XCTAssertEqual(first.id, firstID)
        XCTAssertEqual(first.label, "Dose adjustment")

        XCTAssertThrowsError(
            try TaxonomyService.renameInterventionType(second, to: "dose ADJUSTMENT", in: context)
        ) { error in
            XCTAssertEqual(
                error as? TaxonomyServiceError,
                .duplicateLabel(normalizedLabel: "dose adjustment")
            )
        }
    }

    func testCostDefaultKeepsNilDistinctFromZeroAndRejectsNegative() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext

        let row = try TaxonomyService.addInterventionType(label: "Formulary interchange", in: context)
        XCTAssertNil(row.defaultCostAvoidanceCents)

        try TaxonomyService.setDefaultCostAvoidanceCents(0, on: row, in: context)
        XCTAssertEqual(row.defaultCostAvoidanceCents, 0)

        try TaxonomyService.setDefaultCostAvoidanceCents(nil, on: row, in: context)
        XCTAssertNil(row.defaultCostAvoidanceCents)

        XCTAssertThrowsError(
            try TaxonomyService.setDefaultCostAvoidanceCents(-500, on: row, in: context)
        ) { error in
            XCTAssertEqual(
                error as? TaxonomyServiceError,
                .negativeCostAvoidanceCents(-500)
            )
        }
        XCTAssertNil(row.defaultCostAvoidanceCents)
    }

    // MARK: Soft-deactivation and deletion

    func testSoftDeactivationPreservesRowAndReferences() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext

        let type = try TaxonomyService.addInterventionType(label: "Renal dose adjustment", in: context)
        let line = try TaxonomyService.addServiceLine(label: "Critical care", in: context)
        let intervention = Intervention(type: type, serviceLine: line, acceptance: .accepted)
        context.insert(intervention)
        try context.save()

        try TaxonomyService.setInterventionTypeActive(false, on: type, in: context)
        try TaxonomyService.setServiceLineActive(false, on: line, in: context)

        XCTAssertFalse(type.isActive)
        XCTAssertFalse(line.isActive)
        XCTAssertEqual(intervention.type?.id, type.id)
        XCTAssertEqual(intervention.serviceLine?.id, line.id)
        XCTAssertEqual(try TaxonomyService.allInterventionTypes(in: context).count, 1)
    }

    func testReferencedRowCannotBeHardDeleted() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext

        let drugClass = try TaxonomyService.addDrugClass(label: "Anticoagulants", in: context)
        let intervention = Intervention(drugClass: drugClass, acceptance: .pending)
        context.insert(intervention)
        try context.save()

        XCTAssertThrowsError(
            try TaxonomyService.deleteDrugClass(drugClass, in: context)
        ) { error in
            XCTAssertEqual(
                error as? TaxonomyServiceError,
                .rowIsReferenced(rowID: drugClass.id)
            )
        }
        XCTAssertEqual(try TaxonomyService.allDrugClasses(in: context).count, 1)
        XCTAssertFalse(context.hasChanges)
    }

    func testUnreferencedRowHardDeleteRemovesRow() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext

        let type = try TaxonomyService.addInterventionType(label: "Dose optimization", in: context)
        let drugClass = try TaxonomyService.addDrugClass(label: "Antimicrobials", in: context)
        let line = try TaxonomyService.addServiceLine(label: "Oncology", in: context)

        try TaxonomyService.deleteInterventionType(type, in: context)
        try TaxonomyService.deleteDrugClass(drugClass, in: context)
        try TaxonomyService.deleteServiceLine(line, in: context)

        XCTAssertEqual(try TaxonomyService.allInterventionTypes(in: context).count, 0)
        XCTAssertEqual(try TaxonomyService.allDrugClasses(in: context).count, 0)
        XCTAssertEqual(try TaxonomyService.allServiceLines(in: context).count, 0)
        XCTAssertFalse(context.hasChanges)
    }

    // MARK: Reordering

    func testReorderRequiresCompletePermutation() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext

        let first = try TaxonomyService.addInterventionType(label: "Dose optimization", in: context)
        let second = try TaxonomyService.addInterventionType(label: "Patient education", in: context)

        XCTAssertThrowsError(
            try TaxonomyService.reorderInterventionTypes([first.id], in: context)
        ) { error in
            XCTAssertEqual(error as? TaxonomyServiceError, .reorderMustIncludeEveryRow)
        }

        try TaxonomyService.reorderInterventionTypes([second.id, first.id], in: context)
        let rows = try TaxonomyService.allInterventionTypes(in: context)
        XCTAssertEqual(rows.map(\.id), [second.id, first.id])
        XCTAssertEqual(rows.map(\.sortOrder), [0, 1])
    }

    // MARK: Starter set

    func testStarterSeedPopulatesEmptyStoreInListedOrder() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext

        try TaxonomyService.seedStarterTaxonomies(
            interventionTypeLabels: StarterTaxonomy.interventionTypeLabels,
            drugClassLabels: StarterTaxonomy.drugClassLabels,
            serviceLineLabels: StarterTaxonomy.serviceLineLabels,
            in: context
        )

        let types = try TaxonomyService.allInterventionTypes(in: context)
        let classes = try TaxonomyService.allDrugClasses(in: context)
        let lines = try TaxonomyService.allServiceLines(in: context)
        XCTAssertEqual(types.map(\.label), StarterTaxonomy.interventionTypeLabels)
        XCTAssertEqual(classes.map(\.label), StarterTaxonomy.drugClassLabels)
        XCTAssertEqual(lines.map(\.label), StarterTaxonomy.serviceLineLabels)
        XCTAssertTrue(types.allSatisfy(\.isActive))
        XCTAssertTrue(types.allSatisfy { $0.defaultCostAvoidanceCents == nil })
        XCTAssertFalse(context.hasChanges)
    }

    func testStarterSeedRequiresEmptyTaxonomies() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext

        try TaxonomyService.addServiceLine(label: "Cardiology", in: context)
        XCTAssertThrowsError(
            try TaxonomyService.seedStarterTaxonomies(
                interventionTypeLabels: StarterTaxonomy.interventionTypeLabels,
                drugClassLabels: StarterTaxonomy.drugClassLabels,
                serviceLineLabels: StarterTaxonomy.serviceLineLabels,
                in: context
            )
        ) { error in
            XCTAssertEqual(
                error as? TaxonomyServiceError,
                .starterSeedRequiresEmptyTaxonomies
            )
        }
        XCTAssertEqual(try TaxonomyService.allInterventionTypes(in: context).count, 0)
    }

    func testStarterLabelsSatisfyServiceValidation() throws {
        let allLabels = StarterTaxonomy.interventionTypeLabels
            + StarterTaxonomy.drugClassLabels
            + StarterTaxonomy.serviceLineLabels
        for label in allLabels {
            XCTAssertEqual(try TaxonomyService.normalizedLabel(label), label)
        }
    }

    // MARK: Bootstrap policy

    func testBootstrapPolicyStates() {
        XCTAssertEqual(
            BootstrapPolicy.state(
                hasCompletedFirstRun: false,
                activeInterventionTypeCount: 0,
                activeDrugClassCount: 0
            ),
            .firstRun
        )
        XCTAssertEqual(
            BootstrapPolicy.state(
                hasCompletedFirstRun: false,
                activeInterventionTypeCount: 5,
                activeDrugClassCount: 5
            ),
            .firstRun
        )
        XCTAssertEqual(
            BootstrapPolicy.state(
                hasCompletedFirstRun: true,
                activeInterventionTypeCount: 1,
                activeDrugClassCount: 0
            ),
            .setupNeeded
        )
        XCTAssertEqual(
            BootstrapPolicy.state(
                hasCompletedFirstRun: true,
                activeInterventionTypeCount: 1,
                activeDrugClassCount: 1
            ),
            .captureReady
        )
    }

    // MARK: Backup parity

    func testBackupRoundTripAfterTaxonomyMutations() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext

        try TaxonomyService.seedStarterTaxonomies(
            interventionTypeLabels: StarterTaxonomy.interventionTypeLabels,
            drugClassLabels: StarterTaxonomy.drugClassLabels,
            serviceLineLabels: StarterTaxonomy.serviceLineLabels,
            in: context
        )

        let types = try TaxonomyService.allInterventionTypes(in: context)
        let firstType = try XCTUnwrap(types.first)
        let lastType = try XCTUnwrap(types.last)
        try TaxonomyService.renameInterventionType(firstType, to: "Renal dosing review", in: context)
        try TaxonomyService.setDefaultCostAvoidanceCents(2500, on: firstType, in: context)
        try TaxonomyService.setInterventionTypeActive(false, on: lastType, in: context)
        try TaxonomyService.reorderInterventionTypes(
            Array(types.map(\.id).reversed()),
            in: context
        )

        let classes = try TaxonomyService.allDrugClasses(in: context)
        let firstClass = try XCTUnwrap(classes.first)
        let intervention = Intervention(
            type: firstType,
            drugClass: firstClass,
            acceptance: .accepted,
            costAvoidanceCents: 2500
        )
        context.insert(intervention)
        try context.save()

        let removableLine = try XCTUnwrap(try TaxonomyService.allServiceLines(in: context).last)
        try TaxonomyService.deleteServiceLine(removableLine, in: context)

        let exportDate = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let archive = try BackupService.makeArchive(from: context, createdAt: exportDate)

        let destination = try HippocratesStore.makeContainer(inMemory: true)
        try BackupService.restore(archive, into: destination.mainContext)
        let reexported = try BackupService.makeArchive(
            from: destination.mainContext,
            createdAt: exportDate
        )
        XCTAssertEqual(archive, reexported)
    }
}
