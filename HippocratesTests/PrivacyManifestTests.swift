import Foundation
import XCTest
@testable import Hippocrates

final class PrivacyManifestTests: XCTestCase {
    func testAppPrivacyManifestDeclaresNoTrackingAndNoCollectedData() throws {
        let manifestURL = try XCTUnwrap(
            Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy")
        )
        let data = try Data(contentsOf: manifestURL)
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        let manifest = try XCTUnwrap(object as? [String: Any])

        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.count, 0)
        // Apple TN3181 says to omit these keys when their arrays would be empty.
        XCTAssertNil(manifest["NSPrivacyTrackingDomains"])
        XCTAssertNil(manifest["NSPrivacyAccessedAPITypes"])
    }
}
