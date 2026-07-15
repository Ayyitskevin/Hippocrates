import Foundation

// Raw values are persistence and backup identifiers. Once shipped, rename the
// displayed label instead of changing a raw value; old stores still contain it.
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
