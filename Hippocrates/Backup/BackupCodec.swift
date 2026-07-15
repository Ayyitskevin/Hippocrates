import Foundation

enum BackupCodec {
    static func encode(_ archive: BackupArchive) throws -> Data {
        let encoder = JSONEncoder()
        // sortedKeys makes human inspection and diffs stable. The default Date
        // representation preserves subsecond values used by the round-trip test.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .deferredToDate
        return try encoder.encode(archive)
    }

    static func decode(_ data: Data) throws -> BackupArchive {
        let version = try makeDecoder()
            .decode(FormatEnvelope.self, from: data)
            .formatVersion

        switch version {
        case BackupArchive.currentFormatVersion:
            return try makeDecoder().decode(BackupArchive.self, from: data)
        case 1:
            let legacyArchive = try makeDecoder().decode(
                BackupArchiveV1.self,
                from: data
            )
            return try migrate(legacyArchive)
        default:
            throw BackupError.unsupportedFormatVersion(version)
        }
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return decoder
    }

    /// Format dispatch happens before decoding the payload. Future formats can
    /// retain this tiny envelope even when their value records change shape.
    private struct FormatEnvelope: Decodable {
        let formatVersion: Int
    }

    /// Immutable decoder for backups written before the policy-neutral schema
    /// cleanup. V1 carried an app-wide cost map in addition to type defaults and
    /// could not represent an unanswered staleness decision.
    private struct BackupArchiveV1: Decodable {
        let formatVersion: Int
        let createdAt: Date
        let payload: Payload

        struct Payload: Decodable {
            let interventionTypes: [BackupArchive.InterventionTypeRecord]
            let drugClasses: [BackupArchive.DrugClassRecord]
            let serviceLines: [BackupArchive.ServiceLineRecord]
            let interventions: [InterventionRecord]
            let questions: [BackupArchive.DIQuestionRecord]
            let citations: [BackupArchive.CitationRecord]
            let appConfig: AppConfigRecord?
        }

        struct InterventionRecord: Decodable {
            let id: UUID
            let timestamp: Date
            let typeID: UUID?
            let drugClassID: UUID?
            let serviceLineID: UUID?
            let acceptance: SchemaV1Vocabulary.Acceptance
            let costAvoidanceCents: Int
            let minutesSpent: Int?
            let diQuestionID: UUID?
        }

        struct AppConfigRecord: Decodable {
            let costAvoidanceValues: [String: Int]
            let stalenessIntervalMonths: Int
            let lastExportAt: Date?
        }
    }

    /// V1's app-wide values migrate into the single type-owned source. A
    /// conflicting duplicate is rejected instead of choosing one silently.
    private static func migrate(_ legacy: BackupArchiveV1) throws -> BackupArchive {
        guard legacy.formatVersion == 1 else {
            throw BackupError.unsupportedFormatVersion(legacy.formatVersion)
        }

        var interventionTypes = legacy.payload.interventionTypes
        if let configuration = legacy.payload.appConfig {
            for (key, value) in configuration.costAvoidanceValues {
                guard
                    let typeID = UUID(uuidString: key),
                    let index = interventionTypes.firstIndex(where: { $0.id == typeID })
                else {
                    throw BackupError.invalidCostAvoidanceKey(key)
                }

                if let existingValue = interventionTypes[index].defaultCostAvoidanceCents,
                   existingValue != value {
                    throw BackupError.conflictingLegacyCostAvoidanceValue(
                        typeID: typeID,
                        typeValue: existingValue,
                        configValue: value
                    )
                }
                interventionTypes[index].defaultCostAvoidanceCents = value
            }
        }

        return BackupArchive(
            formatVersion: BackupArchive.currentFormatVersion,
            createdAt: legacy.createdAt,
            payload: .init(
                interventionTypes: interventionTypes,
                drugClasses: legacy.payload.drugClasses,
                serviceLines: legacy.payload.serviceLines,
                interventions: legacy.payload.interventions.map {
                    .init(
                        id: $0.id,
                        timestamp: $0.timestamp,
                        typeID: $0.typeID,
                        drugClassID: $0.drugClassID,
                        serviceLineID: $0.serviceLineID,
                        acceptance: $0.acceptance,
                        costAvoidanceCents: $0.costAvoidanceCents,
                        minutesSpent: $0.minutesSpent,
                        diQuestionID: $0.diQuestionID
                    )
                },
                questions: legacy.payload.questions,
                citations: legacy.payload.citations,
                appConfig: legacy.payload.appConfig.map {
                    .init(
                        stalenessIntervalMonths: $0.stalenessIntervalMonths,
                        lastExportAt: $0.lastExportAt
                    )
                }
            )
        )
    }
}
