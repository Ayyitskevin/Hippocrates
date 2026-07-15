import Foundation
import SwiftData

/// The first persisted schema is versioned even though it has no predecessor.
/// SwiftData migrations refer back to these exact nested model types, so future
/// versions add a new schema enum instead of editing history in place.
enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Intervention.self,
            InterventionType.self,
            DrugClass.self,
            ServiceLine.self,
            DIQuestion.self,
            Citation.self,
            AppConfig.self
        ]
    }

    /// `@Model` turns this reference type into a SwiftData entity. Its UUID is
    /// the portable identity used by JSON backups; SwiftData's own persistent
    /// identifier is store-local and must never be exported.
    @Model
    final class InterventionType {
        @Attribute(.unique) var id: UUID
        var label: String
        var defaultCostAvoidanceCents: Int?
        var isActive: Bool
        var sortOrder: Int

        init(
            id: UUID = UUID(),
            label: String,
            defaultCostAvoidanceCents: Int? = nil,
            isActive: Bool = true,
            sortOrder: Int = 0
        ) {
            self.id = id
            self.label = label
            self.defaultCostAvoidanceCents = defaultCostAvoidanceCents
            self.isActive = isActive
            self.sortOrder = sortOrder
        }
    }

    @Model
    final class DrugClass {
        @Attribute(.unique) var id: UUID
        var label: String
        var isActive: Bool
        var sortOrder: Int

        init(
            id: UUID = UUID(),
            label: String,
            isActive: Bool = true,
            sortOrder: Int = 0
        ) {
            self.id = id
            self.label = label
            self.isActive = isActive
            self.sortOrder = sortOrder
        }
    }

    @Model
    final class ServiceLine {
        @Attribute(.unique) var id: UUID
        var label: String
        var isActive: Bool
        var sortOrder: Int

        init(
            id: UUID = UUID(),
            label: String,
            isActive: Bool = true,
            sortOrder: Int = 0
        ) {
            self.id = id
            self.label = label
            self.isActive = isActive
            self.sortOrder = sortOrder
        }
    }

    /// An intervention deliberately contains no String property. Taxonomy
    /// labels live in separately managed configuration entities; capture never
    /// offers a note, details, patient, room, or other text field.
    @Model
    final class Intervention {
        @Attribute(.unique) var id: UUID
        var timestamp: Date

        @Relationship(deleteRule: .nullify)
        var type: InterventionType?

        @Relationship(deleteRule: .nullify)
        var drugClass: DrugClass?

        @Relationship(deleteRule: .nullify)
        var serviceLine: ServiceLine?

        var acceptance: SchemaV1Vocabulary.Acceptance
        var costAvoidanceCents: Int
        var minutesSpent: Int?

        // The inverse and its delete behavior are declared once on
        // DIQuestion.linkedInterventions. `diQuestion` remains optional so an
        // intervention survives if its linked question is removed.
        var diQuestion: DIQuestion?

        init(
            id: UUID = UUID(),
            timestamp: Date = .now,
            type: InterventionType? = nil,
            drugClass: DrugClass? = nil,
            serviceLine: ServiceLine? = nil,
            acceptance: SchemaV1Vocabulary.Acceptance = .pending,
            costAvoidanceCents: Int? = nil,
            minutesSpent: Int? = nil,
            diQuestion: DIQuestion? = nil
        ) {
            self.id = id
            self.timestamp = timestamp
            self.type = type
            self.drugClass = drugClass
            self.serviceLine = serviceLine
            self.acceptance = acceptance
            self.costAvoidanceCents = costAvoidanceCents
                ?? type?.defaultCostAvoidanceCents
                ?? 0
            self.minutesSpent = minutesSpent
            self.diQuestion = diQuestion
        }
    }

    @Model
    final class DIQuestion {
        @Attribute(.unique) var id: UUID
        var createdAt: Date
        var answeredAt: Date?
        var questionText: String
        var background: String
        var answerText: String
        var searchStrategy: String
        var requestorRole: SchemaV1Vocabulary.RequestorRole
        var questionClass: SchemaV1Vocabulary.DIQuestionClass
        var urgency: SchemaV1Vocabulary.Urgency
        private(set) var verifiedOn: Date
        private(set) var reviewAfter: Date
        var didFollowUp: Bool
        var tags: [String]

        // §7 requires re-verification to append rather than erase history. The
        // initial verification date is the first element.
        private(set) var verificationHistory: [Date]

        @Relationship(deleteRule: .cascade, inverse: \Citation.question)
        var citations: [Citation]

        @Relationship(deleteRule: .nullify, inverse: \Intervention.diQuestion)
        var linkedInterventions: [Intervention]

        init(
            id: UUID = UUID(),
            createdAt: Date = .now,
            answeredAt: Date? = nil,
            questionText: String = "",
            background: String = "",
            answerText: String = "",
            searchStrategy: String = "",
            requestorRole: SchemaV1Vocabulary.RequestorRole = .pharmacist,
            questionClass: SchemaV1Vocabulary.DIQuestionClass = .other,
            urgency: SchemaV1Vocabulary.Urgency = .routine,
            verifiedOn: Date = .now,
            reviewAfter: Date,
            didFollowUp: Bool = false,
            tags: [String] = [],
            verificationHistory: [Date]? = nil,
            citations: [Citation] = [],
            linkedInterventions: [Intervention] = []
        ) {
            self.id = id
            self.createdAt = createdAt
            self.answeredAt = answeredAt
            self.questionText = questionText
            self.background = background
            self.answerText = answerText
            self.searchStrategy = searchStrategy
            self.requestorRole = requestorRole
            self.questionClass = questionClass
            self.urgency = urgency
            self.verifiedOn = verifiedOn
            self.reviewAfter = reviewAfter
            self.didFollowUp = didFollowUp
            self.tags = tags
            let initialHistory = verificationHistory ?? [verifiedOn]
            precondition(
                initialHistory.last == verifiedOn,
                "Verification history must end at the current verification date."
            )
            precondition(
                reviewAfter >= verifiedOn,
                "The review date cannot precede the verification date."
            )
            self.verificationHistory = initialHistory
            self.citations = citations
            self.linkedInterventions = linkedInterventions
        }

        /// Re-verification is one domain operation so callers cannot update the
        /// visible date without also resetting its review clock and audit trail.
        func reverify(on date: Date, reviewAfter newReviewDate: Date) {
            precondition(
                newReviewDate >= date,
                "The review date cannot precede the verification date."
            )
            verifiedOn = date
            reviewAfter = newReviewDate
            verificationHistory.append(date)
        }
    }

    @Model
    final class Citation {
        @Attribute(.unique) var id: UUID
        var question: DIQuestion?
        var tier: SchemaV1Vocabulary.SourceTier
        var title: String
        var locator: String
        var accessedDate: Date
        var urlString: String?

        init(
            id: UUID = UUID(),
            question: DIQuestion? = nil,
            tier: SchemaV1Vocabulary.SourceTier,
            title: String,
            locator: String,
            accessedDate: Date,
            urlString: String? = nil
        ) {
            self.id = id
            self.question = question
            self.tier = tier
            self.title = title
            self.locator = locator
            self.accessedDate = accessedDate
            self.urlString = urlString
        }
    }

    @Model
    final class AppConfig {
        /// SwiftData has no singleton entity primitive. A fixed unique key keeps
        /// two physical rows from surviving, but uniqueness uses upsert behavior;
        /// step 10.3 must own creation through one fetch-or-create path so a
        /// second insert cannot unexpectedly replace existing configuration.
        @Attribute(.unique) private(set) var singletonKey: String

        /// Keys are `InterventionType.id.uuidString`; values are integer cents.
        /// The dictionary starts empty and is never populated from invented data.
        var costAvoidanceValues: [String: Int]
        var stalenessIntervalMonths: Int
        var lastExportAt: Date?

        init(
            costAvoidanceValues: [String: Int] = [:],
            stalenessIntervalMonths: Int = 12,
            lastExportAt: Date? = nil
        ) {
            self.singletonKey = "app"
            self.costAvoidanceValues = costAvoidanceValues
            self.stalenessIntervalMonths = stalenessIntervalMonths
            self.lastExportAt = lastExportAt
        }
    }
}

// Views and services use stable, readable names while migration code retains
// access to each schema's exact nested classes.
typealias Intervention = SchemaV1.Intervention
typealias InterventionType = SchemaV1.InterventionType
typealias DrugClass = SchemaV1.DrugClass
typealias ServiceLine = SchemaV1.ServiceLine
typealias DIQuestion = SchemaV1.DIQuestion
typealias Citation = SchemaV1.Citation
typealias AppConfig = SchemaV1.AppConfig
