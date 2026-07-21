import Foundation
import SwiftUI

struct RXCalcView: View {
    @State private var searchText = ""
    /// Explicit path navigation avoids List `NavigationLink` disclosure
    /// chevrons, which report partial Dynamic Type support at Accessibility 5.
    @State private var navigationPath = NavigationPath()

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
        NavigationStack(path: $navigationPath) {
            // ScrollView + text stack (not List/Label) so every catalog surface
            // uses full Dynamic Type text styles at Accessibility 5. System List
            // cells, disclosure chevrons, and weighted text styles previously
            // failed the hosted Dynamic Type audit with
            // "font sizes are partially unsupported".
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(catalogReviewStatus.catalogTitle)
                            .font(.headline)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("rxcalc.catalog.reviewTitle")

                        Text(catalogReviewStatus.catalogMessage)
                            .font(.body)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("rxcalc.catalog.reviewMessage")

                        Text(
                            "Inputs and results stay on this screen and are never saved. Do not enter patient identifiers."
                        )
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("rxcalc.catalog.nonRetentionWarning")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)
                    .accessibilityElement(children: .contain)

                    if visibleCategories.isEmpty {
                        Text("Calculators")
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text("No calculators match this search.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(visibleCategories) { category in
                            Text(category.name)
                                .font(.headline)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.isHeader)

                            ForEach(category.calculators) { calculator in
                                Button {
                                    navigationPath.append(calculator)
                                } label: {
                                    RXCalculatorRow(calculator: calculator)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier(
                                    "rxcalc.catalog." + calculator.rawValue
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .navigationTitle("RXcalc")
            .navigationBarTitleDisplayMode(.inline)
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
        // Only unmodified Dynamic Type text styles (headline/body/callout).
        // Do not apply .weight(...) — weighted variants report partial Dynamic
        // Type support under the hosted Accessibility 5 audit.
        VStack(alignment: .leading, spacing: 6) {
            Text(descriptor.shortTitle)
                .font(.headline)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(descriptor.summary)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(descriptor.reviewStatus.title)
                .font(.callout)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(
                    "rxcalc.catalog." + calculator.rawValue + ".reviewStatus"
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
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

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @FocusState private var focusedField: FocusField?
    @State private var ageText = ""
    @State private var equationSex: RXEquationSex?
    @State private var weightText = ""
    @State private var weightUnit = RXMassUnit.kilograms
    @State private var creatinineText = ""
    @State private var creatinineUnit = RXCreatinineUnit.milligramsPerDeciliter
    @State private var resultSession = RXResultSession<CreatinineClearanceResult>()
    @State private var errorMessage: String?
    @State private var copyFeedback: String?

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
                    Text(errorMessage)
                        .font(.body)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("rxcalc.crcl.error")
                }
            }

            if let result = resultSession.value {
                RXResultLifecycleBanner(
                    currency: resultSession.currency,
                    staleReason: resultSession.staleReason,
                    accessibilityPrefix: "rxcalc.crcl"
                )

                Section(resultSession.isStale ? "Stale result (not current)" : "Result") {
                    RXResultValue(
                        label: "Estimated CrCl",
                        value: result.millilitersPerMinute,
                        unit: "mL/min",
                        fractionDigits: 1
                    )
                    .accessibilityIdentifier("rxcalc.crcl.result")
                    .opacity(resultSession.isStale ? 0.55 : 1)
                    RXResultReviewNotice(descriptor: calculator.descriptor)
                    Text("This is an estimate, not a dose or CKD stage.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    RXResultCopyCurrentControl(
                        enabled: resultSession.mayCopyOrExportAsCurrent,
                        accessibilityIdentifier: "rxcalc.crcl.copyCurrent",
                        feedback: $copyFeedback,
                        makeSummary: {
                            crclSummary(for: result, currency: resultSession.currency)
                        }
                    )
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

                RXResultProvenanceSection(
                    provenance: result.provenance,
                    currency: resultSession.currency
                )
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
        .onChange(of: dynamicTypeSize) { _, _ in
            resultSession.invalidate(reason: RXResultSession<CreatinineClearanceResult>.dynamicTypeChangedReason)
            copyFeedback = nil
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                resultSession.abandonSurface()
                copyFeedback = nil
                errorMessage = nil
            }
        }
        .onDisappear {
            resultSession.abandonSurface()
            copyFeedback = nil
        }
    }

    private func calculate() {
        focusedField = nil
        copyFeedback = nil
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
            resultSession.clear()
            errorMessage = "Enter every required input and select equation sex."
            return
        }

        do {
            let calculated = try CreatinineClearanceCalculator.calculate(
                CreatinineClearanceInput(
                    ageYears: age,
                    equationSex: equationSex,
                    calculationWeight: weight,
                    weightUnit: weightUnit,
                    serumCreatinine: creatinine,
                    creatinineUnit: creatinineUnit
                )
            )
            resultSession.publish(calculated)
            errorMessage = nil
        } catch {
            resultSession.clear()
            errorMessage = error.localizedDescription
        }
    }

    private func invalidateResult() {
        resultSession.invalidate()
        errorMessage = nil
        copyFeedback = nil
    }

    private func reset() {
        focusedField = nil
        ageText = ""
        equationSex = nil
        weightText = ""
        weightUnit = .kilograms
        creatinineText = ""
        creatinineUnit = .milligramsPerDeciliter
        resultSession.clear()
        errorMessage = nil
        copyFeedback = nil
    }

    private func crclSummary(
        for result: CreatinineClearanceResult,
        currency: RXResultCurrency
    ) -> String? {
        let output =
            "Estimated CrCl "
            + String(result.millilitersPerMinute)
            + " mL/min"
        return RXResultExportGate.currentEngineeringSummary(
            currency: currency,
            formulaIdentifiers: result.provenance.formulaIdentifiers,
            outputDescription: output,
            reviewStatusTitle: result.provenance.sourceReviewStatusTitle,
            calculatedAtDescription: result.provenance.calculatedAt.formatted(
                date: .abbreviated,
                time: .standard
            )
        )
    }
}

private struct CKDEPI2021CreatinineView: View {
    private enum FocusField: Hashable {
        case age
        case creatinine
    }

    let calculator: RXCalculatorKind

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @FocusState private var focusedField: FocusField?
    @State private var ageText = ""
    @State private var equationSex: RXEquationSex?
    @State private var creatinineText = ""
    @State private var creatinineUnit = RXCreatinineUnit.milligramsPerDeciliter
    @State private var resultSession = RXResultSession<CKDEPI2021CreatinineResult>()
    @State private var errorMessage: String?
    @State private var copyFeedback: String?

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
                    Text(errorMessage)
                        .font(.body)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("rxcalc.ckdEPI2021.error")
                }
            }

            if let result = resultSession.value {
                RXResultLifecycleBanner(
                    currency: resultSession.currency,
                    staleReason: resultSession.staleReason,
                    accessibilityPrefix: "rxcalc.ckdEPI2021"
                )

                Section(resultSession.isStale ? "Stale result (not current)" : "Result") {
                    RXResultValue(
                        label: "Indexed eGFR",
                        value: result.indexedMillilitersPerMinutePer1_73SquareMeters,
                        unit: "mL/min/1.73 m²",
                        fractionDigits: 0
                    )
                    .accessibilityIdentifier("rxcalc.ckdEPI2021.result")
                    .opacity(resultSession.isStale ? 0.55 : 1)
                    RXResultReviewNotice(descriptor: calculator.descriptor)
                    Text("RXcalc does not assign a CKD stage or derive an unindexed dosing value.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    RXResultCopyCurrentControl(
                        enabled: resultSession.mayCopyOrExportAsCurrent,
                        accessibilityIdentifier: "rxcalc.ckdEPI2021.copyCurrent",
                        feedback: $copyFeedback,
                        makeSummary: {
                            ckdSummary(for: result, currency: resultSession.currency)
                        }
                    )
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

                RXResultProvenanceSection(
                    provenance: result.provenance,
                    currency: resultSession.currency
                )
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
        .onChange(of: dynamicTypeSize) { _, _ in
            resultSession.invalidate(reason: RXResultSession<CKDEPI2021CreatinineResult>.dynamicTypeChangedReason)
            copyFeedback = nil
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                resultSession.abandonSurface()
                copyFeedback = nil
                errorMessage = nil
            }
        }
        .onDisappear {
            resultSession.abandonSurface()
            copyFeedback = nil
        }
    }

    private func calculate() {
        focusedField = nil
        copyFeedback = nil
        guard
            let age = Int(ageText),
            let equationSex,
            let creatinine = RXDecimalInputParser.parse(
                creatinineText,
                decimalSeparator: Locale.current.decimalSeparator
            )
        else {
            resultSession.clear()
            errorMessage = "Enter every required input and select equation sex."
            return
        }

        do {
            let calculated = try CKDEPI2021CreatinineCalculator.calculate(
                CKDEPI2021CreatinineInput(
                    ageYears: age,
                    equationSex: equationSex,
                    serumCreatinine: creatinine,
                    creatinineUnit: creatinineUnit
                )
            )
            resultSession.publish(calculated)
            errorMessage = nil
        } catch {
            resultSession.clear()
            errorMessage = error.localizedDescription
        }
    }

    private func invalidateResult() {
        resultSession.invalidate()
        errorMessage = nil
        copyFeedback = nil
    }

    private func reset() {
        focusedField = nil
        ageText = ""
        equationSex = nil
        creatinineText = ""
        creatinineUnit = .milligramsPerDeciliter
        resultSession.clear()
        errorMessage = nil
        copyFeedback = nil
    }

    private func ckdSummary(
        for result: CKDEPI2021CreatinineResult,
        currency: RXResultCurrency
    ) -> String? {
        let output =
            "Indexed eGFR "
            + String(result.indexedMillilitersPerMinutePer1_73SquareMeters)
            + " mL/min/1.73 m2"
        return RXResultExportGate.currentEngineeringSummary(
            currency: currency,
            formulaIdentifiers: result.provenance.formulaIdentifiers,
            outputDescription: output,
            reviewStatusTitle: result.provenance.sourceReviewStatusTitle,
            calculatedAtDescription: result.provenance.calculatedAt.formatted(
                date: .abbreviated,
                time: .standard
            )
        )
    }
}

private struct BodySizeView: View {
    private enum FocusField: Hashable {
        case age
        case height
        case weight
    }

    let calculator: RXCalculatorKind

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @FocusState private var focusedField: FocusField?
    @State private var ageText = ""
    @State private var heightText = ""
    @State private var heightUnit = RXLengthUnit.centimeters
    @State private var weightText = ""
    @State private var weightUnit = RXMassUnit.kilograms
    @State private var resultSession = RXResultSession<BodySizeResult>()
    @State private var errorMessage: String?
    @State private var copyFeedback: String?

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
                    Text(errorMessage)
                        .font(.body)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("rxcalc.bodySize.error")
                }
            }

            if let result = resultSession.value {
                RXResultLifecycleBanner(
                    currency: resultSession.currency,
                    staleReason: resultSession.staleReason,
                    accessibilityPrefix: "rxcalc.bodySize"
                )

                Section(resultSession.isStale ? "Stale results (not current)" : "Results") {
                    RXResultValue(
                        label: "Body mass index",
                        value: result.bodyMassIndex,
                        unit: "kg/m²",
                        fractionDigits: 2
                    )
                    .accessibilityIdentifier("rxcalc.bodySize.bmiResult")
                    .opacity(resultSession.isStale ? 0.55 : 1)
                    RXResultValue(
                        label: "Mosteller BSA",
                        value: result.mostellerBodySurfaceAreaSquareMeters,
                        unit: "m²",
                        fractionDigits: 2
                    )
                    .accessibilityIdentifier("rxcalc.bodySize.bsaResult")
                    .opacity(resultSession.isStale ? 0.55 : 1)
                    RXResultReviewNotice(descriptor: calculator.descriptor)
                    Text("RXcalc does not classify BMI or calculate a medication dose.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    RXResultCopyCurrentControl(
                        enabled: resultSession.mayCopyOrExportAsCurrent,
                        accessibilityIdentifier: "rxcalc.bodySize.copyCurrent",
                        feedback: $copyFeedback,
                        makeSummary: {
                            bodySizeSummary(for: result, currency: resultSession.currency)
                        }
                    )
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

                RXResultProvenanceSection(
                    provenance: result.provenance,
                    currency: resultSession.currency
                )
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
        .onChange(of: dynamicTypeSize) { _, _ in
            resultSession.invalidate(reason: RXResultSession<BodySizeResult>.dynamicTypeChangedReason)
            copyFeedback = nil
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                resultSession.abandonSurface()
                copyFeedback = nil
                errorMessage = nil
            }
        }
        .onDisappear {
            resultSession.abandonSurface()
            copyFeedback = nil
        }
    }

    private func calculate() {
        focusedField = nil
        copyFeedback = nil
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
            resultSession.clear()
            errorMessage = "Enter every required input."
            return
        }

        do {
            let calculated = try BodySizeCalculator.calculate(
                BodySizeInput(
                    ageYears: age,
                    height: height,
                    heightUnit: heightUnit,
                    weight: weight,
                    weightUnit: weightUnit
                )
            )
            resultSession.publish(calculated)
            errorMessage = nil
        } catch {
            resultSession.clear()
            errorMessage = error.localizedDescription
        }
    }

    private func invalidateResult() {
        resultSession.invalidate()
        errorMessage = nil
        copyFeedback = nil
    }

    private func reset() {
        focusedField = nil
        ageText = ""
        heightText = ""
        heightUnit = .centimeters
        weightText = ""
        weightUnit = .kilograms
        resultSession.clear()
        errorMessage = nil
        copyFeedback = nil
    }

    private func bodySizeSummary(
        for result: BodySizeResult,
        currency: RXResultCurrency
    ) -> String? {
        let output =
            "BMI "
            + String(result.bodyMassIndex)
            + " kg/m2; Mosteller BSA "
            + String(result.mostellerBodySurfaceAreaSquareMeters)
            + " m2"
        return RXResultExportGate.currentEngineeringSummary(
            currency: currency,
            formulaIdentifiers: result.provenance.formulaIdentifiers,
            outputDescription: output,
            reviewStatusTitle: result.provenance.sourceReviewStatusTitle,
            calculatedAtDescription: result.provenance.calculatedAt.formatted(
                date: .abbreviated,
                time: .standard
            )
        )
    }
}


private struct RXResultReviewNotice: View {
    let descriptor: RXCalculatorDescriptor

    var body: some View {
        Text(descriptor.reviewStatus.title)
            .font(.headline)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("rxcalc.result.reviewStatus")
        ForEach(descriptor.sources) { source in
            Text(source.formulaIdentifier)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        Text(descriptor.reviewStatus.resultMessage)
            .font(.body)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Surfaces calculation provenance for independent verification. Values use
/// Dynamic Type–friendly body/callout styles; safety labels stay readable.
private struct RXResultProvenanceSection: View {
    let provenance: RXCalculationProvenance
    let currency: RXResultCurrency

    var body: some View {
        Section("Calculation provenance") {
            Text(
                currency == .stale
                    ? "Stale engineering output — not current; human review still required"
                    : "Human review required — not an autonomous clinical recommendation"
            )
            .font(.headline)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("rxcalc.result.humanReviewRequired")

            LabeledContent(
                "Result currency",
                value: currency == .current ? "Current calculation" : "Stale — recalculate"
            )
            .font(.body)
            .accessibilityIdentifier("rxcalc.result.currency")

            ForEach(provenance.formulaIdentifiers, id: \.self) { identifier in
                LabeledContent("Formula version", value: identifier)
                    .font(.body)
                    .accessibilityIdentifier("rxcalc.result.formulaVersion")
            }

            LabeledContent("Rounding policy", value: provenance.roundingPolicyIdentity)
                .font(.callout)
                .accessibilityIdentifier("rxcalc.result.roundingPolicy")

            LabeledContent("Source review status", value: provenance.sourceReviewStatusTitle)
                .font(.body)
                .accessibilityIdentifier("rxcalc.result.sourceReviewStatus")

            LabeledContent(
                "Calculated at",
                value: provenance.calculatedAt.formatted(date: .abbreviated, time: .standard)
            )
            .font(.callout)
            .accessibilityIdentifier("rxcalc.result.calculatedAt")

            ForEach(provenance.inputTraces, id: \.name) { trace in
                VStack(alignment: .leading, spacing: 2) {
                    Text(trace.name)
                        .font(.headline)
                    // Concatenation only: executable string interpolation is
                    // fail-closed outside the reviewed allowlist.
                    Text(
                        "Entered "
                            + trace.originalValueDescription
                            + " "
                            + trace.originalUnitSymbol
                            + " → "
                            + String(trace.normalizedValue)
                            + " "
                            + trace.normalizedUnitSymbol
                    )
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }

            Text(
                "Full precision is retained through calculation. Display rounding does not change the stored result value. Independently verify equation, inputs, units, and result before any clinical use. Formula activation for clinical care still requires independent pharmacist or clinical review."
            )
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct RXResultLifecycleBanner: View {
    let currency: RXResultCurrency
    let staleReason: String?
    let accessibilityPrefix: String

    var body: some View {
        if currency == .stale {
            Section {
                Text(RXResultSession<Int>.staleBannerTitle)
                    .font(.headline)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(accessibilityPrefix + ".staleBanner")
                Text(staleReason ?? RXResultSession<Int>.defaultInvalidationReason)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(accessibilityPrefix + ".staleReason")
                Text(RXResultSession<Int>.staleCopyBlockedMessage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(accessibilityPrefix + ".staleCopyBlocked")
            }
        }
    }
}

private struct RXResultCopyCurrentControl: View {
    let enabled: Bool
    let accessibilityIdentifier: String
    @Binding var feedback: String?
    let makeSummary: () -> String?

    var body: some View {
        // Pasteboard APIs are outside the reviewed module allowlist. The control
        // still enforces the current-only gate and surfaces a Draft summary
        // confirmation without writing system pasteboard state.
        Button("Prepare current result summary") {
            if enabled, let summary = makeSummary() {
                feedback =
                    "Current Draft summary prepared ("
                    + String(summary.count)
                    + " characters). Not clinically validated."
            } else {
                feedback = RXResultSession<Int>.staleCopyBlockedMessage
            }
        }
        .disabled(enabled == false)
        .accessibilityIdentifier(accessibilityIdentifier)
        if let feedback {
            Text(feedback)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(accessibilityIdentifier + ".feedback")
        }
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
                .font(.headline)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                Text(unit)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
