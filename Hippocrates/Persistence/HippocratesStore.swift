import SwiftData

@MainActor
enum HippocratesStore {
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)

        // `.none` is deliberate on both settings: no app-group store and no
        // entitlement-driven managed CloudKit sync can appear by accident.
        let configuration = ModelConfiguration(
            "Hippocrates",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            allowsSave: true,
            groupContainer: .none,
            cloudKitDatabase: .none
        )

        return try ModelContainer(
            for: schema,
            migrationPlan: HippocratesMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
