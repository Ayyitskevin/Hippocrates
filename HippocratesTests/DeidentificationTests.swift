import Foundation
import XCTest

@testable import Hippocrates

final class DeidentificationTests: XCTestCase {
    private func categories(in text: String) -> [DeidentificationFinding.Category] {
        DeidentificationScanner.findings(fieldName: "questionText", text: text).map(\.category)
    }

    // MARK: Pattern integrity

    func testEveryPatternCompiles() {
        for (category, patterns) in DeidentificationScanner.patternsByCategory {
            for pattern in patterns {
                XCTAssertNotNil(
                    try? NSRegularExpression(pattern: pattern),
                    category.rawValue
                )
            }
        }
        XCTAssertEqual(
            Set(DeidentificationScanner.orderedCategories),
            Set(DeidentificationFinding.Category.allCases)
        )
    }

    // MARK: Medical record numbers

    func testLabeledMRNIsFlaggedOnce() {
        let findings = DeidentificationScanner.findings(
            fieldName: "background",
            text: "Patient MRN: 12345678 admitted yesterday."
        )
        let mrnFindings = findings.filter { $0.category == .medicalRecordNumber }
        XCTAssertEqual(mrnFindings.count, 1)
        XCTAssertEqual(mrnFindings.first?.matchedText, "MRN: 12345678")
        XCTAssertEqual(mrnFindings.first?.fieldName, "background")
    }

    func testBareLongDigitRunIsFlagged() {
        XCTAssertTrue(categories(in: "chart 87654321 reviewed").contains(.medicalRecordNumber))
        XCTAssertTrue(categories(in: "record no. 445566").contains(.medicalRecordNumber))
    }

    func testDosesAndShortNumbersAreNotFlagged() {
        XCTAssertTrue(categories(in: "vancomycin 1250 mg IV q12h").isEmpty)
        XCTAssertTrue(categories(in: "metoprolol 25 mg twice daily").isEmpty)
        XCTAssertTrue(categories(in: "CrCl 32, potassium 4.2").isEmpty)
        XCTAssertTrue(categories(in: "order 12345 units").isEmpty)
    }

    func testNDCStyleNumbersAreNotFlagged() {
        XCTAssertTrue(categories(in: "NDC 00093-0058-01 on the shelf").isEmpty)
        XCTAssertTrue(categories(in: "compare 0002-8215-01 packaging").isEmpty)
    }

    // MARK: Phone numbers

    func testPhoneNumberFormatsAreFlagged() {
        XCTAssertTrue(categories(in: "call (555) 123-4567 for follow-up").contains(.phoneNumber))
        XCTAssertTrue(categories(in: "pager 555-123-4567").contains(.phoneNumber))
        XCTAssertTrue(categories(in: "fax 555.123.4567 today").contains(.phoneNumber))
        XCTAssertTrue(categories(in: "reach at +1 555 123 4567 soon").contains(.phoneNumber))
    }

    // MARK: Dates

    func testDateFormatsAreFlagged() {
        XCTAssertTrue(categories(in: "admitted 3/14/2026 overnight").contains(.date))
        XCTAssertTrue(categories(in: "seen 03-14-26 in clinic").contains(.date))
        XCTAssertTrue(categories(in: "surgery on 2026-03-14 went well").contains(.date))
        XCTAssertTrue(categories(in: "discharged March 14, 2026").contains(.date))
        XCTAssertTrue(categories(in: "started Jan 3").contains(.date))
    }

    func testFractionsWithoutDateShapeAreNotFlagged() {
        XCTAssertTrue(categories(in: "eGFR above 60 mL").isEmpty)
        XCTAssertTrue(categories(in: "half of one tablet").isEmpty)
    }

    // MARK: Rooms and beds

    func testRoomAndBedReferencesAreFlagged() {
        XCTAssertTrue(categories(in: "moved to Room 412 tonight").contains(.roomOrBed))
        XCTAssertTrue(categories(in: "rm #4 nurse asked").contains(.roomOrBed))
        XCTAssertTrue(categories(in: "Bed 12B isolation").contains(.roomOrBed))
    }

    func testRoomWordAloneIsNotFlagged() {
        XCTAssertTrue(categories(in: "no room for interpretation").isEmpty)
        XCTAssertTrue(categories(in: "store at room temperature").isEmpty)
    }

    // MARK: Ages over 89

    func testAgesOverEightyNineAreFlagged() {
        XCTAssertTrue(categories(in: "a 92-year-old with sepsis").contains(.ageOver89))
        XCTAssertTrue(categories(in: "patient is 90 yo").contains(.ageOver89))
        XCTAssertTrue(categories(in: "a 94 y/o resident").contains(.ageOver89))
        XCTAssertTrue(categories(in: "aged 101 years").contains(.ageOver89))
        XCTAssertTrue(categories(in: "age: 95").contains(.ageOver89))
    }

    func testAgesEightyNineAndUnderAreNotFlagged() {
        XCTAssertTrue(categories(in: "an 89-year-old with sepsis").isEmpty)
        XCTAssertTrue(categories(in: "a 75 yo patient").isEmpty)
        XCTAssertTrue(categories(in: "age 45").isEmpty)
    }

    // MARK: Clean clinical text

    func testCleanDrugInformationTextHasNoFindings() {
        let text = "Linezolid and sertraline carry a serotonin syndrome interaction risk. "
            + "Monitor for clonus and agitation; consider washout before switching."
        XCTAssertTrue(categories(in: text).isEmpty)
    }

    // MARK: Multi-field scan

    func testMultiFieldScanCarriesFieldNames() {
        let findings = DeidentificationScanner.findings(in: [
            (fieldName: "questionText", text: "Is dosing right for a 92-year-old?"),
            (fieldName: "background", text: "MRN 44556677, seen 3/14/2026."),
            (fieldName: "answerText", text: "Reduce the dose for renal function."),
            (fieldName: "searchStrategy", text: "Reviewed tertiary references."),
        ])
        XCTAssertEqual(findings.count, 3)
        XCTAssertEqual(
            Set(findings.map(\.fieldName)),
            ["questionText", "background"]
        )
        let backgroundCategories = findings
            .filter { $0.fieldName == "background" }
            .map(\.category)
        XCTAssertTrue(backgroundCategories.contains(.medicalRecordNumber))
        XCTAssertTrue(backgroundCategories.contains(.date))
    }

    func testFindingsAreOrderedByLocation() {
        let findings = DeidentificationScanner.findings(
            fieldName: "background",
            text: "Room 12 note for a 93-year-old, callback (555) 123-4567."
        )
        XCTAssertEqual(findings.map(\.location), findings.map(\.location).sorted())
        XCTAssertEqual(findings.count, 3)
    }

    func testEmptyTextHasNoFindings() {
        XCTAssertTrue(DeidentificationScanner.findings(fieldName: "answerText", text: "").isEmpty)
    }

    // MARK: Acknowledgment gate (pure)

    func testUnacknowledgedFindingsBlockUntilExactMatch() {
        let findings = DeidentificationScanner.findings(
            fieldName: "background",
            text: "MRN: 12345678 and Room 12"
        )
        XCTAssertFalse(findings.isEmpty)

        let stillBlocking = DeidentificationScanner.unacknowledgedFindings(
            findings,
            acknowledging: []
        )
        XCTAssertEqual(stillBlocking.count, findings.count)

        let partial = DeidentificationScanner.unacknowledgedFindings(
            findings,
            acknowledging: [
                DeidentificationAcknowledgment(
                    fieldName: "background",
                    matchedText: findings[0].matchedText
                )
            ]
        )
        XCTAssertEqual(partial.count, findings.count - 1)

        let wrongField = DeidentificationScanner.unacknowledgedFindings(
            findings,
            acknowledging: findings.map {
                DeidentificationAcknowledgment(fieldName: "answerText", matchedText: $0.matchedText)
            }
        )
        XCTAssertEqual(wrongField.count, findings.count)

        let full = DeidentificationScanner.unacknowledgedFindings(
            findings,
            acknowledging: findings.map {
                DeidentificationAcknowledgment(fieldName: $0.fieldName, matchedText: $0.matchedText)
            }
        )
        XCTAssertTrue(full.isEmpty)
    }

    // MARK: Adversarial synthetic fixtures (no real patient data)

    func testAdversarialSyntheticFixturesFlagTruePositives() {
        // All strings are fabricated. None identify a real person.
        let fixtures: [(String, DeidentificationFinding.Category)] = [
            ("note MRN 12 345 678 filed", .medicalRecordNumber),
            ("mrn#99887766 reviewed", .medicalRecordNumber),
            ("medical-record-number 44556677 on chart", .medicalRecordNumber),
            ("chart id: 11223344", .medicalRecordNumber),
            ("  MRN:\t55667788  ", .medicalRecordNumber),
            ("embedded see MRN12345678 tomorrow", .medicalRecordNumber),
            ("phone 5551234567 for callback", .phoneNumber),
            ("pager 555-123-4567 overnight", .phoneNumber),
            ("fax 555.123.4567 today", .phoneNumber),
            ("DOB March 14th 1940 recorded", .date),
            ("seen 03/14/26 in clinic", .date),
            ("surgery on 2026-03-14", .date),
            ("room no 12 isolation", .roomOrBed),
            ("Bed#3A contact", .roomOrBed),
            ("rm412 transfer", .roomOrBed),
            ("Room 9 step-down", .roomOrBed),
            ("95yo female with sepsis", .ageOver89),
            ("pt 102 y.o. admitted", .ageOver89),
            ("age over 90 per note", .ageOver89),
            ("a 94 y/o resident", .ageOver89),
            ("age: 95 documented", .ageOver89),
        ]

        for (text, expected) in fixtures {
            let found = categories(in: text)
            XCTAssertTrue(
                found.contains(expected),
                "Expected category missing from synthetic adversarial fixture"
            )
            // Keep the fixture text out of the assertion message path so a
            // failure still prints via XCTContext if needed.
            if found.contains(expected) == false {
                XCTFail(text)
            }
        }
    }

    func testAdversarialMultiFieldEmbeddingStillFlagsEachField() {
        let findings = DeidentificationScanner.findings(in: [
            (
                fieldName: "questionText",
                text: "Dose for 92-year-old with CrCl concern?"
            ),
            (
                fieldName: "background",
                text: "Synthetic fixture only. MRN 12 34 5678; callback (555) 123-4567; room no 4B."
            ),
            (
                fieldName: "answerText",
                text: "Use renally adjusted regimen per current label; no identifier in answer."
            ),
            (
                fieldName: "searchStrategy",
                text: "Checked tertiary DI references and primary literature 2024-2026."
            ),
        ])

        let byField = Dictionary(grouping: findings, by: \.fieldName)
        XCTAssertTrue((byField["questionText"] ?? []).contains { $0.category == .ageOver89 })
        let background = byField["background"] ?? []
        XCTAssertTrue(background.contains { $0.category == .medicalRecordNumber })
        XCTAssertTrue(background.contains { $0.category == .phoneNumber })
        XCTAssertTrue(background.contains { $0.category == .roomOrBed })
        XCTAssertTrue((byField["answerText"] ?? []).isEmpty)
        // Year ranges like 2024-2026 may or may not match date patterns; if they
        // do, doctrine prefers false positives. Assert only that strategy has no MRN/phone.
        let strategyCategories = Set((byField["searchStrategy"] ?? []).map(\.category))
        XCTAssertFalse(strategyCategories.contains(.medicalRecordNumber))
        XCTAssertFalse(strategyCategories.contains(.phoneNumber))
    }

    func testCleanClinicalTextStillAvoidsOverFlaggingDoses() {
        let cleanSamples = [
            "Vancomycin 1250 mg IV q12h; trough 12 mcg/mL.",
            "Metoprolol tartrate 25 mg PO BID.",
            "eGFR approximately 58 mL/min/1.73 m2; potassium 4.2.",
            "NDC 00093-0058-01 inventory check.",
            "Half of one tablet with food.",
            "Store at room temperature; no room assignment recorded.",
            "An 89-year-old adult with stable creatinine.",
            "Linezolid and sertraline interaction: monitor for serotonin toxicity.",
        ]
        for text in cleanSamples {
            let found = categories(in: text)
            XCTAssertTrue(
                found.isEmpty,
                "Unexpected finding in clean clinical text"
            )
            if found.isEmpty == false {
                XCTFail(text)
            }
        }
    }
}
