import Foundation
import XCTest
@testable import Hippocrates

final class RXCalcTests: XCTestCase {
    func testCatalogHasUniqueVersionedDraftSourcesAndStructuredUnits() {
        XCTAssertEqual(RXCalculatorKind.allCases.count, 3)

        let identifiers = RXCalculatorKind.allCases.flatMap {
            $0.descriptor.sources.map(\.formulaIdentifier)
        }
        XCTAssertEqual(identifiers, RXClinicalReviewRegistry.requiredFormulaIdentifiers)
        XCTAssertEqual(Set(identifiers).count, identifiers.count)

        for calculator in RXCalculatorKind.allCases {
            let descriptor = calculator.descriptor
            XCTAssertFalse(descriptor.title.isEmpty)
            XCTAssertFalse(descriptor.intendedPopulation.isEmpty)
            XCTAssertFalse(descriptor.equation.isEmpty)
            XCTAssertFalse(descriptor.canonicalInputUnits.isEmpty)
            XCTAssertFalse(descriptor.canonicalOutputUnits.isEmpty)
            XCTAssertFalse(descriptor.limitations.isEmpty)
            XCTAssertFalse(descriptor.sources.isEmpty)
            XCTAssertEqual(
                descriptor.sources.map(\.formulaIdentifier),
                descriptor.reviewFormulaIdentifiers
            )
            for source in descriptor.sources {
                XCTAssertFalse(source.citation.isEmpty)
                XCTAssertFalse(source.sourceLocator.isEmpty)
                XCTAssertEqual(source.sourceMetadataCheckedOn, "2026-07-19")
            }
            XCTAssertEqual(descriptor.reviewStatus, .draft)
        }
    }

    func testCatalogSearchNormalizesTokensAcrossMetadataAndEvidence() {
        func matches(_ query: String) -> [RXCalculatorKind] {
            RXCalculatorKind.allCases.filter { $0.matches(searchText: query) }
        }

        XCTAssertEqual(matches("renal 2021"), [.ckdEPI2021])
        XCTAssertEqual(matches("  ReNaL   2021  "), [.ckdEPI2021])
        XCTAssertEqual(matches("cockcroft-gault"), [.creatinineClearance])
        XCTAssertEqual(matches("cockcroft créatinine"), [.creatinineClearance])
        XCTAssertEqual(matches("bmi bsa"), [.bodySize])
        XCTAssertEqual(matches("standardized adult"), [.ckdEPI2021])
        XCTAssertEqual(matches("140 coefficient"), [.creatinineClearance])
        XCTAssertEqual(matches("muscle mass"), [.ckdEPI2021])
        XCTAssertEqual(
            matches("body_size_mosteller_1987 1.0.0"),
            [.bodySize]
        )
        XCTAssertEqual(matches("Inker Engl"), [.ckdEPI2021])
        XCTAssertEqual(matches("PMID 34554658"), [.ckdEPI2021])
        XCTAssertEqual(matches("mL/min/1.73"), [.ckdEPI2021])
        XCTAssertEqual(matches(""), RXCalculatorKind.allCases)
        XCTAssertTrue(matches("QTc").isEmpty)
        XCTAssertTrue(matches("renal mosteller").isEmpty)
    }

    func testClinicalReviewRegistryStaysDraftAndRequiresExactSourceCoverage() {
        for calculator in RXCalculatorKind.allCases {
            let descriptor = calculator.descriptor
            XCTAssertTrue(
                RXClinicalReviewRegistry.hasExactSourceCoverage(
                    for: descriptor.sources,
                    expectedFormulaIdentifiers: descriptor.reviewFormulaIdentifiers
                )
            )
            XCTAssertEqual(descriptor.reviewStatus, .draft)
        }

        let bodyDescriptor = RXCalculatorKind.bodySize.descriptor
        XCTAssertFalse(
            RXClinicalReviewRegistry.hasExactSourceCoverage(
                for: [bodyDescriptor.sources[0]],
                expectedFormulaIdentifiers: bodyDescriptor.reviewFormulaIdentifiers
            )
        )
        XCTAssertFalse(
            RXClinicalReviewRegistry.hasExactSourceCoverage(
                for: Array(bodyDescriptor.sources.reversed()),
                expectedFormulaIdentifiers: bodyDescriptor.reviewFormulaIdentifiers
            )
        )
        XCTAssertFalse(
            RXClinicalReviewRegistry.hasExactSourceCoverage(
                for: bodyDescriptor.sources,
                expectedFormulaIdentifiers: [
                    RXClinicalReviewRegistry.requiredFormulaIdentifiers[2],
                    RXClinicalReviewRegistry.requiredFormulaIdentifiers[2]
                ]
            )
        )
    }

    func testClinicalReviewStatusHasDraftOnlyRuntimeCopy() {
        let draft = RXClinicalReviewStatus.draft

        XCTAssertEqual(draft.title, "Draft — independent clinical review required")
        XCTAssertEqual(draft.catalogTitle, "Draft clinical content")
        XCTAssertTrue(draft.catalogMessage.contains("not passed independent clinical review"))
        XCTAssertTrue(draft.resultMessage.contains("Development output only"))
    }

    func testDecimalParserAcceptsCurrentSeparatorAndRejectsAmbiguousInput() {
        XCTAssertEqual(
            RXDecimalInputParser.parse("1.25", decimalSeparator: "."),
            1.25
        )
        XCTAssertEqual(
            RXDecimalInputParser.parse("1,25", decimalSeparator: ","),
            1.25
        )
        XCTAssertNil(RXDecimalInputParser.parse("1.234", decimalSeparator: ","))
        XCTAssertNil(RXDecimalInputParser.parse("1,234", decimalSeparator: "."))
        XCTAssertNil(RXDecimalInputParser.parse("1.234,5", decimalSeparator: ","))
        XCTAssertNil(RXDecimalInputParser.parse("1,234.5", decimalSeparator: "."))
        XCTAssertNil(RXDecimalInputParser.parse("1,2,3", decimalSeparator: ","))
        XCTAssertNil(RXDecimalInputParser.parse("", decimalSeparator: "."))
    }

    func testCockcroftGaultMatchesEquationDerivedEngineeringFixtures() throws {
        let male = try CreatinineClearanceCalculator.calculate(
            CreatinineClearanceInput(
                ageYears: 50,
                equationSex: .male,
                calculationWeight: 70,
                weightUnit: .kilograms,
                serumCreatinine: 1,
                creatinineUnit: .milligramsPerDeciliter
            )
        )
        XCTAssertEqual(male.millilitersPerMinute, 87.5, accuracy: 0.000_000_1)

        let female = try CreatinineClearanceCalculator.calculate(
            CreatinineClearanceInput(
                ageYears: 50,
                equationSex: .female,
                calculationWeight: 70,
                weightUnit: .kilograms,
                serumCreatinine: 1,
                creatinineUnit: .milligramsPerDeciliter
            )
        )
        XCTAssertEqual(female.millilitersPerMinute, 74.375, accuracy: 0.000_000_1)
    }

    func testCockcroftGaultConventionalAndSIInputsAreEquivalent() throws {
        let conventional = try CreatinineClearanceCalculator.calculate(
            CreatinineClearanceInput(
                ageYears: 65,
                equationSex: .male,
                calculationWeight: 70,
                weightUnit: .kilograms,
                serumCreatinine: 1,
                creatinineUnit: .milligramsPerDeciliter
            )
        )
        let converted = try CreatinineClearanceCalculator.calculate(
            CreatinineClearanceInput(
                ageYears: 65,
                equationSex: .male,
                calculationWeight: 154.323_583_529_414_3,
                weightUnit: .pounds,
                serumCreatinine: 88.4,
                creatinineUnit: .micromolesPerLiter
            )
        )

        XCTAssertEqual(
            conventional.millilitersPerMinute,
            converted.millilitersPerMinute,
            accuracy: 0.000_000_1
        )
        XCTAssertEqual(converted.calculationWeightKilograms, 70, accuracy: 0.000_000_1)
        XCTAssertEqual(
            converted.serumCreatinineMilligramsPerDeciliter,
            1,
            accuracy: 0.000_000_1
        )
    }

    func testCKDEPI2021MatchesOfficialNKFImplementationVectors() throws {
        let fixtures: [(age: Int, sex: RXEquationSex, creatinine: Double, expected: Double)] = [
            (18, .male, 0.90, 127),
            (18, .male, 0.91, 125),
            (18, .female, 0.70, 128),
            (18, .female, 0.71, 126),
            (90, .male, 0.50, 97),
            (90, .male, 1.50, 44),
            (90, .female, 0.50, 89),
            (90, .female, 1.50, 33)
        ]

        for fixture in fixtures {
            let result = try CKDEPI2021CreatinineCalculator.calculate(
                CKDEPI2021CreatinineInput(
                    ageYears: fixture.age,
                    equationSex: fixture.sex,
                    serumCreatinine: fixture.creatinine,
                    creatinineUnit: .milligramsPerDeciliter
                )
            )
            XCTAssertEqual(
                result.indexedMillilitersPerMinutePer1_73SquareMeters.rounded(),
                fixture.expected
            )
        }
    }

    func testCKDEPI2021UnitConversionAndCreatinineDirection() throws {
        let conventional = try CKDEPI2021CreatinineCalculator.calculate(
            CKDEPI2021CreatinineInput(
                ageYears: 45,
                equationSex: .female,
                serumCreatinine: 1,
                creatinineUnit: .milligramsPerDeciliter
            )
        )
        let converted = try CKDEPI2021CreatinineCalculator.calculate(
            CKDEPI2021CreatinineInput(
                ageYears: 45,
                equationSex: .female,
                serumCreatinine: 88.4,
                creatinineUnit: .micromolesPerLiter
            )
        )
        let higherCreatinine = try CKDEPI2021CreatinineCalculator.calculate(
            CKDEPI2021CreatinineInput(
                ageYears: 45,
                equationSex: .female,
                serumCreatinine: 2,
                creatinineUnit: .milligramsPerDeciliter
            )
        )

        XCTAssertEqual(
            conventional.indexedMillilitersPerMinutePer1_73SquareMeters,
            converted.indexedMillilitersPerMinutePer1_73SquareMeters,
            accuracy: 0.000_000_1
        )
        XCTAssertLessThan(
            higherCreatinine.indexedMillilitersPerMinutePer1_73SquareMeters,
            conventional.indexedMillilitersPerMinutePer1_73SquareMeters
        )
    }

    func testBodySizeMatchesEquationDerivedEngineeringFixtures() throws {
        let result = try BodySizeCalculator.calculate(
            BodySizeInput(
                ageYears: 40,
                height: 170,
                heightUnit: .centimeters,
                weight: 70,
                weightUnit: .kilograms
            )
        )

        XCTAssertEqual(result.bodyMassIndex, 24.221_453_287_197_235, accuracy: 0.000_000_1)
        XCTAssertEqual(
            result.mostellerBodySurfaceAreaSquareMeters,
            1.818_118_685_772_619,
            accuracy: 0.000_000_1
        )
    }

    func testBodySizeMetricAndUSInputsAreEquivalent() throws {
        let metric = try BodySizeCalculator.calculate(
            BodySizeInput(
                ageYears: 40,
                height: 170,
                heightUnit: .centimeters,
                weight: 70,
                weightUnit: .kilograms
            )
        )
        let customary = try BodySizeCalculator.calculate(
            BodySizeInput(
                ageYears: 40,
                height: 66.929_133_858_267_72,
                heightUnit: .inches,
                weight: 154.323_583_529_414_3,
                weightUnit: .pounds
            )
        )

        XCTAssertEqual(metric.bodyMassIndex, customary.bodyMassIndex, accuracy: 0.000_000_1)
        XCTAssertEqual(
            metric.mostellerBodySurfaceAreaSquareMeters,
            customary.mostellerBodySurfaceAreaSquareMeters,
            accuracy: 0.000_000_1
        )
    }

    func testBodySizeRejectsNineteenYearOldForCDCAdultBMI() {
        XCTAssertThrowsError(
            try BodySizeCalculator.calculate(
                BodySizeInput(
                    ageYears: 19,
                    height: 170,
                    heightUnit: .centimeters,
                    weight: 70,
                    weightUnit: .kilograms
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? RXCalculationError,
                .adultBMIageRequired
            )
        }
    }

    func testCalculatorsRejectOutOfPopulationAndInvalidInputs() {
        XCTAssertThrowsError(
            try CKDEPI2021CreatinineCalculator.calculate(
                CKDEPI2021CreatinineInput(
                    ageYears: 17,
                    equationSex: .male,
                    serumCreatinine: 1,
                    creatinineUnit: .milligramsPerDeciliter
                )
            )
        ) { error in
            XCTAssertEqual(error as? RXCalculationError, .adultAgeRequired)
        }

        XCTAssertThrowsError(
            try CKDEPI2021CreatinineCalculator.calculate(
                CKDEPI2021CreatinineInput(
                    ageYears: 900,
                    equationSex: .male,
                    serumCreatinine: 1,
                    creatinineUnit: .milligramsPerDeciliter
                )
            )
        ) { error in
            XCTAssertEqual(error as? RXCalculationError, .ageOutsideEquation)
        }

        XCTAssertThrowsError(
            try CreatinineClearanceCalculator.calculate(
                CreatinineClearanceInput(
                    ageYears: 140,
                    equationSex: .female,
                    calculationWeight: 70,
                    weightUnit: .kilograms,
                    serumCreatinine: 1,
                    creatinineUnit: .milligramsPerDeciliter
                )
            )
        ) { error in
            XCTAssertEqual(error as? RXCalculationError, .ageOutsideEquation)
        }

        XCTAssertThrowsError(
            try CreatinineClearanceCalculator.calculate(
                CreatinineClearanceInput(
                    ageYears: 50,
                    equationSex: .male,
                    calculationWeight: 70,
                    weightUnit: .kilograms,
                    serumCreatinine: 0,
                    creatinineUnit: .milligramsPerDeciliter
                )
            )
        ) { error in
            XCTAssertEqual(error as? RXCalculationError, .positiveCreatinineRequired)
        }

        XCTAssertThrowsError(
            try BodySizeCalculator.calculate(
                BodySizeInput(
                    ageYears: 40,
                    height: .infinity,
                    heightUnit: .centimeters,
                    weight: 70,
                    weightUnit: .kilograms
                )
            )
        ) { error in
            XCTAssertEqual(error as? RXCalculationError, .finiteValuesRequired)
        }

        XCTAssertThrowsError(
            try BodySizeCalculator.calculate(
                BodySizeInput(
                    ageYears: 40,
                    height: 170,
                    heightUnit: .centimeters,
                    weight: .nan,
                    weightUnit: .kilograms
                )
            )
        ) { error in
            XCTAssertEqual(error as? RXCalculationError, .finiteValuesRequired)
        }

        XCTAssertThrowsError(
            try CreatinineClearanceCalculator.calculate(
                CreatinineClearanceInput(
                    ageYears: 50,
                    equationSex: .male,
                    calculationWeight: 70,
                    weightUnit: .kilograms,
                    serumCreatinine: .greatestFiniteMagnitude,
                    creatinineUnit: .milligramsPerDeciliter
                )
            )
        ) { error in
            XCTAssertEqual(error as? RXCalculationError, .calculationOutsideNumericRange)
        }

        XCTAssertThrowsError(
            try CKDEPI2021CreatinineCalculator.calculate(
                CKDEPI2021CreatinineInput(
                    ageYears: 45,
                    equationSex: .female,
                    serumCreatinine: .greatestFiniteMagnitude,
                    creatinineUnit: .milligramsPerDeciliter
                )
            )
        ) { error in
            XCTAssertEqual(error as? RXCalculationError, .calculationOutsideNumericRange)
        }

        XCTAssertThrowsError(
            try BodySizeCalculator.calculate(
                BodySizeInput(
                    ageYears: 40,
                    height: .greatestFiniteMagnitude,
                    heightUnit: .inches,
                    weight: 70,
                    weightUnit: .kilograms
                )
            )
        ) { error in
            XCTAssertEqual(error as? RXCalculationError, .calculationOutsideNumericRange)
        }
    }
}
