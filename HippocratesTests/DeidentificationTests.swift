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
}
