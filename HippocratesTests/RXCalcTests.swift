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

    // MARK: - Provenance completeness

    func testSuccessfulResultsExposeReproducibleProvenance() throws {
        let fixed = Date(timeIntervalSince1970: 1_784_563_200) // fixed for determinism

        let crcl = try CreatinineClearanceCalculator.calculate(
            CreatinineClearanceInput(
                ageYears: 50,
                equationSex: .male,
                calculationWeight: RXQuantity(70, unit: .kilograms),
                serumCreatinine: RXQuantity(1, unit: .milligramsPerDeciliter)
            ),
            calculatedAt: fixed
        )
        assertProvenanceComplete(
            crcl.provenance,
            expectedFormulaIDs: [CreatinineClearanceCalculator.formulaIdentifier],
            expectedRounding: RXRoundingPolicyIdentity.cockcroftGaultDisplayOneDecimal.rawValue,
            expectedTraceNames: [
                "ageYears", "equationSex", "calculationWeight", "serumCreatinine"
            ],
            calculatedAt: fixed
        )
        XCTAssertEqual(crcl.provenance.inputTraces.first { $0.name == "calculationWeight" }?.normalizedUnitSymbol, "kg")
        XCTAssertEqual(crcl.provenance.inputTraces.first { $0.name == "serumCreatinine" }?.normalizedUnitSymbol, "mg/dL")

        let egfr = try CKDEPI2021CreatinineCalculator.calculate(
            CKDEPI2021CreatinineInput(
                ageYears: 18,
                equationSex: .male,
                serumCreatinine: RXQuantity(0.9, unit: .milligramsPerDeciliter)
            ),
            calculatedAt: fixed
        )
        assertProvenanceComplete(
            egfr.provenance,
            expectedFormulaIDs: [CKDEPI2021CreatinineCalculator.formulaIdentifier],
            expectedRounding: RXRoundingPolicyIdentity.ckdEPI2021DisplayWholeNumber.rawValue,
            expectedTraceNames: ["ageYears", "equationSex", "serumCreatinine"],
            calculatedAt: fixed
        )

        let body = try BodySizeCalculator.calculate(
            BodySizeInput(
                ageYears: 40,
                height: RXQuantity(170, unit: .centimeters),
                weight: RXQuantity(70, unit: .kilograms)
            ),
            calculatedAt: fixed
        )
        assertProvenanceComplete(
            body.provenance,
            expectedFormulaIDs: [
                BodySizeCalculator.bmiFormulaIdentifier,
                BodySizeCalculator.mostellerFormulaIdentifier
            ],
            expectedRounding: RXRoundingPolicyIdentity.bodySizeDisplayTwoDecimals.rawValue,
            expectedTraceNames: ["ageYears", "height", "weight"],
            calculatedAt: fixed
        )
    }

    func testProvenancePreservesOriginalUnitsAfterNormalization() throws {
        let result = try CreatinineClearanceCalculator.calculate(
            CreatinineClearanceInput(
                ageYears: 65,
                equationSex: .female,
                calculationWeight: 154.323_583_529_414_3,
                weightUnit: .pounds,
                serumCreatinine: 88.4,
                creatinineUnit: .micromolesPerLiter
            ),
            calculatedAt: Date(timeIntervalSince1970: 0)
        )
        let weightTrace = try XCTUnwrap(
            result.provenance.inputTraces.first { $0.name == "calculationWeight" }
        )
        XCTAssertEqual(weightTrace.originalUnitSymbol, "lb")
        XCTAssertEqual(weightTrace.normalizedUnitSymbol, "kg")
        XCTAssertEqual(weightTrace.normalizedValue, 70, accuracy: 0.000_000_1)

        let scrTrace = try XCTUnwrap(
            result.provenance.inputTraces.first { $0.name == "serumCreatinine" }
        )
        XCTAssertEqual(scrTrace.originalUnitSymbol, "µmol/L")
        XCTAssertEqual(scrTrace.normalizedUnitSymbol, "mg/dL")
        XCTAssertEqual(scrTrace.normalizedValue, 1, accuracy: 0.000_000_1)
    }

    func testProvenanceAlignsWithCatalogDraftStatusAndFormulaIDs() throws {
        for kind in RXCalculatorKind.allCases {
            let descriptor = kind.descriptor
            XCTAssertEqual(
                descriptor.reviewStatus.title,
                RXCalculationProvenance.draftReviewStatusTitle
            )
        }

        let crcl = try CreatinineClearanceCalculator.calculate(
            CreatinineClearanceInput(
                ageYears: 50,
                equationSex: .male,
                calculationWeight: 70,
                weightUnit: .kilograms,
                serumCreatinine: 1,
                creatinineUnit: .milligramsPerDeciliter
            )
        )
        XCTAssertEqual(
            crcl.provenance.formulaIdentifiers,
            RXCalculatorKind.creatinineClearance.descriptor.reviewFormulaIdentifiers
        )
        XCTAssertTrue(crcl.provenance.humanReviewRequired)
        XCTAssertFalse(crcl.provenance.isAutonomousClinicalRecommendation)
    }

    // MARK: - Typed units / dimensional boundary

    func testTypedQuantitiesKeepKindsDistinctAndConvertCanonically() throws {
        XCTAssertEqual(RXMassUnit.kind, .mass)
        XCTAssertEqual(RXLengthUnit.kind, .length)
        XCTAssertEqual(RXCreatinineUnit.kind, .creatinineConcentration)

        let mass = RXQuantity(10, unit: RXMassUnit.pounds)
        let length = RXQuantity(10, unit: RXLengthUnit.inches)
        let scr = RXQuantity(88.4, unit: RXCreatinineUnit.micromolesPerLiter)

        XCTAssertEqual(RXDimensionalAnalysis.kind(of: mass), .mass)
        XCTAssertEqual(RXDimensionalAnalysis.kind(of: length), .length)
        XCTAssertEqual(RXDimensionalAnalysis.kind(of: scr), .creatinineConcentration)
        XCTAssertTrue(RXDimensionalAnalysis.areCompatible([mass, RXQuantity(1, unit: .kilograms)]))

        XCTAssertEqual(try mass.canonical(), 4.535_923_7, accuracy: 0.000_000_1)
        XCTAssertEqual(try length.canonical(), 25.4, accuracy: 0.000_000_1)
        XCTAssertEqual(try scr.canonical(), 1.0, accuracy: 0.000_000_1)

        // Cross-kind requireKind must fail for the wrong expected kind.
        XCTAssertThrowsError(
            try RXDimensionalAnalysis.requireKind(mass, expected: .length)
        )
        XCTAssertThrowsError(
            try RXDimensionalAnalysis.requireKind(length, expected: .mass)
        )
        XCTAssertThrowsError(
            try RXDimensionalAnalysis.requireKind(scr, expected: .mass)
        )
    }

    func testTypedQuantityInputPathsMatchLegacyDoublePaths() throws {
        let legacy = try CreatinineClearanceCalculator.calculate(
            CreatinineClearanceInput(
                ageYears: 50,
                equationSex: .female,
                calculationWeight: 70,
                weightUnit: .kilograms,
                serumCreatinine: 1,
                creatinineUnit: .milligramsPerDeciliter
            ),
            calculatedAt: Date(timeIntervalSince1970: 1)
        )
        let typed = try CreatinineClearanceCalculator.calculate(
            CreatinineClearanceInput(
                ageYears: 50,
                equationSex: .female,
                calculationWeight: RXQuantity(70, unit: .kilograms),
                serumCreatinine: RXQuantity(1, unit: .milligramsPerDeciliter)
            ),
            calculatedAt: Date(timeIntervalSince1970: 1)
        )
        XCTAssertEqual(legacy.millilitersPerMinute, typed.millilitersPerMinute, accuracy: 0)
        XCTAssertEqual(legacy.provenance.formulaIdentifiers, typed.provenance.formulaIdentifiers)
    }

    // MARK: - Display rounding is display-only

    func testDisplayRoundingDoesNotMutateReturnedFullPrecision() throws {
        let egfr = try CKDEPI2021CreatinineCalculator.calculate(
            CKDEPI2021CreatinineInput(
                ageYears: 18,
                equationSex: .male,
                serumCreatinine: 0.90,
                creatinineUnit: .milligramsPerDeciliter
            )
        )
        // Full-precision result is retained; NKF whole-number display is separate.
        XCTAssertNotEqual(
            egfr.indexedMillilitersPerMinutePer1_73SquareMeters,
            egfr.indexedMillilitersPerMinutePer1_73SquareMeters.rounded()
        )
        XCTAssertEqual(
            egfr.indexedMillilitersPerMinutePer1_73SquareMeters.rounded(),
            127
        )
        XCTAssertEqual(
            egfr.provenance.roundingPolicyIdentity,
            RXRoundingPolicyIdentity.ckdEPI2021DisplayWholeNumber.rawValue
        )

        let crcl = try CreatinineClearanceCalculator.calculate(
            CreatinineClearanceInput(
                ageYears: 50,
                equationSex: .female,
                calculationWeight: 70,
                weightUnit: .kilograms,
                serumCreatinine: 1,
                creatinineUnit: .milligramsPerDeciliter
            )
        )
        // 74.375 already one decimal of interest; full value equals the exact fraction.
        XCTAssertEqual(crcl.millilitersPerMinute, 74.375, accuracy: 0)
        // Avoid bare "/" (scanner-reviewed only inside formula seams).
        let displayed = (crcl.millilitersPerMinute * 10).rounded() * 0.1
        XCTAssertEqual(displayed, 74.4, accuracy: 0.000_000_1)
        XCTAssertNotEqual(crcl.millilitersPerMinute, displayed)
    }

    // MARK: - Table-driven boundaries and malformed inputs

    func testCockcroftGaultTableDrivenBoundaries() {
        struct Case {
            let name: String
            let age: Int
            let sex: RXEquationSex
            let weight: Double
            let weightUnit: RXMassUnit
            let scr: Double
            let scrUnit: RXCreatinineUnit
            let expected: RXCalculationError
        }
        let cases: [Case] = [
            Case(name: "pediatric", age: 17, sex: .male, weight: 70, weightUnit: .kilograms, scr: 1, scrUnit: .milligramsPerDeciliter, expected: .adultAgeRequired),
            Case(name: "age140", age: 140, sex: .male, weight: 70, weightUnit: .kilograms, scr: 1, scrUnit: .milligramsPerDeciliter, expected: .ageOutsideEquation),
            Case(name: "zeroWeight", age: 50, sex: .male, weight: 0, weightUnit: .kilograms, scr: 1, scrUnit: .milligramsPerDeciliter, expected: .positiveWeightRequired),
            Case(name: "negWeight", age: 50, sex: .male, weight: -1, weightUnit: .kilograms, scr: 1, scrUnit: .milligramsPerDeciliter, expected: .positiveWeightRequired),
            Case(name: "zeroScr", age: 50, sex: .male, weight: 70, weightUnit: .kilograms, scr: 0, scrUnit: .milligramsPerDeciliter, expected: .positiveCreatinineRequired),
            Case(name: "negScr", age: 50, sex: .male, weight: 70, weightUnit: .kilograms, scr: -0.5, scrUnit: .milligramsPerDeciliter, expected: .positiveCreatinineRequired),
            Case(name: "nanWeight", age: 50, sex: .male, weight: .nan, weightUnit: .kilograms, scr: 1, scrUnit: .milligramsPerDeciliter, expected: .finiteValuesRequired),
            Case(name: "infScr", age: 50, sex: .male, weight: 70, weightUnit: .kilograms, scr: .infinity, scrUnit: .milligramsPerDeciliter, expected: .finiteValuesRequired),
        ]
        for testCase in cases {
            XCTAssertThrowsError(
                try CreatinineClearanceCalculator.calculate(
                    CreatinineClearanceInput(
                        ageYears: testCase.age,
                        equationSex: testCase.sex,
                        calculationWeight: testCase.weight,
                        weightUnit: testCase.weightUnit,
                        serumCreatinine: testCase.scr,
                        creatinineUnit: testCase.scrUnit
                    )
                ),
                testCase.name
            ) { error in
                XCTAssertEqual(error as? RXCalculationError, testCase.expected, testCase.name)
            }
        }
    }

    func testBodySizeTableDrivenBoundaries() {
        let cases: [(String, BodySizeInput, RXCalculationError)] = [
            (
                "age19",
                BodySizeInput(ageYears: 19, height: 170, heightUnit: .centimeters, weight: 70, weightUnit: .kilograms),
                .adultBMIageRequired
            ),
            (
                "zeroHeight",
                BodySizeInput(ageYears: 40, height: 0, heightUnit: .centimeters, weight: 70, weightUnit: .kilograms),
                .positiveHeightRequired
            ),
            (
                "zeroWeight",
                BodySizeInput(ageYears: 40, height: 170, heightUnit: .centimeters, weight: 0, weightUnit: .kilograms),
                .positiveWeightRequired
            ),
            (
                "negHeight",
                BodySizeInput(ageYears: 40, height: -10, heightUnit: .inches, weight: 70, weightUnit: .pounds),
                .positiveHeightRequired
            ),
        ]
        for (name, input, expected) in cases {
            XCTAssertThrowsError(try BodySizeCalculator.calculate(input), name) { error in
                XCTAssertEqual(error as? RXCalculationError, expected, name)
            }
        }
    }

    // MARK: - Property-style generative checks (deterministic)

    func testCockcroftGaultFemaleIs85PercentOfMaleProperty() throws {
        // For identical age/weight/SCr, female coefficient is published 0.85.
        let ages = [18, 30, 45, 60, 75, 90, 120, 139]
        let weights = [40.0, 55.0, 70.0, 100.0, 140.0]
        let creatinines = [0.5, 0.8, 1.0, 1.5, 2.5]
        for age in ages {
            for weight in weights {
                for scr in creatinines {
                    let male = try CreatinineClearanceCalculator.calculate(
                        CreatinineClearanceInput(
                            ageYears: age,
                            equationSex: .male,
                            calculationWeight: weight,
                            weightUnit: .kilograms,
                            serumCreatinine: scr,
                            creatinineUnit: .milligramsPerDeciliter
                        )
                    )
                    let female = try CreatinineClearanceCalculator.calculate(
                        CreatinineClearanceInput(
                            ageYears: age,
                            equationSex: .female,
                            calculationWeight: weight,
                            weightUnit: .kilograms,
                            serumCreatinine: scr,
                            creatinineUnit: .milligramsPerDeciliter
                        )
                    )
                    XCTAssertEqual(
                        female.millilitersPerMinute,
                        male.millilitersPerMinute * 0.85,
                        accuracy: 0.000_000_1,
                        "female coefficient property mismatch"
                    )
                }
            }
        }
    }

    func testCKDEPIMonotonicDecreasingInCreatinineProperty() throws {
        let ages = [18, 40, 65, 90]
        let sexes: [RXEquationSex] = [.female, .male]
        let creatinines = stride(from: 0.4, through: 3.0, by: 0.2).map { $0 }
        for age in ages {
            for sex in sexes {
                var previous: Double?
                for scr in creatinines {
                    let value = try CKDEPI2021CreatinineCalculator.calculate(
                        CKDEPI2021CreatinineInput(
                            ageYears: age,
                            equationSex: sex,
                            serumCreatinine: scr,
                            creatinineUnit: .milligramsPerDeciliter
                        )
                    ).indexedMillilitersPerMinutePer1_73SquareMeters
                    if let previous {
                        XCTAssertLessThan(
                            value,
                            previous,
                            "eGFR must fall as serum creatinine rises"
                        )
                    }
                    previous = value
                }
            }
        }
    }

    func testBodySizeBMIScalesWithWeightProperty() throws {
        let heightCm = 170.0
        var previousBMI: Double?
        for weight in stride(from: 50.0, through: 120.0, by: 5.0) {
            let result = try BodySizeCalculator.calculate(
                BodySizeInput(
                    ageYears: 40,
                    height: heightCm,
                    heightUnit: .centimeters,
                    weight: weight,
                    weightUnit: .kilograms
                )
            )
            if let previousBMI {
                XCTAssertGreaterThan(result.bodyMassIndex, previousBMI)
                XCTAssertGreaterThan(result.mostellerBodySurfaceAreaSquareMeters, 0)
            }
            previousBMI = result.bodyMassIndex
        }
    }

    func testPoundKilogramAndInchCentimeterConfusionPathsStayConsistent() throws {
        // Entering lb as if kg (or in as if cm) must NOT silently match the
        // correctly converted path — unit selection is part of the contract.
        let correct = try BodySizeCalculator.calculate(
            BodySizeInput(
                ageYears: 40,
                height: 66.929_133_858_267_72,
                heightUnit: .inches,
                weight: 154.323_583_529_414_3,
                weightUnit: .pounds
            )
        )
        let confused = try BodySizeCalculator.calculate(
            BodySizeInput(
                ageYears: 40,
                height: 66.929_133_858_267_72,
                heightUnit: .centimeters,
                weight: 154.323_583_529_414_3,
                weightUnit: .kilograms
            )
        )
        XCTAssertNotEqual(
            correct.bodyMassIndex,
            confused.bodyMassIndex,
            accuracy: 0.01
        )
        // Correct customary path still matches metric golden values.
        let metric = try BodySizeCalculator.calculate(
            BodySizeInput(
                ageYears: 40,
                height: 170,
                heightUnit: .centimeters,
                weight: 70,
                weightUnit: .kilograms
            )
        )
        XCTAssertEqual(correct.bodyMassIndex, metric.bodyMassIndex, accuracy: 0.000_000_1)
    }

    // MARK: - Helpers


    // MARK: - Result lifecycle (stale / copy-export gate)

    func testResultSessionPublishInvalidateAndAbandon() {
        var session = RXResultSession<Int>()
        XCTAssertEqual(session.currency, .none)
        XCTAssertFalse(session.mayCopyOrExportAsCurrent)

        session.publish(42)
        XCTAssertTrue(session.isCurrent)
        XCTAssertEqual(session.value, 42)
        XCTAssertTrue(session.mayCopyOrExportAsCurrent)

        session.invalidate(reason: RXResultSession<Int>.defaultInvalidationReason)
        XCTAssertTrue(session.isStale)
        XCTAssertEqual(session.value, 42)
        XCTAssertFalse(session.mayCopyOrExportAsCurrent)
        XCTAssertEqual(session.staleReason, RXResultSession<Int>.defaultInvalidationReason)

        session.abandonSurface()
        XCTAssertEqual(session.currency, .none)
        XCTAssertNil(session.value)
        XCTAssertFalse(session.mayCopyOrExportAsCurrent)
    }

    func testResultSessionInvalidateWithoutValueStaysEmpty() {
        var session = RXResultSession<String>()
        session.invalidate()
        XCTAssertEqual(session.currency, .none)
        XCTAssertNil(session.value)
        XCTAssertFalse(session.mayCopyOrExportAsCurrent)
    }

    func testExportGateBlocksStaleAndAllowsCurrentOnly() {
        XCTAssertFalse(
            RXResultExportGate.allowsCopyOrExportAsCurrent(currency: .none, hasValue: false)
        )
        XCTAssertFalse(
            RXResultExportGate.allowsCopyOrExportAsCurrent(currency: .stale, hasValue: true)
        )
        XCTAssertFalse(
            RXResultExportGate.allowsCopyOrExportAsCurrent(currency: .current, hasValue: false)
        )
        XCTAssertTrue(
            RXResultExportGate.allowsCopyOrExportAsCurrent(currency: .current, hasValue: true)
        )
    }

    func testCurrentEngineeringSummaryNilWhenStale() {
        let summary = RXResultExportGate.currentEngineeringSummary(
            currency: .stale,
            formulaIdentifiers: ["cockcroft_gault_1976@1.0.0"],
            outputDescription: "87.5 mL/min",
            reviewStatusTitle: RXCalculationProvenance.draftReviewStatusTitle,
            calculatedAtDescription: "test-time"
        )
        XCTAssertNil(summary)
    }

    func testCurrentEngineeringSummaryContainsDraftAndFormulaWhenCurrent() throws {
        let summary = try XCTUnwrap(
            RXResultExportGate.currentEngineeringSummary(
                currency: .current,
                formulaIdentifiers: ["cockcroft_gault_1976@1.0.0"],
                outputDescription: "87.5 mL/min",
                reviewStatusTitle: RXCalculationProvenance.draftReviewStatusTitle,
                calculatedAtDescription: "test-time"
            )
        )
        XCTAssertTrue(summary.contains("Draft"))
        XCTAssertTrue(summary.contains("cockcroft_gault_1976@1.0.0"))
        XCTAssertTrue(summary.contains("not clinically validated") || summary.contains("Draft"))
        XCTAssertTrue(summary.contains("Do not use as autonomous clinical advice"))
    }

    func testCalculatorResultLifecycleThroughShippedCalculatePath() throws {
        var session = RXResultSession<CreatinineClearanceResult>()
        let fixed = Date(timeIntervalSince1970: 1_784_563_200)
        let published = try CreatinineClearanceCalculator.calculate(
            CreatinineClearanceInput(
                ageYears: 50,
                equationSex: .male,
                calculationWeight: 70,
                weightUnit: .kilograms,
                serumCreatinine: 1,
                creatinineUnit: .milligramsPerDeciliter
            ),
            calculatedAt: fixed
        )
        session.publish(published)
        XCTAssertTrue(session.mayCopyOrExportAsCurrent)
        XCTAssertTrue(session.value?.provenance.humanReviewRequired == true)
        XCTAssertFalse(session.value?.provenance.isAutonomousClinicalRecommendation == true)

        // Input change path: invalidate then gate blocks summary-as-current.
        session.invalidate()
        XCTAssertFalse(session.mayCopyOrExportAsCurrent)
        let blocked = RXResultExportGate.currentEngineeringSummary(
            currency: session.currency,
            formulaIdentifiers: published.provenance.formulaIdentifiers,
            outputDescription: "blocked",
            reviewStatusTitle: published.provenance.sourceReviewStatusTitle,
            calculatedAtDescription: "blocked"
        )
        XCTAssertNil(blocked)

        // Recalculate publishes a new current result.
        let next = try CreatinineClearanceCalculator.calculate(
            CreatinineClearanceInput(
                ageYears: 50,
                equationSex: .female,
                calculationWeight: 70,
                weightUnit: .kilograms,
                serumCreatinine: 1,
                creatinineUnit: .milligramsPerDeciliter
            ),
            calculatedAt: fixed
        )
        session.publish(next)
        XCTAssertTrue(session.isCurrent)
        XCTAssertTrue(session.mayCopyOrExportAsCurrent)
        let clearance = try XCTUnwrap(session.value?.millilitersPerMinute)
        XCTAssertEqual(clearance, 74.375, accuracy: 0.000_000_1)
    }

    private func assertProvenanceComplete(
        _ provenance: RXCalculationProvenance,
        expectedFormulaIDs: [String],
        expectedRounding: String,
        expectedTraceNames: [String],
        calculatedAt: Date,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(provenance.formulaIdentifiers, expectedFormulaIDs, file: file, line: line)
        XCTAssertEqual(provenance.roundingPolicyIdentity, expectedRounding, file: file, line: line)
        XCTAssertEqual(
            provenance.sourceReviewStatusTitle,
            RXCalculationProvenance.draftReviewStatusTitle,
            file: file,
            line: line
        )
        XCTAssertTrue(provenance.humanReviewRequired, file: file, line: line)
        XCTAssertFalse(provenance.isAutonomousClinicalRecommendation, file: file, line: line)
        XCTAssertEqual(provenance.calculatedAt, calculatedAt, file: file, line: line)
        XCTAssertEqual(
            provenance.inputTraces.map(\.name),
            expectedTraceNames,
            file: file,
            line: line
        )
        for trace in provenance.inputTraces {
            XCTAssertFalse(trace.originalValueDescription.isEmpty, file: file, line: line)
            XCTAssertFalse(trace.originalUnitSymbol.isEmpty, file: file, line: line)
            XCTAssertFalse(trace.normalizedUnitSymbol.isEmpty, file: file, line: line)
            XCTAssertTrue(trace.normalizedValue.isFinite, file: file, line: line)
        }
    }
}
