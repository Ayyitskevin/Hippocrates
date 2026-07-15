import Foundation
import XCTest
@testable import Hippocrates

final class PrivacyManifestTests: XCTestCase {
    func testAppPrivacyManifestDeclaresNoTrackingAndNoCollectedData() throws {
        let manifestPath = try XCTUnwrap(
            Bundle.main.path(forResource: "PrivacyInfo", ofType: "xcprivacy")
        )
        let data = try XCTUnwrap(FileManager.default.contents(atPath: manifestPath))
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        let manifest = try XCTUnwrap(object as? [String: Any])

        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.count, 0)
        // Apple TN3181 says to omit these keys when their arrays would be empty.
        XCTAssertNil(manifest["NSPrivacyTrackingDomains"])
        XCTAssertNil(manifest["NSPrivacyAccessedAPITypes"])
    }
}
