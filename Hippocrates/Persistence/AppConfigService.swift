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
    /// A compiler-enforced capability for the model's construction and mutation
    /// seams in safe Swift. The type is visible to SchemaV1, but only this file
    /// can create an instance and only this service retains one.
    final class Authority: Sendable {
        fileprivate static let canonical = Authority()

        fileprivate init() {}
    }

    private static let authority = Authority.canonical

    /// Validates identity as well as static type so a distinct `Authority`
    /// instance cannot satisfy the capability seam.
    nonisolated static func requireAuthority(_ candidate: Authority) {
        precondition(
            candidate === Authority.canonical,
            "Only AppConfigService may construct or mutate AppConfig"
        )
    }

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

        let configuration = AppConfig(
            stalenessIntervalMonths: nil,
            lastExportAt: nil,
            authority: authority
        )
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
            lastExportAt: lastExportAt,
            authority: authority
        )
        context.insert(configuration)
        return configuration
    }

    static func setStalenessIntervalMonths(
        _ stalenessIntervalMonths: Int?,
        on configuration: AppConfig
    ) throws {
        try configuration.updateStalenessIntervalMonths(
            stalenessIntervalMonths,
            authority: authority
        )
    }

    /// I-011: called only by the full-backup flow when an archive has been
    /// generated and handed to the share sheet.
    static func setLastExportAt(
        _ lastExportAt: Date?,
        on configuration: AppConfig
    ) {
        configuration.updateLastExportAt(lastExportAt, authority: authority)
    }

    nonisolated static func validate(stalenessIntervalMonths: Int?) throws {
        if let stalenessIntervalMonths, stalenessIntervalMonths <= 0 {
            throw AppConfigServiceError.invalidStalenessIntervalMonths(
                stalenessIntervalMonths
            )
        }
    }
}
