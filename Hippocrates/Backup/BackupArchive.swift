import Foundation

/// A pure-value, versioned representation of the store. SwiftData model
/// instances and PersistentIdentifier values belong to one ModelContext/store,
/// so exporting them directly would make a backup impossible to restore safely.
struct BackupArchive: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1

    var formatVersion: Int
    var createdAt: Date
    var payload: Payload

    init(
        formatVersion: Int = BackupArchive.currentFormatVersion,
        createdAt: Date = .now,
        payload: Payload
    ) {
        self.formatVersion = formatVersion
        self.createdAt = createdAt
        self.payload = payload
    }
}

extension BackupArchive {
    struct Payload: Codable, Equatable, Sendable {
        var interventionTypes: [InterventionTypeRecord]
        var drugClasses: [DrugClassRecord]
        var serviceLines: [ServiceLineRecord]
        var interventions: [InterventionRecord]
        var questions: [DIQuestionRecord]
        var citations: [CitationRecord]
        var appConfig: AppConfigRecord?
    }

    struct InterventionTypeRecord: Codable, Equatable, Sendable {
        var id: UUID
        var label: String
        var defaultCostAvoidanceCents: Int?
        var isActive: Bool
        var sortOrder: Int
    }

    struct DrugClassRecord: Codable, Equatable, Sendable {
        var id: UUID
        var label: String
        var isActive: Bool
        var sortOrder: Int
    }

    struct ServiceLineRecord: Codable, Equatable, Sendable {
        var id: UUID
        var label: String
        var isActive: Bool
        var sortOrder: Int
    }

    struct InterventionRecord: Codable, Equatable, Sendable {
        var id: UUID
        var timestamp: Date
        var typeID: UUID?
        var drugClassID: UUID?
        var serviceLineID: UUID?
        var acceptance: Acceptance
        var costAvoidanceCents: Int
        var minutesSpent: Int?
        var diQuestionID: UUID?
    }

    struct DIQuestionRecord: Codable, Equatable, Sendable {
        var id: UUID
        var createdAt: Date
        var answeredAt: Date?
        var questionText: String
        var background: String
        var answerText: String
        var searchStrategy: String
        var requestorRole: RequestorRole
        var questionClass: DIQuestionClass
        var urgency: Urgency
        var verifiedOn: Date
        var reviewAfter: Date
        var didFollowUp: Bool
        var tags: [String]
        var verificationHistory: [Date]
    }

    struct CitationRecord: Codable, Equatable, Sendable {
        var id: UUID
        var questionID: UUID?
        var tier: SourceTier
        var title: String
        var locator: String
        var accessedDate: Date
        var urlString: String?
    }

    struct AppConfigRecord: Codable, Equatable, Sendable {
        var costAvoidanceValues: [String: Int]
        var stalenessIntervalMonths: Int
        var lastExportAt: Date?
    }
}
