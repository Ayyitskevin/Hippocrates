// Linux pure-function safety driver.
// Compiles against the shipped Foundation-only sources:
//   Hippocrates/Features/RXCalc/RXCalculations.swift
//   Hippocrates/Safety/DeidentificationScanner.swift
// Asserts provenance, typed units, golden vectors, and adversarial de-id
// fixtures without XCTest or the full app target.
//
// Usage (from repo root, e.g. under Docker swift:6.1):
//   swiftc -o /tmp/hippo-safety \
//     Hippocrates/Features/RXCalc/RXCalculations.swift \
//     Hippocrates/Safety/DeidentificationScanner.swift \
//     Scripts/linux-pure-safety-driver.swift \
//   && /tmp/hippo-safety

import Foundation

// MARK: - Minimal harness

private struct AssertionError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if condition() == false {
        throw AssertionError(message: message)
    }
}

private func expectEqual<T: Equatable>(_ left: T, _ right: T, _ message: String) throws {
    try expect(left == right, "\(message): \(left) != \(right)")
}

private func expectEqual(
    _ left: Double,
    _ right: Double,
    accuracy: Double,
    _ message: String
) throws {
    try expect(abs(left - right) <= accuracy, "\(message): \(left) !~ \(right) ±\(accuracy)")
}

// MARK: - RXcalc provenance + golden vectors

private func testCreatinineClearanceProvenanceAndGolden() throws {
    let fixed = Date(timeIntervalSince1970: 1_784_563_200)
    let male = try CreatinineClearanceCalculator.calculate(
        CreatinineClearanceInput(
            ageYears: 50,
            equationSex: .male,
            calculationWeight: RXQuantity(70, unit: .kilograms),
            serumCreatinine: RXQuantity(1, unit: .milligramsPerDeciliter)
        ),
        calculatedAt: fixed
    )
    try expectEqual(male.millilitersPerMinute, 87.5, accuracy: 1e-9, "CG male golden")
    try expectEqual(
        male.provenance.formulaIdentifiers,
        [CreatinineClearanceCalculator.formulaIdentifier],
        "CG formula id"
    )
    try expect(male.provenance.humanReviewRequired, "CG human review")
    try expect(
        male.provenance.isAutonomousClinicalRecommendation == false,
        "CG not autonomous recommendation"
    )
    try expectEqual(male.provenance.calculatedAt, fixed, "CG timestamp")
    try expectEqual(
        male.provenance.roundingPolicyIdentity,
        RXRoundingPolicyIdentity.cockcroftGaultDisplayOneDecimal.rawValue,
        "CG rounding identity"
    )
    try expect(
        male.provenance.inputTraces.contains { $0.name == "calculationWeight" && $0.normalizedUnitSymbol == "kg" },
        "CG weight normalized to kg"
    )

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
    try expectEqual(female.millilitersPerMinute, 74.375, accuracy: 1e-9, "CG female golden")
    try expectEqual(
        female.millilitersPerMinute,
        male.millilitersPerMinute * 0.85,
        accuracy: 1e-9,
        "CG female coefficient"
    )
}

private func testCKDEPIVectorsAndDisplayOnlyRounding() throws {
    let fixtures: [(Int, RXEquationSex, Double, Double)] = [
        (18, .male, 0.90, 127),
        (18, .male, 0.91, 125),
        (18, .female, 0.70, 128),
        (18, .female, 0.71, 126),
        (90, .male, 0.50, 97),
        (90, .male, 1.50, 44),
        (90, .female, 0.50, 89),
        (90, .female, 1.50, 33),
    ]
    for (age, sex, scr, expectedWhole) in fixtures {
        let result = try CKDEPI2021CreatinineCalculator.calculate(
            CKDEPI2021CreatinineInput(
                ageYears: age,
                equationSex: sex,
                serumCreatinine: scr,
                creatinineUnit: .milligramsPerDeciliter
            )
        )
        try expectEqual(
            result.indexedMillilitersPerMinutePer1_73SquareMeters.rounded(),
            expectedWhole,
            "CKD-EPI vector age=\(age) sex=\(sex) scr=\(scr)"
        )
        try expect(
            result.provenance.humanReviewRequired
                && result.provenance.isAutonomousClinicalRecommendation == false,
            "CKD-EPI human-review boundary"
        )
        // Full precision retained; whole-number display is not the stored value.
        try expect(
            result.indexedMillilitersPerMinutePer1_73SquareMeters
                != result.indexedMillilitersPerMinutePer1_73SquareMeters.rounded()
                || result.indexedMillilitersPerMinutePer1_73SquareMeters
                    .truncatingRemainder(dividingBy: 1) == 0,
            "CKD-EPI retains calculation value for vector age=\(age)"
        )
    }
}

private func testBodySizeAndUnitKinds() throws {
    let result = try BodySizeCalculator.calculate(
        BodySizeInput(
            ageYears: 40,
            height: RXQuantity(170, unit: .centimeters),
            weight: RXQuantity(70, unit: .kilograms)
        )
    )
    try expectEqual(result.bodyMassIndex, 24.221_453_287_197_235, accuracy: 1e-9, "BMI golden")
    try expectEqual(
        result.mostellerBodySurfaceAreaSquareMeters,
        1.818_118_685_772_619,
        accuracy: 1e-9,
        "Mosteller golden"
    )
    try expectEqual(
        result.provenance.formulaIdentifiers,
        [
            BodySizeCalculator.bmiFormulaIdentifier,
            BodySizeCalculator.mostellerFormulaIdentifier,
        ],
        "body-size formula ids"
    )

    try expectEqual(RXMassUnit.kind, .mass, "mass kind")
    try expectEqual(RXLengthUnit.kind, .length, "length kind")
    try expectEqual(RXCreatinineUnit.kind, .creatinineConcentration, "scr kind")

    let lb = RXQuantity(10, unit: RXMassUnit.pounds)
    try expectEqual(try lb.canonical(), 4.535_923_7, accuracy: 1e-9, "lb→kg NIST")
    do {
        try RXDimensionalAnalysis.requireKind(lb, expected: .length)
        throw AssertionError(message: "mass must not satisfy length kind")
    } catch is AssertionError {
        throw AssertionError(message: "mass must not satisfy length kind")
    } catch {
        // expected RXCalculationError path from requireKind
    }
}

private func testBoundaries() throws {
    do {
        _ = try CreatinineClearanceCalculator.calculate(
            CreatinineClearanceInput(
                ageYears: 17,
                equationSex: .male,
                calculationWeight: 70,
                weightUnit: .kilograms,
                serumCreatinine: 1,
                creatinineUnit: .milligramsPerDeciliter
            )
        )
        throw AssertionError(message: "age 17 must fail")
    } catch let error as RXCalculationError {
        try expectEqual(error, .adultAgeRequired, "adult age")
    }

    do {
        _ = try BodySizeCalculator.calculate(
            BodySizeInput(
                ageYears: 19,
                height: 170,
                heightUnit: .centimeters,
                weight: 70,
                weightUnit: .kilograms
            )
        )
        throw AssertionError(message: "age 19 BMI must fail")
    } catch let error as RXCalculationError {
        try expectEqual(error, .adultBMIageRequired, "BMI age")
    }

    do {
        _ = try CreatinineClearanceCalculator.calculate(
            CreatinineClearanceInput(
                ageYears: 50,
                equationSex: .male,
                calculationWeight: 0,
                weightUnit: .kilograms,
                serumCreatinine: 1,
                creatinineUnit: .milligramsPerDeciliter
            )
        )
        throw AssertionError(message: "zero weight must fail")
    } catch let error as RXCalculationError {
        try expectEqual(error, .positiveWeightRequired, "positive weight")
    }
}

// MARK: - De-identification adversarial fixtures (synthetic only)

private func testResultLifecycleGates() throws {
    var session = RXResultSession<Double>()
    session.publish(87.5)
    try expect(session.mayCopyOrExportAsCurrent, "current may copy")
    session.invalidate()
    try expect(session.mayCopyOrExportAsCurrent == false, "stale blocks copy")
    try expect(
        RXResultExportGate.currentEngineeringSummary(
            currency: .stale,
            formulaIdentifiers: ["cockcroft_gault_1976@1.0.0"],
            outputDescription: "x",
            reviewStatusTitle: "Draft",
            calculatedAtDescription: "t"
        ) == nil,
        "stale summary nil"
    )
    let current = RXResultExportGate.currentEngineeringSummary(
        currency: .current,
        formulaIdentifiers: ["cockcroft_gault_1976@1.0.0"],
        outputDescription: "87.5 mL per min",
        reviewStatusTitle: RXCalculationProvenance.draftReviewStatusTitle,
        calculatedAtDescription: "t"
    )
    try expect(current != nil, "current summary present")
    try expect(current?.contains("Draft") == true, "draft label in summary")
    session.abandonSurface()
    try expect(session.currency == .none, "abandon clears")
}

private func testDeidentificationAdversarial() throws {
    func categories(_ text: String) -> [DeidentificationFinding.Category] {
        DeidentificationScanner.findings(fieldName: "questionText", text: text).map(\.category)
    }

    let truePositives: [(String, DeidentificationFinding.Category)] = [
        ("note MRN 12 345 678 filed", .medicalRecordNumber),
        ("mrn#99887766 reviewed", .medicalRecordNumber),
        ("room no 12 isolation", .roomOrBed),
        ("Bed#3A contact", .roomOrBed),
        ("pt 102 y.o. admitted", .ageOver89),
        ("age over 90 per note", .ageOver89),
        ("phone 5551234567 for callback", .phoneNumber),
        ("call (555) 123-4567 for follow-up", .phoneNumber),
        ("admitted 3/14/2026 overnight", .date),
        ("discharged March 14, 2026", .date),
    ]
    for (text, expected) in truePositives {
        try expect(
            categories(text).contains(expected),
            "expected \(expected) in: \(text); got \(categories(text))"
        )
    }

    let clean = [
        "Vancomycin 1250 mg IV q12h",
        "An 89-year-old adult with stable creatinine",
        "Store at room temperature",
        "NDC 00093-0058-01 on the shelf",
        "Linezolid and sertraline carry a serotonin syndrome interaction risk",
    ]
    for text in clean {
        try expect(categories(text).isEmpty, "clean text flagged: \(text) -> \(categories(text))")
    }

    let findings = DeidentificationScanner.findings(
        fieldName: "background",
        text: "MRN: 12345678 and Room 12"
    )
    try expect(findings.isEmpty == false, "findings present")
    let blocked = DeidentificationScanner.unacknowledgedFindings(findings, acknowledging: [])
    try expectEqual(blocked.count, findings.count, "unacknowledged blocks")
    let cleared = DeidentificationScanner.unacknowledgedFindings(
        findings,
        acknowledging: findings.map {
            DeidentificationAcknowledgment(fieldName: $0.fieldName, matchedText: $0.matchedText)
        }
    )
    try expect(cleared.isEmpty, "full acknowledgment clears")
}

// MARK: - Entry

@main
enum LinuxPureSafetyDriver {
    static func main() {
        do {
            try testCreatinineClearanceProvenanceAndGolden()
            try testCKDEPIVectorsAndDisplayOnlyRounding()
            try testBodySizeAndUnitKinds()
            try testBoundaries()
            try testResultLifecycleGates()
            try testDeidentificationAdversarial()
            print("linux-pure-safety-driver: ALL ASSERTIONS PASSED")
        } catch {
            fputs("linux-pure-safety-driver FAILED: \(error)\n", stderr)
            exit(1)
        }
    }
}
