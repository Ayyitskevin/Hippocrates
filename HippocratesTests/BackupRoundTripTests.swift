import Foundation
import SwiftData
import XCTest
@testable import Hippocrates

@MainActor
final class BackupRoundTripTests: XCTestCase {
    private let exportDate = Date(timeIntervalSinceReferenceDate: 800_000_000.125)

    private enum BackupRepresentationV2: Equatable {
        case record(String)
        case foreignUUID(String)
        case inverse(model: String, field: String)
        case reconstructedConstant(String)

        var recordField: String? {
            switch self {
            case let .record(field), let .foreignUUID(field):
                field
            case .inverse, .reconstructedConstant:
                nil
            }
        }

        var foreignUUIDField: String? {
            guard case let .foreignUUID(field) = self else { return nil }
            return field
        }

        var inverseReference: String? {
            guard case let .inverse(model, field) = self else { return nil }
            return model + "." + field
        }

        var reconstructedValue: String? {
            guard case let .reconstructedConstant(value) = self else { return nil }
            return value
        }
    }

    private struct CompleteFixture {
        var expectedArchive: BackupArchive
        var citationID: UUID
        var interventionID: UUID
    }

    private enum DanglingReferenceCase: CaseIterable {
        case interventionType
        case interventionDrugClass
        case interventionServiceLine
        case interventionQuestion
        case citationQuestion
    }

    private enum DuplicateIdentifierCase: CaseIterable {
        case interventionType
        case drugClass
        case serviceLine
        case intervention
        case question
        case citation
    }

    private enum NonemptyDestinationCase: CaseIterable {
        case interventionType
        case drugClass
        case serviceLine
        case intervention
        case question
        case citation
        case appConfig
    }

    private enum InvalidRestoreArchiveCase: CaseIterable {
        case negativeInterventionCost
        case negativeStalenessInterval
        case verificationHistoryWrongEnd
        case verificationHistoryEqualDates
        case reviewDateEqualsVerification
        case unsupportedFormatVersion
    }

    private var backupCoverageV2: [String: [String: BackupRepresentationV2]] {
        [
            "InterventionType": [
                "id": .record("id"),
                "label": .record("label"),
                "defaultCostAvoidanceCents": .record("defaultCostAvoidanceCents"),
                "isActive": .record("isActive"),
                "sortOrder": .record("sortOrder")
            ],
            "DrugClass": [
                "id": .record("id"),
                "label": .record("label"),
                "isActive": .record("isActive"),
                "sortOrder": .record("sortOrder")
            ],
            "ServiceLine": [
                "id": .record("id"),
                "label": .record("label"),
                "isActive": .record("isActive"),
                "sortOrder": .record("sortOrder")
            ],
            "Intervention": [
                "id": .record("id"),
                "timestamp": .record("timestamp"),
                "type": .foreignUUID("typeID"),
                "drugClass": .foreignUUID("drugClassID"),
                "serviceLine": .foreignUUID("serviceLineID"),
                "acceptance": .record("acceptance"),
                "costAvoidanceCents": .record("costAvoidanceCents"),
                "minutesSpent": .record("minutesSpent"),
                "diQuestion": .foreignUUID("diQuestionID")
            ],
            "DIQuestion": [
                "id": .record("id"),
                "createdAt": .record("createdAt"),
                "answeredAt": .record("answeredAt"),
                "questionText": .record("questionText"),
                "background": .record("background"),
                "answerText": .record("answerText"),
                "searchStrategy": .record("searchStrategy"),
                "requestorRole": .record("requestorRole"),
                "questionClass": .record("questionClass"),
                "urgency": .record("urgency"),
                "verifiedOn": .record("verifiedOn"),
                "reviewAfter": .record("reviewAfter"),
                "didFollowUp": .record("didFollowUp"),
                "tags": .record("tags"),
                "verificationHistory": .record("verificationHistory"),
                "citations": .inverse(model: "Citation", field: "questionID"),
                "linkedInterventions": .inverse(model: "Intervention", field: "diQuestionID")
            ],
            "Citation": [
                "id": .record("id"),
                "question": .foreignUUID("questionID"),
                "tier": .record("tier"),
                "title": .record("title"),
                "locator": .record("locator"),
                "accessedDate": .record("accessedDate"),
                "urlString": .record("urlString")
            ],
            "AppConfig": [
                "singletonKey": .reconstructedConstant("app"),
                "stalenessIntervalMonths": .record("stalenessIntervalMonths"),
                "lastExportAt": .record("lastExportAt")
            ]
        ]
    }

    private var backupRecordFieldsV2: [String: Set<String>] {
        [
            "InterventionType": ["id", "label", "defaultCostAvoidanceCents", "isActive", "sortOrder"],
            "DrugClass": ["id", "label", "isActive", "sortOrder"],
            "ServiceLine": ["id", "label", "isActive", "sortOrder"],
            "Intervention": [
                "id", "timestamp", "typeID", "drugClassID", "serviceLineID", "acceptance",
                "costAvoidanceCents", "minutesSpent", "diQuestionID"
            ],
            "DIQuestion": [
                "id", "createdAt", "answeredAt", "questionText", "background", "answerText",
                "searchStrategy", "requestorRole", "questionClass", "urgency", "verifiedOn",
                "reviewAfter", "didFollowUp", "tags", "verificationHistory"
            ],
            "Citation": ["id", "questionID", "tier", "title", "locator", "accessedDate", "urlString"],
            "AppConfig": ["stalenessIntervalMonths", "lastExportAt"]
        ]
    }

    func testBackupCoverageExactlyMatchesSchemaV1() throws {
        let schema = Schema(versionedSchema: SchemaV1.self)
        var entitiesByModelName: [String: Schema.Entity] = [:]
        for entity in schema.entities {
            // Versioned-schema model names may carry nesting or module qualifiers.
            // The reviewed backup contract owns the unique leaf names.
            let matchingModelNames = backupCoverageV2.keys.filter { modelName in
                entity.name == modelName || entity.name.hasSuffix("." + modelName)
            }
            XCTAssertEqual(matchingModelNames.count, 1)
            let modelName = try XCTUnwrap(matchingModelNames.first)
            XCTAssertNil(entitiesByModelName.updateValue(entity, forKey: modelName))
        }

        let actualPersistedFields = try Dictionary(
            uniqueKeysWithValues: backupCoverageV2.keys.map { modelName in
                (
                    modelName,
                    persistedFields(in: try XCTUnwrap(entitiesByModelName[modelName]))
                )
            }
        )
        let coveredPersistedFields = backupCoverageV2.mapValues { Set($0.keys) }

        XCTAssertEqual(Set(entitiesByModelName.keys), Set(backupCoverageV2.keys))
        XCTAssertEqual(actualPersistedFields, coveredPersistedFields)

        let representedRecordFields = backupCoverageV2.mapValues { coverage in
            Set(coverage.values.compactMap(\.recordField))
        }
        XCTAssertEqual(representedRecordFields, backupRecordFieldsV2)

        let availableForeignUUIDReferences = Set(
            backupCoverageV2.flatMap { model, coverage in
                coverage.values.compactMap(\.foreignUUIDField).map { model + "." + $0 }
            }
        )
        let inverseReferences = Set(
            backupCoverageV2.values.flatMap { coverage in
                coverage.values.compactMap(\.inverseReference)
            }
        )
        XCTAssertTrue(inverseReferences.isSubset(of: availableForeignUUIDReferences))

        let reconstructedConstants = Dictionary(
            uniqueKeysWithValues: backupCoverageV2.flatMap { model, coverage in
                coverage.compactMap { field, representation in
                    representation.reconstructedValue.map { (model + "." + field, $0) }
                }
            }
        )
        XCTAssertEqual(reconstructedConstants, ["AppConfig.singletonKey": "app"])
    }

    func testCompleteStoreRoundTripsLosslessly() throws {
        let source = try HippocratesStore.makeContainer(inMemory: true)
        let fixture = try insertCompleteFixture(into: source.mainContext)

        let sourceArchive = try BackupService.makeArchive(
            from: source.mainContext,
            createdAt: exportDate
        )
        XCTAssertEqual(sourceArchive.formatVersion, BackupArchive.currentFormatVersion)
        XCTAssertEqual(sourceArchive.createdAt, exportDate)
        XCTAssertEqual(sourceArchive, fixture.expectedArchive)
        let encoded = try BackupCodec.encode(sourceArchive)
        let decoded = try BackupCodec.decode(encoded)
        XCTAssertEqual(decoded, fixture.expectedArchive)

        let destination = try HippocratesStore.makeContainer(inMemory: true)
        try BackupService.restore(decoded, into: destination.mainContext)
        XCTAssertFalse(destination.mainContext.hasChanges)
        let restoredArchive = try BackupService.makeArchive(
            from: destination.mainContext,
            createdAt: exportDate
        )

        XCTAssertEqual(restoredArchive, fixture.expectedArchive)
        try assertCompleteFixture(fixture, in: destination.mainContext)

        let restoredQuestions = try destination.mainContext.fetch(FetchDescriptor<DIQuestion>())
        let restoredQuestion = try XCTUnwrap(restoredQuestions.first)
        XCTAssertEqual(restoredQuestion.citations.map(\.id), [fixture.citationID])
        XCTAssertEqual(restoredQuestion.linkedInterventions.map(\.id), [fixture.interventionID])
    }

    func testDanglingReferenceIsRejectedBeforeDestinationMutation() throws {
        let source = try HippocratesStore.makeContainer(inMemory: true)
        let fixture = try insertCompleteFixture(into: source.mainContext)
        let missingID = try XCTUnwrap(
            UUID(uuidString: "70000000-0000-0000-0000-000000000007")
        )

        for referenceCase in DanglingReferenceCase.allCases {
            var archive = fixture.expectedArchive
            let expectedError: BackupError

            switch referenceCase {
            case .interventionType:
                archive.payload.interventions[0].typeID = missingID
                expectedError = .danglingReference(
                    entity: "Intervention",
                    id: fixture.interventionID,
                    field: "typeID",
                    referencedID: missingID
                )
            case .interventionDrugClass:
                archive.payload.interventions[0].drugClassID = missingID
                expectedError = .danglingReference(
                    entity: "Intervention",
                    id: fixture.interventionID,
                    field: "drugClassID",
                    referencedID: missingID
                )
            case .interventionServiceLine:
                archive.payload.interventions[0].serviceLineID = missingID
                expectedError = .danglingReference(
                    entity: "Intervention",
                    id: fixture.interventionID,
                    field: "serviceLineID",
                    referencedID: missingID
                )
            case .interventionQuestion:
                archive.payload.interventions[0].diQuestionID = missingID
                expectedError = .danglingReference(
                    entity: "Intervention",
                    id: fixture.interventionID,
                    field: "diQuestionID",
                    referencedID: missingID
                )
            case .citationQuestion:
                archive.payload.citations[0].questionID = missingID
                expectedError = .danglingReference(
                    entity: "Citation",
                    id: fixture.citationID,
                    field: "questionID",
                    referencedID: missingID
                )
            }

            let destination = try HippocratesStore.makeContainer(inMemory: true)
            XCTAssertThrowsError(
                try BackupService.restore(archive, into: destination.mainContext)
            ) { error in
                XCTAssertEqual(error as? BackupError, expectedError)
            }
            try assertEmptyBackupDestination(destination.mainContext)
        }
    }

    func testDuplicateIdentifiersAreRejectedBeforeDestinationMutation() throws {
        let source = try HippocratesStore.makeContainer(inMemory: true)
        let fixture = try insertCompleteFixture(into: source.mainContext)

        for duplicateCase in DuplicateIdentifierCase.allCases {
            var archive = fixture.expectedArchive
            let duplicateID: UUID
            let entity: String

            switch duplicateCase {
            case .interventionType:
                let duplicate = archive.payload.interventionTypes[0]
                duplicateID = duplicate.id
                entity = "InterventionType"
                archive.payload.interventionTypes.append(duplicate)
            case .drugClass:
                let duplicate = archive.payload.drugClasses[0]
                duplicateID = duplicate.id
                entity = "DrugClass"
                archive.payload.drugClasses.append(duplicate)
            case .serviceLine:
                let duplicate = archive.payload.serviceLines[0]
                duplicateID = duplicate.id
                entity = "ServiceLine"
                archive.payload.serviceLines.append(duplicate)
            case .intervention:
                let duplicate = archive.payload.interventions[0]
                duplicateID = duplicate.id
                entity = "Intervention"
                archive.payload.interventions.append(duplicate)
            case .question:
                let duplicate = archive.payload.questions[0]
                duplicateID = duplicate.id
                entity = "DIQuestion"
                archive.payload.questions.append(duplicate)
            case .citation:
                let duplicate = archive.payload.citations[0]
                duplicateID = duplicate.id
                entity = "Citation"
                archive.payload.citations.append(duplicate)
            }

            let destination = try HippocratesStore.makeContainer(inMemory: true)
            XCTAssertThrowsError(
                try BackupService.restore(archive, into: destination.mainContext)
            ) { error in
                XCTAssertEqual(
                    error as? BackupError,
                    .duplicateIdentifier(entity: entity, id: duplicateID)
                )
            }
            try assertEmptyBackupDestination(destination.mainContext)
        }
    }

    func testInvalidArchivesAreRejectedBeforeDestinationMutation() throws {
        let source = try HippocratesStore.makeContainer(inMemory: true)
        let fixture = try insertCompleteFixture(into: source.mainContext)

        for invalidCase in InvalidRestoreArchiveCase.allCases {
            var archive = fixture.expectedArchive
            let expectedError: BackupError

            switch invalidCase {
            case .negativeInterventionCost:
                var intervention = try XCTUnwrap(archive.payload.interventions.first)
                intervention.costAvoidanceCents = -1
                archive.payload.interventions[0] = intervention
                expectedError = .invalidCostAvoidanceValue(
                    entity: "Intervention",
                    id: intervention.id,
                    value: -1
                )

            case .negativeStalenessInterval:
                var configuration = try XCTUnwrap(archive.payload.appConfig)
                configuration.stalenessIntervalMonths = -1
                archive.payload.appConfig = configuration
                expectedError = .invalidStalenessIntervalMonths(-1)

            case .verificationHistoryWrongEnd:
                var question = try XCTUnwrap(archive.payload.questions.first)
                question.verificationHistory = [
                    question.verifiedOn.addingTimeInterval(-1)
                ]
                archive.payload.questions[0] = question
                expectedError = .verificationHistoryDoesNotEndAtVerifiedOn(
                    questionID: question.id
                )

            case .verificationHistoryEqualDates:
                var question = try XCTUnwrap(archive.payload.questions.first)
                let previousVerification = question.verifiedOn.addingTimeInterval(-1)
                question.verificationHistory = [
                    previousVerification,
                    previousVerification,
                    question.verifiedOn
                ]
                archive.payload.questions[0] = question
                expectedError = .verificationHistoryNotChronological(
                    questionID: question.id
                )

            case .reviewDateEqualsVerification:
                var question = try XCTUnwrap(archive.payload.questions.first)
                question.reviewAfter = question.verifiedOn
                archive.payload.questions[0] = question
                expectedError = .reviewDateMustFollowVerification(
                    questionID: question.id
                )

            case .unsupportedFormatVersion:
                archive.formatVersion = 999
                expectedError = .unsupportedFormatVersion(999)
            }

            let destination = try HippocratesStore.makeContainer(inMemory: true)
            let context = destination.mainContext
            try assertEmptyBackupDestination(context)

            XCTAssertThrowsError(
                try BackupService.restore(archive, into: context)
            ) { error in
                XCTAssertEqual(
                    error as? BackupError,
                    expectedError
                )
            }

            try assertEmptyBackupDestination(context)
        }
    }

    func testNegativeMinutesSpentIsRejectedAtExportAndRestoreBoundaries() throws {
        let source = try HippocratesStore.makeContainer(inMemory: true)
        let fixture = try insertCompleteFixture(into: source.mainContext)
        let sourceContext = source.mainContext
        let sourceIntervention = try XCTUnwrap(
            sourceContext.fetch(FetchDescriptor<Intervention>()).first
        )
        sourceIntervention.minutesSpent = -1
        try sourceContext.save()
        XCTAssertFalse(sourceContext.hasChanges)

        XCTAssertThrowsError(
            try BackupService.makeArchive(
                from: sourceContext,
                createdAt: exportDate
            )
        ) { error in
            XCTAssertEqual(
                error as? BackupError,
                .invalidMinutesSpentValue(
                    interventionID: sourceIntervention.id,
                    value: -1
                )
            )
        }
        XCTAssertFalse(sourceContext.hasChanges)
        XCTAssertEqual(sourceIntervention.minutesSpent, -1)

        var invalidArchive = fixture.expectedArchive
        let interventionID = try XCTUnwrap(
            invalidArchive.payload.interventions.first?.id
        )
        invalidArchive.payload.interventions[0].minutesSpent = -1
        let destination = try HippocratesStore.makeContainer(inMemory: true)
        let destinationContext = destination.mainContext
        try assertEmptyBackupDestination(destinationContext)

        XCTAssertThrowsError(
            try BackupService.restore(invalidArchive, into: destinationContext)
        ) { error in
            XCTAssertEqual(
                error as? BackupError,
                .invalidMinutesSpentValue(
                    interventionID: interventionID,
                    value: -1
                )
            )
        }
        try assertEmptyBackupDestination(destinationContext)

        let validMinutesSpent: [Int?] = [nil, 0, 1]
        for minutesSpent in validMinutesSpent {
            var validArchive = fixture.expectedArchive
            validArchive.payload.interventions[0].minutesSpent = minutesSpent
            XCTAssertNoThrow(try BackupService.validate(validArchive))
        }
    }

    func testRestoreRefusesEveryNonemptyDestinationWithoutMutation() throws {
        let source = try HippocratesStore.makeContainer(inMemory: true)
        let archive = try insertCompleteFixture(into: source.mainContext).expectedArchive

        for destinationCase in NonemptyDestinationCase.allCases {
            let destination = try HippocratesStore.makeContainer(inMemory: true)
            let context = destination.mainContext
            try insertExistingDestination(destinationCase, into: context)
            try context.save()
            XCTAssertFalse(context.hasChanges)
            let before = try BackupService.makeArchive(
                from: context,
                createdAt: exportDate
            )

            XCTAssertThrowsError(try BackupService.restore(archive, into: context)) { error in
                XCTAssertEqual(error as? BackupError, .destinationNotEmpty)
            }

            XCTAssertFalse(context.hasChanges)
            let after = try BackupService.makeArchive(
                from: context,
                createdAt: exportDate
            )
            XCTAssertEqual(after, before)
        }
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

    func testRestoreRefusesContextWithPendingUpdateWithoutDiscardingIt() throws {
        let source = try HippocratesStore.makeContainer(inMemory: true)
        _ = try insertCompleteFixture(into: source.mainContext)
        let archive = try BackupService.makeArchive(from: source.mainContext, createdAt: exportDate)

        let destination = try HippocratesStore.makeContainer(inMemory: true)
        let existing = DrugClass(
            label: "Saved configuration",
            isActive: true,
            sortOrder: 7
        )
        destination.mainContext.insert(existing)
        try destination.mainContext.save()
        existing.label = "Unsaved configuration"
        existing.isActive = false
        XCTAssertTrue(destination.mainContext.hasChanges)

        XCTAssertThrowsError(try BackupService.restore(archive, into: destination.mainContext)) { error in
            XCTAssertEqual(error as? BackupError, .destinationHasPendingChanges)
        }

        XCTAssertTrue(destination.mainContext.hasChanges)
        let fetched = try XCTUnwrap(
            destination.mainContext.fetch(FetchDescriptor<DrugClass>()).first
        )
        XCTAssertEqual(fetched.id, existing.id)
        XCTAssertEqual(fetched.label, "Unsaved configuration")
        XCTAssertFalse(fetched.isActive)
        XCTAssertEqual(fetched.sortOrder, 7)
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
              "createdAt": 800000000.125,
              "formatVersion": 1,
              "payload": {
                "appConfig": {
                  "costAvoidanceValues": {
                    "10000000-0000-0000-0000-000000000001": 12500
                  },
                  "lastExportAt": 799000000.5,
                  "stalenessIntervalMonths": 12
                },
                "citations": [
                  {
                    "accessedDate": 700005001.125,
                    "id": "50000000-0000-0000-0000-000000000001",
                    "locator": "Legacy locator 1",
                    "questionID": "40000000-0000-0000-0000-000000000001",
                    "tier": "tertiary",
                    "title": "Legacy citation 1",
                    "urlString": "Legacy source identifier 1"
                  },
                  {
                    "accessedDate": 700005002.125,
                    "id": "50000000-0000-0000-0000-000000000002",
                    "locator": "Legacy locator 2",
                    "questionID": "40000000-0000-0000-0000-000000000002",
                    "tier": "secondary",
                    "title": "Legacy citation 2"
                  },
                  {
                    "accessedDate": 700005003.125,
                    "id": "50000000-0000-0000-0000-000000000003",
                    "locator": "Legacy locator 3",
                    "questionID": "40000000-0000-0000-0000-000000000003",
                    "tier": "primary",
                    "title": "Legacy citation 3",
                    "urlString": "Legacy source identifier 3"
                  },
                  {
                    "accessedDate": 700005004.125,
                    "id": "50000000-0000-0000-0000-000000000004",
                    "locator": "Legacy locator 4",
                    "questionID": "40000000-0000-0000-0000-000000000004",
                    "tier": "guideline",
                    "title": "Legacy citation 4"
                  },
                  {
                    "accessedDate": 700005005.125,
                    "id": "50000000-0000-0000-0000-000000000005",
                    "locator": "Legacy locator 5",
                    "questionID": "40000000-0000-0000-0000-000000000005",
                    "tier": "label",
                    "title": "Legacy citation 5",
                    "urlString": "Legacy source identifier 5"
                  },
                  {
                    "accessedDate": 700005006.125,
                    "id": "50000000-0000-0000-0000-000000000006",
                    "locator": "Legacy locator 6",
                    "questionID": "40000000-0000-0000-0000-000000000006",
                    "tier": "institutionPolicy",
                    "title": "Legacy citation 6"
                  }
                ],
                "drugClasses": [
                  {
                    "id": "20000000-0000-0000-0000-000000000001",
                    "isActive": false,
                    "label": "Legacy antimicrobial",
                    "sortOrder": 2
                  },
                  {
                    "id": "20000000-0000-0000-0000-000000000002",
                    "isActive": true,
                    "label": "Legacy cardiology",
                    "sortOrder": 1
                  }
                ],
                "interventionTypes": [
                  {
                    "id": "10000000-0000-0000-0000-000000000001",
                    "isActive": false,
                    "label": "Legacy folded type",
                    "sortOrder": 2
                  },
                  {
                    "defaultCostAvoidanceCents": 2500,
                    "id": "10000000-0000-0000-0000-000000000002",
                    "isActive": true,
                    "label": "Legacy explicit type",
                    "sortOrder": 1
                  }
                ],
                "interventions": [
                  {
                    "acceptance": "accepted",
                    "costAvoidanceCents": 0,
                    "diQuestionID": "40000000-0000-0000-0000-000000000001",
                    "drugClassID": "20000000-0000-0000-0000-000000000001",
                    "id": "60000000-0000-0000-0000-000000000001",
                    "minutesSpent": 5,
                    "serviceLineID": "30000000-0000-0000-0000-000000000001",
                    "timestamp": 700006001.125,
                    "typeID": "10000000-0000-0000-0000-000000000001"
                  },
                  {
                    "acceptance": "rejected",
                    "costAvoidanceCents": 2500,
                    "diQuestionID": "40000000-0000-0000-0000-000000000002",
                    "drugClassID": "20000000-0000-0000-0000-000000000002",
                    "id": "60000000-0000-0000-0000-000000000002",
                    "serviceLineID": "30000000-0000-0000-0000-000000000002",
                    "timestamp": 700006002.125,
                    "typeID": "10000000-0000-0000-0000-000000000002"
                  },
                  {
                    "acceptance": "pending",
                    "costAvoidanceCents": 12500,
                    "diQuestionID": "40000000-0000-0000-0000-000000000003",
                    "id": "60000000-0000-0000-0000-000000000003",
                    "minutesSpent": 11,
                    "serviceLineID": "30000000-0000-0000-0000-000000000001",
                    "timestamp": 700006003.125,
                    "typeID": "10000000-0000-0000-0000-000000000001"
                  },
                  {
                    "acceptance": "notApplicable",
                    "costAvoidanceCents": 300,
                    "drugClassID": "20000000-0000-0000-0000-000000000002",
                    "id": "60000000-0000-0000-0000-000000000004",
                    "minutesSpent": 0,
                    "timestamp": 700006004.125
                  }
                ],
                "questions": [
                  {
                    "answerText": "Legacy answer 1",
                    "answeredAt": 700001001.25,
                    "background": "Legacy background 1",
                    "createdAt": 700000001.125,
                    "didFollowUp": true,
                    "id": "40000000-0000-0000-0000-000000000001",
                    "questionClass": "dosing",
                    "questionText": "Legacy question 1",
                    "requestorRole": "resident",
                    "reviewAfter": 700004001.75,
                    "searchStrategy": "Legacy search 1",
                    "tags": ["legacy", "dosing"],
                    "urgency": "routine",
                    "verificationHistory": [700002001.25, 700003001.5],
                    "verifiedOn": 700003001.5
                  },
                  {
                    "answerText": "Legacy answer 2",
                    "background": "Legacy background 2",
                    "createdAt": 700000002.125,
                    "didFollowUp": false,
                    "id": "40000000-0000-0000-0000-000000000002",
                    "questionClass": "adverseEffect",
                    "questionText": "Legacy question 2",
                    "requestorRole": "nurse",
                    "reviewAfter": 700004002.75,
                    "searchStrategy": "Legacy search 2",
                    "tags": [],
                    "urgency": "sameDay",
                    "verificationHistory": [700002002.25, 700003002.5],
                    "verifiedOn": 700003002.5
                  },
                  {
                    "answerText": "Legacy answer 3",
                    "answeredAt": 700001003.25,
                    "background": "Legacy background 3",
                    "createdAt": 700000003.125,
                    "didFollowUp": true,
                    "id": "40000000-0000-0000-0000-000000000003",
                    "questionClass": "interaction",
                    "questionText": "Legacy question 3",
                    "requestorRole": "attending",
                    "reviewAfter": 700004003.75,
                    "searchStrategy": "Legacy search 3",
                    "tags": ["legacy", "interaction"],
                    "urgency": "stat",
                    "verificationHistory": [700002003.25, 700003003.5],
                    "verifiedOn": 700003003.5
                  },
                  {
                    "answerText": "Legacy answer 4",
                    "background": "Legacy background 4",
                    "createdAt": 700000004.125,
                    "didFollowUp": false,
                    "id": "40000000-0000-0000-0000-000000000004",
                    "questionClass": "compatibility",
                    "questionText": "Legacy question 4",
                    "requestorRole": "pharmacist",
                    "reviewAfter": 700004004.75,
                    "searchStrategy": "Legacy search 4",
                    "tags": [],
                    "urgency": "routine",
                    "verificationHistory": [700002004.25, 700003004.5],
                    "verifiedOn": 700003004.5
                  },
                  {
                    "answerText": "Legacy answer 5",
                    "answeredAt": 700001005.25,
                    "background": "Legacy background 5",
                    "createdAt": 700000005.125,
                    "didFollowUp": true,
                    "id": "40000000-0000-0000-0000-000000000005",
                    "questionClass": "availability",
                    "questionText": "Legacy question 5",
                    "requestorRole": "student",
                    "reviewAfter": 700004005.75,
                    "searchStrategy": "Legacy search 5",
                    "tags": ["legacy", "availability"],
                    "urgency": "sameDay",
                    "verificationHistory": [700002005.25, 700003005.5],
                    "verifiedOn": 700003005.5
                  },
                  {
                    "answerText": "Legacy answer 6",
                    "background": "Legacy background 6",
                    "createdAt": 700000006.125,
                    "didFollowUp": false,
                    "id": "40000000-0000-0000-0000-000000000006",
                    "questionClass": "administration",
                    "questionText": "Legacy question 6",
                    "requestorRole": "careTeam",
                    "reviewAfter": 700004006.75,
                    "searchStrategy": "Legacy search 6",
                    "tags": [],
                    "urgency": "stat",
                    "verificationHistory": [700002006.25, 700003006.5],
                    "verifiedOn": 700003006.5
                  },
                  {
                    "answerText": "Legacy answer 7",
                    "answeredAt": 700001007.25,
                    "background": "Legacy background 7",
                    "createdAt": 700000007.125,
                    "didFollowUp": true,
                    "id": "40000000-0000-0000-0000-000000000007",
                    "questionClass": "pregnancyLactation",
                    "questionText": "Legacy question 7",
                    "requestorRole": "other",
                    "reviewAfter": 700004007.75,
                    "searchStrategy": "Legacy search 7",
                    "tags": ["legacy", "pregnancy"],
                    "urgency": "routine",
                    "verificationHistory": [700002007.25, 700003007.5],
                    "verifiedOn": 700003007.5
                  },
                  {
                    "answerText": "Legacy answer 8",
                    "background": "Legacy background 8",
                    "createdAt": 700000008.125,
                    "didFollowUp": false,
                    "id": "40000000-0000-0000-0000-000000000008",
                    "questionClass": "therapeutics",
                    "questionText": "Legacy question 8",
                    "requestorRole": "resident",
                    "reviewAfter": 700004008.75,
                    "searchStrategy": "Legacy search 8",
                    "tags": [],
                    "urgency": "sameDay",
                    "verificationHistory": [700002008.25, 700003008.5],
                    "verifiedOn": 700003008.5
                  },
                  {
                    "answerText": "Legacy answer 9",
                    "answeredAt": 700001009.25,
                    "background": "Legacy background 9",
                    "createdAt": 700000009.125,
                    "didFollowUp": true,
                    "id": "40000000-0000-0000-0000-000000000009",
                    "questionClass": "toxicology",
                    "questionText": "Legacy question 9",
                    "requestorRole": "nurse",
                    "reviewAfter": 700004009.75,
                    "searchStrategy": "Legacy search 9",
                    "tags": ["legacy", "toxicology"],
                    "urgency": "stat",
                    "verificationHistory": [700002009.25, 700003009.5],
                    "verifiedOn": 700003009.5
                  },
                  {
                    "answerText": "Legacy answer 10",
                    "background": "Legacy background 10",
                    "createdAt": 700000010.125,
                    "didFollowUp": false,
                    "id": "40000000-0000-0000-0000-00000000000A",
                    "questionClass": "pharmacokinetics",
                    "questionText": "Legacy question 10",
                    "requestorRole": "attending",
                    "reviewAfter": 700004010.75,
                    "searchStrategy": "Legacy search 10",
                    "tags": [],
                    "urgency": "routine",
                    "verificationHistory": [700002010.25, 700003010.5],
                    "verifiedOn": 700003010.5
                  },
                  {
                    "answerText": "Legacy answer 11",
                    "answeredAt": 700001011.25,
                    "background": "Legacy background 11",
                    "createdAt": 700000011.125,
                    "didFollowUp": true,
                    "id": "40000000-0000-0000-0000-00000000000B",
                    "questionClass": "other",
                    "questionText": "Legacy question 11",
                    "requestorRole": "pharmacist",
                    "reviewAfter": 700004011.75,
                    "searchStrategy": "Legacy search 11",
                    "tags": ["legacy", "other"],
                    "urgency": "sameDay",
                    "verificationHistory": [700002011.25, 700003011.5],
                    "verifiedOn": 700003011.5
                  }
                ],
                "serviceLines": [
                  {
                    "id": "30000000-0000-0000-0000-000000000001",
                    "isActive": true,
                    "label": "Legacy critical care",
                    "sortOrder": 1
                  },
                  {
                    "id": "30000000-0000-0000-0000-000000000002",
                    "isActive": false,
                    "label": "Legacy emergency",
                    "sortOrder": 2
                  }
                ]
              }
            }
            """#.utf8
        )

        let migrated = try BackupCodec.decode(data)
        let type1ID = try XCTUnwrap(UUID(uuidString: "10000000-0000-0000-0000-000000000001"))
        let type2ID = try XCTUnwrap(UUID(uuidString: "10000000-0000-0000-0000-000000000002"))
        let drugClass1ID = try XCTUnwrap(UUID(uuidString: "20000000-0000-0000-0000-000000000001"))
        let drugClass2ID = try XCTUnwrap(UUID(uuidString: "20000000-0000-0000-0000-000000000002"))
        let serviceLine1ID = try XCTUnwrap(UUID(uuidString: "30000000-0000-0000-0000-000000000001"))
        let serviceLine2ID = try XCTUnwrap(UUID(uuidString: "30000000-0000-0000-0000-000000000002"))
        let question1ID = try XCTUnwrap(UUID(uuidString: "40000000-0000-0000-0000-000000000001"))
        let question2ID = try XCTUnwrap(UUID(uuidString: "40000000-0000-0000-0000-000000000002"))
        let question3ID = try XCTUnwrap(UUID(uuidString: "40000000-0000-0000-0000-000000000003"))
        let question4ID = try XCTUnwrap(UUID(uuidString: "40000000-0000-0000-0000-000000000004"))
        let question5ID = try XCTUnwrap(UUID(uuidString: "40000000-0000-0000-0000-000000000005"))
        let question6ID = try XCTUnwrap(UUID(uuidString: "40000000-0000-0000-0000-000000000006"))
        let question7ID = try XCTUnwrap(UUID(uuidString: "40000000-0000-0000-0000-000000000007"))
        let question8ID = try XCTUnwrap(UUID(uuidString: "40000000-0000-0000-0000-000000000008"))
        let question9ID = try XCTUnwrap(UUID(uuidString: "40000000-0000-0000-0000-000000000009"))
        let question10ID = try XCTUnwrap(UUID(uuidString: "40000000-0000-0000-0000-00000000000A"))
        let question11ID = try XCTUnwrap(UUID(uuidString: "40000000-0000-0000-0000-00000000000B"))
        let citation1ID = try XCTUnwrap(UUID(uuidString: "50000000-0000-0000-0000-000000000001"))
        let citation2ID = try XCTUnwrap(UUID(uuidString: "50000000-0000-0000-0000-000000000002"))
        let citation3ID = try XCTUnwrap(UUID(uuidString: "50000000-0000-0000-0000-000000000003"))
        let citation4ID = try XCTUnwrap(UUID(uuidString: "50000000-0000-0000-0000-000000000004"))
        let citation5ID = try XCTUnwrap(UUID(uuidString: "50000000-0000-0000-0000-000000000005"))
        let citation6ID = try XCTUnwrap(UUID(uuidString: "50000000-0000-0000-0000-000000000006"))
        let intervention1ID = try XCTUnwrap(UUID(uuidString: "60000000-0000-0000-0000-000000000001"))
        let intervention2ID = try XCTUnwrap(UUID(uuidString: "60000000-0000-0000-0000-000000000002"))
        let intervention3ID = try XCTUnwrap(UUID(uuidString: "60000000-0000-0000-0000-000000000003"))
        let intervention4ID = try XCTUnwrap(UUID(uuidString: "60000000-0000-0000-0000-000000000004"))

        let expectedArchive = BackupArchive(
            createdAt: Date(timeIntervalSinceReferenceDate: 800_000_000.125),
            payload: .init(
                interventionTypes: [
                    .init(
                        id: type1ID,
                        label: "Legacy folded type",
                        defaultCostAvoidanceCents: 12_500,
                        isActive: false,
                        sortOrder: 2
                    ),
                    .init(
                        id: type2ID,
                        label: "Legacy explicit type",
                        defaultCostAvoidanceCents: 2_500,
                        isActive: true,
                        sortOrder: 1
                    )
                ],
                drugClasses: [
                    .init(
                        id: drugClass1ID,
                        label: "Legacy antimicrobial",
                        isActive: false,
                        sortOrder: 2
                    ),
                    .init(
                        id: drugClass2ID,
                        label: "Legacy cardiology",
                        isActive: true,
                        sortOrder: 1
                    )
                ],
                serviceLines: [
                    .init(
                        id: serviceLine1ID,
                        label: "Legacy critical care",
                        isActive: true,
                        sortOrder: 1
                    ),
                    .init(
                        id: serviceLine2ID,
                        label: "Legacy emergency",
                        isActive: false,
                        sortOrder: 2
                    )
                ],
                interventions: [
                    .init(
                        id: intervention1ID,
                        timestamp: Date(timeIntervalSinceReferenceDate: 700_006_001.125),
                        typeID: type1ID,
                        drugClassID: drugClass1ID,
                        serviceLineID: serviceLine1ID,
                        acceptance: .accepted,
                        costAvoidanceCents: 0,
                        minutesSpent: 5,
                        diQuestionID: question1ID
                    ),
                    .init(
                        id: intervention2ID,
                        timestamp: Date(timeIntervalSinceReferenceDate: 700_006_002.125),
                        typeID: type2ID,
                        drugClassID: drugClass2ID,
                        serviceLineID: serviceLine2ID,
                        acceptance: .rejected,
                        costAvoidanceCents: 2_500,
                        minutesSpent: nil,
                        diQuestionID: question2ID
                    ),
                    .init(
                        id: intervention3ID,
                        timestamp: Date(timeIntervalSinceReferenceDate: 700_006_003.125),
                        typeID: type1ID,
                        drugClassID: nil,
                        serviceLineID: serviceLine1ID,
                        acceptance: .pending,
                        costAvoidanceCents: 12_500,
                        minutesSpent: 11,
                        diQuestionID: question3ID
                    ),
                    .init(
                        id: intervention4ID,
                        timestamp: Date(timeIntervalSinceReferenceDate: 700_006_004.125),
                        typeID: nil,
                        drugClassID: drugClass2ID,
                        serviceLineID: nil,
                        acceptance: .notApplicable,
                        costAvoidanceCents: 300,
                        minutesSpent: 0,
                        diQuestionID: nil
                    )
                ],
                questions: [
                    .init(
                        id: question1ID,
                        createdAt: Date(timeIntervalSinceReferenceDate: 700_000_001.125),
                        answeredAt: Date(timeIntervalSinceReferenceDate: 700_001_001.25),
                        questionText: "Legacy question 1",
                        background: "Legacy background 1",
                        answerText: "Legacy answer 1",
                        searchStrategy: "Legacy search 1",
                        requestorRole: .resident,
                        questionClass: .dosing,
                        urgency: .routine,
                        verifiedOn: Date(timeIntervalSinceReferenceDate: 700_003_001.5),
                        reviewAfter: Date(timeIntervalSinceReferenceDate: 700_004_001.75),
                        didFollowUp: true,
                        tags: ["legacy", "dosing"],
                        verificationHistory: [
                            Date(timeIntervalSinceReferenceDate: 700_002_001.25),
                            Date(timeIntervalSinceReferenceDate: 700_003_001.5)
                        ]
                    ),
                    .init(
                        id: question2ID,
                        createdAt: Date(timeIntervalSinceReferenceDate: 700_000_002.125),
                        answeredAt: nil,
                        questionText: "Legacy question 2",
                        background: "Legacy background 2",
                        answerText: "Legacy answer 2",
                        searchStrategy: "Legacy search 2",
                        requestorRole: .nurse,
                        questionClass: .adverseEffect,
                        urgency: .sameDay,
                        verifiedOn: Date(timeIntervalSinceReferenceDate: 700_003_002.5),
                        reviewAfter: Date(timeIntervalSinceReferenceDate: 700_004_002.75),
                        didFollowUp: false,
                        tags: [],
                        verificationHistory: [
                            Date(timeIntervalSinceReferenceDate: 700_002_002.25),
                            Date(timeIntervalSinceReferenceDate: 700_003_002.5)
                        ]
                    ),
                    .init(
                        id: question3ID,
                        createdAt: Date(timeIntervalSinceReferenceDate: 700_000_003.125),
                        answeredAt: Date(timeIntervalSinceReferenceDate: 700_001_003.25),
                        questionText: "Legacy question 3",
                        background: "Legacy background 3",
                        answerText: "Legacy answer 3",
                        searchStrategy: "Legacy search 3",
                        requestorRole: .attending,
                        questionClass: .interaction,
                        urgency: .stat,
                        verifiedOn: Date(timeIntervalSinceReferenceDate: 700_003_003.5),
                        reviewAfter: Date(timeIntervalSinceReferenceDate: 700_004_003.75),
                        didFollowUp: true,
                        tags: ["legacy", "interaction"],
                        verificationHistory: [
                            Date(timeIntervalSinceReferenceDate: 700_002_003.25),
                            Date(timeIntervalSinceReferenceDate: 700_003_003.5)
                        ]
                    ),
                    .init(
                        id: question4ID,
                        createdAt: Date(timeIntervalSinceReferenceDate: 700_000_004.125),
                        answeredAt: nil,
                        questionText: "Legacy question 4",
                        background: "Legacy background 4",
                        answerText: "Legacy answer 4",
                        searchStrategy: "Legacy search 4",
                        requestorRole: .pharmacist,
                        questionClass: .compatibility,
                        urgency: .routine,
                        verifiedOn: Date(timeIntervalSinceReferenceDate: 700_003_004.5),
                        reviewAfter: Date(timeIntervalSinceReferenceDate: 700_004_004.75),
                        didFollowUp: false,
                        tags: [],
                        verificationHistory: [
                            Date(timeIntervalSinceReferenceDate: 700_002_004.25),
                            Date(timeIntervalSinceReferenceDate: 700_003_004.5)
                        ]
                    ),
                    .init(
                        id: question5ID,
                        createdAt: Date(timeIntervalSinceReferenceDate: 700_000_005.125),
                        answeredAt: Date(timeIntervalSinceReferenceDate: 700_001_005.25),
                        questionText: "Legacy question 5",
                        background: "Legacy background 5",
                        answerText: "Legacy answer 5",
                        searchStrategy: "Legacy search 5",
                        requestorRole: .student,
                        questionClass: .availability,
                        urgency: .sameDay,
                        verifiedOn: Date(timeIntervalSinceReferenceDate: 700_003_005.5),
                        reviewAfter: Date(timeIntervalSinceReferenceDate: 700_004_005.75),
                        didFollowUp: true,
                        tags: ["legacy", "availability"],
                        verificationHistory: [
                            Date(timeIntervalSinceReferenceDate: 700_002_005.25),
                            Date(timeIntervalSinceReferenceDate: 700_003_005.5)
                        ]
                    ),
                    .init(
                        id: question6ID,
                        createdAt: Date(timeIntervalSinceReferenceDate: 700_000_006.125),
                        answeredAt: nil,
                        questionText: "Legacy question 6",
                        background: "Legacy background 6",
                        answerText: "Legacy answer 6",
                        searchStrategy: "Legacy search 6",
                        requestorRole: .careTeam,
                        questionClass: .administration,
                        urgency: .stat,
                        verifiedOn: Date(timeIntervalSinceReferenceDate: 700_003_006.5),
                        reviewAfter: Date(timeIntervalSinceReferenceDate: 700_004_006.75),
                        didFollowUp: false,
                        tags: [],
                        verificationHistory: [
                            Date(timeIntervalSinceReferenceDate: 700_002_006.25),
                            Date(timeIntervalSinceReferenceDate: 700_003_006.5)
                        ]
                    ),
                    .init(
                        id: question7ID,
                        createdAt: Date(timeIntervalSinceReferenceDate: 700_000_007.125),
                        answeredAt: Date(timeIntervalSinceReferenceDate: 700_001_007.25),
                        questionText: "Legacy question 7",
                        background: "Legacy background 7",
                        answerText: "Legacy answer 7",
                        searchStrategy: "Legacy search 7",
                        requestorRole: .other,
                        questionClass: .pregnancyLactation,
                        urgency: .routine,
                        verifiedOn: Date(timeIntervalSinceReferenceDate: 700_003_007.5),
                        reviewAfter: Date(timeIntervalSinceReferenceDate: 700_004_007.75),
                        didFollowUp: true,
                        tags: ["legacy", "pregnancy"],
                        verificationHistory: [
                            Date(timeIntervalSinceReferenceDate: 700_002_007.25),
                            Date(timeIntervalSinceReferenceDate: 700_003_007.5)
                        ]
                    ),
                    .init(
                        id: question8ID,
                        createdAt: Date(timeIntervalSinceReferenceDate: 700_000_008.125),
                        answeredAt: nil,
                        questionText: "Legacy question 8",
                        background: "Legacy background 8",
                        answerText: "Legacy answer 8",
                        searchStrategy: "Legacy search 8",
                        requestorRole: .resident,
                        questionClass: .therapeutics,
                        urgency: .sameDay,
                        verifiedOn: Date(timeIntervalSinceReferenceDate: 700_003_008.5),
                        reviewAfter: Date(timeIntervalSinceReferenceDate: 700_004_008.75),
                        didFollowUp: false,
                        tags: [],
                        verificationHistory: [
                            Date(timeIntervalSinceReferenceDate: 700_002_008.25),
                            Date(timeIntervalSinceReferenceDate: 700_003_008.5)
                        ]
                    ),
                    .init(
                        id: question9ID,
                        createdAt: Date(timeIntervalSinceReferenceDate: 700_000_009.125),
                        answeredAt: Date(timeIntervalSinceReferenceDate: 700_001_009.25),
                        questionText: "Legacy question 9",
                        background: "Legacy background 9",
                        answerText: "Legacy answer 9",
                        searchStrategy: "Legacy search 9",
                        requestorRole: .nurse,
                        questionClass: .toxicology,
                        urgency: .stat,
                        verifiedOn: Date(timeIntervalSinceReferenceDate: 700_003_009.5),
                        reviewAfter: Date(timeIntervalSinceReferenceDate: 700_004_009.75),
                        didFollowUp: true,
                        tags: ["legacy", "toxicology"],
                        verificationHistory: [
                            Date(timeIntervalSinceReferenceDate: 700_002_009.25),
                            Date(timeIntervalSinceReferenceDate: 700_003_009.5)
                        ]
                    ),
                    .init(
                        id: question10ID,
                        createdAt: Date(timeIntervalSinceReferenceDate: 700_000_010.125),
                        answeredAt: nil,
                        questionText: "Legacy question 10",
                        background: "Legacy background 10",
                        answerText: "Legacy answer 10",
                        searchStrategy: "Legacy search 10",
                        requestorRole: .attending,
                        questionClass: .pharmacokinetics,
                        urgency: .routine,
                        verifiedOn: Date(timeIntervalSinceReferenceDate: 700_003_010.5),
                        reviewAfter: Date(timeIntervalSinceReferenceDate: 700_004_010.75),
                        didFollowUp: false,
                        tags: [],
                        verificationHistory: [
                            Date(timeIntervalSinceReferenceDate: 700_002_010.25),
                            Date(timeIntervalSinceReferenceDate: 700_003_010.5)
                        ]
                    ),
                    .init(
                        id: question11ID,
                        createdAt: Date(timeIntervalSinceReferenceDate: 700_000_011.125),
                        answeredAt: Date(timeIntervalSinceReferenceDate: 700_001_011.25),
                        questionText: "Legacy question 11",
                        background: "Legacy background 11",
                        answerText: "Legacy answer 11",
                        searchStrategy: "Legacy search 11",
                        requestorRole: .pharmacist,
                        questionClass: .other,
                        urgency: .sameDay,
                        verifiedOn: Date(timeIntervalSinceReferenceDate: 700_003_011.5),
                        reviewAfter: Date(timeIntervalSinceReferenceDate: 700_004_011.75),
                        didFollowUp: true,
                        tags: ["legacy", "other"],
                        verificationHistory: [
                            Date(timeIntervalSinceReferenceDate: 700_002_011.25),
                            Date(timeIntervalSinceReferenceDate: 700_003_011.5)
                        ]
                    )
                ],
                citations: [
                    .init(
                        id: citation1ID,
                        questionID: question1ID,
                        tier: .tertiary,
                        title: "Legacy citation 1",
                        locator: "Legacy locator 1",
                        accessedDate: Date(timeIntervalSinceReferenceDate: 700_005_001.125),
                        urlString: "Legacy source identifier 1"
                    ),
                    .init(
                        id: citation2ID,
                        questionID: question2ID,
                        tier: .secondary,
                        title: "Legacy citation 2",
                        locator: "Legacy locator 2",
                        accessedDate: Date(timeIntervalSinceReferenceDate: 700_005_002.125),
                        urlString: nil
                    ),
                    .init(
                        id: citation3ID,
                        questionID: question3ID,
                        tier: .primary,
                        title: "Legacy citation 3",
                        locator: "Legacy locator 3",
                        accessedDate: Date(timeIntervalSinceReferenceDate: 700_005_003.125),
                        urlString: "Legacy source identifier 3"
                    ),
                    .init(
                        id: citation4ID,
                        questionID: question4ID,
                        tier: .guideline,
                        title: "Legacy citation 4",
                        locator: "Legacy locator 4",
                        accessedDate: Date(timeIntervalSinceReferenceDate: 700_005_004.125),
                        urlString: nil
                    ),
                    .init(
                        id: citation5ID,
                        questionID: question5ID,
                        tier: .label,
                        title: "Legacy citation 5",
                        locator: "Legacy locator 5",
                        accessedDate: Date(timeIntervalSinceReferenceDate: 700_005_005.125),
                        urlString: "Legacy source identifier 5"
                    ),
                    .init(
                        id: citation6ID,
                        questionID: question6ID,
                        tier: .institutionPolicy,
                        title: "Legacy citation 6",
                        locator: "Legacy locator 6",
                        accessedDate: Date(timeIntervalSinceReferenceDate: 700_005_006.125),
                        urlString: nil
                    )
                ],
                appConfig: .init(
                    stalenessIntervalMonths: 12,
                    lastExportAt: Date(timeIntervalSinceReferenceDate: 799_000_000.5)
                )
            )
        )

        XCTAssertEqual(migrated, expectedArchive)
        XCTAssertFalse(migrated.payload.interventionTypes.isEmpty)
        XCTAssertFalse(migrated.payload.drugClasses.isEmpty)
        XCTAssertFalse(migrated.payload.serviceLines.isEmpty)
        XCTAssertFalse(migrated.payload.interventions.isEmpty)
        XCTAssertFalse(migrated.payload.questions.isEmpty)
        XCTAssertFalse(migrated.payload.citations.isEmpty)
        XCTAssertNotNil(migrated.payload.appConfig)
        XCTAssertEqual(
            Set(migrated.payload.interventions.map(\.acceptance.rawValue)),
            Set(SchemaV1Vocabulary.Acceptance.allCases.map(\.rawValue))
        )
        XCTAssertEqual(
            Set(migrated.payload.questions.map(\.requestorRole.rawValue)),
            Set(SchemaV1Vocabulary.RequestorRole.allCases.map(\.rawValue))
        )
        XCTAssertEqual(
            Set(migrated.payload.questions.map(\.questionClass.rawValue)),
            Set(SchemaV1Vocabulary.DIQuestionClass.allCases.map(\.rawValue))
        )
        XCTAssertEqual(
            Set(migrated.payload.questions.map(\.urgency.rawValue)),
            Set(SchemaV1Vocabulary.Urgency.allCases.map(\.rawValue))
        )
        XCTAssertEqual(
            Set(migrated.payload.citations.map(\.tier.rawValue)),
            Set(SchemaV1Vocabulary.SourceTier.allCases.map(\.rawValue))
        )
        XCTAssertTrue(
            migrated.payload.interventions.contains {
                $0.typeID != nil
                    && $0.drugClassID != nil
                    && $0.serviceLineID != nil
                    && $0.diQuestionID != nil
            }
        )
        XCTAssertTrue(
            migrated.payload.citations.contains {
                $0.questionID != nil
            }
        )
        XCTAssertNoThrow(try BackupService.validate(migrated))

        let destination = try HippocratesStore.makeContainer(inMemory: true)
        try BackupService.restore(migrated, into: destination.mainContext)
        XCTAssertFalse(destination.mainContext.hasChanges)
        let restoredArchive = try BackupService.makeArchive(
            from: destination.mainContext,
            createdAt: Date(timeIntervalSinceReferenceDate: 800_000_000.125)
        )
        XCTAssertEqual(restoredArchive, expectedArchive)
        try assertCompleteFixture(
            CompleteFixture(
                expectedArchive: expectedArchive,
                citationID: citation1ID,
                interventionID: intervention1ID
            ),
            in: destination.mainContext
        )

        let reencoded = try BackupCodec.encode(migrated)
        XCTAssertEqual(try BackupCodec.decode(reencoded), expectedArchive)
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

    func testLegacyV1CostMapNormalizesCaseVariedUUIDAliases() throws {
        let typeID = try XCTUnwrap(
            UUID(uuidString: "ABCDEFAB-CDEF-ABCD-EFAB-CDEFABCDEFAB")
        )
        let matchingAliases = Data(
            #"""
            {
              "createdAt": 0,
              "formatVersion": 1,
              "payload": {
                "appConfig": {
                  "costAvoidanceValues": {
                    "ABCDEFAB-CDEF-ABCD-EFAB-CDEFABCDEFAB": 100,
                    "abcdefab-cdef-abcd-efab-cdefabcdefab": 100
                  },
                  "lastExportAt": null,
                  "stalenessIntervalMonths": 12
                },
                "citations": [],
                "drugClasses": [],
                "interventionTypes": [
                  {
                    "id": "ABCDEFAB-CDEF-ABCD-EFAB-CDEFABCDEFAB",
                    "isActive": true,
                    "label": "Legacy aliased type",
                    "sortOrder": 0
                  }
                ],
                "interventions": [],
                "questions": [],
                "serviceLines": []
              }
            }
            """#.utf8
        )

        let migrated = try BackupCodec.decode(matchingAliases)
        XCTAssertEqual(migrated.payload.interventionTypes.first?.id, typeID)
        XCTAssertEqual(
            migrated.payload.interventionTypes.first?.defaultCostAvoidanceCents,
            100
        )

        let conflictingAliases = Data(
            String(decoding: matchingAliases, as: UTF8.self)
                .replacingOccurrences(
                    of: "\"abcdefab-cdef-abcd-efab-cdefabcdefab\": 100",
                    with: "\"abcdefab-cdef-abcd-efab-cdefabcdefab\": 200"
                )
                .utf8
        )
        XCTAssertThrowsError(try BackupCodec.decode(conflictingAliases)) { error in
            guard
                let backupError = error as? BackupError,
                case let .conflictingLegacyCostAvoidanceValue(
                    actualTypeID,
                    firstValue,
                    secondValue
                ) = backupError
            else {
                return XCTFail("Expected a normalized legacy cost-map conflict")
            }
            XCTAssertEqual(actualTypeID, typeID)
            XCTAssertEqual(Set([firstValue, secondValue]), Set([100, 200]))
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

    private func insertExistingDestination(
        _ destinationCase: NonemptyDestinationCase,
        into context: ModelContext
    ) throws {
        switch destinationCase {
        case .interventionType:
            context.insert(
                InterventionType(
                    label: "Existing intervention type",
                    defaultCostAvoidanceCents: 2_500,
                    isActive: false,
                    sortOrder: 1
                )
            )
        case .drugClass:
            context.insert(
                DrugClass(
                    label: "Existing drug class",
                    isActive: false,
                    sortOrder: 2
                )
            )
        case .serviceLine:
            context.insert(
                ServiceLine(
                    label: "Existing service line",
                    isActive: false,
                    sortOrder: 3
                )
            )
        case .intervention:
            context.insert(
                Intervention(
                    timestamp: exportDate.addingTimeInterval(-300),
                    acceptance: .notApplicable,
                    costAvoidanceCents: 0,
                    minutesSpent: 4
                )
            )
        case .question:
            let verifiedOn = exportDate.addingTimeInterval(-86_400)
            context.insert(
                DIQuestion(
                    createdAt: verifiedOn.addingTimeInterval(-3_600),
                    answeredAt: verifiedOn.addingTimeInterval(-900),
                    questionText: "Existing de-identified question",
                    background: "Existing professional context",
                    answerText: "Existing answer",
                    searchStrategy: "Existing source sequence",
                    requestorRole: .nurse,
                    questionClass: .administration,
                    urgency: .sameDay,
                    verifiedOn: verifiedOn,
                    reviewAfter: exportDate,
                    didFollowUp: true,
                    tags: ["existing"],
                    verificationHistory: [verifiedOn]
                )
            )
        case .citation:
            context.insert(
                Citation(
                    tier: .guideline,
                    title: "Existing source",
                    locator: "Section 1",
                    accessedDate: exportDate.addingTimeInterval(-600),
                    urlString: "local-reference-id"
                )
            )
        case .appConfig:
            _ = try AppConfigService.insertForRestore(
                stalenessIntervalMonths: 9,
                lastExportAt: exportDate.addingTimeInterval(-60),
                into: context
            )
        }
    }

    private func insertCompleteFixture(
        into context: ModelContext
    ) throws -> CompleteFixture {
        let typeID = try XCTUnwrap(UUID(uuidString: "10000000-0000-0000-0000-000000000001"))
        let drugClassID = try XCTUnwrap(UUID(uuidString: "20000000-0000-0000-0000-000000000002"))
        let serviceLineID = try XCTUnwrap(UUID(uuidString: "30000000-0000-0000-0000-000000000003"))
        let questionID = try XCTUnwrap(UUID(uuidString: "40000000-0000-0000-0000-000000000004"))
        let citationID = try XCTUnwrap(UUID(uuidString: "50000000-0000-0000-0000-000000000005"))
        let interventionID = try XCTUnwrap(UUID(uuidString: "60000000-0000-0000-0000-000000000006"))

        let verifiedOn = Date(timeIntervalSinceReferenceDate: 750_000_000.75)
        let reviewAfter = Date(timeIntervalSinceReferenceDate: 781_536_000.75)
        let previousVerification = verifiedOn.addingTimeInterval(-86_400)

        let type = InterventionType(
            id: typeID,
            label: "Documented intervention",
            defaultCostAvoidanceCents: 12_500,
            isActive: false,
            sortOrder: 1
        )
        let drugClass = DrugClass(
            id: drugClassID,
            label: "Configured class",
            isActive: false,
            sortOrder: 2
        )
        let serviceLine = ServiceLine(
            id: serviceLineID,
            label: "Configured service",
            isActive: true,
            sortOrder: 3
        )
        let question = DIQuestion(
            id: questionID,
            createdAt: previousVerification.addingTimeInterval(-3_600),
            answeredAt: verifiedOn.addingTimeInterval(-900),
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
            verificationHistory: [previousVerification, verifiedOn]
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
        let configuration = try AppConfigService.insertForRestore(
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

        let expectedArchive = BackupArchive(
            createdAt: exportDate,
            payload: .init(
                interventionTypes: [
                    .init(
                        id: type.id,
                        label: type.label,
                        defaultCostAvoidanceCents: type.defaultCostAvoidanceCents,
                        isActive: type.isActive,
                        sortOrder: type.sortOrder
                    )
                ],
                drugClasses: [
                    .init(
                        id: drugClass.id,
                        label: drugClass.label,
                        isActive: drugClass.isActive,
                        sortOrder: drugClass.sortOrder
                    )
                ],
                serviceLines: [
                    .init(
                        id: serviceLine.id,
                        label: serviceLine.label,
                        isActive: serviceLine.isActive,
                        sortOrder: serviceLine.sortOrder
                    )
                ],
                interventions: [
                    .init(
                        id: intervention.id,
                        timestamp: intervention.timestamp,
                        typeID: type.id,
                        drugClassID: drugClass.id,
                        serviceLineID: serviceLine.id,
                        acceptance: intervention.acceptance,
                        costAvoidanceCents: intervention.costAvoidanceCents,
                        minutesSpent: intervention.minutesSpent,
                        diQuestionID: question.id
                    )
                ],
                questions: [
                    .init(
                        id: question.id,
                        createdAt: question.createdAt,
                        answeredAt: question.answeredAt,
                        questionText: question.questionText,
                        background: question.background,
                        answerText: question.answerText,
                        searchStrategy: question.searchStrategy,
                        requestorRole: question.requestorRole,
                        questionClass: question.questionClass,
                        urgency: question.urgency,
                        verifiedOn: question.verifiedOn,
                        reviewAfter: question.reviewAfter,
                        didFollowUp: question.didFollowUp,
                        tags: question.tags,
                        verificationHistory: question.verificationHistory
                    )
                ],
                citations: [
                    .init(
                        id: citation.id,
                        questionID: question.id,
                        tier: citation.tier,
                        title: citation.title,
                        locator: citation.locator,
                        accessedDate: citation.accessedDate,
                        urlString: citation.urlString
                    )
                ],
                appConfig: .init(
                    stalenessIntervalMonths: configuration.stalenessIntervalMonths,
                    lastExportAt: configuration.lastExportAt
                )
            )
        )
        return CompleteFixture(
            expectedArchive: expectedArchive,
            citationID: citationID,
            interventionID: interventionID
        )
    }

    private func persistedFields(in entity: Schema.Entity) -> Set<String> {
        Set(entity.attributes.filter { !$0.isTransient }.map(\.name))
            .union(entity.relationships.filter { !$0.isTransient }.map(\.name))
    }

    private func assertEmptyBackupDestination(_ context: ModelContext) throws {
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<InterventionType>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DrugClass>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ServiceLine>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Intervention>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DIQuestion>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Citation>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AppConfig>()), 0)
        XCTAssertFalse(context.hasChanges)
    }

    private func assertCompleteFixture(
        _ fixture: CompleteFixture,
        in context: ModelContext
    ) throws {
        let payload = fixture.expectedArchive.payload
        let types = try context.fetch(FetchDescriptor<InterventionType>())
        let drugClasses = try context.fetch(FetchDescriptor<DrugClass>())
        let serviceLines = try context.fetch(FetchDescriptor<ServiceLine>())
        let interventions = try context.fetch(FetchDescriptor<Intervention>())
        let questions = try context.fetch(FetchDescriptor<DIQuestion>())
        let citations = try context.fetch(FetchDescriptor<Citation>())
        let configurations = try context.fetch(FetchDescriptor<AppConfig>())

        XCTAssertEqual(types.count, payload.interventionTypes.count)
        XCTAssertEqual(drugClasses.count, payload.drugClasses.count)
        XCTAssertEqual(serviceLines.count, payload.serviceLines.count)
        XCTAssertEqual(interventions.count, payload.interventions.count)
        XCTAssertEqual(questions.count, payload.questions.count)
        XCTAssertEqual(citations.count, payload.citations.count)
        XCTAssertEqual(configurations.count, payload.appConfig == nil ? 0 : 1)

        let typesByID = Dictionary(uniqueKeysWithValues: types.map { ($0.id, $0) })
        let drugClassesByID = Dictionary(uniqueKeysWithValues: drugClasses.map { ($0.id, $0) })
        let serviceLinesByID = Dictionary(uniqueKeysWithValues: serviceLines.map { ($0.id, $0) })
        let interventionsByID = Dictionary(uniqueKeysWithValues: interventions.map { ($0.id, $0) })
        let questionsByID = Dictionary(uniqueKeysWithValues: questions.map { ($0.id, $0) })
        let citationsByID = Dictionary(uniqueKeysWithValues: citations.map { ($0.id, $0) })

        for record in payload.interventionTypes {
            let type = try XCTUnwrap(typesByID[record.id])
            XCTAssertEqual(type.id, record.id)
            XCTAssertEqual(type.label, record.label)
            XCTAssertEqual(type.defaultCostAvoidanceCents, record.defaultCostAvoidanceCents)
            XCTAssertEqual(type.isActive, record.isActive)
            XCTAssertEqual(type.sortOrder, record.sortOrder)
        }

        for record in payload.drugClasses {
            let drugClass = try XCTUnwrap(drugClassesByID[record.id])
            XCTAssertEqual(drugClass.id, record.id)
            XCTAssertEqual(drugClass.label, record.label)
            XCTAssertEqual(drugClass.isActive, record.isActive)
            XCTAssertEqual(drugClass.sortOrder, record.sortOrder)
        }

        for record in payload.serviceLines {
            let serviceLine = try XCTUnwrap(serviceLinesByID[record.id])
            XCTAssertEqual(serviceLine.id, record.id)
            XCTAssertEqual(serviceLine.label, record.label)
            XCTAssertEqual(serviceLine.isActive, record.isActive)
            XCTAssertEqual(serviceLine.sortOrder, record.sortOrder)
        }

        for record in payload.interventions {
            let intervention = try XCTUnwrap(interventionsByID[record.id])
            XCTAssertEqual(intervention.id, record.id)
            XCTAssertEqual(intervention.timestamp, record.timestamp)
            XCTAssertEqual(intervention.type?.id, record.typeID)
            XCTAssertEqual(intervention.drugClass?.id, record.drugClassID)
            XCTAssertEqual(intervention.serviceLine?.id, record.serviceLineID)
            XCTAssertEqual(intervention.acceptance, record.acceptance)
            XCTAssertEqual(intervention.costAvoidanceCents, record.costAvoidanceCents)
            XCTAssertEqual(intervention.minutesSpent, record.minutesSpent)
            XCTAssertEqual(intervention.diQuestion?.id, record.diQuestionID)
        }

        for record in payload.questions {
            let question = try XCTUnwrap(questionsByID[record.id])
            XCTAssertEqual(question.id, record.id)
            XCTAssertEqual(question.createdAt, record.createdAt)
            XCTAssertEqual(question.answeredAt, record.answeredAt)
            XCTAssertEqual(question.questionText, record.questionText)
            XCTAssertEqual(question.background, record.background)
            XCTAssertEqual(question.answerText, record.answerText)
            XCTAssertEqual(question.searchStrategy, record.searchStrategy)
            XCTAssertEqual(question.requestorRole, record.requestorRole)
            XCTAssertEqual(question.questionClass, record.questionClass)
            XCTAssertEqual(question.urgency, record.urgency)
            XCTAssertEqual(question.verifiedOn, record.verifiedOn)
            XCTAssertEqual(question.reviewAfter, record.reviewAfter)
            XCTAssertEqual(question.didFollowUp, record.didFollowUp)
            XCTAssertEqual(question.tags, record.tags)
            XCTAssertEqual(question.verificationHistory, record.verificationHistory)

            let expectedCitationIDs = payload.citations
                .filter { $0.questionID == record.id }
                .map(\.id)
                .sorted { $0.uuidString < $1.uuidString }
            let expectedInterventionIDs = payload.interventions
                .filter { $0.diQuestionID == record.id }
                .map(\.id)
                .sorted { $0.uuidString < $1.uuidString }
            XCTAssertEqual(
                question.citations.map(\.id).sorted { $0.uuidString < $1.uuidString },
                expectedCitationIDs
            )
            XCTAssertEqual(
                question.linkedInterventions.map(\.id).sorted {
                    $0.uuidString < $1.uuidString
                },
                expectedInterventionIDs
            )
        }

        for record in payload.citations {
            let citation = try XCTUnwrap(citationsByID[record.id])
            XCTAssertEqual(citation.id, record.id)
            XCTAssertEqual(citation.question?.id, record.questionID)
            XCTAssertEqual(citation.tier, record.tier)
            XCTAssertEqual(citation.title, record.title)
            XCTAssertEqual(citation.locator, record.locator)
            XCTAssertEqual(citation.accessedDate, record.accessedDate)
            XCTAssertEqual(citation.urlString, record.urlString)
        }

        if let appConfigRecord = payload.appConfig {
            let configuration = try XCTUnwrap(configurations.first)
            XCTAssertEqual(configuration.singletonKey, "app")
            XCTAssertEqual(
                configuration.stalenessIntervalMonths,
                appConfigRecord.stalenessIntervalMonths
            )
            XCTAssertEqual(configuration.lastExportAt, appConfigRecord.lastExportAt)
        }
    }
}
