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

    func testPersistedEnumRawValuesAreExplicitAndStable() {
        XCTAssertEqual(Acceptance.allCases.map(\.rawValue), [
            "accepted", "rejected", "pending", "notApplicable"
        ])
        XCTAssertEqual(RequestorRole.allCases.map(\.rawValue), [
            "resident", "nurse", "attending", "pharmacist", "student", "careTeam", "other"
        ])
        XCTAssertEqual(Urgency.allCases.map(\.rawValue), ["routine", "sameDay", "stat"])
        XCTAssertEqual(SourceTier.allCases.map(\.rawValue), [
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
        let config = AppConfig(
            costAvoidanceValues: [:],
            stalenessIntervalMonths: 12,
            lastExportAt: nil
        )

        container.mainContext.insert(type)
        container.mainContext.insert(question)
        container.mainContext.insert(intervention)
        container.mainContext.insert(config)
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
    }
}
