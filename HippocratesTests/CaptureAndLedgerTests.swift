import Foundation
import SwiftData
import XCTest

@testable import Hippocrates

@MainActor
final class CaptureAndLedgerTests: XCTestCase {
    // MARK: Frecency ranking (pure)

    func testRankingOrdersByFrequencyThenRecencyThenStableOrder() {
        let a = RankableType(id: UUID(), sortOrder: 2, label: "Alpha")
        let b = RankableType(id: UUID(), sortOrder: 1, label: "Bravo")
        let c = RankableType(id: UUID(), sortOrder: 0, label: "Charlie")

        let base = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let usage = [
            TypeUsage(typeID: a.id, usedAt: base),
            TypeUsage(typeID: a.id, usedAt: base.addingTimeInterval(10)),
            TypeUsage(typeID: b.id, usedAt: base.addingTimeInterval(20)),
        ]

        let ranked = FrecencyRanking.rank(types: [a, b, c], recentUsage: usage)
        // a used twice, b once, c never; c falls to configured sortOrder last.
        XCTAssertEqual(ranked.map(\.id), [a.id, b.id, c.id])
    }

    func testRankingBreaksEqualCountByMostRecentUse() {
        let x = RankableType(id: UUID(), sortOrder: 0, label: "Xray")
        let y = RankableType(id: UUID(), sortOrder: 1, label: "Yankee")
        let base = Date(timeIntervalSinceReferenceDate: 2_000_000)
        let usage = [
            TypeUsage(typeID: x.id, usedAt: base),
            TypeUsage(typeID: y.id, usedAt: base.addingTimeInterval(60)),
        ]
        let ranked = FrecencyRanking.rank(types: [x, y], recentUsage: usage)
        XCTAssertEqual(ranked.map(\.id), [y.id, x.id])
    }

    func testRankingIsDeterministicAndStableForUnusedTypes() {
        let first = RankableType(id: UUID(), sortOrder: 0, label: "same")
        let second = RankableType(id: UUID(), sortOrder: 0, label: "SAME")
        let ranked = FrecencyRanking.rank(types: [second, first], recentUsage: [])
        // Equal count, no usage, equal sortOrder: case-insensitive label ties,
        // and identical lowercased labels keep a deterministic result.
        XCTAssertEqual(ranked.count, 2)
        XCTAssertEqual(Set(ranked.map(\.id)), [first.id, second.id])
    }

    func testRankingIgnoresUsageForUnknownTypes() {
        let a = RankableType(id: UUID(), sortOrder: 0, label: "Alpha")
        let ghost = UUID()
        let usage = [TypeUsage(typeID: ghost, usedAt: .now)]
        let ranked = FrecencyRanking.rank(types: [a], recentUsage: usage)
        XCTAssertEqual(ranked.map(\.id), [a.id])
    }

    // MARK: Capture

    func testRecordSnapshotsTypeCostDefault() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let type = try TaxonomyService.addInterventionType(
            label: "Renal dose adjustment",
            defaultCostAvoidanceCents: 5_000,
            in: context
        )
        let drugClass = try TaxonomyService.addDrugClass(label: "Antimicrobials", in: context)

        let intervention = try InterventionCaptureService.record(
            CaptureDraft(typeID: type.id, drugClassID: drugClass.id, acceptance: .pending),
            in: context
        )
        XCTAssertEqual(intervention.costAvoidanceCents, 5_000)
        XCTAssertEqual(intervention.acceptance, .pending)
        XCTAssertFalse(context.hasChanges)
    }

    func testRecordKeepsUnknownCostDistinctFromZero() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let unsetType = try TaxonomyService.addInterventionType(label: "Education", in: context)
        let zeroType = try TaxonomyService.addInterventionType(
            label: "Clarification",
            defaultCostAvoidanceCents: 0,
            in: context
        )
        let drugClass = try TaxonomyService.addDrugClass(label: "Analgesics", in: context)

        let unsetIntervention = try InterventionCaptureService.record(
            CaptureDraft(typeID: unsetType.id, drugClassID: drugClass.id, acceptance: .accepted),
            in: context
        )
        let zeroIntervention = try InterventionCaptureService.record(
            CaptureDraft(typeID: zeroType.id, drugClassID: drugClass.id, acceptance: .accepted),
            in: context
        )
        XCTAssertNil(unsetIntervention.costAvoidanceCents)
        XCTAssertEqual(zeroIntervention.costAvoidanceCents, 0)
    }

    func testRecordOverrideWinsOverTypeDefault() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let type = try TaxonomyService.addInterventionType(
            label: "Dose optimization",
            defaultCostAvoidanceCents: 5_000,
            in: context
        )
        let drugClass = try TaxonomyService.addDrugClass(label: "Cardiovascular agents", in: context)
        let intervention = try InterventionCaptureService.record(
            CaptureDraft(
                typeID: type.id,
                drugClassID: drugClass.id,
                acceptance: .accepted,
                costAvoidanceCentsOverride: 12_000
            ),
            in: context
        )
        XCTAssertEqual(intervention.costAvoidanceCents, 12_000)
    }

    func testRecordRejectsUnknownTypeAndNegativeMinutes() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let drugClass = try TaxonomyService.addDrugClass(label: "Anticoagulants", in: context)

        XCTAssertThrowsError(
            try InterventionCaptureService.record(
                CaptureDraft(typeID: UUID(), drugClassID: drugClass.id, acceptance: .pending),
                in: context
            )
        )

        let type = try TaxonomyService.addInterventionType(label: "Monitoring", in: context)
        XCTAssertThrowsError(
            try InterventionCaptureService.record(
                CaptureDraft(
                    typeID: type.id,
                    drugClassID: drugClass.id,
                    acceptance: .pending,
                    minutesSpent: -5
                ),
                in: context
            )
        ) { error in
            XCTAssertEqual(error as? InterventionCaptureError, .negativeMinutes(-5))
        }
        XCTAssertEqual(try InterventionLedgerService.recent(in: context).count, 0)
    }

    // MARK: Ranking through the store

    func testRankedActiveTypesReflectsRecentUse() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let seldom = try TaxonomyService.addInterventionType(label: "Seldom", in: context)
        let frequent = try TaxonomyService.addInterventionType(label: "Frequent", in: context)
        let drugClass = try TaxonomyService.addDrugClass(label: "Diabetes agents", in: context)

        let base = Date(timeIntervalSinceReferenceDate: 3_000_000)
        try InterventionCaptureService.record(
            CaptureDraft(typeID: seldom.id, drugClassID: drugClass.id, acceptance: .accepted),
            at: base,
            in: context
        )
        for offset in 1...3 {
            try InterventionCaptureService.record(
                CaptureDraft(typeID: frequent.id, drugClassID: drugClass.id, acceptance: .accepted),
                at: base.addingTimeInterval(Double(offset) * 60),
                in: context
            )
        }
        let ranked = try InterventionCaptureService.rankedActiveTypes(in: context)
        XCTAssertEqual(ranked.first?.id, frequent.id)
    }

    func testRankedActiveTypesExcludesInactive() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let active = try TaxonomyService.addInterventionType(label: "Active", in: context)
        let inactive = try TaxonomyService.addInterventionType(label: "Retired", in: context)
        try TaxonomyService.setInterventionTypeActive(false, on: inactive, in: context)

        let ranked = try InterventionCaptureService.rankedActiveTypes(in: context)
        XCTAssertEqual(ranked.map(\.id), [active.id])
    }

    // MARK: Ledger edit, acceptance flip, and delete

    func testLedgerAcceptanceFlipResolvesPending() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let type = try TaxonomyService.addInterventionType(label: "Renal dose adjustment", in: context)
        let drugClass = try TaxonomyService.addDrugClass(label: "Antimicrobials", in: context)
        let intervention = try InterventionCaptureService.record(
            CaptureDraft(typeID: type.id, drugClassID: drugClass.id, acceptance: .pending),
            in: context
        )

        try InterventionLedgerService.setAcceptance(
            .accepted,
            forInterventionID: intervention.id,
            in: context
        )
        let summaries = try InterventionLedgerService.recent(in: context)
        XCTAssertEqual(summaries.first?.acceptance, .accepted)
    }

    func testLedgerEditChangesStructuredFieldsOnly() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let type = try TaxonomyService.addInterventionType(label: "IV to PO conversion", in: context)
        let newType = try TaxonomyService.addInterventionType(label: "Dose optimization", in: context)
        let drugClass = try TaxonomyService.addDrugClass(label: "Antimicrobials", in: context)
        let line = try TaxonomyService.addServiceLine(label: "Critical care", in: context)
        let intervention = try InterventionCaptureService.record(
            CaptureDraft(typeID: type.id, drugClassID: drugClass.id, acceptance: .pending),
            in: context
        )

        try InterventionLedgerService.apply(
            InterventionEdit(
                typeID: newType.id,
                drugClassID: drugClass.id,
                serviceLineID: line.id,
                acceptance: .rejected,
                minutesSpent: 15,
                costAvoidanceCents: 2_500
            ),
            toInterventionID: intervention.id,
            in: context
        )
        let summary = try XCTUnwrap(try InterventionLedgerService.recent(in: context).first)
        XCTAssertEqual(summary.typeID, newType.id)
        XCTAssertEqual(summary.serviceLineID, line.id)
        XCTAssertEqual(summary.acceptance, .rejected)
        XCTAssertEqual(summary.minutesSpent, 15)
        XCTAssertEqual(summary.costAvoidanceCents, 2_500)
    }

    func testLedgerEditRejectsNegativeCost() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let type = try TaxonomyService.addInterventionType(label: "Monitoring", in: context)
        let drugClass = try TaxonomyService.addDrugClass(label: "Immunosuppressants", in: context)
        let intervention = try InterventionCaptureService.record(
            CaptureDraft(typeID: type.id, drugClassID: drugClass.id, acceptance: .pending),
            in: context
        )
        XCTAssertThrowsError(
            try InterventionLedgerService.apply(
                InterventionEdit(
                    typeID: type.id,
                    drugClassID: drugClass.id,
                    serviceLineID: nil,
                    acceptance: .pending,
                    minutesSpent: nil,
                    costAvoidanceCents: -100
                ),
                toInterventionID: intervention.id,
                in: context
            )
        ) { error in
            XCTAssertEqual(error as? InterventionLedgerError, .negativeCostAvoidanceCents(-100))
        }
    }

    func testLedgerDeleteRemovesInterventionAndUndoUsesSamePath() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let type = try TaxonomyService.addInterventionType(label: "Education", in: context)
        let drugClass = try TaxonomyService.addDrugClass(label: "Respiratory agents", in: context)
        let intervention = try InterventionCaptureService.record(
            CaptureDraft(typeID: type.id, drugClassID: drugClass.id, acceptance: .pending),
            in: context
        )
        XCTAssertEqual(try InterventionLedgerService.recent(in: context).count, 1)

        try InterventionLedgerService.deleteIntervention(id: intervention.id, in: context)
        XCTAssertEqual(try InterventionLedgerService.recent(in: context).count, 0)
        XCTAssertFalse(context.hasChanges)

        // Taxonomy rows survive the intervention delete (nullify rule).
        XCTAssertEqual(try TaxonomyService.allInterventionTypes(in: context).count, 1)
        XCTAssertEqual(try TaxonomyService.allDrugClasses(in: context).count, 1)
    }

    func testLedgerRecentIsNewestFirstAndBounded() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let type = try TaxonomyService.addInterventionType(label: "Monitoring", in: context)
        let drugClass = try TaxonomyService.addDrugClass(label: "Chemotherapy", in: context)
        let base = Date(timeIntervalSinceReferenceDate: 4_000_000)
        for offset in 0..<5 {
            try InterventionCaptureService.record(
                CaptureDraft(typeID: type.id, drugClassID: drugClass.id, acceptance: .pending),
                at: base.addingTimeInterval(Double(offset) * 60),
                in: context
            )
        }
        let recent = try InterventionLedgerService.recent(limit: 3, in: context)
        XCTAssertEqual(recent.count, 3)
        XCTAssertEqual(recent.map(\.timestamp), recent.map(\.timestamp).sorted(by: >))
    }

    // MARK: Backup parity after capture and ledger edits

    func testBackupRoundTripAfterCaptureAndEdits() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let type = try TaxonomyService.addInterventionType(
            label: "Renal dose adjustment",
            defaultCostAvoidanceCents: 5_000,
            in: context
        )
        let drugClass = try TaxonomyService.addDrugClass(label: "Antimicrobials", in: context)
        let line = try TaxonomyService.addServiceLine(label: "Critical care", in: context)

        let base = Date(timeIntervalSinceReferenceDate: 5_000_000)
        let first = try InterventionCaptureService.record(
            CaptureDraft(typeID: type.id, drugClassID: drugClass.id, acceptance: .pending),
            at: base,
            in: context
        )
        try InterventionCaptureService.record(
            CaptureDraft(
                typeID: type.id,
                drugClassID: drugClass.id,
                acceptance: .accepted,
                serviceLineID: line.id,
                minutesSpent: 10
            ),
            at: base.addingTimeInterval(60),
            in: context
        )
        try InterventionLedgerService.setAcceptance(.accepted, forInterventionID: first.id, in: context)

        let exportDate = Date(timeIntervalSinceReferenceDate: 6_000_000)
        let archive = try BackupService.makeArchive(from: context, createdAt: exportDate)
        let destination = try HippocratesStore.makeContainer(inMemory: true)
        try BackupService.restore(archive, into: destination.mainContext)
        let reexported = try BackupService.makeArchive(from: destination.mainContext, createdAt: exportDate)
        XCTAssertEqual(archive, reexported)
    }
}
