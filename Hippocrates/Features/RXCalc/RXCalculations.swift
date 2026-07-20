import Foundation

// MARK: - Equation sex

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

// MARK: - Dimensional kinds and typed quantities
//
// Unit kinds are separated at the type level so a mass quantity cannot be
// passed where length or creatinine concentration is required. Conversion to a
// single canonical representation happens only inside the matching kind.

enum RXUnitKind: String, Sendable, Equatable, CaseIterable {
    case mass
    case length
    case creatinineConcentration
}

/// Units that convert a raw numeric entry into one canonical SI-ish value for
/// a single physical kind. Different kinds never share a concrete unit type.
protocol RXUnitConverting: Equatable, Hashable, Sendable {
    static var kind: RXUnitKind { get }
    var symbol: String { get }
    /// Convert `value` in this unit to the kind's canonical representation.
    func canonicalValue(from value: Double) -> Double
}

/// A numeric measurement tagged with its unit. Incompatible kinds cannot be
/// mixed without an explicit, reviewed conversion path (none exists across kinds).
struct RXQuantity<Unit: RXUnitConverting>: Equatable, Sendable {
    let value: Double
    let unit: Unit

    init(_ value: Double, unit: Unit) {
        self.value = value
        self.unit = unit
    }

    var kind: RXUnitKind { Unit.kind }

    /// Canonical value for this quantity's kind, or a validation error.
    func canonical() throws -> Double {
        guard value.isFinite else {
            throw RXCalculationError.finiteValuesRequired
        }
        let converted = unit.canonicalValue(from: value)
        guard converted.isFinite else {
            throw RXCalculationError.calculationOutsideNumericRange
        }
        return converted
    }
}

enum RXMassUnit: String, CaseIterable, Identifiable, Sendable, RXUnitConverting {
    case kilograms
    case pounds

    static var kind: RXUnitKind { .mass }

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .kilograms:
            "kg"
        case .pounds:
            "lb"
        }
    }

    /// NIST SP 811 Appendix B.8: 1 lb = 0.45359237 kg (exact).
    func canonicalValue(from value: Double) -> Double {
        kilograms(from: value)
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

enum RXLengthUnit: String, CaseIterable, Identifiable, Sendable, RXUnitConverting {
    case centimeters
    case inches

    static var kind: RXUnitKind { .length }

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .centimeters:
            "cm"
        case .inches:
            "in"
        }
    }

    /// NIST SP 811 Appendix B.8: 1 in = 2.54 cm (exact).
    func canonicalValue(from value: Double) -> Double {
        centimeters(from: value)
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

enum RXCreatinineUnit: String, CaseIterable, Identifiable, Sendable, RXUnitConverting {
    case milligramsPerDeciliter
    case micromolesPerLiter

    static var kind: RXUnitKind { .creatinineConcentration }

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .milligramsPerDeciliter:
            "mg/dL"
        case .micromolesPerLiter:
            "µmol/L"
        }
    }

    /// Conventional factor used by NKF/NIDDK CKD-EPI guidance: mg/dL = µmol/L / 88.4.
    func canonicalValue(from value: Double) -> Double {
        milligramsPerDeciliter(from: value)
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

/// Runtime dimensional guard for homogeneous quantity collections. Cross-kind
/// combinations are a compile-time error when using `RXQuantity`; this helper
/// documents and tests the kind identity for same-kind arrays and conversions.
enum RXDimensionalAnalysis {
    static func kind<Unit: RXUnitConverting>(of quantity: RXQuantity<Unit>) -> RXUnitKind {
        quantity.kind
    }

    /// Returns true only when every quantity shares the same unit kind (always
    /// true for a homogeneous `RXQuantity` array; useful in generic helpers).
    static func areCompatible<Unit: RXUnitConverting>(_ quantities: [RXQuantity<Unit>]) -> Bool {
        guard let first = quantities.first else { return true }
        return quantities.allSatisfy { $0.kind == first.kind }
    }

    /// Rejects using a quantity whose declared kind does not match `expected`.
    static func requireKind<Unit: RXUnitConverting>(
        _ quantity: RXQuantity<Unit>,
        expected: RXUnitKind
    ) throws {
        guard quantity.kind == expected else {
            throw RXCalculationError.finiteValuesRequired
        }
    }
}

// MARK: - Decimal input parsing

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

// MARK: - Errors

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

// MARK: - Provenance (reproducibility + human-review boundary)

/// One entered quantity after unit normalization, for result reproducibility.
struct RXInputTrace: Equatable, Sendable {
    let name: String
    let originalValueDescription: String
    let originalUnitSymbol: String
    let normalizedValue: Double
    let normalizedUnitSymbol: String
}

/// Stable identities for display-only rounding policies. Calculation results
/// always retain full Double precision; these strings never alter arithmetic.
enum RXRoundingPolicyIdentity: String, Sendable, Equatable {
    case cockcroftGaultDisplayOneDecimal = "retain_full_precision;display_1_decimal_place"
    case ckdEPI2021DisplayWholeNumber = "retain_full_precision;display_whole_number_nkf"
    case bodySizeDisplayTwoDecimals = "retain_full_precision;display_2_decimal_places"
}

/// Enough information to reproduce a successful calculation without re-entering
/// the form. Results are always Draft / human-review-required and never an
/// autonomous clinical recommendation or dosing instruction.
struct RXCalculationProvenance: Equatable, Sendable {
    let formulaIdentifiers: [String]
    let roundingPolicyIdentity: String
    let sourceReviewStatusTitle: String
    /// Always true for shipped R1 formulas (P-008 activation is not implemented).
    let humanReviewRequired: Bool
    /// Always false: RXcalc performs source-identified arithmetic only.
    let isAutonomousClinicalRecommendation: Bool
    let calculatedAt: Date
    let inputTraces: [RXInputTrace]

    /// Must stay aligned with `RXClinicalReviewStatus.draft.title` (fail-closed Draft).
    static let draftReviewStatusTitle = "Draft — independent clinical review required"

    static func draft(
        formulaIdentifiers: [String],
        roundingPolicyIdentity: RXRoundingPolicyIdentity,
        calculatedAt: Date,
        inputTraces: [RXInputTrace]
    ) -> RXCalculationProvenance {
        RXCalculationProvenance(
            formulaIdentifiers: formulaIdentifiers,
            roundingPolicyIdentity: roundingPolicyIdentity.rawValue,
            sourceReviewStatusTitle: draftReviewStatusTitle,
            humanReviewRequired: true,
            isAutonomousClinicalRecommendation: false,
            calculatedAt: calculatedAt,
            inputTraces: inputTraces
        )
    }
}

// MARK: - Cockcroft–Gault

struct CreatinineClearanceInput: Equatable, Sendable {
    let ageYears: Int
    let equationSex: RXEquationSex
    let calculationWeight: Double
    let weightUnit: RXMassUnit
    let serumCreatinine: Double
    let creatinineUnit: RXCreatinineUnit

    /// Typed-quantity convenience: mass and creatinine kinds are distinct types.
    init(
        ageYears: Int,
        equationSex: RXEquationSex,
        calculationWeight: RXQuantity<RXMassUnit>,
        serumCreatinine: RXQuantity<RXCreatinineUnit>
    ) {
        self.ageYears = ageYears
        self.equationSex = equationSex
        self.calculationWeight = calculationWeight.value
        self.weightUnit = calculationWeight.unit
        self.serumCreatinine = serumCreatinine.value
        self.creatinineUnit = serumCreatinine.unit
    }

    init(
        ageYears: Int,
        equationSex: RXEquationSex,
        calculationWeight: Double,
        weightUnit: RXMassUnit,
        serumCreatinine: Double,
        creatinineUnit: RXCreatinineUnit
    ) {
        self.ageYears = ageYears
        self.equationSex = equationSex
        self.calculationWeight = calculationWeight
        self.weightUnit = weightUnit
        self.serumCreatinine = serumCreatinine
        self.creatinineUnit = creatinineUnit
    }

    var weightQuantity: RXQuantity<RXMassUnit> {
        RXQuantity(calculationWeight, unit: weightUnit)
    }

    var creatinineQuantity: RXQuantity<RXCreatinineUnit> {
        RXQuantity(serumCreatinine, unit: creatinineUnit)
    }
}

struct CreatinineClearanceResult: Equatable, Sendable {
    let millilitersPerMinute: Double
    let ageYears: Int
    let equationSex: RXEquationSex
    let calculationWeightKilograms: Double
    let serumCreatinineMilligramsPerDeciliter: Double
    let provenance: RXCalculationProvenance
}

struct CreatinineClearanceCalculator {
    static let formulaIdentifier = "cockcroft_gault_1976@1.0.0"

    static func calculate(
        _ input: CreatinineClearanceInput,
        calculatedAt: Date = .now
    ) throws -> CreatinineClearanceResult {
        guard input.ageYears >= 18 else {
            throw RXCalculationError.adultAgeRequired
        }
        guard input.ageYears < 140 else {
            throw RXCalculationError.ageOutsideEquation
        }
        guard input.calculationWeight.isFinite, input.serumCreatinine.isFinite else {
            throw RXCalculationError.finiteValuesRequired
        }

        try RXDimensionalAnalysis.requireKind(input.weightQuantity, expected: .mass)
        try RXDimensionalAnalysis.requireKind(input.creatinineQuantity, expected: .creatinineConcentration)

        let weightKilograms = try input.weightQuantity.canonical()
        let creatinine = try input.creatinineQuantity.canonical()
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

        let provenance = RXCalculationProvenance.draft(
            formulaIdentifiers: [formulaIdentifier],
            roundingPolicyIdentity: .cockcroftGaultDisplayOneDecimal,
            calculatedAt: calculatedAt,
            inputTraces: [
                RXInputTrace(
                    name: "ageYears",
                    originalValueDescription: String(input.ageYears),
                    originalUnitSymbol: "years",
                    normalizedValue: Double(input.ageYears),
                    normalizedUnitSymbol: "years"
                ),
                RXInputTrace(
                    name: "equationSex",
                    originalValueDescription: input.equationSex.rawValue,
                    originalUnitSymbol: "equation_sex",
                    normalizedValue: input.equationSex == .female ? 0.85 : 1.0,
                    normalizedUnitSymbol: "sex_coefficient"
                ),
                RXInputTrace(
                    name: "calculationWeight",
                    originalValueDescription: String(input.calculationWeight),
                    originalUnitSymbol: input.weightUnit.symbol,
                    normalizedValue: weightKilograms,
                    normalizedUnitSymbol: "kg"
                ),
                RXInputTrace(
                    name: "serumCreatinine",
                    originalValueDescription: String(input.serumCreatinine),
                    originalUnitSymbol: input.creatinineUnit.symbol,
                    normalizedValue: creatinine,
                    normalizedUnitSymbol: "mg/dL"
                ),
            ]
        )

        return CreatinineClearanceResult(
            millilitersPerMinute: clearance,
            ageYears: input.ageYears,
            equationSex: input.equationSex,
            calculationWeightKilograms: weightKilograms,
            serumCreatinineMilligramsPerDeciliter: creatinine,
            provenance: provenance
        )
    }
}

// MARK: - 2021 CKD-EPI creatinine

struct CKDEPI2021CreatinineInput: Equatable, Sendable {
    let ageYears: Int
    let equationSex: RXEquationSex
    let serumCreatinine: Double
    let creatinineUnit: RXCreatinineUnit

    init(
        ageYears: Int,
        equationSex: RXEquationSex,
        serumCreatinine: RXQuantity<RXCreatinineUnit>
    ) {
        self.ageYears = ageYears
        self.equationSex = equationSex
        self.serumCreatinine = serumCreatinine.value
        self.creatinineUnit = serumCreatinine.unit
    }

    init(
        ageYears: Int,
        equationSex: RXEquationSex,
        serumCreatinine: Double,
        creatinineUnit: RXCreatinineUnit
    ) {
        self.ageYears = ageYears
        self.equationSex = equationSex
        self.serumCreatinine = serumCreatinine
        self.creatinineUnit = creatinineUnit
    }

    var creatinineQuantity: RXQuantity<RXCreatinineUnit> {
        RXQuantity(serumCreatinine, unit: creatinineUnit)
    }
}

struct CKDEPI2021CreatinineResult: Equatable, Sendable {
    let indexedMillilitersPerMinutePer1_73SquareMeters: Double
    let ageYears: Int
    let equationSex: RXEquationSex
    let serumCreatinineMilligramsPerDeciliter: Double
    let provenance: RXCalculationProvenance
}

struct CKDEPI2021CreatinineCalculator {
    static let formulaIdentifier = "ckd_epi_creatinine_2021@1.0.0"

    static func calculate(
        _ input: CKDEPI2021CreatinineInput,
        calculatedAt: Date = .now
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

        try RXDimensionalAnalysis.requireKind(
            input.creatinineQuantity,
            expected: .creatinineConcentration
        )

        let creatinine = try input.creatinineQuantity.canonical()
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

        let provenance = RXCalculationProvenance.draft(
            formulaIdentifiers: [formulaIdentifier],
            roundingPolicyIdentity: .ckdEPI2021DisplayWholeNumber,
            calculatedAt: calculatedAt,
            inputTraces: [
                RXInputTrace(
                    name: "ageYears",
                    originalValueDescription: String(input.ageYears),
                    originalUnitSymbol: "years",
                    normalizedValue: Double(input.ageYears),
                    normalizedUnitSymbol: "years"
                ),
                RXInputTrace(
                    name: "equationSex",
                    originalValueDescription: input.equationSex.rawValue,
                    originalUnitSymbol: "equation_sex",
                    normalizedValue: sexCoefficient,
                    normalizedUnitSymbol: "sex_coefficient"
                ),
                RXInputTrace(
                    name: "serumCreatinine",
                    originalValueDescription: String(input.serumCreatinine),
                    originalUnitSymbol: input.creatinineUnit.symbol,
                    normalizedValue: creatinine,
                    normalizedUnitSymbol: "mg/dL"
                ),
            ]
        )

        return CKDEPI2021CreatinineResult(
            indexedMillilitersPerMinutePer1_73SquareMeters: estimate,
            ageYears: input.ageYears,
            equationSex: input.equationSex,
            serumCreatinineMilligramsPerDeciliter: creatinine,
            provenance: provenance
        )
    }
}

// MARK: - Body size (BMI + Mosteller BSA)

struct BodySizeInput: Equatable, Sendable {
    let ageYears: Int
    let height: Double
    let heightUnit: RXLengthUnit
    let weight: Double
    let weightUnit: RXMassUnit

    init(
        ageYears: Int,
        height: RXQuantity<RXLengthUnit>,
        weight: RXQuantity<RXMassUnit>
    ) {
        self.ageYears = ageYears
        self.height = height.value
        self.heightUnit = height.unit
        self.weight = weight.value
        self.weightUnit = weight.unit
    }

    init(
        ageYears: Int,
        height: Double,
        heightUnit: RXLengthUnit,
        weight: Double,
        weightUnit: RXMassUnit
    ) {
        self.ageYears = ageYears
        self.height = height
        self.heightUnit = heightUnit
        self.weight = weight
        self.weightUnit = weightUnit
    }

    var heightQuantity: RXQuantity<RXLengthUnit> {
        RXQuantity(height, unit: heightUnit)
    }

    var weightQuantity: RXQuantity<RXMassUnit> {
        RXQuantity(weight, unit: weightUnit)
    }
}

struct BodySizeResult: Equatable, Sendable {
    let bodyMassIndex: Double
    let mostellerBodySurfaceAreaSquareMeters: Double
    let ageYears: Int
    let heightCentimeters: Double
    let weightKilograms: Double
    let provenance: RXCalculationProvenance
}

struct BodySizeCalculator {
    static let bmiFormulaIdentifier = "body_mass_index_cdc_metric@1.0.0"
    static let mostellerFormulaIdentifier = "body_size_mosteller_1987@1.0.0"

    static func calculate(
        _ input: BodySizeInput,
        calculatedAt: Date = .now
    ) throws -> BodySizeResult {
        guard input.ageYears >= 20 else {
            throw RXCalculationError.adultBMIageRequired
        }
        guard input.ageYears < 140 else {
            throw RXCalculationError.ageOutsideEquation
        }
        guard input.height.isFinite, input.weight.isFinite else {
            throw RXCalculationError.finiteValuesRequired
        }

        try RXDimensionalAnalysis.requireKind(input.heightQuantity, expected: .length)
        try RXDimensionalAnalysis.requireKind(input.weightQuantity, expected: .mass)

        let heightCentimeters = try input.heightQuantity.canonical()
        let weightKilograms = try input.weightQuantity.canonical()
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

        let provenance = RXCalculationProvenance.draft(
            formulaIdentifiers: [bmiFormulaIdentifier, mostellerFormulaIdentifier],
            roundingPolicyIdentity: .bodySizeDisplayTwoDecimals,
            calculatedAt: calculatedAt,
            inputTraces: [
                RXInputTrace(
                    name: "ageYears",
                    originalValueDescription: String(input.ageYears),
                    originalUnitSymbol: "years",
                    normalizedValue: Double(input.ageYears),
                    normalizedUnitSymbol: "years"
                ),
                RXInputTrace(
                    name: "height",
                    originalValueDescription: String(input.height),
                    originalUnitSymbol: input.heightUnit.symbol,
                    normalizedValue: heightCentimeters,
                    normalizedUnitSymbol: "cm"
                ),
                RXInputTrace(
                    name: "weight",
                    originalValueDescription: String(input.weight),
                    originalUnitSymbol: input.weightUnit.symbol,
                    normalizedValue: weightKilograms,
                    normalizedUnitSymbol: "kg"
                ),
            ]
        )

        return BodySizeResult(
            bodyMassIndex: bodyMassIndex,
            mostellerBodySurfaceAreaSquareMeters: bodySurfaceArea,
            ageYears: input.ageYears,
            heightCentimeters: heightCentimeters,
            weightKilograms: weightKilograms,
            provenance: provenance
        )
    }
}

// MARK: - Result lifecycle (current vs stale; copy/export gate)
//
// RXcalc results are never durable. This session model makes it impossible to
// treat a superseded calculation as the current output after inputs, units, or
// surface context change. It does not store PHI and does not authorize clinical use.

/// Currency of a calculator result on the working surface.
enum RXResultCurrency: String, Equatable, Sendable {
    /// No calculation has been published on this surface.
    case none
    /// Latest successful calculation for the current inputs.
    case current
    /// A prior calculation remains visible only as historical/stale context.
    case stale
}

/// Pure, Foundation-only lifecycle for one calculator surface.
/// Copy/export-as-current is allowed only while `currency == .current`.
struct RXResultSession<Value: Equatable & Sendable>: Equatable, Sendable {
    private(set) var currency: RXResultCurrency = .none
    private(set) var value: Value?
    /// Human-readable reason the last result is no longer current (stale only).
    private(set) var staleReason: String?

    var isCurrent: Bool {
        currency == .current && value != nil
    }

    var isStale: Bool {
        currency == .stale && value != nil
    }

    /// Gate for any copy/share/export path that would present numbers as the
    /// active calculation. Stale and empty sessions always return false.
    var mayCopyOrExportAsCurrent: Bool {
        isCurrent
    }

    /// Fixed labels for UI / VoiceOver (no dynamic string interpolation required).
    static var staleBannerTitle: String {
        "Stale result — not current"
    }

    static var staleCopyBlockedMessage: String {
        "Copy and export as a current result are blocked until you recalculate."
    }

    static var defaultInvalidationReason: String {
        "An input, unit, or working context changed after this calculation."
    }

    static var surfaceAbandonedReason: String {
        "Left the calculator surface or the app left the active state."
    }

    static var dynamicTypeChangedReason: String {
        "Dynamic Type size changed after this calculation."
    }

    mutating func publish(_ newValue: Value) {
        value = newValue
        currency = .current
        staleReason = nil
    }

    /// Marks any published value stale so it cannot be treated as current.
    /// No-op when nothing has been published.
    mutating func invalidate(reason: String = Self.defaultInvalidationReason) {
        guard value != nil else {
            currency = .none
            staleReason = nil
            return
        }
        currency = .stale
        staleReason = reason
    }

    /// Drops all visible result state (used on clear, hard reset, abandon).
    mutating func clear() {
        value = nil
        currency = .none
        staleReason = nil
    }

    /// Leaving the calculator, backgrounding, or relaunching must not leave a
    /// prior result looking current. Clears rather than soft-stales.
    mutating func abandonSurface() {
        clear()
    }
}

/// Central gate used by any copy/export seam. Pure function so tests drive the
/// shipped decision without re-implementing UI policy.
enum RXResultExportGate {
    /// Returns whether a payload may be presented as the *current* calculation.
    /// Draft clinical status does not by itself block copy of engineering
    /// numbers, but stale/none always do.
    static func allowsCopyOrExportAsCurrent(
        currency: RXResultCurrency,
        hasValue: Bool
    ) -> Bool {
        currency == .current && hasValue
    }

    /// Builds a non-PHI engineering summary only when the gate allows it.
    /// Returns nil when the session is not current (callers must not invent text).
    static func currentEngineeringSummary(
        currency: RXResultCurrency,
        formulaIdentifiers: [String],
        outputDescription: String,
        reviewStatusTitle: String,
        calculatedAtDescription: String
    ) -> String? {
        guard allowsCopyOrExportAsCurrent(currency: currency, hasValue: true) else {
            return nil
        }
        var lines: [String] = [
            "RXcalc Draft engineering output — not clinically validated",
            reviewStatusTitle,
            "Calculated at: " + calculatedAtDescription,
            "Output: " + outputDescription,
        ]
        for identifier in formulaIdentifiers {
            lines.append("Formula: " + identifier)
        }
        lines.append("Do not use as autonomous clinical advice or a dose.")
        return lines.joined(separator: "\n")
    }
}
