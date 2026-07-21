import XCTest

@MainActor
final class RXCalcCatalogAccessibilityTests: XCTestCase {
    private let timeout = 10.0

    func testCatalogAtAccessibility5OnCompactPhone() throws {
        continueAfterFailure = false

        let app = XCUIApplication()
        app.launch()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: timeout), "The app window did not appear")
        XCTAssertLessThanOrEqual(
            window.frame.width,
            375,
            "This contract must run on a compact iPhone viewport"
        )

        completeFirstRunIfNeeded(in: app)
        openRXCalc(in: app)

        XCTAssertTrue(
            app.navigationBars["RXcalc"].waitForExistence(timeout: timeout),
            "The RXcalc catalog did not appear"
        )

        let searchField = app.searchFields.firstMatch
        if searchField.waitForExistence(timeout: 2) == false || searchField.isHittable == false {
            app.swipeDown()
        }
        XCTAssertTrue(
            searchField.waitForExistence(timeout: timeout) && searchField.isHittable,
            "RXcalc search must remain reachable at Accessibility 5"
        )

        assertReachableText("Draft clinical content", in: app)
        // Long Draft copy exceeds XCUITest's 128-character identifier query
        // limit and NSPredicate is scanner-forbidden, so assert via stable
        // accessibility identifiers plus full label equality.
        assertReachableLabeledElement(
            identifier: "rxcalc.catalog.reviewTitle",
            expectedLabel: "Draft clinical content",
            in: app
        )
        assertReachableLabeledElement(
            identifier: "rxcalc.catalog.reviewMessage",
            expectedLabel: "This development build has not passed independent clinical review. Do not use RXcalc for patient care. It performs source-identified arithmetic only.",
            in: app
        )
        assertReachableLabeledElement(
            identifier: "rxcalc.catalog.nonRetentionWarning",
            expectedLabel: "Inputs and results stay on this screen and are never saved. Do not enter patient identifiers.",
            in: app
        )
        try auditVisibleCatalog(in: app, attachmentName: "RXcalc catalog warning")

        assertReachableText("Body Size", in: app)
        try assertCatalogRow(
            identifier: "rxcalc.catalog.bodySize",
            title: "BMI and BSA",
            summary: "Calculates adult BMI and Mosteller body surface area from one height and weight entry.",
            in: app
        )

        assertReachableText("Renal", in: app)
        try assertCatalogRow(
            identifier: "rxcalc.catalog.ckdEPI2021",
            title: "2021 CKD-EPI eGFR",
            summary: "Estimates race-free adult GFR from age, standardized serum creatinine, and equation sex.",
            in: app
        )
        try assertCatalogRow(
            identifier: "rxcalc.catalog.creatinineClearance",
            title: "Creatinine Clearance",
            summary: "Estimates unindexed adult creatinine clearance from age, entered calculation weight, serum creatinine, and equation sex.",
            destinationTitle: "Creatinine Clearance",
            in: app
        )
    }

    private func completeFirstRunIfNeeded(in app: XCUIApplication) {
        let welcome = app.staticTexts["Welcome to Hippocrates"]
        guard welcome.waitForExistence(timeout: timeout) else {
            XCTAssertTrue(
                app.tabBars.firstMatch.waitForExistence(timeout: timeout),
                "The app showed neither first run nor the post-first-run tab shell"
            )
            return
        }

        let responsibilityButton = app.buttons["I understand my responsibilities"]
        XCTAssertTrue(
            reveal(responsibilityButton, in: app, maximumSwipes: 20),
            "The responsibility acknowledgement was not reachable"
        )
        responsibilityButton.tap()

        let categoriesButton = app.buttons["Add selected categories"]
        XCTAssertTrue(
            reveal(categoriesButton, in: app, maximumSwipes: 60),
            "The starter-category action was not reachable"
        )
        categoriesButton.tap()

        XCTAssertTrue(
            app.tabBars.firstMatch.waitForExistence(timeout: timeout),
            "First run did not complete into the post-first-run tab shell"
        )
    }

    private func openRXCalc(in app: XCUIApplication) {
        let directTab = app.tabBars.buttons["RXcalc"]
        if directTab.waitForExistence(timeout: 2) && directTab.isHittable {
            directTab.tap()
            return
        }

        let moreTab = app.tabBars.buttons["More"]
        XCTAssertTrue(
            moreTab.waitForExistence(timeout: timeout) && moreTab.isHittable,
            "Neither RXcalc nor the compact-layout More tab was reachable"
        )
        moreTab.tap()

        let rxCalcCell = app.cells.containing(.staticText, identifier: "RXcalc").firstMatch
        if rxCalcCell.waitForExistence(timeout: 3) {
            rxCalcCell.tap()
            return
        }

        let rxCalcText = app.staticTexts["RXcalc"].firstMatch
        XCTAssertTrue(
            rxCalcText.waitForExistence(timeout: timeout) && rxCalcText.isHittable,
            "RXcalc was not reachable from the More tab"
        )
        rxCalcText.tap()
    }

    private func assertReachableText(_ text: String, in app: XCUIApplication) {
        let element = app.staticTexts[text].firstMatch
        XCTAssertTrue(
            reveal(element, in: app, maximumSwipes: 20),
            "Expected complete catalog text was not reachable"
        )
        XCTAssertTrue(
            app.windows.firstMatch.frame.intersects(element.frame),
            "Expected catalog text was outside the visible compact viewport"
        )
    }

    private func assertReachableLabeledElement(
        identifier: String,
        expectedLabel: String,
        in app: XCUIApplication
    ) {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(
            reveal(element, in: app, maximumSwipes: 20),
            "Expected catalog element was not reachable"
        )
        XCTAssertEqual(
            element.label,
            expectedLabel,
            "Expected complete catalog label text"
        )
        XCTAssertTrue(
            app.windows.firstMatch.frame.intersects(element.frame),
            "Expected catalog text was outside the visible compact viewport"
        )
    }

    private func assertCatalogRow(
        identifier: String,
        title: String,
        summary: String,
        destinationTitle: String? = nil,
        in app: XCUIApplication
    ) throws {
        let row = app.buttons[identifier].firstMatch
        XCTAssertTrue(
            reveal(row, in: app, maximumSwipes: 20),
            "A catalog row was not reachable"
        )
        XCTAssertTrue(row.label.contains(title), "A catalog title was incomplete")
        XCTAssertTrue(row.label.contains(summary), "A catalog summary was incomplete")
        XCTAssertTrue(
            row.label.contains("Draft — independent clinical review required"),
            "A catalog Draft status was missing"
        )
        XCTAssertTrue(
            app.windows.firstMatch.frame.intersects(row.frame),
            "A catalog row was outside the visible compact viewport"
        )

        try auditVisibleCatalog(in: app, attachmentName: identifier)

        if let destinationTitle {
            XCTAssertTrue(
                reveal(row, in: app, maximumSwipes: 20),
                "An audited catalog button was not reachable for activation"
            )
            row.tap()
            XCTAssertTrue(
                app.navigationBars[destinationTitle].waitForExistence(timeout: timeout),
                "The catalog button did not open its calculator"
            )
        }
    }

    private func auditVisibleCatalog(in app: XCUIApplication, attachmentName: String) throws {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = attachmentName
        attachment.lifetime = .keepAlways
        add(attachment)

        // Fail closed: catalog controls must retain valid traits, usable hit
        // regions, Dynamic Type, and unclipped text at Accessibility 5.
        try app.performAccessibilityAudit(for: [
            .dynamicType,
            .hitRegion,
            .textClipped,
            .trait,
        ])
    }

    private func reveal(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maximumSwipes: Int
    ) -> Bool {
        for _ in 0..<maximumSwipes {
            if element.exists && element.isHittable {
                return true
            }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }
}
