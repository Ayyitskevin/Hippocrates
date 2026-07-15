import Foundation
import SwiftData

enum AppConfigServiceError: Error, Equatable {
    case multipleConfigurations(count: Int)
    case creationRequiresCleanContext
    case configurationAlreadyExists
    case invalidStalenessIntervalMonths(Int)
}

/// Owns the one logical configuration row. SwiftData uniqueness may upsert a
/// duplicate key, so callers use this main-actor path instead of inserting an
/// `AppConfig` and hoping for a uniqueness failure.
@MainActor
enum AppConfigService {
    static func existing(in context: ModelContext) throws -> AppConfig? {
        let configurations = try context.fetch(FetchDescriptor<AppConfig>())
        guard configurations.count <= 1 else {
            throw AppConfigServiceError.multipleConfigurations(
                count: configurations.count
            )
        }
        return configurations.first
    }

    /// Creates and persists the policy-neutral row only from a clean context.
    /// This avoids a hidden save committing edits owned by another feature.
    static func fetchOrCreate(in context: ModelContext) throws -> AppConfig {
        if let configuration = try existing(in: context) {
            return configuration
        }

        guard !context.hasChanges else {
            throw AppConfigServiceError.creationRequiresCleanContext
        }

        let configuration = AppConfig()
        context.insert(configuration)
        do {
            try context.save()
            return configuration
        } catch {
            // The context was clean before this operation, so rollback discards
            // only the configuration insert owned by this service.
            context.rollback()
            throw error
        }
    }

    /// Backup restore owns its surrounding transaction and therefore needs an
    /// insertion path that deliberately does not save. Restore calls this before
    /// inserting the rest of the graph into its dedicated, verified-empty context.
    static func insertForRestore(
        stalenessIntervalMonths: Int?,
        lastExportAt: Date?,
        into context: ModelContext
    ) throws -> AppConfig {
        guard try existing(in: context) == nil else {
            throw AppConfigServiceError.configurationAlreadyExists
        }
        try validate(stalenessIntervalMonths: stalenessIntervalMonths)

        let configuration = AppConfig(
            stalenessIntervalMonths: stalenessIntervalMonths,
            lastExportAt: lastExportAt
        )
        context.insert(configuration)
        return configuration
    }

    static func setStalenessIntervalMonths(
        _ stalenessIntervalMonths: Int?,
        on configuration: AppConfig
    ) throws {
        try configuration.updateStalenessIntervalMonths(stalenessIntervalMonths)
    }

    nonisolated static func validate(stalenessIntervalMonths: Int?) throws {
        if let stalenessIntervalMonths, stalenessIntervalMonths <= 0 {
            throw AppConfigServiceError.invalidStalenessIntervalMonths(
                stalenessIntervalMonths
            )
        }
    }
}
