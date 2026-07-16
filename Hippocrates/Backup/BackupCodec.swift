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
            let interventionTypes: [InterventionTypeRecord]
            let drugClasses: [DrugClassRecord]
            let serviceLines: [ServiceLineRecord]
            let interventions: [InterventionRecord]
            let questions: [DIQuestionRecord]
            let citations: [CitationRecord]
            let appConfig: AppConfigRecord?
        }

        struct InterventionTypeRecord: Decodable {
            let id: UUID
            let label: String
            let defaultCostAvoidanceCents: Int?
            let isActive: Bool
            let sortOrder: Int
        }

        struct DrugClassRecord: Decodable {
            let id: UUID
            let label: String
            let isActive: Bool
            let sortOrder: Int
        }

        struct ServiceLineRecord: Decodable {
            let id: UUID
            let label: String
            let isActive: Bool
            let sortOrder: Int
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

        struct DIQuestionRecord: Decodable {
            let id: UUID
            let createdAt: Date
            let answeredAt: Date?
            let questionText: String
            let background: String
            let answerText: String
            let searchStrategy: String
            let requestorRole: SchemaV1Vocabulary.RequestorRole
            let questionClass: SchemaV1Vocabulary.DIQuestionClass
            let urgency: SchemaV1Vocabulary.Urgency
            let verifiedOn: Date
            let reviewAfter: Date
            let didFollowUp: Bool
            let tags: [String]
            let verificationHistory: [Date]
        }

        struct CitationRecord: Decodable {
            let id: UUID
            let questionID: UUID?
            let tier: SchemaV1Vocabulary.SourceTier
            let title: String
            let locator: String
            let accessedDate: Date
            let urlString: String?
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

        let legacyTypeIDs = Set(legacy.payload.interventionTypes.map(\.id))
        var migratedCostAvoidanceValues: [UUID: Int] = [:]
        if let configuration = legacy.payload.appConfig {
            for (key, value) in configuration.costAvoidanceValues {
                guard
                    let typeID = UUID(uuidString: key),
                    legacyTypeIDs.contains(typeID)
                else {
                    throw BackupError.invalidCostAvoidanceKey(key)
                }

                if let existingValue = legacy.payload.interventionTypes
                    .first(where: { $0.id == typeID })?
                    .defaultCostAvoidanceCents,
                   existingValue != value {
                    throw BackupError.conflictingLegacyCostAvoidanceValue(
                        typeID: typeID,
                        typeValue: existingValue,
                        configValue: value
                    )
                }

                if let existingValue = migratedCostAvoidanceValues[typeID],
                   existingValue != value {
                    throw BackupError.conflictingLegacyCostAvoidanceValue(
                        typeID: typeID,
                        typeValue: existingValue,
                        configValue: value
                    )
                }
                migratedCostAvoidanceValues[typeID] = value
            }
        }

        return BackupArchive(
            formatVersion: BackupArchive.currentFormatVersion,
            createdAt: legacy.createdAt,
            payload: .init(
                interventionTypes: legacy.payload.interventionTypes.map {
                    .init(
                        id: $0.id,
                        label: $0.label,
                        defaultCostAvoidanceCents:
                            $0.defaultCostAvoidanceCents
                            ?? migratedCostAvoidanceValues[$0.id],
                        isActive: $0.isActive,
                        sortOrder: $0.sortOrder
                    )
                },
                drugClasses: legacy.payload.drugClasses.map {
                    .init(
                        id: $0.id,
                        label: $0.label,
                        isActive: $0.isActive,
                        sortOrder: $0.sortOrder
                    )
                },
                serviceLines: legacy.payload.serviceLines.map {
                    .init(
                        id: $0.id,
                        label: $0.label,
                        isActive: $0.isActive,
                        sortOrder: $0.sortOrder
                    )
                },
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
                questions: legacy.payload.questions.map {
                    .init(
                        id: $0.id,
                        createdAt: $0.createdAt,
                        answeredAt: $0.answeredAt,
                        questionText: $0.questionText,
                        background: $0.background,
                        answerText: $0.answerText,
                        searchStrategy: $0.searchStrategy,
                        requestorRole: $0.requestorRole,
                        questionClass: $0.questionClass,
                        urgency: $0.urgency,
                        verifiedOn: $0.verifiedOn,
                        reviewAfter: $0.reviewAfter,
                        didFollowUp: $0.didFollowUp,
                        tags: $0.tags,
                        verificationHistory: $0.verificationHistory
                    )
                },
                citations: legacy.payload.citations.map {
                    .init(
                        id: $0.id,
                        questionID: $0.questionID,
                        tier: $0.tier,
                        title: $0.title,
                        locator: $0.locator,
                        accessedDate: $0.accessedDate,
                        urlString: $0.urlString
                    )
                },
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
