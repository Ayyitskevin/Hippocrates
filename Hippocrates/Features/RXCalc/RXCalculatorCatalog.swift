import Foundation

struct RXClinicalSource: Equatable, Identifiable, Sendable {
    let formulaIdentifier: String
    let citation: String
    let sourceLocator: String
    let sourceMetadataCheckedOn: String

    var id: String { formulaIdentifier }
}

struct RXCalculatorDescriptor: Equatable, Sendable {
    let title: String
    let shortTitle: String
    let category: String
    let summary: String
    let intendedPopulation: String
    let equation: String
    let canonicalInputUnits: [String]
    let canonicalOutputUnits: [String]
    let roundingPolicy: String
    let limitations: [String]
    let sources: [RXClinicalSource]
    let reviewFormulaIdentifiers: [String]
    let searchTerms: [String]

    var reviewStatus: RXClinicalReviewStatus {
        RXClinicalReviewRegistry.status(
            for: sources,
            expectedFormulaIdentifiers: reviewFormulaIdentifiers
        )
    }
}

enum RXCalculatorKind: String, CaseIterable, Hashable, Identifiable, Sendable {
    case creatinineClearance
    case ckdEPI2021
    case bodySize

    var id: String { rawValue }

    var descriptor: RXCalculatorDescriptor {
        switch self {
        case .creatinineClearance:
            RXCalculatorDescriptor(
                title: "Creatinine Clearance (Cockcroft–Gault)",
                shortTitle: "Creatinine Clearance",
                category: "Renal",
                summary: "Estimates unindexed adult creatinine clearance from age, entered calculation weight, serum creatinine, and equation sex.",
                intendedPopulation: "Adults age 18 or older with stable kidney function.",
                equation: "eCrCl = ((140 − age) × weight × sex coefficient) / (72 × serum creatinine)",
                canonicalInputUnits: [
                    "Age: years",
                    "Calculation weight: kg",
                    "Serum creatinine: mg/dL",
                    "Equation sex: female or male"
                ],
                canonicalOutputUnits: ["Estimated creatinine clearance: mL/min"],
                roundingPolicy: "The calculation retains full precision. RXcalc displays one decimal place.",
                limitations: [
                    "Use only when kidney function and serum creatinine are stable.",
                    "RXcalc uses the calculation weight exactly as entered. It does not choose actual, ideal, adjusted, lean, or another weight strategy.",
                    "The original equation was derived primarily in adult men and applied a published 0.85 coefficient for women.",
                    "Use the clinically appropriate equation sex under local policy when sex fields differ or are ambiguous.",
                    "Do not infer a medication dose or CKD stage from this result. Confirm the current drug label and institutional policy."
                ],
                sources: [
                    RXClinicalSource(
                        formulaIdentifier: "cockcroft_gault_1976@1.0.0",
                        citation: "Cockcroft DW, Gault MH. Nephron. 1976;16(1):31-41.",
                        sourceLocator: "PMID 1244564 · DOI 10.1159/000180580",
                        sourceMetadataCheckedOn: "2026-07-19"
                    )
                ],
                reviewFormulaIdentifiers: ["cockcroft_gault_1976@1.0.0"],
                searchTerms: [
                    "creatinine clearance", "cockcroft gault", "crcl", "renal", "kidney", "drug dosing"
                ]
            )
        case .ckdEPI2021:
            RXCalculatorDescriptor(
                title: "eGFR (2021 CKD-EPI Creatinine)",
                shortTitle: "2021 CKD-EPI eGFR",
                category: "Renal",
                summary: "Estimates race-free adult GFR from age, standardized serum creatinine, and equation sex.",
                intendedPopulation: "Adults age 18 or older with standardized serum creatinine measurement.",
                equation: "eGFR = 142 × min(SCr/κ, 1)^α × max(SCr/κ, 1)^−1.200 × 0.9938^age × 1.012 if female",
                canonicalInputUnits: [
                    "Age: years",
                    "Serum creatinine: mg/dL",
                    "Equation sex: female or male"
                ],
                canonicalOutputUnits: ["Indexed eGFR: mL/min/1.73 m²"],
                roundingPolicy: "The calculation retains full precision. RXcalc displays the indexed result as a whole number, matching NKF implementation guidance.",
                limitations: [
                    "This is the race-free 2021 creatinine-only equation and requires standardized serum creatinine.",
                    "The result is indexed to 1.73 m². RXcalc does not de-index it or translate it into a medication dose.",
                    "Creatinine-only estimates may be inaccurate with rapidly changing kidney function, unusual muscle mass, or other non-GFR determinants.",
                    "Near a critical decision value, consider the current drug label and a more accurate method such as combined creatinine-cystatin C or measured clearance.",
                    "Use the clinically appropriate equation sex under local policy when sex fields differ or are ambiguous."
                ],
                sources: [
                    RXClinicalSource(
                        formulaIdentifier: "ckd_epi_creatinine_2021@1.0.0",
                        citation: "Inker LA et al. N Engl J Med. 2021;385:1737-1749.",
                        sourceLocator: "PMID 34554658 · official NKF/NIDDK implementation guidance",
                        sourceMetadataCheckedOn: "2026-07-19"
                    )
                ],
                reviewFormulaIdentifiers: ["ckd_epi_creatinine_2021@1.0.0"],
                searchTerms: [
                    "egfr", "ckd epi", "glomerular filtration rate", "renal", "kidney", "race free"
                ]
            )
        case .bodySize:
            RXCalculatorDescriptor(
                title: "Body Size (BMI and Mosteller BSA)",
                shortTitle: "BMI and BSA",
                category: "Body Size",
                summary: "Calculates adult BMI and Mosteller body surface area from one height and weight entry.",
                intendedPopulation: "Adults age 20 or older. RXcalc does not classify BMI or derive a dose.",
                equation: "BMI = weight kg / height m² · BSA = √(height cm × weight kg / 3600)",
                canonicalInputUnits: [
                    "Age: years",
                    "Height: cm",
                    "Weight: kg"
                ],
                canonicalOutputUnits: [
                    "Body mass index: kg/m²",
                    "Mosteller body surface area: m²"
                ],
                roundingPolicy: "The calculations retain full precision. RXcalc displays BMI and BSA to two decimal places.",
                limitations: [
                    "BMI and BSA are estimates derived from height and weight; they do not measure body composition or organ function.",
                    "RXcalc does not apply BMI categories or a treatment interpretation.",
                    "A BSA result is not a medication order. Verify the prescribed protocol, dose basis, caps, and current label independently."
                ],
                sources: [
                    RXClinicalSource(
                        formulaIdentifier: "body_mass_index_cdc_metric@1.0.0",
                        citation: "Centers for Disease Control and Prevention. BMI Frequently Asked Questions. June 28, 2024.",
                        sourceLocator: "CDC BMI FAQ · How is BMI calculated?",
                        sourceMetadataCheckedOn: "2026-07-19"
                    ),
                    RXClinicalSource(
                        formulaIdentifier: "body_size_mosteller_1987@1.0.0",
                        citation: "Mosteller RD. N Engl J Med. 1987;317:1098.",
                        sourceLocator: "PMID 3657876 · DOI 10.1056/NEJM198710223171717",
                        sourceMetadataCheckedOn: "2026-07-19"
                    )
                ],
                reviewFormulaIdentifiers: [
                    "body_mass_index_cdc_metric@1.0.0",
                    "body_size_mosteller_1987@1.0.0"
                ],
                searchTerms: [
                    "body mass index", "bmi", "body surface area", "bsa", "mosteller", "height", "weight"
                ]
            )
        }
    }

    func matches(searchText: String) -> Bool {
        let queryTokens = Self.normalizedSearchTokens(in: searchText)
        guard queryTokens.isEmpty == false else { return true }

        let descriptor = descriptor
        var searchableValues = [
            descriptor.title,
            descriptor.shortTitle,
            descriptor.category,
            descriptor.summary,
            descriptor.intendedPopulation,
            descriptor.equation,
            descriptor.roundingPolicy
        ]
        searchableValues.append(contentsOf: descriptor.canonicalInputUnits)
        searchableValues.append(contentsOf: descriptor.canonicalOutputUnits)
        searchableValues.append(contentsOf: descriptor.limitations)
        searchableValues.append(contentsOf: descriptor.searchTerms)
        for source in descriptor.sources {
            searchableValues.append(source.formulaIdentifier)
            searchableValues.append(source.citation)
            searchableValues.append(source.sourceLocator)
        }

        let searchableIndex = Self.normalizedSearchTokens(
            in: searchableValues.joined(separator: " ")
        ).joined(separator: " ")

        return queryTokens.allSatisfy { token in
            searchableIndex.contains(token)
        }
    }

    private static func normalizedSearchTokens(in text: String) -> [String] {
        let folded = text.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let normalizedCharacters = folded.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                ? Character(String(scalar))
                : Character(" ")
        }
        return String(normalizedCharacters)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }
}
