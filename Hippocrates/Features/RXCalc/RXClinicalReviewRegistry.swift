import Foundation

struct RXClinicalReviewStatus: Equatable, Sendable {
    static let draft = Self()

    private init() {}

    var title: String {
        "Draft — independent clinical review required"
    }

    var catalogTitle: String {
        "Draft clinical content"
    }

    var catalogMessage: String {
        "This development build has not passed independent clinical review. Do not use RXcalc for patient care. It performs source-identified arithmetic only."
    }

    var resultMessage: String {
        "Development output only. Independently verify the equation, inputs, units, and result before any clinical use."
    }
}

enum RXClinicalReviewRegistry {
    static let requiredFormulaIdentifiers = [
        "cockcroft_gault_1976@1.0.0",
        "ckd_epi_creatinine_2021@1.0.0",
        "body_mass_index_cdc_metric@1.0.0",
        "body_size_mosteller_1987@1.0.0"
    ]

    // P-008 has no production activation path. Runtime status is a stateless,
    // Draft-only value; future reviewed-state wording lives only in the external
    // candidate packet until a separately approved binding design exists.
    static func status(
        for sources: [RXClinicalSource],
        expectedFormulaIdentifiers: [String]
    ) -> RXClinicalReviewStatus {
        guard hasExactSourceCoverage(
            for: sources,
            expectedFormulaIdentifiers: expectedFormulaIdentifiers
        ) else {
            return .draft
        }
        return .draft
    }

    static func hasExactSourceCoverage(
        for sources: [RXClinicalSource],
        expectedFormulaIdentifiers: [String]
    ) -> Bool {
        let requiredIdentifiers = Set(requiredFormulaIdentifiers)
        let sourceIdentifiers = sources.map(\.formulaIdentifier)
        return expectedFormulaIdentifiers.isEmpty == false
            && Set(expectedFormulaIdentifiers).count == expectedFormulaIdentifiers.count
            && expectedFormulaIdentifiers.allSatisfy(requiredIdentifiers.contains)
            && sourceIdentifiers == expectedFormulaIdentifiers
    }
}
