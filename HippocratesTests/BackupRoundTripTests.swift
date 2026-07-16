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
        let typeRecord = try XCTUnwrap(payload.interventionTypes.first)
        let drugClassRecord = try XCTUnwrap(payload.drugClasses.first)
        let serviceLineRecord = try XCTUnwrap(payload.serviceLines.first)
        let interventionRecord = try XCTUnwrap(payload.interventions.first)
        let questionRecord = try XCTUnwrap(payload.questions.first)
        let citationRecord = try XCTUnwrap(payload.citations.first)
        let appConfigRecord = try XCTUnwrap(payload.appConfig)

        let types = try context.fetch(FetchDescriptor<InterventionType>())
        let drugClasses = try context.fetch(FetchDescriptor<DrugClass>())
        let serviceLines = try context.fetch(FetchDescriptor<ServiceLine>())
        let interventions = try context.fetch(FetchDescriptor<Intervention>())
        let questions = try context.fetch(FetchDescriptor<DIQuestion>())
        let citations = try context.fetch(FetchDescriptor<Citation>())
        let configurations = try context.fetch(FetchDescriptor<AppConfig>())

        XCTAssertEqual(types.count, 1)
        XCTAssertEqual(drugClasses.count, 1)
        XCTAssertEqual(serviceLines.count, 1)
        XCTAssertEqual(interventions.count, 1)
        XCTAssertEqual(questions.count, 1)
        XCTAssertEqual(citations.count, 1)
        XCTAssertEqual(configurations.count, 1)

        let type = try XCTUnwrap(types.first)
        XCTAssertEqual(type.id, typeRecord.id)
        XCTAssertEqual(type.label, typeRecord.label)
        XCTAssertEqual(type.defaultCostAvoidanceCents, typeRecord.defaultCostAvoidanceCents)
        XCTAssertEqual(type.isActive, typeRecord.isActive)
        XCTAssertEqual(type.sortOrder, typeRecord.sortOrder)

        let drugClass = try XCTUnwrap(drugClasses.first)
        XCTAssertEqual(drugClass.id, drugClassRecord.id)
        XCTAssertEqual(drugClass.label, drugClassRecord.label)
        XCTAssertEqual(drugClass.isActive, drugClassRecord.isActive)
        XCTAssertEqual(drugClass.sortOrder, drugClassRecord.sortOrder)

        let serviceLine = try XCTUnwrap(serviceLines.first)
        XCTAssertEqual(serviceLine.id, serviceLineRecord.id)
        XCTAssertEqual(serviceLine.label, serviceLineRecord.label)
        XCTAssertEqual(serviceLine.isActive, serviceLineRecord.isActive)
        XCTAssertEqual(serviceLine.sortOrder, serviceLineRecord.sortOrder)

        let intervention = try XCTUnwrap(interventions.first)
        XCTAssertEqual(intervention.id, interventionRecord.id)
        XCTAssertEqual(intervention.timestamp, interventionRecord.timestamp)
        XCTAssertEqual(intervention.type?.id, interventionRecord.typeID)
        XCTAssertEqual(intervention.drugClass?.id, interventionRecord.drugClassID)
        XCTAssertEqual(intervention.serviceLine?.id, interventionRecord.serviceLineID)
        XCTAssertEqual(intervention.acceptance, interventionRecord.acceptance)
        XCTAssertEqual(intervention.costAvoidanceCents, interventionRecord.costAvoidanceCents)
        XCTAssertEqual(intervention.minutesSpent, interventionRecord.minutesSpent)
        XCTAssertEqual(intervention.diQuestion?.id, interventionRecord.diQuestionID)

        let question = try XCTUnwrap(questions.first)
        XCTAssertEqual(question.id, questionRecord.id)
        XCTAssertEqual(question.createdAt, questionRecord.createdAt)
        XCTAssertEqual(question.answeredAt, questionRecord.answeredAt)
        XCTAssertEqual(question.questionText, questionRecord.questionText)
        XCTAssertEqual(question.background, questionRecord.background)
        XCTAssertEqual(question.answerText, questionRecord.answerText)
        XCTAssertEqual(question.searchStrategy, questionRecord.searchStrategy)
        XCTAssertEqual(question.requestorRole, questionRecord.requestorRole)
        XCTAssertEqual(question.questionClass, questionRecord.questionClass)
        XCTAssertEqual(question.urgency, questionRecord.urgency)
        XCTAssertEqual(question.verifiedOn, questionRecord.verifiedOn)
        XCTAssertEqual(question.reviewAfter, questionRecord.reviewAfter)
        XCTAssertEqual(question.didFollowUp, questionRecord.didFollowUp)
        XCTAssertEqual(question.tags, questionRecord.tags)
        XCTAssertEqual(question.verificationHistory, questionRecord.verificationHistory)
        XCTAssertEqual(question.citations.map(\.id), [citationRecord.id])
        XCTAssertEqual(question.linkedInterventions.map(\.id), [interventionRecord.id])

        let citation = try XCTUnwrap(citations.first)
        XCTAssertEqual(citation.id, citationRecord.id)
        XCTAssertEqual(citation.question?.id, citationRecord.questionID)
        XCTAssertEqual(citation.tier, citationRecord.tier)
        XCTAssertEqual(citation.title, citationRecord.title)
        XCTAssertEqual(citation.locator, citationRecord.locator)
        XCTAssertEqual(citation.accessedDate, citationRecord.accessedDate)
        XCTAssertEqual(citation.urlString, citationRecord.urlString)

        let configuration = try XCTUnwrap(configurations.first)
        XCTAssertEqual(configuration.singletonKey, "app")
        XCTAssertEqual(configuration.stalenessIntervalMonths, appConfigRecord.stalenessIntervalMonths)
        XCTAssertEqual(configuration.lastExportAt, appConfigRecord.lastExportAt)
    }
}
