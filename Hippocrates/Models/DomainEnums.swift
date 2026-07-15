import Foundation

/// Persisted value types belong to a schema version just as much as `@Model`
/// classes do. Keeping V1's enums in a frozen namespace prevents a future V2
/// display or taxonomy change from silently changing how a V1 store decodes.
enum SchemaV1Vocabulary {
    // Raw values are persistence and backup identifiers. Once shipped, rename
    // a displayed label instead of changing one of these values.
    enum Acceptance: String, Codable, CaseIterable, Sendable {
        case accepted
        case rejected
        case pending
        case notApplicable
    }

    enum RequestorRole: String, Codable, CaseIterable, Sendable {
        case resident
        case nurse
        case attending
        case pharmacist
        case student
        case careTeam
        case other
    }

    enum DIQuestionClass: String, Codable, CaseIterable, Sendable {
        case dosing
        case adverseEffect
        case interaction
        case compatibility
        case availability
        case administration
        case pregnancyLactation
        case therapeutics
        case toxicology
        case pharmacokinetics
        case other
    }

    enum Urgency: String, Codable, CaseIterable, Sendable {
        case routine
        case sameDay
        case stat
    }

    enum SourceTier: String, Codable, CaseIterable, Sendable {
        case tertiary
        case secondary
        case primary
        case guideline
        case label
        case institutionPolicy
    }
}

// Application code uses concise current-version names. Historical schema and
// backup code always spell out SchemaV1Vocabulary so these aliases can move to
// V2 without mutating V1's decoding contract.
typealias Acceptance = SchemaV1Vocabulary.Acceptance
typealias RequestorRole = SchemaV1Vocabulary.RequestorRole
typealias DIQuestionClass = SchemaV1Vocabulary.DIQuestionClass
typealias Urgency = SchemaV1Vocabulary.Urgency
typealias SourceTier = SchemaV1Vocabulary.SourceTier
