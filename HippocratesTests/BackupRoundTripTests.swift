import Foundation
import SwiftData
import XCTest
@testable import Hippocrates

@MainActor
final class BackupRoundTripTests: XCTestCase {
    private let exportDate = Date(timeIntervalSinceReferenceDate: 800_000_000.125)

    func testCompleteStoreRoundTripsLosslessly() throws {
        let source = try HippocratesStore.makeContainer(inMemory: true)
        let fixture = try insertCompleteFixture(into: source.mainContext)

        let sourceArchive = try BackupService.makeArchive(
            from: source.mainContext,
            createdAt: exportDate
        )
        let encoded = try BackupCodec.encode(sourceArchive)
        let decoded = try BackupCodec.decode(encoded)
        XCTAssertEqual(decoded, sourceArchive)

        let destination = try HippocratesStore.makeContainer(inMemory: true)
        try BackupService.restore(decoded, into: destination.mainContext)
        let restoredArchive = try BackupService.makeArchive(
            from: destination.mainContext,
            createdAt: exportDate
        )

        XCTAssertEqual(restoredArchive, sourceArchive)

        let restoredQuestions = try destination.mainContext.fetch(FetchDescriptor<DIQuestion>())
        let restoredQuestion = try XCTUnwrap(restoredQuestions.first)
        XCTAssertEqual(restoredQuestion.citations.map(\.id), [fixture.citationID])
        XCTAssertEqual(restoredQuestion.linkedInterventions.map(\.id), [fixture.interventionID])
    }

    func testDanglingReferenceIsRejectedBeforeDestinationMutation() throws {
        let source = try HippocratesStore.makeContainer(inMemory: true)
        _ = try insertCompleteFixture(into: source.mainContext)
        var archive = try BackupService.makeArchive(from: source.mainContext, createdAt: exportDate)
        archive.payload.interventions[0].typeID = UUID()

        let destination = try HippocratesStore.makeContainer(inMemory: true)
        XCTAssertThrowsError(try BackupService.restore(archive, into: destination.mainContext)) { error in
            guard case BackupError.danglingReference = error else {
                return XCTFail("Expected a dangling-reference error, got \(error)")
            }
        }
        XCTAssertEqual(try destination.mainContext.fetchCount(FetchDescriptor<Intervention>()), 0)
        XCTAssertEqual(try destination.mainContext.fetchCount(FetchDescriptor<InterventionType>()), 0)
    }

    func testUnknownBackupVersionIsRejected() throws {
        let emptyPayload = BackupArchive.Payload(
            interventionTypes: [],
            drugClasses: [],
            serviceLines: [],
            interventions: [],
            questions: [],
            citations: [],
            appConfig: nil
        )
        let archive = BackupArchive(formatVersion: 999, createdAt: exportDate, payload: emptyPayload)
        let destination = try HippocratesStore.makeContainer(inMemory: true)

        XCTAssertThrowsError(try BackupService.restore(archive, into: destination.mainContext)) { error in
            XCTAssertEqual(error as? BackupError, .unsupportedFormatVersion(999))
        }
    }

    func testRestoreRefusesToMergeIntoNonemptyStore() throws {
        let source = try HippocratesStore.makeContainer(inMemory: true)
        _ = try insertCompleteFixture(into: source.mainContext)
        let archive = try BackupService.makeArchive(from: source.mainContext, createdAt: exportDate)

        let destination = try HippocratesStore.makeContainer(inMemory: true)
        destination.mainContext.insert(DrugClass(label: "Existing configuration"))
        try destination.mainContext.save()

        XCTAssertThrowsError(try BackupService.restore(archive, into: destination.mainContext)) { error in
            XCTAssertEqual(error as? BackupError, .destinationNotEmpty)
        }
        XCTAssertEqual(try destination.mainContext.fetchCount(FetchDescriptor<DrugClass>()), 1)
        XCTAssertEqual(try destination.mainContext.fetchCount(FetchDescriptor<Intervention>()), 0)
    }

    func testRestoreRefusesContextWithPendingInsertWithoutDiscardingIt() throws {
        let source = try HippocratesStore.makeContainer(inMemory: true)
        _ = try insertCompleteFixture(into: source.mainContext)
        let archive = try BackupService.makeArchive(from: source.mainContext, createdAt: exportDate)

        let destination = try HippocratesStore.makeContainer(inMemory: true)
        destination.mainContext.insert(DrugClass(label: "Unsaved configuration"))
        XCTAssertTrue(destination.mainContext.hasChanges)

        XCTAssertThrowsError(try BackupService.restore(archive, into: destination.mainContext)) { error in
            XCTAssertEqual(error as? BackupError, .destinationHasPendingChanges)
        }

        // Restore must neither save nor roll back work owned by another screen.
        XCTAssertTrue(destination.mainContext.hasChanges)
    }

    func testRestoreRefusesContextWithPendingDeleteWithoutDiscardingIt() throws {
        let source = try HippocratesStore.makeContainer(inMemory: true)
        _ = try insertCompleteFixture(into: source.mainContext)
        let archive = try BackupService.makeArchive(from: source.mainContext, createdAt: exportDate)

        let destination = try HippocratesStore.makeContainer(inMemory: true)
        let existing = DrugClass(label: "Saved configuration")
        destination.mainContext.insert(existing)
        try destination.mainContext.save()
        destination.mainContext.delete(existing)
        XCTAssertTrue(destination.mainContext.hasChanges)

        XCTAssertThrowsError(try BackupService.restore(archive, into: destination.mainContext)) { error in
            XCTAssertEqual(error as? BackupError, .destinationHasPendingChanges)
        }

        XCTAssertTrue(destination.mainContext.hasChanges)
    }

    func testVerificationHistoryMustEndAtCurrentVerificationDate() throws {
        let verifiedOn = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let invalidQuestion = BackupArchive.DIQuestionRecord(
            id: UUID(),
            createdAt: verifiedOn,
            answeredAt: nil,
            questionText: "Question",
            background: "Background",
            answerText: "Answer",
            searchStrategy: "Search",
            requestorRole: .pharmacist,
            questionClass: .other,
            urgency: .routine,
            verifiedOn: verifiedOn,
            reviewAfter: verifiedOn.addingTimeInterval(86_400),
            didFollowUp: false,
            tags: [],
            verificationHistory: []
        )
        let archive = BackupArchive(
            createdAt: exportDate,
            payload: .init(
                interventionTypes: [],
                drugClasses: [],
                serviceLines: [],
                interventions: [],
                questions: [invalidQuestion],
                citations: [],
                appConfig: nil
            )
        )

        XCTAssertThrowsError(try BackupService.validate(archive)) { error in
            XCTAssertEqual(
                error as? BackupError,
                .verificationHistoryDoesNotEndAtVerifiedOn(questionID: invalidQuestion.id)
            )
        }
    }

    func testReviewDateCannotPrecedeVerificationDate() throws {
        let verifiedOn = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let invalidQuestion = BackupArchive.DIQuestionRecord(
            id: UUID(),
            createdAt: verifiedOn,
            answeredAt: nil,
            questionText: "Question",
            background: "Background",
            answerText: "Answer",
            searchStrategy: "Search",
            requestorRole: .pharmacist,
            questionClass: .other,
            urgency: .routine,
            verifiedOn: verifiedOn,
            reviewAfter: verifiedOn.addingTimeInterval(-1),
            didFollowUp: false,
            tags: [],
            verificationHistory: [verifiedOn]
        )
        let archive = BackupArchive(
            createdAt: exportDate,
            payload: .init(
                interventionTypes: [],
                drugClasses: [],
                serviceLines: [],
                interventions: [],
                questions: [invalidQuestion],
                citations: [],
                appConfig: nil
            )
        )

        XCTAssertThrowsError(try BackupService.validate(archive)) { error in
            XCTAssertEqual(
                error as? BackupError,
                .reviewDatePrecedesVerification(questionID: invalidQuestion.id)
            )
        }
    }

    private func insertCompleteFixture(
        into context: ModelContext
    ) throws -> (citationID: UUID, interventionID: UUID) {
        let typeID = try XCTUnwrap(UUID(uuidString: "10000000-0000-0000-0000-000000000001"))
        let drugClassID = try XCTUnwrap(UUID(uuidString: "20000000-0000-0000-0000-000000000002"))
        let serviceLineID = try XCTUnwrap(UUID(uuidString: "30000000-0000-0000-0000-000000000003"))
        let questionID = try XCTUnwrap(UUID(uuidString: "40000000-0000-0000-0000-000000000004"))
        let citationID = try XCTUnwrap(UUID(uuidString: "50000000-0000-0000-0000-000000000005"))
        let interventionID = try XCTUnwrap(UUID(uuidString: "60000000-0000-0000-0000-000000000006"))

        let verifiedOn = Date(timeIntervalSinceReferenceDate: 750_000_000.75)
        let reviewAfter = Date(timeIntervalSinceReferenceDate: 781_536_000.75)

        let type = InterventionType(
            id: typeID,
            label: "Documented intervention",
            defaultCostAvoidanceCents: 12_500,
            sortOrder: 1
        )
        let drugClass = DrugClass(id: drugClassID, label: "Configured class", sortOrder: 2)
        let serviceLine = ServiceLine(id: serviceLineID, label: "Configured service", sortOrder: 3)
        let question = DIQuestion(
            id: questionID,
            createdAt: verifiedOn.addingTimeInterval(-3_600),
            answeredAt: verifiedOn,
            questionText: "What information was requested?",
            background: "De-identified professional context.",
            answerText: "The pharmacist's completed response.",
            searchStrategy: "Sources reviewed in sequence.",
            requestorRole: .resident,
            questionClass: .availability,
            urgency: .sameDay,
            verifiedOn: verifiedOn,
            reviewAfter: reviewAfter,
            didFollowUp: true,
            tags: ["portfolio", "teaching"],
            verificationHistory: [verifiedOn]
        )
        let citation = Citation(
            id: citationID,
            question: question,
            tier: .primary,
            title: "Published source",
            locator: "Table 2",
            accessedDate: verifiedOn,
            urlString: "https://example.org/source"
        )
        let intervention = Intervention(
            id: interventionID,
            timestamp: verifiedOn.addingTimeInterval(1_800),
            type: type,
            drugClass: drugClass,
            serviceLine: serviceLine,
            acceptance: .accepted,
            costAvoidanceCents: 12_500,
            minutesSpent: 7,
            diQuestion: question
        )
        let config = AppConfig(
            costAvoidanceValues: [typeID.uuidString: 12_500],
            stalenessIntervalMonths: 12,
            lastExportAt: exportDate
        )

        context.insert(type)
        context.insert(drugClass)
        context.insert(serviceLine)
        context.insert(question)
        context.insert(citation)
        context.insert(intervention)
        context.insert(config)
        try context.save()

        return (citationID, interventionID)
    }
}
