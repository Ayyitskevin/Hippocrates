import Foundation
import SwiftUI

struct RXCalcView: View {
    @State private var searchText = ""

    private var visibleCalculators: [RXCalculatorKind] {
        RXCalculatorKind.allCases.filter { calculator in
            calculator.matches(searchText: searchText)
        }
    }

    private var visibleCategories: [RXCalculatorCategory] {
        Dictionary(grouping: visibleCalculators) { calculator in
            calculator.descriptor.category
        }
        .map { category, calculators in
            RXCalculatorCategory(
                name: category,
                calculators: calculators.sorted { lhs, rhs in
                    lhs.descriptor.shortTitle.localizedStandardCompare(
                        rhs.descriptor.shortTitle
                    ) == .orderedAscending
                }
            )
        }
        .sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private var catalogReviewStatus: RXClinicalReviewStatus {
        .draft
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            catalogReviewStatus.catalogTitle,
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.headline)
                        .foregroundStyle(.orange)

                        Text(catalogReviewStatus.catalogMessage)
                            .font(.subheadline)

                        Text(
                            "Inputs and results stay on this screen and are never saved. Do not enter patient identifiers."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                if visibleCategories.isEmpty {
                    Section("Calculators") {
                        Text("No calculators match this search.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(visibleCategories) { category in
                        Section(category.name) {
                            ForEach(category.calculators) { calculator in
                                NavigationLink(value: calculator) {
                                    RXCalculatorRow(calculator: calculator)
                                }
                                .accessibilityIdentifier(
                                    "rxcalc.catalog." + calculator.rawValue
                                )
                            }
                        }
                    }
                }
            }
            .navigationTitle("RXcalc")
            .searchable(
                text: $searchText,
                prompt: "Search formulas, evidence, or categories"
            )
            .navigationDestination(for: RXCalculatorKind.self) { calculator in
                RXCalculatorDetailView(calculator: calculator)
            }
        }
    }
}

private struct RXCalculatorCategory: Identifiable {
    let name: String
    let calculators: [RXCalculatorKind]

    var id: String { name }
}

private struct RXCalculatorRow: View {
    let calculator: RXCalculatorKind

    var body: some View {
        let descriptor = calculator.descriptor
        VStack(alignment: .leading, spacing: 4) {
            Text(descriptor.shortTitle)
                .font(.headline)
            Text(descriptor.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Label(
                descriptor.reviewStatus.title,
                systemImage: "exclamationmark.shield.fill"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
            .accessibilityIdentifier(
                "rxcalc.catalog." + calculator.rawValue + ".reviewStatus"
            )
        }
        .padding(.vertical, 4)
    }
}

private struct RXCalculatorDetailView: View {
    let calculator: RXCalculatorKind

    var body: some View {
        Group {
            switch calculator {
            case .creatinineClearance:
                CreatinineClearanceView(calculator: calculator)
            case .ckdEPI2021:
                CKDEPI2021CreatinineView(calculator: calculator)
            case .bodySize:
                BodySizeView(calculator: calculator)
            }
        }
        .navigationTitle(calculator.descriptor.shortTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RXCalculatorSafetyPrelude: View {
    let descriptor: RXCalculatorDescriptor

    var body: some View {
        Section("When to use") {
            Text(descriptor.summary)
            LabeledContent("Population", value: descriptor.intendedPopulation)
            Label(
                descriptor.reviewStatus.title,
                systemImage: "exclamationmark.shield.fill"
            )
            .foregroundStyle(.orange)
            .accessibilityIdentifier("rxcalc.detail.reviewStatus")
        }
    }
}

private struct RXCalculatorEvidenceSections: View {
    let descriptor: RXCalculatorDescriptor

    var body: some View {
        Section("Limitations") {
            ForEach(descriptor.limitations, id: \.self) { limitation in
                Label(limitation, systemImage: "exclamationmark.circle")
                    .font(.subheadline)
            }
        }

        Section("Equation and evidence") {
            ForEach(descriptor.canonicalInputUnits, id: \.self) { unit in
                LabeledContent("Canonical input", value: unit)
            }
            ForEach(descriptor.canonicalOutputUnits, id: \.self) { unit in
                LabeledContent("Canonical output", value: unit)
            }
            Text(descriptor.equation)
                .font(.callout.monospaced())
                .textSelection(.enabled)
            Text(descriptor.roundingPolicy)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(descriptor.sources) { source in
                LabeledContent("Formula version", value: source.formulaIdentifier)
                LabeledContent("Citation", value: source.citation)
                LabeledContent("Locator", value: source.sourceLocator)
                LabeledContent("Source metadata checked", value: source.sourceMetadataCheckedOn)
            }
        }
    }
}

private struct CreatinineClearanceView: View {
    private enum FocusField: Hashable {
        case age
        case weight
        case creatinine
    }

    let calculator: RXCalculatorKind

    @FocusState private var focusedField: FocusField?
    @State private var ageText = ""
    @State private var equationSex: RXEquationSex?
    @State private var weightText = ""
    @State private var weightUnit = RXMassUnit.kilograms
    @State private var creatinineText = ""
    @State private var creatinineUnit = RXCreatinineUnit.milligramsPerDeciliter
    @State private var result: CreatinineClearanceResult?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            RXCalculatorSafetyPrelude(descriptor: calculator.descriptor)

            Section("Inputs") {
                TextField("Age in years", text: $ageText)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .age)
                    .accessibilityIdentifier("rxcalc.crcl.age")
                    .accessibilityHint("Required whole-number age in years.")

                Picker("Equation sex", selection: $equationSex) {
                    Text("Select").tag(RXEquationSex?.none)
                    ForEach(RXEquationSex.allCases) { sex in
                        Text(sex.title).tag(Optional(sex))
                    }
                }
                .accessibilityIdentifier("rxcalc.crcl.equationSex")

                TextField("Calculation weight", text: $weightText)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .weight)
                    .accessibilityIdentifier("rxcalc.crcl.weight")
                    .accessibilityHint("Required calculation weight in the selected unit.")
                Picker("Weight unit", selection: $weightUnit) {
                    ForEach(RXMassUnit.allCases) { unit in
                        Text(unit.symbol).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("rxcalc.crcl.weightUnit")

                TextField("Serum creatinine", text: $creatinineText)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .creatinine)
                    .accessibilityIdentifier("rxcalc.crcl.creatinine")
                    .accessibilityHint("Required serum creatinine in the selected unit.")
                Picker("Creatinine unit", selection: $creatinineUnit) {
                    ForEach(RXCreatinineUnit.allCases) { unit in
                        Text(unit.symbol).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("rxcalc.crcl.creatinineUnit")

                Button("Calculate") {
                    calculate()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("rxcalc.crcl.calculate")

                Button("Clear", role: .cancel) {
                    reset()
                }
                .accessibilityIdentifier("rxcalc.crcl.clear")
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }

            if let result {
                Section("Result") {
                    RXResultValue(
                        label: "Estimated CrCl",
                        value: result.millilitersPerMinute,
                        unit: "mL/min",
                        fractionDigits: 1
                    )
                    .accessibilityIdentifier("rxcalc.crcl.result")
                    RXResultReviewNotice(descriptor: calculator.descriptor)
                    Text("This is an estimate, not a dose or CKD stage.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Inputs used") {
                    LabeledContent("Age") {
                        Text(result.ageYears, format: .number)
                        Text("years")
                    }
                    LabeledContent("Equation sex", value: result.equationSex.title)
                    RXResultValue(
                        label: "Calculation weight",
                        value: result.calculationWeightKilograms,
                        unit: "kg",
                        fractionDigits: 2
                    )
                    RXResultValue(
                        label: "Serum creatinine",
                        value: result.serumCreatinineMilligramsPerDeciliter,
                        unit: "mg/dL",
                        fractionDigits: 3
                    )
                }
            }

            RXCalculatorEvidenceSections(descriptor: calculator.descriptor)
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
                .accessibilityIdentifier("rxcalc.crcl.keyboardDone")
            }
        }
        .onChange(of: ageText) { _, _ in invalidateResult() }
        .onChange(of: equationSex) { _, _ in invalidateResult() }
        .onChange(of: weightText) { _, _ in invalidateResult() }
        .onChange(of: weightUnit) { _, _ in
            weightText = ""
            invalidateResult()
        }
        .onChange(of: creatinineText) { _, _ in invalidateResult() }
        .onChange(of: creatinineUnit) { _, _ in
            creatinineText = ""
            invalidateResult()
        }
    }

    private func calculate() {
        focusedField = nil
        guard
            let age = Int(ageText),
            let equationSex,
            let weight = RXDecimalInputParser.parse(
                weightText,
                decimalSeparator: Locale.current.decimalSeparator
            ),
            let creatinine = RXDecimalInputParser.parse(
                creatinineText,
                decimalSeparator: Locale.current.decimalSeparator
            )
        else {
            result = nil
            errorMessage = "Enter every required input and select equation sex."
            return
        }

        do {
            result = try CreatinineClearanceCalculator.calculate(
                CreatinineClearanceInput(
                    ageYears: age,
                    equationSex: equationSex,
                    calculationWeight: weight,
                    weightUnit: weightUnit,
                    serumCreatinine: creatinine,
                    creatinineUnit: creatinineUnit
                )
            )
            errorMessage = nil
        } catch {
            result = nil
            errorMessage = error.localizedDescription
        }
    }

    private func invalidateResult() {
        result = nil
        errorMessage = nil
    }

    private func reset() {
        focusedField = nil
        ageText = ""
        equationSex = nil
        weightText = ""
        weightUnit = .kilograms
        creatinineText = ""
        creatinineUnit = .milligramsPerDeciliter
        invalidateResult()
    }
}

private struct CKDEPI2021CreatinineView: View {
    private enum FocusField: Hashable {
        case age
        case creatinine
    }

    let calculator: RXCalculatorKind

    @FocusState private var focusedField: FocusField?
    @State private var ageText = ""
    @State private var equationSex: RXEquationSex?
    @State private var creatinineText = ""
    @State private var creatinineUnit = RXCreatinineUnit.milligramsPerDeciliter
    @State private var result: CKDEPI2021CreatinineResult?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            RXCalculatorSafetyPrelude(descriptor: calculator.descriptor)

            Section("Inputs") {
                TextField("Age in years", text: $ageText)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .age)
                    .accessibilityIdentifier("rxcalc.ckdEPI2021.age")
                    .accessibilityHint("Required whole-number age in years.")

                Picker("Equation sex", selection: $equationSex) {
                    Text("Select").tag(RXEquationSex?.none)
                    ForEach(RXEquationSex.allCases) { sex in
                        Text(sex.title).tag(Optional(sex))
                    }
                }
                .accessibilityIdentifier("rxcalc.ckdEPI2021.equationSex")

                TextField("Standardized serum creatinine", text: $creatinineText)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .creatinine)
                    .accessibilityIdentifier("rxcalc.ckdEPI2021.creatinine")
                    .accessibilityHint("Required serum creatinine in the selected unit.")
                Picker("Creatinine unit", selection: $creatinineUnit) {
                    ForEach(RXCreatinineUnit.allCases) { unit in
                        Text(unit.symbol).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("rxcalc.ckdEPI2021.creatinineUnit")

                Button("Calculate") {
                    calculate()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("rxcalc.ckdEPI2021.calculate")

                Button("Clear", role: .cancel) {
                    reset()
                }
                .accessibilityIdentifier("rxcalc.ckdEPI2021.clear")
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }

            if let result {
                Section("Result") {
                    RXResultValue(
                        label: "Indexed eGFR",
                        value: result.indexedMillilitersPerMinutePer1_73SquareMeters,
                        unit: "mL/min/1.73 m²",
                        fractionDigits: 0
                    )
                    .accessibilityIdentifier("rxcalc.ckdEPI2021.result")
                    RXResultReviewNotice(descriptor: calculator.descriptor)
                    Text("RXcalc does not assign a CKD stage or derive an unindexed dosing value.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Inputs used") {
                    LabeledContent("Age") {
                        Text(result.ageYears, format: .number)
                        Text("years")
                    }
                    LabeledContent("Equation sex", value: result.equationSex.title)
                    RXResultValue(
                        label: "Serum creatinine",
                        value: result.serumCreatinineMilligramsPerDeciliter,
                        unit: "mg/dL",
                        fractionDigits: 3
                    )
                }
            }

            RXCalculatorEvidenceSections(descriptor: calculator.descriptor)
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
                .accessibilityIdentifier("rxcalc.ckdEPI2021.keyboardDone")
            }
        }
        .onChange(of: ageText) { _, _ in invalidateResult() }
        .onChange(of: equationSex) { _, _ in invalidateResult() }
        .onChange(of: creatinineText) { _, _ in invalidateResult() }
        .onChange(of: creatinineUnit) { _, _ in
            creatinineText = ""
            invalidateResult()
        }
    }

    private func calculate() {
        focusedField = nil
        guard
            let age = Int(ageText),
            let equationSex,
            let creatinine = RXDecimalInputParser.parse(
                creatinineText,
                decimalSeparator: Locale.current.decimalSeparator
            )
        else {
            result = nil
            errorMessage = "Enter every required input and select equation sex."
            return
        }

        do {
            result = try CKDEPI2021CreatinineCalculator.calculate(
                CKDEPI2021CreatinineInput(
                    ageYears: age,
                    equationSex: equationSex,
                    serumCreatinine: creatinine,
                    creatinineUnit: creatinineUnit
                )
            )
            errorMessage = nil
        } catch {
            result = nil
            errorMessage = error.localizedDescription
        }
    }

    private func invalidateResult() {
        result = nil
        errorMessage = nil
    }

    private func reset() {
        focusedField = nil
        ageText = ""
        equationSex = nil
        creatinineText = ""
        creatinineUnit = .milligramsPerDeciliter
        invalidateResult()
    }
}

private struct BodySizeView: View {
    private enum FocusField: Hashable {
        case age
        case height
        case weight
    }

    let calculator: RXCalculatorKind

    @FocusState private var focusedField: FocusField?
    @State private var ageText = ""
    @State private var heightText = ""
    @State private var heightUnit = RXLengthUnit.centimeters
    @State private var weightText = ""
    @State private var weightUnit = RXMassUnit.kilograms
    @State private var result: BodySizeResult?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            RXCalculatorSafetyPrelude(descriptor: calculator.descriptor)

            Section("Inputs") {
                TextField("Age in years", text: $ageText)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .age)
                    .accessibilityIdentifier("rxcalc.bodySize.age")
                    .accessibilityHint("Required whole-number age in years.")

                TextField("Height", text: $heightText)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .height)
                    .accessibilityIdentifier("rxcalc.bodySize.height")
                    .accessibilityHint("Required height in the selected unit.")
                Picker("Height unit", selection: $heightUnit) {
                    ForEach(RXLengthUnit.allCases) { unit in
                        Text(unit.symbol).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("rxcalc.bodySize.heightUnit")

                TextField("Weight", text: $weightText)
                    .keyboardType(.decimalPad)
                    .focused($focusedField, equals: .weight)
                    .accessibilityIdentifier("rxcalc.bodySize.weight")
                    .accessibilityHint("Required weight in the selected unit.")
                Picker("Weight unit", selection: $weightUnit) {
                    ForEach(RXMassUnit.allCases) { unit in
                        Text(unit.symbol).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("rxcalc.bodySize.weightUnit")

                Button("Calculate") {
                    calculate()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("rxcalc.bodySize.calculate")

                Button("Clear", role: .cancel) {
                    reset()
                }
                .accessibilityIdentifier("rxcalc.bodySize.clear")
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }

            if let result {
                Section("Results") {
                    RXResultValue(
                        label: "Body mass index",
                        value: result.bodyMassIndex,
                        unit: "kg/m²",
                        fractionDigits: 2
                    )
                    .accessibilityIdentifier("rxcalc.bodySize.bmiResult")
                    RXResultValue(
                        label: "Mosteller BSA",
                        value: result.mostellerBodySurfaceAreaSquareMeters,
                        unit: "m²",
                        fractionDigits: 2
                    )
                    .accessibilityIdentifier("rxcalc.bodySize.bsaResult")
                    RXResultReviewNotice(descriptor: calculator.descriptor)
                    Text("RXcalc does not classify BMI or calculate a medication dose.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Inputs used") {
                    LabeledContent("Age") {
                        Text(result.ageYears, format: .number)
                        Text("years")
                    }
                    RXResultValue(
                        label: "Height",
                        value: result.heightCentimeters,
                        unit: "cm",
                        fractionDigits: 2
                    )
                    RXResultValue(
                        label: "Weight",
                        value: result.weightKilograms,
                        unit: "kg",
                        fractionDigits: 2
                    )
                }
            }

            RXCalculatorEvidenceSections(descriptor: calculator.descriptor)
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
                .accessibilityIdentifier("rxcalc.bodySize.keyboardDone")
            }
        }
        .onChange(of: ageText) { _, _ in invalidateResult() }
        .onChange(of: heightText) { _, _ in invalidateResult() }
        .onChange(of: heightUnit) { _, _ in
            heightText = ""
            invalidateResult()
        }
        .onChange(of: weightText) { _, _ in invalidateResult() }
        .onChange(of: weightUnit) { _, _ in
            weightText = ""
            invalidateResult()
        }
    }

    private func calculate() {
        focusedField = nil
        guard
            let age = Int(ageText),
            let height = RXDecimalInputParser.parse(
                heightText,
                decimalSeparator: Locale.current.decimalSeparator
            ),
            let weight = RXDecimalInputParser.parse(
                weightText,
                decimalSeparator: Locale.current.decimalSeparator
            )
        else {
            result = nil
            errorMessage = "Enter every required input."
            return
        }

        do {
            result = try BodySizeCalculator.calculate(
                BodySizeInput(
                    ageYears: age,
                    height: height,
                    heightUnit: heightUnit,
                    weight: weight,
                    weightUnit: weightUnit
                )
            )
            errorMessage = nil
        } catch {
            result = nil
            errorMessage = error.localizedDescription
        }
    }

    private func invalidateResult() {
        result = nil
        errorMessage = nil
    }

    private func reset() {
        focusedField = nil
        ageText = ""
        heightText = ""
        heightUnit = .centimeters
        weightText = ""
        weightUnit = .kilograms
        invalidateResult()
    }
}


private struct RXResultReviewNotice: View {
    let descriptor: RXCalculatorDescriptor

    var body: some View {
        Label(
            descriptor.reviewStatus.title,
            systemImage: "exclamationmark.shield.fill"
        )
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.orange)
        .accessibilityIdentifier("rxcalc.result.reviewStatus")
        ForEach(descriptor.sources) { source in
            Text(source.formulaIdentifier)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        Text(descriptor.reviewStatus.resultMessage)
            .font(.subheadline)
            .foregroundStyle(.orange)
    }
}

private struct RXResultValue: View {
    let label: String
    let value: Double
    let unit: String
    let fractionDigits: Int

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 4) {
                Text(
                    value,
                    format: .number.precision(.fractionLength(fractionDigits))
                )
                .fontWeight(.semibold)
                Text(unit)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
