import Foundation
import XCTest
@testable import Hippocrates

final class PrivacyManifestTests: XCTestCase {
    private struct ManifestContract: Decodable {
        let tracking: Bool
        let collectedDataTypes: [String]

        private enum CodingKeys: String, CodingKey {
            case tracking = "NSPrivacyTracking"
            case collectedDataTypes = "NSPrivacyCollectedDataTypes"
        }
    }

    private final class ManifestRootKeyCounter: NSObject, XMLParserDelegate {
        private var elementStack: [String] = []
        private var currentRootKey: String?
        private(set) var rootKeyCounts: [String: Int] = [:]

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            if elementName == "key", elementStack == ["plist", "dict"] {
                currentRootKey = ""
            }
            elementStack.append(elementName)
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            if elementName == "key",
                elementStack == ["plist", "dict", "key"],
                let key = currentRootKey {
                rootKeyCounts[key, default: 0] += 1
                currentRootKey = nil
            }
            elementStack.removeLast()
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard currentRootKey != nil else { return }
            currentRootKey!.append(contentsOf: string)
        }
    }

    func testAppPrivacyManifestDeclaresNoTrackingAndNoCollectedData() throws {
        let manifestPath = try XCTUnwrap(
            Bundle.main.path(forResource: "PrivacyInfo", ofType: "xcprivacy")
        )
        let data = try XCTUnwrap(FileManager.default.contents(atPath: manifestPath))
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        let manifest = try XCTUnwrap(object as? [String: Any])

        let expectedKeys = Set(["NSPrivacyTracking", "NSPrivacyCollectedDataTypes"])
        XCTAssertEqual(Set(manifest.keys), expectedKeys)
        let keyCounter = ManifestRootKeyCounter()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = keyCounter
        XCTAssertTrue(parser.parse())
        XCTAssertEqual(
            keyCounter.rootKeyCounts,
            ["NSPrivacyTracking": 1, "NSPrivacyCollectedDataTypes": 1]
        )
        let contract = try PropertyListDecoder().decode(ManifestContract.self, from: data)
        XCTAssertFalse(contract.tracking)
        XCTAssertTrue(contract.collectedDataTypes.isEmpty)
        // Apple TN3181 says to omit these keys when their arrays would be empty.
        XCTAssertNil(manifest["NSPrivacyTrackingDomains"])
        XCTAssertNil(manifest["NSPrivacyAccessedAPITypes"])
    }
}
