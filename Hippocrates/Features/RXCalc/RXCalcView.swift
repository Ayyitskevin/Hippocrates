import Foundation
import SwiftUI

struct RXCalcView: View {
    @State private var searchText = ""

    private var visibleCalculators: [RXCalculatorKind] {
        RXCalculatorKind.allCases.filter { calculator in
            calculator.matches(searchText: searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            "Draft clinical content",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.headline)
                        .foregroundStyle(.orange)

                        Text(
                            "This development build has not passed independent clinical review. Do not use RXcalc for patient care. It performs source-identified arithmetic only."
                        )
                        .font(.subheadline)

                        Text(
                            "Inputs and results stay on this screen and are never saved. Do not enter patient identifiers."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Calculators") {
                    if visibleCalculators.isEmpty {
                        Text("No calculators match this search.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(visibleCalculators) { calculator in
                            NavigationLink(value: calculator) {
                                RXCalculatorRow(calculator: calculator)
                            }
                        }
                    }
                }
            }
            .navigationTitle("RXcalc")
            .searchable(text: $searchText, prompt: "Search formulas or categories")
            .navigationDestination(for: RXCalculatorKind.self) { calculator in
                RXCalculatorDetailView(calculator: calculator)
            }
        }
    }
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
            Text(descriptor.category)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
            Label(descriptor.reviewStatus.title, systemImage: "exclamationmark.shield.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
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

private struct RXCalculatorContextSections: View {
    let descriptor: RXCalculatorDescriptor

    var body: some View {
        Section("When to use") {
            Text(descriptor.summary)
            LabeledContent("Population", value: descriptor.intendedPopulation)
            Label(descriptor.reviewStatus.title, systemImage: "exclamationmark.shield.fill")
                .foregroundStyle(.orange)
        }

        Section("Limitations") {
            ForEach(descriptor.limitations, id: \.self) { limitation in
                Label(limitation, systemImage: "exclamationmark.circle")
                    .font(.subheadline)
            }
        }

        Section("Equation and evidence") {
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
                LabeledContent("Source reviewed", value: source.sourceReviewedOn)
            }
        }
    }
}

private struct CreatinineClearanceView: View {
    let calculator: RXCalculatorKind

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
            RXCalculatorContextSections(descriptor: calculator.descriptor)

            Section("Inputs") {
                TextField("Age in years", text: $ageText)
                    .keyboardType(.numberPad)

                Picker("Equation sex", selection: $equationSex) {
                    Text("Select").tag(RXEquationSex?.none)
                    ForEach(RXEquationSex.allCases) { sex in
                        Text(sex.title).tag(Optional(sex))
                    }
                }

                TextField("Calculation weight", text: $weightText)
                    .keyboardType(.decimalPad)
                Picker("Weight unit", selection: $weightUnit) {
                    ForEach(RXMassUnit.allCases) { unit in
                        Text(unit.symbol).tag(unit)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Serum creatinine", text: $creatinineText)
                    .keyboardType(.decimalPad)
                Picker("Creatinine unit", selection: $creatinineUnit) {
                    ForEach(RXCreatinineUnit.allCases) { unit in
                        Text(unit.symbol).tag(unit)
                    }
                }
                .pickerStyle(.segmented)

                Button("Calculate") {
                    calculate()
                }
                .buttonStyle(.borderedProminent)

                Button("Clear", role: .cancel) {
                    reset()
                }
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
        }
        .scrollDismissesKeyboard(.interactively)
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
    let calculator: RXCalculatorKind

    @State private var ageText = ""
    @State private var equationSex: RXEquationSex?
    @State private var creatinineText = ""
    @State private var creatinineUnit = RXCreatinineUnit.milligramsPerDeciliter
    @State private var result: CKDEPI2021CreatinineResult?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            RXCalculatorContextSections(descriptor: calculator.descriptor)

            Section("Inputs") {
                TextField("Age in years", text: $ageText)
                    .keyboardType(.numberPad)

                Picker("Equation sex", selection: $equationSex) {
                    Text("Select").tag(RXEquationSex?.none)
                    ForEach(RXEquationSex.allCases) { sex in
                        Text(sex.title).tag(Optional(sex))
                    }
                }

                TextField("Standardized serum creatinine", text: $creatinineText)
                    .keyboardType(.decimalPad)
                Picker("Creatinine unit", selection: $creatinineUnit) {
                    ForEach(RXCreatinineUnit.allCases) { unit in
                        Text(unit.symbol).tag(unit)
                    }
                }
                .pickerStyle(.segmented)

                Button("Calculate") {
                    calculate()
                }
                .buttonStyle(.borderedProminent)

                Button("Clear", role: .cancel) {
                    reset()
                }
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
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: ageText) { _, _ in invalidateResult() }
        .onChange(of: equationSex) { _, _ in invalidateResult() }
        .onChange(of: creatinineText) { _, _ in invalidateResult() }
        .onChange(of: creatinineUnit) { _, _ in
            creatinineText = ""
            invalidateResult()
        }
    }

    private func calculate() {
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
        ageText = ""
        equationSex = nil
        creatinineText = ""
        creatinineUnit = .milligramsPerDeciliter
        invalidateResult()
    }
}

private struct BodySizeView: View {
    let calculator: RXCalculatorKind

    @State private var ageText = ""
    @State private var heightText = ""
    @State private var heightUnit = RXLengthUnit.centimeters
    @State private var weightText = ""
    @State private var weightUnit = RXMassUnit.kilograms
    @State private var result: BodySizeResult?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            RXCalculatorContextSections(descriptor: calculator.descriptor)

            Section("Inputs") {
                TextField("Age in years", text: $ageText)
                    .keyboardType(.numberPad)

                TextField("Height", text: $heightText)
                    .keyboardType(.decimalPad)
                Picker("Height unit", selection: $heightUnit) {
                    ForEach(RXLengthUnit.allCases) { unit in
                        Text(unit.symbol).tag(unit)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Weight", text: $weightText)
                    .keyboardType(.decimalPad)
                Picker("Weight unit", selection: $weightUnit) {
                    ForEach(RXMassUnit.allCases) { unit in
                        Text(unit.symbol).tag(unit)
                    }
                }
                .pickerStyle(.segmented)

                Button("Calculate") {
                    calculate()
                }
                .buttonStyle(.borderedProminent)

                Button("Clear", role: .cancel) {
                    reset()
                }
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
                    RXResultValue(
                        label: "Mosteller BSA",
                        value: result.mostellerBodySurfaceAreaSquareMeters,
                        unit: "m²",
                        fractionDigits: 2
                    )
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
        }
        .scrollDismissesKeyboard(.interactively)
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
        Label(descriptor.reviewStatus.title, systemImage: "exclamationmark.shield.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.orange)
        ForEach(descriptor.sources) { source in
            Text(source.formulaIdentifier)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        Text("Development output only. Independently verify the equation, inputs, units, and result before any clinical use.")
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
