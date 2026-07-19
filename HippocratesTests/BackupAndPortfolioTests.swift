import Foundation
import SwiftData
import XCTest

@testable import Hippocrates

@MainActor
final class BackupAndPortfolioTests: XCTestCase {
    // MARK: Reminder policy

    func testReminderStaysQuietWithoutARecordedExport() {
        XCTAssertFalse(BackupReminderPolicy.shouldRemind(lastExportAt: nil, now: .now))
    }

    func testReminderTriggersAtNinetyDays() {
        let base = Date(timeIntervalSinceReferenceDate: 900_000_000)
        let eightyNineDays = base.addingTimeInterval(89.0 * 86_400.0)
        let ninetyDays = base.addingTimeInterval(90.0 * 86_400.0)
        XCTAssertFalse(BackupReminderPolicy.shouldRemind(lastExportAt: base, now: eightyNineDays))
        XCTAssertTrue(BackupReminderPolicy.shouldRemind(lastExportAt: base, now: ninetyDays))
    }

    // MARK: The I-011 export timestamp

    func testRecordBackupCreatedSetsAndPersistsLastExportAt() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext
        _ = try AppConfigService.fetchOrCreate(in: context)
        XCTAssertNil(try BackupExportService.lastExportAt(in: context))

        let stamp = Date(timeIntervalSinceReferenceDate: 910_000_000)
        try BackupExportService.recordBackupCreated(at: stamp, in: context)

        XCTAssertEqual(try BackupExportService.lastExportAt(in: context), stamp)
        XCTAssertFalse(context.hasChanges)

        // The timestamp is part of the backup itself and round-trips.
        let archive = try BackupService.makeArchive(from: context)
        let destination = try HippocratesStore.makeContainer(inMemory: true)
        try BackupService.restore(archive, into: destination.mainContext)
        XCTAssertEqual(
            try BackupExportService.lastExportAt(in: destination.mainContext),
            stamp
        )
    }

    func testBackupDataRoundTripsThroughCodec() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext
        _ = try AppConfigService.fetchOrCreate(in: context)
        try TaxonomyService.addInterventionType(label: "Renal dose adjustment", in: context)

        let data = try BackupExportService.makeBackupData(in: context)
        let decoded = try BackupCodec.decode(data)
        XCTAssertEqual(decoded.payload.interventionTypes.count, 1)
        XCTAssertNotNil(decoded.payload.appConfig)
    }

    // MARK: Portfolio formatting

    private func sampleQuestion(
        created: Date,
        answered: Bool
    ) -> PortfolioQuestion {
        PortfolioQuestion(
            createdAt: created,
            answeredAt: answered ? created.addingTimeInterval(3_600) : nil,
            questionText: "Is linezolid safe with sertraline?",
            background: "Adult inpatient on stable therapy.",
            requestorLabel: "Pharmacist",
            classLabel: "Interaction",
            urgencyLabel: "Routine",
            searchStrategy: "Reviewed tertiary references.",
            answerText: "Monitor for serotonin syndrome.",
            citations: [
                PortfolioCitation(
                    tierLabel: "Primary",
                    title: "Case series",
                    locator: "Journal 2024",
                    accessedDate: created,
                    urlText: nil
                )
            ],
            didFollowUp: true,
            verifiedOn: created.addingTimeInterval(3_600),
            reviewAfter: created.addingTimeInterval(7_200)
        )
    }

    func testPortfolioKeepsStandardResponseOrder() throws {
        let created = Date(timeIntervalSinceReferenceDate: 920_000_000)
        let document = DIPortfolio.document(questions: [sampleQuestion(created: created, answered: true)])

        let sections = [
            "Question:",
            "Background:",
            "Classification:",
            "Search strategy:",
            "Answer:",
            "References:",
            "Follow-up completed:",
            "Verified:",
            "Review after:",
        ]
        var previousIndex = document.startIndex
        for section in sections {
            let range = try XCTUnwrap(document.range(of: section), section)
            XCTAssertTrue(previousIndex <= range.lowerBound, section)
            previousIndex = range.lowerBound
        }
        XCTAssertTrue(document.contains("1. [Primary] Case series - Journal 2024"))
    }

    func testPortfolioMarksDraftsAndOmitsVerificationForThem() {
        let created = Date(timeIntervalSinceReferenceDate: 930_000_000)
        let document = DIPortfolio.document(questions: [sampleQuestion(created: created, answered: false)])
        XCTAssertTrue(document.contains("Status: Draft"))
        XCTAssertFalse(document.contains("Verified:"))
    }

    func testPortfolioIsDeterministicAcrossInputOrder() {
        let early = sampleQuestion(
            created: Date(timeIntervalSinceReferenceDate: 940_000_000),
            answered: true
        )
        let late = sampleQuestion(
            created: Date(timeIntervalSinceReferenceDate: 941_000_000),
            answered: false
        )
        let forward = DIPortfolio.document(questions: [early, late])
        let reversed = DIPortfolio.document(questions: [late, early])
        XCTAssertEqual(forward, reversed)
        let earlyRange = forward.range(of: "Status: Draft")
        XCTAssertNotNil(earlyRange)
    }

    func testPortfolioOfNothingIsEmpty() {
        XCTAssertEqual(DIPortfolio.document(questions: []), "")
    }
}
