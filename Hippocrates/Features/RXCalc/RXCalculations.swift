import Foundation

enum RXEquationSex: String, CaseIterable, Identifiable, Sendable {
    case female
    case male

    var id: String { rawValue }

    var title: String {
        switch self {
        case .female:
            "Female"
        case .male:
            "Male"
        }
    }
}

enum RXMassUnit: String, CaseIterable, Identifiable, Sendable {
    case kilograms
    case pounds

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .kilograms:
            "kg"
        case .pounds:
            "lb"
        }
    }

    func kilograms(from value: Double) -> Double {
        switch self {
        case .kilograms:
            value
        case .pounds:
            value * 0.453_592_37
        }
    }
}

enum RXLengthUnit: String, CaseIterable, Identifiable, Sendable {
    case centimeters
    case inches

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .centimeters:
            "cm"
        case .inches:
            "in"
        }
    }

    func centimeters(from value: Double) -> Double {
        switch self {
        case .centimeters:
            value
        case .inches:
            value * 2.54
        }
    }
}

enum RXCreatinineUnit: String, CaseIterable, Identifiable, Sendable {
    case milligramsPerDeciliter
    case micromolesPerLiter

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .milligramsPerDeciliter:
            "mg/dL"
        case .micromolesPerLiter:
            "µmol/L"
        }
    }

    func milligramsPerDeciliter(from value: Double) -> Double {
        switch self {
        case .milligramsPerDeciliter:
            value
        case .micromolesPerLiter:
            value / 88.4
        }
    }
}

enum RXDecimalInputParser {
    static func parse(_ text: String, decimalSeparator: String?) -> Double? {
        let activeSeparator = decimalSeparator.flatMap { separator in
            separator.isEmpty ? nil : separator
        } ?? "."
        let commonSeparators = [".", ","]
        guard commonSeparators
            .filter({ $0 != activeSeparator })
            .allSatisfy({ text.contains($0) == false })
        else {
            return nil
        }

        let normalized = activeSeparator == "."
            ? text
            : text.replacingOccurrences(of: activeSeparator, with: ".")
        return Double(normalized)
    }
}

enum RXCalculationError: Error, Equatable, LocalizedError, Sendable {
    case finiteValuesRequired
    case adultAgeRequired
    case adultBMIageRequired
    case ageOutsideEquation
    case positiveWeightRequired
    case positiveHeightRequired
    case positiveCreatinineRequired
    case calculationOutsideNumericRange

    var errorDescription: String? {
        switch self {
        case .finiteValuesRequired:
            "All values must be finite numbers."
        case .adultAgeRequired:
            "This calculator is limited to adults age 18 or older."
        case .adultBMIageRequired:
            "The adult BMI calculator is limited to people age 20 or older."
        case .ageOutsideEquation:
            "RXcalc accepts ages from 18 through 139 years."
        case .positiveWeightRequired:
            "Weight must be greater than zero."
        case .positiveHeightRequired:
            "Height must be greater than zero."
        case .positiveCreatinineRequired:
            "Serum creatinine must be greater than zero."
        case .calculationOutsideNumericRange:
            "The entered values exceed this calculator's supported numeric range."
        }
    }
}

struct CreatinineClearanceInput: Equatable, Sendable {
    let ageYears: Int
    let equationSex: RXEquationSex
    let calculationWeight: Double
    let weightUnit: RXMassUnit
    let serumCreatinine: Double
    let creatinineUnit: RXCreatinineUnit
}

struct CreatinineClearanceResult: Equatable, Sendable {
    let millilitersPerMinute: Double
    let ageYears: Int
    let equationSex: RXEquationSex
    let calculationWeightKilograms: Double
    let serumCreatinineMilligramsPerDeciliter: Double
}

struct CreatinineClearanceCalculator {
    static func calculate(_ input: CreatinineClearanceInput) throws -> CreatinineClearanceResult {
        guard input.ageYears >= 18 else {
            throw RXCalculationError.adultAgeRequired
        }
        guard input.ageYears < 140 else {
            throw RXCalculationError.ageOutsideEquation
        }
        guard input.calculationWeight.isFinite, input.serumCreatinine.isFinite else {
            throw RXCalculationError.finiteValuesRequired
        }

        let weightKilograms = input.weightUnit.kilograms(from: input.calculationWeight)
        let creatinine = input.creatinineUnit.milligramsPerDeciliter(
            from: input.serumCreatinine
        )
        guard weightKilograms.isFinite, creatinine.isFinite else {
            throw RXCalculationError.calculationOutsideNumericRange
        }
        guard weightKilograms > 0 else {
            throw RXCalculationError.positiveWeightRequired
        }
        guard creatinine > 0 else {
            throw RXCalculationError.positiveCreatinineRequired
        }

        let sexCoefficient = input.equationSex == .female ? 0.85 : 1.0
        let numerator = (140.0 - Double(input.ageYears))
            * weightKilograms
            * sexCoefficient
        let denominator = 72.0 * creatinine
        let clearance = numerator / denominator
        guard clearance.isFinite, clearance > 0 else {
            throw RXCalculationError.calculationOutsideNumericRange
        }

        return CreatinineClearanceResult(
            millilitersPerMinute: clearance,
            ageYears: input.ageYears,
            equationSex: input.equationSex,
            calculationWeightKilograms: weightKilograms,
            serumCreatinineMilligramsPerDeciliter: creatinine
        )
    }
}

struct CKDEPI2021CreatinineInput: Equatable, Sendable {
    let ageYears: Int
    let equationSex: RXEquationSex
    let serumCreatinine: Double
    let creatinineUnit: RXCreatinineUnit
}

struct CKDEPI2021CreatinineResult: Equatable, Sendable {
    let indexedMillilitersPerMinutePer1_73SquareMeters: Double
    let ageYears: Int
    let equationSex: RXEquationSex
    let serumCreatinineMilligramsPerDeciliter: Double
}

struct CKDEPI2021CreatinineCalculator {
    static func calculate(
        _ input: CKDEPI2021CreatinineInput
    ) throws -> CKDEPI2021CreatinineResult {
        guard input.ageYears >= 18 else {
            throw RXCalculationError.adultAgeRequired
        }
        guard input.ageYears < 140 else {
            throw RXCalculationError.ageOutsideEquation
        }
        guard input.serumCreatinine.isFinite else {
            throw RXCalculationError.finiteValuesRequired
        }

        let creatinine = input.creatinineUnit.milligramsPerDeciliter(
            from: input.serumCreatinine
        )
        guard creatinine.isFinite else {
            throw RXCalculationError.calculationOutsideNumericRange
        }
        guard creatinine > 0 else {
            throw RXCalculationError.positiveCreatinineRequired
        }

        let kappa = input.equationSex == .female ? 0.7 : 0.9
        let alpha = input.equationSex == .female ? -0.241 : -0.302
        let sexCoefficient = input.equationSex == .female ? 1.012 : 1.0
        let normalizedCreatinine = creatinine / kappa
        guard normalizedCreatinine.isFinite else {
            throw RXCalculationError.calculationOutsideNumericRange
        }
        let lowerSpline = min(normalizedCreatinine, 1.0)
        let upperSpline = max(normalizedCreatinine, 1.0)
        let estimate = 142.0
            * pow(lowerSpline, alpha)
            * pow(upperSpline, -1.2)
            * pow(0.9938, Double(input.ageYears))
            * sexCoefficient
        guard estimate.isFinite, estimate > 0 else {
            throw RXCalculationError.calculationOutsideNumericRange
        }

        return CKDEPI2021CreatinineResult(
            indexedMillilitersPerMinutePer1_73SquareMeters: estimate,
            ageYears: input.ageYears,
            equationSex: input.equationSex,
            serumCreatinineMilligramsPerDeciliter: creatinine
        )
    }
}

struct BodySizeInput: Equatable, Sendable {
    let ageYears: Int
    let height: Double
    let heightUnit: RXLengthUnit
    let weight: Double
    let weightUnit: RXMassUnit
}

struct BodySizeResult: Equatable, Sendable {
    let bodyMassIndex: Double
    let mostellerBodySurfaceAreaSquareMeters: Double
    let ageYears: Int
    let heightCentimeters: Double
    let weightKilograms: Double
}

struct BodySizeCalculator {
    static func calculate(_ input: BodySizeInput) throws -> BodySizeResult {
        guard input.ageYears >= 20 else {
            throw RXCalculationError.adultBMIageRequired
        }
        guard input.ageYears < 140 else {
            throw RXCalculationError.ageOutsideEquation
        }
        guard input.height.isFinite, input.weight.isFinite else {
            throw RXCalculationError.finiteValuesRequired
        }

        let heightCentimeters = input.heightUnit.centimeters(from: input.height)
        let weightKilograms = input.weightUnit.kilograms(from: input.weight)
        guard heightCentimeters.isFinite, weightKilograms.isFinite else {
            throw RXCalculationError.calculationOutsideNumericRange
        }
        guard heightCentimeters > 0 else {
            throw RXCalculationError.positiveHeightRequired
        }
        guard weightKilograms > 0 else {
            throw RXCalculationError.positiveWeightRequired
        }

        let heightMeters = heightCentimeters * 0.01
        let bodyMassIndex = weightKilograms / (heightMeters * heightMeters)
        let mostellerRadicand = (heightCentimeters * weightKilograms) / 3_600.0
        let bodySurfaceArea = mostellerRadicand.squareRoot()
        guard
            bodyMassIndex.isFinite, bodyMassIndex > 0,
            bodySurfaceArea.isFinite, bodySurfaceArea > 0
        else {
            throw RXCalculationError.calculationOutsideNumericRange
        }

        return BodySizeResult(
            bodyMassIndex: bodyMassIndex,
            mostellerBodySurfaceAreaSquareMeters: bodySurfaceArea,
            ageYears: input.ageYears,
            heightCentimeters: heightCentimeters,
            weightKilograms: weightKilograms
        )
    }
}
