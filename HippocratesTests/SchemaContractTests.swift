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
}
