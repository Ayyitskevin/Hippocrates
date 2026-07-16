import Foundation
import SwiftData
import XCTest
@testable import Hippocrates

@MainActor
final class SchemaContractTests: XCTestCase {
    func testVersionedSchemaAndMigrationPlanExistFromVersionOne() throws {
        XCTAssertEqual(SchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(SchemaV1.models.count, 7)
        XCTAssertEqual(HippocratesMigrationPlan.schemas.count, 1)
        XCTAssertTrue(HippocratesMigrationPlan.stages.isEmpty)

        let container = try HippocratesStore.makeContainer(inMemory: true)
        XCTAssertNotNil(container.migrationPlan)
        XCTAssertEqual(container.configurations.count, 1)

        let configuration = try XCTUnwrap(container.configurations.first)
        XCTAssertNil(configuration.cloudKitContainerIdentifier)
        XCTAssertNil(configuration.groupAppContainerIdentifier)
    }

    func testTaxonomiesAndConfigAreSeededEmpty() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<InterventionType>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DrugClass>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ServiceLine>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AppConfig>()), 0)
    }

    func testAppConfigFetchOrCreateIsPolicyNeutralAndIdempotent() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext

        let first = try AppConfigService.fetchOrCreate(in: context)
        XCTAssertNil(first.stalenessIntervalMonths)
        XCTAssertNil(first.lastExportAt)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AppConfig>()), 1)

        try AppConfigService.setStalenessIntervalMonths(6, on: first)
        try context.save()

        let second = try AppConfigService.fetchOrCreate(in: context)
        XCTAssertTrue(first === second)
        XCTAssertEqual(second.stalenessIntervalMonths, 6)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AppConfig>()), 1)
    }

    func testAppConfigCreationDoesNotSaveUnrelatedPendingWork() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let context = container.mainContext
        context.insert(DrugClass(label: "Unsaved"))

        XCTAssertThrowsError(try AppConfigService.fetchOrCreate(in: context)) { error in
            XCTAssertEqual(
                error as? AppConfigServiceError,
                .creationRequiresCleanContext
            )
        }
        XCTAssertTrue(context.hasChanges)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AppConfig>()), 0)
    }

    func testConfigurationRejectsNonpositiveStalenessIntervals() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let configuration = try AppConfigService.fetchOrCreate(
            in: container.mainContext
        )

        for value in [0, -1] {
            XCTAssertThrowsError(
                try AppConfigService.setStalenessIntervalMonths(
                    value,
                    on: configuration
                )
            ) { error in
                XCTAssertEqual(
                    error as? AppConfigServiceError,
                    .invalidStalenessIntervalMonths(value)
                )
            }
        }
        XCTAssertNoThrow(
            try AppConfigService.setStalenessIntervalMonths(nil, on: configuration)
        )
        XCTAssertNoThrow(
            try AppConfigService.setStalenessIntervalMonths(6, on: configuration)
        )
    }

    func testFreshnessDatesRequirePositiveStrictlyChronologicalIntervals() {
        let date = Date(timeIntervalSinceReferenceDate: 700_000_000)
        XCTAssertFalse(DIQuestion.reviewWindowIsValid(verifiedOn: date, reviewAfter: date))
        XCTAssertFalse(
            DIQuestion.reviewWindowIsValid(
                verifiedOn: date,
                reviewAfter: date.addingTimeInterval(-1)
            )
        )
        XCTAssertTrue(
            DIQuestion.reviewWindowIsValid(
                verifiedOn: date,
                reviewAfter: date.addingTimeInterval(1)
            )
        )
        XCTAssertTrue(
            DIQuestion.verificationHistoryIsChronological([
                date,
                date.addingTimeInterval(1)
            ])
        )
        XCTAssertFalse(DIQuestion.verificationHistoryIsChronological([date, date]))
    }

    func testPersistedEnumRawValuesAreExplicitAndStable() {
        XCTAssertEqual(SchemaV1Vocabulary.Acceptance.allCases.map(\.rawValue), [
            "accepted", "rejected", "pending", "notApplicable"
        ])
        XCTAssertEqual(SchemaV1Vocabulary.RequestorRole.allCases.map(\.rawValue), [
            "resident", "nurse", "attending", "pharmacist", "student", "careTeam", "other"
        ])
        XCTAssertEqual(SchemaV1Vocabulary.DIQuestionClass.allCases.map(\.rawValue), [
            "dosing", "adverseEffect", "interaction", "compatibility", "availability",
            "administration", "pregnancyLactation", "therapeutics", "toxicology",
            "pharmacokinetics", "other"
        ])
        XCTAssertEqual(SchemaV1Vocabulary.Urgency.allCases.map(\.rawValue), ["routine", "sameDay", "stat"])
        XCTAssertEqual(SchemaV1Vocabulary.SourceTier.allCases.map(\.rawValue), [
            "tertiary", "secondary", "primary", "guideline", "label", "institutionPolicy"
        ])
    }

    func testReverificationUpdatesDateClockAndHistoryAsOneOperation() throws {
        let container = try HippocratesStore.makeContainer(inMemory: true)
        let originalDate = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let originalReviewDate = originalDate.addingTimeInterval(31_536_000)
        let question = DIQuestion(
            verifiedOn: originalDate,
            reviewAfter: originalReviewDate
        )
        container.mainContext.insert(question)
        try container.mainContext.save()

        let newDate = originalDate.addingTimeInterval(86_400)
        let newReviewDate = newDate.addingTimeInterval(15_768_000)
        question.reverify(on: newDate, reviewAfter: newReviewDate)
        try container.mainContext.save()

        XCTAssertEqual(question.verifiedOn, newDate)
        XCTAssertEqual(question.reviewAfter, newReviewDate)
        XCTAssertEqual(question.verificationHistory, [originalDate, newDate])
    }

    func testVersionOneStoreSurvivesCloseAndReopen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HippocratesStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeLocation = directory.appendingPathComponent("Hippocrates.store")
        let typeID = UUID()
        let interventionID = UUID()
        let questionID = UUID()
        let verifiedOn = Date(timeIntervalSinceReferenceDate: 760_000_000)
        let reviewAfter = verifiedOn.addingTimeInterval(31_536_000)

        try writeFileBackedFixture(
            to: storeLocation,
            typeID: typeID,
            interventionID: interventionID,
            questionID: questionID,
            verifiedOn: verifiedOn,
            reviewAfter: reviewAfter
        )
        try assertFileBackedFixture(
            at: storeLocation,
            typeID: typeID,
            interventionID: interventionID,
            questionID: questionID,
            verifiedOn: verifiedOn,
            reviewAfter: reviewAfter
        )
    }

    func testCompleteBackupRestoreSurvivesFileBackedCloseAndReopen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HippocratesRestore", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let restoreStoreLocation = directory.appendingPathComponent("HippocratesRestore.store")
        let typeID = try XCTUnwrap(
            UUID(uuidString: "11000000-0000-0000-0000-000000000001")
        )
        let drugClassID = try XCTUnwrap(
            UUID(uuidString: "22000000-0000-0000-0000-000000000002")
        )
        let serviceLineID = try XCTUnwrap(
            UUID(uuidString: "33000000-0000-0000-0000-000000000003")
        )
        let questionID = try XCTUnwrap(
            UUID(uuidString: "44000000-0000-0000-0000-000000000004")
        )
        let citationID = try XCTUnwrap(
            UUID(uuidString: "55000000-0000-0000-0000-000000000005")
        )
        let interventionID = try XCTUnwrap(
            UUID(uuidString: "66000000-0000-0000-0000-000000000006")
        )
        let archiveCreatedAt = Date(timeIntervalSinceReferenceDate: 810_000_000.125)
        let questionCreatedAt = Date(timeIntervalSinceReferenceDate: 770_000_000.25)
        let previousVerification = Date(timeIntervalSinceReferenceDate: 779_000_000.5)
        let answeredAt = Date(timeIntervalSinceReferenceDate: 779_500_000.625)
        let verifiedOn = Date(timeIntervalSinceReferenceDate: 780_000_000.75)
        let reviewAfter = Date(timeIntervalSinceReferenceDate: 811_536_000.75)
        let interventionTimestamp = Date(timeIntervalSinceReferenceDate: 780_001_800.5)
        let accessedDate = Date(timeIntervalSinceReferenceDate: 780_000_100.875)
        let lastExportAt = Date(timeIntervalSinceReferenceDate: 809_000_000.25)
        let archive = BackupArchive(
            createdAt: archiveCreatedAt,
            payload: .init(
                interventionTypes: [
                    .init(
                        id: typeID,
                        label: "Restored intervention type",
                        defaultCostAvoidanceCents: 24_500,
                        isActive: false,
                        sortOrder: 1
                    )
                ],
                drugClasses: [
                    .init(
                        id: drugClassID,
                        label: "Restored drug class",
                        isActive: true,
                        sortOrder: 2
                    )
                ],
                serviceLines: [
                    .init(
                        id: serviceLineID,
                        label: "Restored service line",
                        isActive: false,
                        sortOrder: 3
                    )
                ],
                interventions: [
                    .init(
                        id: interventionID,
                        timestamp: interventionTimestamp,
                        typeID: typeID,
                        drugClassID: drugClassID,
                        serviceLineID: serviceLineID,
                        acceptance: .notApplicable,
                        costAvoidanceCents: 24_500,
                        minutesSpent: 11,
                        diQuestionID: questionID
                    )
                ],
                questions: [
                    .init(
                        id: questionID,
                        createdAt: questionCreatedAt,
                        answeredAt: answeredAt,
                        questionText: "Complete de-identified restore question",
                        background: "Complete professional context",
                        answerText: "Complete reviewed response",
                        searchStrategy: "Complete source sequence",
                        requestorRole: .careTeam,
                        questionClass: .pharmacokinetics,
                        urgency: .stat,
                        verifiedOn: verifiedOn,
                        reviewAfter: reviewAfter,
                        didFollowUp: true,
                        tags: ["restore", "durability"],
                        verificationHistory: [previousVerification, verifiedOn]
                    )
                ],
                citations: [
                    .init(
                        id: citationID,
                        questionID: questionID,
                        tier: .institutionPolicy,
                        title: "Complete restored source",
                        locator: "Section 4",
                        accessedDate: accessedDate,
                        urlString: "local-reference-id"
                    )
                ],
                appConfig: .init(
                    stalenessIntervalMonths: 9,
                    lastExportAt: lastExportAt
                )
            )
        )
        try BackupService.validate(archive)

        func restoreArchive() throws {
            let container = try makeFileBackedContainer(at: restoreStoreLocation)
            let context = container.mainContext
            try BackupService.restore(archive, into: context)
            XCTAssertFalse(context.hasChanges)
        }

        func assertReopenedArchive() throws {
            let container = try makeFileBackedContainer(at: restoreStoreLocation)
            let context = container.mainContext
            XCTAssertFalse(context.hasChanges)

            let reexportedArchive = try BackupService.makeArchive(
                from: context,
                createdAt: archiveCreatedAt
            )
            XCTAssertEqual(reexportedArchive, archive)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<InterventionType>()), 1)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<DrugClass>()), 1)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<ServiceLine>()), 1)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<Intervention>()), 1)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<DIQuestion>()), 1)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<Citation>()), 1)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<AppConfig>()), 1)

            let question = try XCTUnwrap(
                context.fetch(FetchDescriptor<DIQuestion>()).first
            )
            XCTAssertEqual(question.citations.count, 1)
            XCTAssertEqual(question.citations.first?.id, citationID)
            XCTAssertEqual(question.linkedInterventions.count, 1)
            XCTAssertEqual(question.linkedInterventions.first?.id, interventionID)
            let configuration = try XCTUnwrap(
                context.fetch(FetchDescriptor<AppConfig>()).first
            )
            XCTAssertEqual(configuration.singletonKey, "app")
        }

        try restoreArchive()
        try assertReopenedArchive()
    }

    private func makeFileBackedContainer(at storeLocation: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration(
            "HippocratesPersistenceTest",
            schema: schema,
            url: storeLocation,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: HippocratesMigrationPlan.self,
            configurations: [configuration]
        )
    }

    private func writeFileBackedFixture(
        to storeLocation: URL,
        typeID: UUID,
        interventionID: UUID,
        questionID: UUID,
        verifiedOn: Date,
        reviewAfter: Date
    ) throws {
        let container = try makeFileBackedContainer(at: storeLocation)
        let type = InterventionType(
            id: typeID,
            label: "Persisted type",
            defaultCostAvoidanceCents: nil,
            sortOrder: 4
        )
        let question = DIQuestion(
            id: questionID,
            questionText: "De-identified question",
            requestorRole: .pharmacist,
            questionClass: .therapeutics,
            urgency: .routine,
            verifiedOn: verifiedOn,
            reviewAfter: reviewAfter,
            tags: ["portfolio"],
            verificationHistory: [verifiedOn]
        )
        let intervention = Intervention(
            id: interventionID,
            timestamp: verifiedOn,
            type: type,
            acceptance: .accepted,
            costAvoidanceCents: 0,
            diQuestion: question
        )
        let config = try AppConfigService.fetchOrCreate(in: container.mainContext)
        try AppConfigService.setStalenessIntervalMonths(12, on: config)

        container.mainContext.insert(type)
        container.mainContext.insert(question)
        container.mainContext.insert(intervention)
        try container.mainContext.save()
    }

    private func assertFileBackedFixture(
        at storeLocation: URL,
        typeID: UUID,
        interventionID: UUID,
        questionID: UUID,
        verifiedOn: Date,
        reviewAfter: Date
    ) throws {
        let container = try makeFileBackedContainer(at: storeLocation)
        let types = try container.mainContext.fetch(FetchDescriptor<InterventionType>())
        let interventions = try container.mainContext.fetch(FetchDescriptor<Intervention>())
        let questions = try container.mainContext.fetch(FetchDescriptor<DIQuestion>())
        let configs = try container.mainContext.fetch(FetchDescriptor<AppConfig>())

        let type = try XCTUnwrap(types.first)
        let intervention = try XCTUnwrap(interventions.first)
        let question = try XCTUnwrap(questions.first)
        let config = try XCTUnwrap(configs.first)
        XCTAssertEqual(types.count, 1)
        XCTAssertEqual(interventions.count, 1)
        XCTAssertEqual(questions.count, 1)
        XCTAssertEqual(configs.count, 1)
        XCTAssertEqual(type.id, typeID)
        XCTAssertEqual(intervention.id, interventionID)
        XCTAssertEqual(intervention.type?.id, typeID)
        XCTAssertEqual(intervention.diQuestion?.id, questionID)
        XCTAssertEqual(intervention.acceptance, .accepted)
        XCTAssertEqual(question.id, questionID)
        XCTAssertEqual(question.requestorRole, .pharmacist)
        XCTAssertEqual(question.questionClass, .therapeutics)
        XCTAssertEqual(question.verifiedOn, verifiedOn)
        XCTAssertEqual(question.reviewAfter, reviewAfter)
        XCTAssertEqual(question.verificationHistory, [verifiedOn])
        XCTAssertEqual(question.tags, ["portfolio"])
        XCTAssertEqual(intervention.costAvoidanceCents, 0)
        XCTAssertEqual(config.stalenessIntervalMonths, 12)
    }
}
