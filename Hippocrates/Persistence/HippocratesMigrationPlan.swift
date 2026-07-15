import SwiftData

enum HippocratesMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    // There is no prior store yet. Future migrations append stages here and
    // retain SchemaV1 unchanged so existing installations remain readable.
    static var stages: [MigrationStage] {
        []
    }
}
