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

    func testReviewDateMustFollowVerificationDate() throws {
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
            reviewAfter: verifiedOn,
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
                .reviewDateMustFollowVerification(questionID: invalidQuestion.id)
            )
        }
    }

    func testUnsetAndExplicitZeroCostsRoundTripDistinctly() throws {
        let typeID = try XCTUnwrap(
            UUID(uuidString: "10000000-0000-0000-0000-000000000010")
        )
        let unsetID = try XCTUnwrap(
            UUID(uuidString: "60000000-0000-0000-0000-000000000060")
        )
        let zeroID = try XCTUnwrap(
            UUID(uuidString: "60000000-0000-0000-0000-000000000061")
        )
        let source = try HippocratesStore.makeContainer(inMemory: true)
        let type = InterventionType(
            id: typeID,
            label: "Configured type",
            defaultCostAvoidanceCents: 5_000
        )
        let unset = Intervention(
            id: unsetID,
            type: type,
            acceptance: .accepted
        )
        let explicitZero = Intervention(
            id: zeroID,
            type: type,
            acceptance: .accepted,
            costAvoidanceCents: 0
        )
        source.mainContext.insert(type)
        source.mainContext.insert(unset)
        source.mainContext.insert(explicitZero)
        try source.mainContext.save()

        let archive = try BackupService.makeArchive(
            from: source.mainContext,
            createdAt: exportDate
        )
        let records = Dictionary(
            uniqueKeysWithValues: archive.payload.interventions.map {
                ($0.id, $0)
            }
        )
        let unsetRecord = try XCTUnwrap(records[unsetID])
        let zeroRecord = try XCTUnwrap(records[zeroID])
        XCTAssertEqual(records.count, 2)
        XCTAssertNil(unsetRecord.costAvoidanceCents)
        XCTAssertEqual(zeroRecord.costAvoidanceCents, 0)

        let destination = try HippocratesStore.makeContainer(inMemory: true)
        try BackupService.restore(archive, into: destination.mainContext)
        let restored = try BackupService.makeArchive(
            from: destination.mainContext,
            createdAt: exportDate
        )
        XCTAssertEqual(restored, archive)
    }

    func testLegacyV1BackupMigratesInValueSpace() throws {
        let data = Data(
            #"""
            {
              "createdAt": 0,
              "formatVersion": 1,
              "payload": {
                "appConfig": {
                  "costAvoidanceValues": {
                    "10000000-0000-0000-0000-000000000001": 12500
                  },
                  "lastExportAt": null,
                  "stalenessIntervalMonths": 12
                },
                "citations": [],
                "drugClasses": [],
                "interventionTypes": [
                  {
                    "defaultCostAvoidanceCents": null,
                    "id": "10000000-0000-0000-0000-000000000001",
                    "isActive": true,
                    "label": "Legacy type",
                    "sortOrder": 0
                  }
                ],
                "interventions": [
                  {
                    "acceptance": "accepted",
                    "costAvoidanceCents": 0,
                    "diQuestionID": null,
                    "drugClassID": null,
                    "id": "60000000-0000-0000-0000-000000000006",
                    "minutesSpent": null,
                    "serviceLineID": null,
                    "timestamp": 0,
                    "typeID": "10000000-0000-0000-0000-000000000001"
                  }
                ],
                "questions": [],
                "serviceLines": []
              }
            }
            """#.utf8
        )

        let migrated = try BackupCodec.decode(data)
        XCTAssertEqual(migrated.formatVersion, BackupArchive.currentFormatVersion)
        XCTAssertEqual(
            migrated.payload.interventionTypes.first?.defaultCostAvoidanceCents,
            12_500
        )
        XCTAssertEqual(migrated.payload.interventions.first?.costAvoidanceCents, 0)
        XCTAssertEqual(migrated.payload.appConfig?.stalenessIntervalMonths, 12)
        XCTAssertNoThrow(try BackupService.validate(migrated))

        let reencoded = try BackupCodec.encode(migrated)
        XCTAssertEqual(try BackupCodec.decode(reencoded), migrated)
    }

    func testLegacyV1CostMapRejectsInvalidKeyAndConflict() throws {
        let typeID = try XCTUnwrap(
            UUID(uuidString: "10000000-0000-0000-0000-000000000001")
        )

        let invalidKey = makeLegacyV1CostMapArchive(
            typeID: typeID,
            typeDefault: nil,
            costMapKey: "not-a-uuid",
            costMapValue: 100
        )
        XCTAssertThrowsError(try BackupCodec.decode(invalidKey)) { error in
            XCTAssertEqual(
                error as? BackupError,
                .invalidCostAvoidanceKey("not-a-uuid")
            )
        }

        let conflict = makeLegacyV1CostMapArchive(
            typeID: typeID,
            typeDefault: 100,
            costMapKey: typeID.uuidString,
            costMapValue: 200
        )
        XCTAssertThrowsError(try BackupCodec.decode(conflict)) { error in
            XCTAssertEqual(
                error as? BackupError,
                .conflictingLegacyCostAvoidanceValue(
                    typeID: typeID,
                    typeValue: 100,
                    configValue: 200
                )
            )
        }
    }

    func testUnknownEncodedVersionFailsBeforePayloadDecoding() {
        let data = Data(#"{"formatVersion":999}"#.utf8)
        XCTAssertThrowsError(try BackupCodec.decode(data)) { error in
            XCTAssertEqual(error as? BackupError, .unsupportedFormatVersion(999))
        }
    }

    func testVerificationHistoryMustBeStrictlyChronological() {
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
            verificationHistory: [
                verifiedOn,
                verifiedOn.addingTimeInterval(-1),
                verifiedOn
            ]
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
                .verificationHistoryNotChronological(questionID: invalidQuestion.id)
            )
        }
    }

    func testNegativeCostAndNonpositiveStalenessAreRejected() {
        let typeID = UUID()
        var archive = BackupArchive(
            createdAt: exportDate,
            payload: .init(
                interventionTypes: [
                    .init(
                        id: typeID,
                        label: "Configured type",
                        defaultCostAvoidanceCents: -1,
                        isActive: true,
                        sortOrder: 0
                    )
                ],
                drugClasses: [],
                serviceLines: [],
                interventions: [],
                questions: [],
                citations: [],
                appConfig: nil
            )
        )

        XCTAssertThrowsError(try BackupService.validate(archive)) { error in
            XCTAssertEqual(
                error as? BackupError,
                .invalidCostAvoidanceValue(
                    entity: "InterventionType",
                    id: typeID,
                    value: -1
                )
            )
        }

        archive.payload.interventionTypes[0].defaultCostAvoidanceCents = nil
        archive.payload.appConfig = .init(
            stalenessIntervalMonths: 0,
            lastExportAt: nil
        )
        XCTAssertThrowsError(try BackupService.validate(archive)) { error in
            XCTAssertEqual(
                error as? BackupError,
                .invalidStalenessIntervalMonths(0)
            )
        }
    }

    private func makeLegacyV1CostMapArchive(
        typeID: UUID,
        typeDefault: Int?,
        costMapKey: String,
        costMapValue: Int
    ) -> Data {
        let typeDefaultJSON = typeDefault.map { String($0) } ?? "null"
        return Data(
            """
            {
              "createdAt": 0,
              "formatVersion": 1,
              "payload": {
                "appConfig": {
                  "costAvoidanceValues": {
                    "\(costMapKey)": \(costMapValue)
                  },
                  "lastExportAt": null,
                  "stalenessIntervalMonths": 12
                },
                "citations": [],
                "drugClasses": [],
                "interventionTypes": [
                  {
                    "defaultCostAvoidanceCents": \(typeDefaultJSON),
                    "id": "\(typeID.uuidString)",
                    "isActive": true,
                    "label": "Legacy type",
                    "sortOrder": 0
                  }
                ],
                "interventions": [],
                "questions": [],
                "serviceLines": []
              }
            }
            """.utf8
        )
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
            urlString: "https://example.invalid/source"
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
        _ = try AppConfigService.insertForRestore(
            stalenessIntervalMonths: 12,
            lastExportAt: exportDate,
            into: context
        )

        context.insert(type)
        context.insert(drugClass)
        context.insert(serviceLine)
        context.insert(question)
        context.insert(citation)
        context.insert(intervention)
        try context.save()

        return (citationID, interventionID)
    }
}
