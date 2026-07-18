#!/usr/bin/env swift

import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

private enum SourceRuleID: String {
    case urlSession
    case nsURLConnection
    case nwConnection
    case cfSocket
    case webView
    case safariController
    case urlRequest
    case openURL
    case link
    case shareLink
    case uiApplication
    case urlComponents
    case foundationURLValue
    case contentsOfLoader
    case urlBackedStream
    case fileBoundarySurface
    case externalDataIngress
    case securityScopedResource
    case pathFileAccess
    case hostStream
    case lowLevelNetwork
    case managedCloudKit
    case conditionalCompilation
    case dynamicInvocation
    case modelDeletion
    case implicitResourceLoader
    case richTextLink
    case asyncImage
    case ubiquitousStore
    case escapedIdentifier
    case unicodeEscape
    case bareSlashToken
    case externalAddressLiteral
}

private struct Finding: Equatable {
    let path: String
    let line: Int
    let message: String
    let sourceRuleID: SourceRuleID?

    init(path: String, line: Int, message: String, sourceRuleID: SourceRuleID? = nil) {
        self.path = path
        self.line = line
        self.message = message
        self.sourceRuleID = sourceRuleID
    }
}

private struct SourceRule {
    let id: SourceRuleID
    let pattern: String
    let message: String
}

private enum LexMode {
    case code
    case lineComment
    case blockComment
    case string
    case extendedRegex
}

/// Removes Swift comments while preserving code, string literals, and line
/// positions. A grep is not enough here: `https://` inside a string contains the
/// same `//` characters that begin a comment, and Swift block comments can nest.
private func lexedSource(_ source: String, preservingLiterals: Bool) -> String {
    let characters = Array(source)
    var output: [Character] = []
    output.reserveCapacity(characters.count)

    var index = 0
    var mode = LexMode.code
    var blockDepth = 0
    var stringHashCount = 0
    var stringQuoteCount = 1
    var regexHashCount = 0

    func character(at offset: Int) -> Character? {
        guard offset >= 0, offset < characters.count else { return nil }
        return characters[offset]
    }

    func quoteCount(at offset: Int) -> Int {
        guard character(at: offset) == "\"" else { return 0 }
        if character(at: offset + 1) == "\"", character(at: offset + 2) == "\"" {
            return 3
        }
        return 1
    }

    func appendSpaces(_ count: Int) {
        output.append(contentsOf: repeatElement(" ", count: count))
    }
    func appendLiteral(_ literalCharacters: ArraySlice<Character>) {
        for character in literalCharacters {
            output.append(
                preservingLiterals || character == "\n" ? character : " "
            )
        }
    }

    func appendLiteral(_ character: Character) {
        output.append(preservingLiterals || character == "\n" ? character : " ")
    }


    while index < characters.count {
        let current = characters[index]

        switch mode {
        case .code:
            if current == "/", character(at: index + 1) == "/" {
                appendSpaces(2)
                index += 2
                mode = .lineComment
                continue
            }

            if current == "/", character(at: index + 1) == "*" {
                appendSpaces(2)
                index += 2
                blockDepth = 1
                mode = .blockComment
                continue
            }

            var rawHashes = 0
            if current == "#" {
                var cursor = index
                while character(at: cursor) == "#" {
                    rawHashes += 1
                    cursor += 1
                }

                // Extended regex literals use #/.../# (or more hashes). Their
                // pattern may legitimately contain `//`; treating that as a
                // comment could hide live code after the closing delimiter.
                if character(at: cursor) == "/" {
                    appendLiteral(characters[index...cursor])
                    index = cursor + 1
                    regexHashCount = rawHashes
                    mode = .extendedRegex
                    continue
                }

                let quotes = quoteCount(at: cursor)
                if quotes > 0 {
                    appendLiteral(characters[index..<(cursor + quotes)])
                    index = cursor + quotes
                    stringHashCount = rawHashes
                    stringQuoteCount = quotes
                    mode = .string
                    continue
                }
            }

            let quotes = quoteCount(at: index)
            if quotes > 0 {
                appendLiteral(characters[index..<(index + quotes)])
                index += quotes
                stringHashCount = 0
                stringQuoteCount = quotes
                mode = .string
                continue
            }

            output.append(current)
            index += 1

        case .lineComment:
            if current == "\n" {
                output.append(current)
                index += 1
                mode = .code
            } else {
                output.append(" ")
                index += 1
            }

        case .blockComment:
            if current == "/", character(at: index + 1) == "*" {
                appendSpaces(2)
                index += 2
                blockDepth += 1
                continue
            }

            if current == "*", character(at: index + 1) == "/" {
                appendSpaces(2)
                index += 2
                blockDepth -= 1
                if blockDepth == 0 {
                    mode = .code
                }
                continue
            }

            output.append(current == "\n" ? "\n" : " ")
            index += 1

        case .string:
            // Backslash escapes apply to ordinary Swift strings. Raw strings use
            // a matching number of `#` characters and do not take this branch.
            if stringHashCount == 0, current == "\\", character(at: index + 1) != nil {
                appendLiteral(current)
                appendLiteral(characters[index + 1])
                index += 2
                continue
            }

            let hasClosingQuotes = quoteCount(at: index) == stringQuoteCount
            if hasClosingQuotes {
                let hashesStart = index + stringQuoteCount
                var closesRawString = true
                for hashOffset in 0..<stringHashCount {
                    if character(at: hashesStart + hashOffset) != "#" {
                        closesRawString = false
                        break
                    }
                }

                if closesRawString {
                    let end = hashesStart + stringHashCount
                    appendLiteral(characters[index..<end])
                    index = end
                    mode = .code
                    continue
                }
            }

            appendLiteral(current)
            index += 1

        case .extendedRegex:
            if current == "\\", character(at: index + 1) != nil {
                appendLiteral(current)
                appendLiteral(characters[index + 1])
                index += 2
                continue
            }

            if current == "/" {
                var closesRegex = true
                for hashOffset in 0..<regexHashCount {
                    if character(at: index + 1 + hashOffset) != "#" {
                        closesRegex = false
                        break
                    }
                }
                if closesRegex {
                    let end = index + 1 + regexHashCount
                    appendLiteral(characters[index..<end])
                    index = end
                    mode = .code
                    continue
                }
            }

            appendLiteral(current)
            index += 1
        }
    }

    return String(output)
}

private func sourceWithoutComments(_ source: String) -> String {
    lexedSource(source, preservingLiterals: true)
}

private func sourceForStructure(_ source: String) -> String {
    lexedSource(source, preservingLiterals: false)
}

private let sourceRules: [SourceRule] = [
    SourceRule(id: .urlSession, pattern: #"\bURLSession[A-Za-z0-9_]*\b"#, message: "URLSession violates the no-network boundary"),
    SourceRule(id: .nsURLConnection, pattern: #"\bNSURLConnection\b"#, message: "NSURLConnection violates the no-network boundary"),
    SourceRule(id: .nwConnection, pattern: #"\bNWConnection\b"#, message: "NWConnection violates the no-network boundary"),
    SourceRule(id: .cfSocket, pattern: #"\bCFSocket[A-Za-z0-9_]*\b"#, message: "CFSocket violates the no-network boundary"),
    SourceRule(id: .webView, pattern: #"\bWKWebView\b"#, message: "WKWebView violates the no-network boundary"),
    SourceRule(
        id: .safariController,
        pattern: #"\bSFSafariViewController\b"#,
        message: "SFSafariViewController can open a network surface"
    ),
    SourceRule(id: .urlRequest, pattern: #"\bURLRequest\b"#, message: "URLRequest violates the no-network boundary"),
    SourceRule(
        id: .openURL,
        pattern: #"\b(?:openURL|onOpenURL|OpenURLAction|handlesExternalEvents)\b"#,
        message: "openURL violates the no-network boundary"
    ),
    SourceRule(id: .link, pattern: #"\bLink\b"#, message: "Link can open a network surface; use plain citation text"),
    SourceRule(
        id: .shareLink,
        pattern: #"\bShareLink\b"#,
        message: "ShareLink requires a separately reviewed, app-owned transfer boundary"
    ),
    SourceRule(
        id: .asyncImage,
        pattern: #"\bAsyncImage\b"#,
        message: "AsyncImage violates the no-network boundary"
    ),
    SourceRule(
        id: .uiApplication,
        pattern: #"\bUIApplication\b"#,
        message: "UIApplication can open an external network surface"
    ),
    SourceRule(
        id: .urlComponents,
        pattern: #"\b(?:URLComponents|NSURLComponents)\b"#,
        message: "URLComponents can construct an external network destination"
    ),
    SourceRule(
        id: .foundationURLValue,
        pattern: #"\b(?:URL|NSURL)\b"#,
        message: "Foundation URL values are forbidden in shipping code; use FileDocument or Data transfer"
    ),
    SourceRule(
        id: .contentsOfLoader,
        pattern: #"(?:(?:\b(?:Data|NSData|String|NSString|NSArray|NSDictionary|XMLParser|NSXMLParser)\s*(?:\.\s*init)?|\.\s*init)\s*\(\s*contentsOf\s*:|\bNSAttributedString\s*(?:\.\s*init)?\s*\(\s*url\s*:)"#,
        message: "contentsOf URL loading is forbidden"
    ),
    SourceRule(
        id: .urlBackedStream,
        pattern: #"(?:(?:\b(?:InputStream|NSInputStream|OutputStream|NSOutputStream)\s*(?:\.\s*init)?\s*\(\s*(?:url|fileAtPath|toFileAtPath)\s*:)|\.\s*init\s*\(\s*(?:url|fileAtPath|toFileAtPath)\s*:)"#,
        message: "URL-backed initializers and URL/path-backed streams require explicit local-file boundary review"
    ),
    SourceRule(
        id: .fileBoundarySurface,
        pattern: #"\b(?:fileImporter|fileExporter|fileMover|DocumentGroup|DocumentGroupLaunchScene|DocumentLaunchView|documentBrowserContextMenu|UIDocumentPickerViewController|UIDocumentBrowserViewController|UIDocumentInteractionController)\b"#,
        message: "File-picker and document-browser surfaces require explicit local-file boundary review"
    ),
    SourceRule(
        id: .externalDataIngress,
        pattern: #"(?:\.\s*(?:onDrop|dropDestination|pasteDestination|onPasteCommand|onContinueUserActivity|loadItem|loadObject|loadDataRepresentation|loadFileRepresentation|loadInPlaceFileRepresentation|loadTransferable)\s*\(|\b(?:NSItemProvider|PasteButton|NSUserActivity|OpenDocumentAction|NewDocumentAction)\b|\bimportedContentType\s*:)"#,
        message: "External drop, paste, item-provider, and activity ingress requires explicit restore-boundary review"
    ),
    SourceRule(
        id: .securityScopedResource,
        pattern: #"\b(?:startAccessingSecurityScopedResource|stopAccessingSecurityScopedResource|CFURLStartAccessingSecurityScopedResource|CFURLStopAccessingSecurityScopedResource|bookmarkData|resolvingBookmarkData|withSecurityScope|securityScopeAllowOnlyReadAccess)\b"#,
        message: "Security-scoped file access requires the reviewed local-file adapter"
    ),
    SourceRule(
        id: .pathFileAccess,
        pattern: #"(?:(?:\b(?:Data|NSData|String|NSString|NSArray|NSDictionary)\s*(?:\.\s*init)?|\.\s*init)\s*\(\s*contentsOf(?:Mapped)?File\s*:|\.\s*(?:contents(?:Equal)?|subpaths|subpathsOfDirectory)\s*\(\s*atPath\s*:|\.\s*(?:contentsOfDirectory|enumerator)\s*\(\s*at(?:Path)?\s*:|(?:(?:\b(?:FileHandle|NSFileHandle)\s*(?:\.\s*init)?|\.\s*init)\s*\(\s*for(?:ReadingFrom(?:URL)?|WritingTo(?:URL)?|Updating(?:URL)?|ReadingAtPath|WritingAtPath|UpdatingAtPath)\s*:)|\bFileWrapper\s*(?:\.\s*init)?\s*\(\s*url\s*:|\.\s*(?:read\s*\(\s*from|matchesContents\s*\(\s*of)\s*:|\bNSKeyedUnarchiver\s*\.\s*unarchive[A-Za-z0-9_]*\s*\(\s*withFile\s*:|\b(?:NSFileCoordinator|NSFilePresenter)\b)"#,
        message: "Path-based file access requires explicit local-file boundary review"
    ),
    SourceRule(
        id: .hostStream,
        pattern: #"\b(?:Stream|NSStream)\s*\.\s*getStreamsToHost\b"#,
        message: "Host-backed streams violate the no-network boundary"
    ),
    SourceRule(
        id: .lowLevelNetwork,
        pattern: #"\b(?:socket|socketpair|connect|bind|listen|accept|send|sendto|recv|recvfrom|getaddrinfo|freeaddrinfo|getnameinfo|gethostbyname|gethostbyname2|gethostbyaddr|getipnodebyname|getipnodebyaddr|inet_addr|inet_pton|inet_ntop|(?:NS)?NetService(?:Browser)?|CFNetService[A-Za-z0-9_]*|CF(?:Read|Write)?Stream[A-Za-z0-9_]*|CFHost[A-Za-z0-9_]*|CFURLCreate[A-Za-z0-9_]*|SCNetworkReachability[A-Za-z0-9_]*)\b"#,
        message: "Low-level socket or host lookup APIs violate the no-network boundary"
    ),
    SourceRule(
        id: .ubiquitousStore,
        pattern: #"\b(?:NSUbiquitousKeyValueStore|NSMetadataQuery|ubiquityIdentityToken|ubiquitousItem[A-Za-z0-9_]*|startDownloadingUbiquitousItem|evictUbiquitousItem|setUbiquitous|isUbiquitousItem|forPublishingUbiquitousItemAt)\b|\burl\s*\(\s*forUbiquityContainerIdentifier\s*:"#,
        message: "iCloud and ubiquity APIs violate the no-network boundary"
    ),
    SourceRule(
        id: .managedCloudKit,
        pattern: #"\bcloudKitDatabase\s*:(?!\s*\.none\b)|\.\s*modelContainer\s*\(\s*for\s*:"#,
        message: "SwiftData managed CloudKit must remain explicitly disabled"
    ),
    SourceRule(
        id: .conditionalCompilation,
        pattern: #"(?m)^\s*#(?:if|elseif|else|endif)\b"#,
        message: "Conditional compilation is forbidden inside the reviewed source boundary"
    ),
    SourceRule(
        id: .dynamicInvocation,
        pattern: #"@\s*_[A-Za-z0-9_]+|\b(?:NSExpression|NSPredicate|NSInvocation|NSProxy|NSMethodSignature|NSClassFromString|NSSelectorFromString|Selector|Unmanaged|Unsafe[A-Za-z0-9_]*|unsafe[A-Z][A-Za-z0-9_]*|withUnsafe(?!(?:Continuation|ThrowingContinuation|CurrentTask)\b)[A-Za-z0-9_]*|withContiguousStorageIfAvailable|copyBytes|withVaList|CFBridgingRetain|CFBridgingRelease|dlopen|dlsym|objc_msgSend|class_createInstance|objc_allocateClassPair|object_getClass|class_getMethodImplementation|method_getImplementation|valueForKey|valueForKeyPath|setValue|setValuesForKeys|mutableArrayValue|mutableSetValue|mutableOrderedSetValue|dictionaryWithValues)\b|\.\s*(?:fromOpaque|toOpaque|assumingMemoryBound|bindMemory|withMemoryRebound|load|loadUnaligned|storeBytes|copyMemory|perform|method)\s*\(|\.\s*(?:value|mutableArrayValue|mutableSetValue|mutableOrderedSetValue|dictionaryWithValues)\s*\(\s*(?:forKey|forKeyPath|forKeys)\s*:"#,
        message: "Dynamic invocation, unsafe memory, and runtime symbol lookup are forbidden inside the reviewed source boundary"
    ),
    SourceRule(
        id: .modelDeletion,
        pattern: #"\.\s*delete\b"#,
        message: "Model deletion requires an explicitly reviewed lifecycle service"
    ),
    SourceRule(
        id: .implicitResourceLoader,
        pattern: #"\.\s*(?:resourceBytes|lines)\b"#,
        message: "Implicit URL resource loading is forbidden inside the reviewed source boundary"
    ),
    SourceRule(
        id: .richTextLink,
        pattern: #"\b(?:LocalizedStringKey|AttributedString)\b|\]\s*\(|\bText\s*(?:\.\s*init)?\s*\(\s*\.\s*init\s*\("#,
        message: "Rich-text link construction is forbidden; citations must remain plain text"
    ),
    SourceRule(
        id: .unicodeEscape,
        pattern: #"\\u\s*\{[0-9A-Fa-f_]+\}"#,
        message: "Unicode escapes are forbidden because they can hide reviewed address and rich-text syntax"
    ),
    SourceRule(
        id: .externalAddressLiteral,
        pattern: #"(?i)\b(?:https?|wss?|ftp)://[^\s"']+|\b(?:mailto|tel|sms):[^\s"']+"#,
        message: "External address literals are forbidden in shipping source"
    )
]

private let projectRules: [(token: String, message: String)] = [
    ("Network.framework", "Network.framework must not be linked"),
    ("WebKit.framework", "WebKit.framework must not be linked"),
    ("CFNetwork.framework", "CFNetwork.framework must not be linked"),
    ("OTHER_LDFLAGS", "Custom linker flags require explicit offline-boundary review"),
    ("OTHER_SWIFT_FLAGS", "Custom Swift compiler flags are forbidden"),
    ("OTHER_CFLAGS", "Custom C compiler flags are forbidden"),
    ("OTHER_CPLUSPLUSFLAGS", "Custom C++ compiler flags are forbidden"),
    ("SWIFT_OBJC_BRIDGING_HEADER", "Objective-C bridging headers are forbidden"),
    ("GCC_PREFIX_HEADER", "Prefix headers are forbidden"),
    ("MODULEMAP_FILE", "Custom module maps are forbidden"),
    ("SWIFT_INCLUDE_PATHS", "Custom Swift include paths are forbidden"),
    ("HEADER_SEARCH_PATHS", "Custom header search paths are forbidden"),
    ("FRAMEWORK_SEARCH_PATHS", "Custom framework search paths are forbidden"),
    ("LIBRARY_SEARCH_PATHS", "Custom library search paths are forbidden"),
    ("baseConfigurationReference", "XCConfig injection is forbidden"),
    ("CODE_SIGN_ENTITLEMENTS", "Entitlements require explicit architecture review"),
    ("wrapper.framework", "Binary frameworks are forbidden"),
    ("wrapper.xcframework", "Binary XCFrameworks are forbidden"),
    ("wrapper.pb-project", "Xcode subprojects are forbidden"),
    ("PBXReferenceProxy", "Xcode subproject products are forbidden"),
    ("isa = PBXBuildRule;", "Custom build rules are forbidden"),
    ("PBXHeadersBuildPhase", "Header build phases are forbidden"),
    ("PBXCopyFilesBuildPhase", "Copy-files build phases are forbidden"),
    ("PBXAggregateTarget", "Aggregate targets are forbidden"),
    ("PBXLegacyTarget", "Legacy targets are forbidden"),
    ("PBXFileSystemSynchronizedRootGroup", "Synchronized filesystem groups are forbidden"),
    ("PBXFileSystemSynchronizedBuildFileExceptionSet", "Synchronized build-file exceptions are forbidden"),
    ("fileSystemSynchronizedGroups", "Synchronized target groups are forbidden"),
    ("XCRemoteSwiftPackageReference", "Remote Swift Package dependencies are forbidden"),
    ("XCLocalSwiftPackageReference", "Local Swift Package dependencies are forbidden"),
    ("XCSwiftPackageProductDependency", "Swift Package products are forbidden"),
    ("packageReferences", "Project package references are forbidden"),
    ("packageProductDependencies", "Target package products are forbidden")
]

private let projectSettingRules: [(pattern: String, message: String)] = [
    (
        #""?\b(?:SWIFT_EXEC|SWIFT_DRIVER_[A-Za-z0-9_]*|CC|CPLUSPLUS|LD|LDPLUSPLUS|LIBTOOL|TOOLCHAINS|EXCLUDED_SOURCE_FILE_NAMES|INCLUDED_SOURCE_FILE_NAMES|RULE_LAUNCH_[A-Za-z0-9_]*|PATH|BASH_ENV|ENV|DEVELOPER_DIR|DYLD_INSERT_LIBRARIES|DYLD_LIBRARY_PATH|DYLD_FRAMEWORK_PATH|LD_PRELOAD|SRCROOT|PROJECT_DIR|PROJECT_FILE_PATH|TMPDIR|HOME)(?:\[[^\]\r\n=]+\])*"?\s*="#,
        "Custom build tools, process environments, and source inclusion/exclusion settings are forbidden"
    )
]

private func projectPolicyFindings(in projectText: String, path: String) -> [Finding] {
    let visibleProjectText = pbxWithoutComments(projectText)
    var results: [Finding] = projectRules.compactMap { rule in
        guard visibleProjectText.contains(rule.token) else { return nil }
        return Finding(path: path, line: 1, message: rule.message)
    }

    var buildSettingBlocks: [String] = []
    do {
        let objects = try pbxObjects(in: projectText).mapValues(pbxWithoutComments)
        for object in objects.values where try pbxISA(in: object) == "XCBuildConfiguration" {
            guard
                let settings = try pbxTopLevelProperties(in: object)["buildSettings"],
                settings.first == "{",
                settings.last == "}"
            else {
                throw pbxParserError(41, "XCBuildConfiguration has no parseable buildSettings dictionary")
            }
            buildSettingBlocks.append(settings)
        }
    } catch {
        results.append(
            Finding(path: path, line: 1, message: "Xcode build settings could not be parsed for boundary policy")
        )
        return results
    }

    for settings in buildSettingBlocks {
        if settings.contains("\\") {
            results.append(
                Finding(path: path, line: 1, message: "Escapes inside Xcode build settings are forbidden")
            )
        }
        for rule in projectSettingRules
        where settings.range(of: rule.pattern, options: .regularExpression) != nil {
            results.append(Finding(path: path, line: 1, message: rule.message))
        }
    }
    return results
}


private let shippingAllowedImports: Set<String> = [
    "Charts",
    "CoreTransferable",
    "Foundation",
    "SwiftData",
    "SwiftUI",
    "UniformTypeIdentifiers"
]

private let testAllowedImports: Set<String> = [
    "Foundation",
    "Hippocrates",
    "SwiftData",
    "XCTest"
]

private func lineNumber(in text: String, at utf16Location: Int) -> Int {
    guard let range = Range(NSRange(location: 0, length: utf16Location), in: text) else {
        return 1
    }
    return text[range].reduce(into: 1) { line, character in
        if character == "\n" { line += 1 }
    }
}

private func findings(
    in source: String,
    path: String,
    allowing exception: ((SourceRuleID, String) -> Bool)? = nil
) throws -> [Finding] {
    let visibleSource = sourceWithoutComments(source)
    let fullRange = NSRange(visibleSource.startIndex..<visibleSource.endIndex, in: visibleSource)
    var results: [Finding] = []

    for rule in sourceRules {
        let expression = try NSRegularExpression(pattern: rule.pattern)
        for match in expression.matches(in: visibleSource, range: fullRange) {
            guard let matchRange = Range(match.range, in: visibleSource) else { continue }
            let matchedText = String(visibleSource[matchRange])
            if exception?(rule.id, matchedText) == true {
                continue
            }
            results.append(
                Finding(
                    path: path,
                    line: lineNumber(in: visibleSource, at: match.range.location),
                    message: rule.message,
                    sourceRuleID: rule.id
                )
            )
        }
    }
    let structuralSource = sourceForStructure(source)
    if let backtickIndex = structuralSource.firstIndex(of: "\u{60}") {
        let location = NSRange(
            structuralSource.startIndex..<backtickIndex,
            in: structuralSource
        ).length
        results.append(
            Finding(
                path: path,
                line: lineNumber(in: structuralSource, at: location),
                message: "Backticked identifiers are forbidden inside the reviewed source boundary",
                sourceRuleID: .escapedIdentifier
            )
        )
    }
    if let slashIndex = structuralSource.firstIndex(of: "/") {
        let location = NSRange(
            structuralSource.startIndex..<slashIndex,
            in: structuralSource
        ).length
        results.append(
            Finding(
                path: path,
                line: lineNumber(in: structuralSource, at: location),
                message: "Bare slash operators and regex literals require explicit boundary-parser review",
                sourceRuleID: .bareSlashToken
            )
        )
    }


    return results
}

private enum ReviewedSourceIdentity: String {
    case hippocratesApp = "Hippocrates/App/HippocratesApp.swift"
    case domainEnums = "Hippocrates/Models/DomainEnums.swift"
    case schemaV1 = "Hippocrates/Persistence/SchemaV1.swift"
    case appConfigService = "Hippocrates/Persistence/AppConfigService.swift"
    case hippocratesStore = "Hippocrates/Persistence/HippocratesStore.swift"
    case backupArchive = "Hippocrates/Backup/BackupArchive.swift"
    case backupService = "Hippocrates/Backup/BackupService.swift"
    case taxonomyService = "Hippocrates/Services/TaxonomyService.swift"
    case interventionLedgerService = "Hippocrates/Services/InterventionLedgerService.swift"
    case summaryView = "Hippocrates/Features/Summary/SummaryView.swift"
    case schemaContractTests = "HippocratesTests/SchemaContractTests.swift"
    case backupRoundTripTests = "HippocratesTests/BackupRoundTripTests.swift"
    case privacyManifestTests = "HippocratesTests/PrivacyManifestTests.swift"
    case other = ""
}

private func reviewedSourceIdentity(
    for file: URL,
    repositoryRoot: URL
) -> ReviewedSourceIdentity {
    let normalizedRoot = repositoryRoot.standardizedFileURL.path
    let normalizedFile = file.standardizedFileURL.path
    guard pathIsBeneath(normalizedFile, rootPath: normalizedRoot) else {
        return .other
    }
    let relativePath = String(normalizedFile.dropFirst(normalizedRoot.count + 1))
    return ReviewedSourceIdentity(rawValue: relativePath) ?? .other
}

private func testFindings(
    in source: String,
    path: String,
    identity: ReviewedSourceIdentity
) throws -> [Finding] {
    var reviewedSource = source
    var results: [Finding] = []

    func maskExactlyOnce(_ seam: String, with replacement: String) {
        let count = reviewedSource.components(separatedBy: seam).count - 1
        guard count == 1 else {
            results.append(
                Finding(
                    path: path,
                    line: 1,
                    message: "Reviewed test-only offline seam changed or was duplicated"
                )
            )
            return
        }
        reviewedSource = reviewedSource.replacingOccurrences(of: seam, with: replacement)
    }

    if identity == .schemaContractTests {
        let localStoreSeams = [
            "    private func makeFileBackedContainer(at storeLocation: URL, allowsSave: Bool = true) throws -> ModelContainer {",
            "        to storeLocation: URL,",
            "        at storeLocation: URL,"
        ]
        for seam in localStoreSeams {
            maskExactlyOnce(
                seam,
                with: seam.replacingOccurrences(of: "URL", with: "OfflineStoreLocation")
            )
        }
    } else if identity == .backupRoundTripTests {
        let citationSeam = #"            urlString: "https://example.invalid/source""#
        maskExactlyOnce(
            citationSeam,
            with: #"            urlString: "reviewed-citation.invalid""#
        )
        let pendingDeleteSeam = "        destination.mainContext.delete(existing)"
        maskExactlyOnce(
            pendingDeleteSeam,
            with: "        reviewedPendingDelete(existing)"
        )
    } else if identity == .privacyManifestTests {
        let manifestReadSeam =
            "        let data = try XCTUnwrap(FileManager.default.contents(atPath: manifestPath))"
        maskExactlyOnce(
            manifestReadSeam,
            with: "        let data = try XCTUnwrap(reviewedBundledManifestBytes)"
        )
    }

    results.append(contentsOf: try findings(in: reviewedSource, path: path))
    return results
}
private func appSourceFindings(
    in source: String,
    path: String,
    identity: ReviewedSourceIdentity
) throws -> [Finding] {
    var reviewedSource = source
    var results: [Finding] = []

    func maskExactlyOnce(_ seam: String, with replacement: String) {
        let count = reviewedSource.components(separatedBy: seam).count - 1
        guard count == 1 else {
            results.append(
                Finding(
                    path: path,
                    line: 1,
                    message: "Reviewed taxonomy lifecycle seam changed or was duplicated"
                )
            )
            return
        }
        reviewedSource = reviewedSource.replacingOccurrences(of: seam, with: replacement)
    }

    if identity == .taxonomyService {
        // Milestone 1: the one reviewed shipping model-deletion seam. Only an
        // unreferenced taxonomy row reaches it, and only through
        // TaxonomyService's checked delete paths. Every other .delete spelling
        // in shipping code remains closed.
        maskExactlyOnce(
            "        context.delete(row)",
            with: "        context.rollback()"
        )
    }

    if identity == .interventionLedgerService {
        // Milestone 2 / I-013: the one reviewed intervention-deletion seam.
        // Five-second undo and the ledger's confirmed delete both reach it
        // through InterventionLedgerService.deleteIntervention. Every other
        // .delete spelling in shipping code remains closed.
        maskExactlyOnce(
            "        context.delete(intervention)",
            with: "        context.rollback()"
        )
    }

    // Milestone 3: SummaryView owns the one reviewed ShareLink boundary. Its
    // Transferable is backed by DataRepresentation over app-owned bytes, so
    // no file URL exists and the system has no link preview to fetch.
    // ShareLink anywhere else in shipping code remains closed.
    results.append(
        contentsOf: try findings(in: reviewedSource, path: path) { ruleID, _ in
            identity == .summaryView && ruleID == .shareLink
        }
    )
    return results
}

private func importFindings(
    in source: String,
    path: String,
    allowedModules: Set<String>
) throws -> [Finding] {
    let code = sourceForStructure(source)
    let codeRange = NSRange(code.startIndex..<code.endIndex, in: code)
    let importTokenExpression = try NSRegularExpression(pattern: #"\bimport\b"#)
    let importExpression = try NSRegularExpression(
        pattern: #"\bimport\s+(?:(?:typealias|struct|class|enum|protocol|let|var|func)\s+)?((?:\x{60})?[\p{L}_][\p{L}\p{N}_]*(?:\x{60})?)"#
    )
    let tokenMatches = importTokenExpression.matches(in: code, range: codeRange)
    let importMatches = importExpression.matches(in: code, range: codeRange)
    var results: [Finding] = []

    if tokenMatches.count != importMatches.count {
        results.append(
            Finding(
                path: path,
                line: 1,
                message: "An import declaration could not be parsed against the reviewed module allowlist"
            )
        )
    }

    for match in importMatches {
        guard let moduleRange = Range(match.range(at: 1), in: code) else {
            continue
        }
        let module = String(code[moduleRange]).replacingOccurrences(of: "\u{60}", with: "")
        if allowedModules.contains(module) == false {
            results.append(
                Finding(
                    path: path,
                    line: lineNumber(in: code, at: match.range.location),
                    message: "Import \(module) is outside the reviewed module allowlist"
                )
            )
        }
    }
    return results
}

private func interpolationArchitectureFindings(
    in source: String,
    path: String,
    identity: ReviewedSourceIdentity
) throws -> [Finding] {
    let visibleSource = sourceWithoutComments(source)
    let sourceRange = NSRange(visibleSource.startIndex..<visibleSource.endIndex, in: visibleSource)
    let interpolationToken = try NSRegularExpression(pattern: #"\\(?:#+)?\("#)

    let allowedPatterns: [String]
    if identity == .hippocratesApp {
        allowedPatterns = [#"\\\(error\)"#]
    } else if identity == .backupRoundTripTests {
        allowedPatterns = [
            #"\\\(costMapKey\)"#,
            #"\\\(costMapValue\)"#,
            #"\\\(typeDefaultJSON\)"#,
            #"\\\(typeID\.uuidString\)"#
        ]
    } else if identity == .schemaContractTests {
        allowedPatterns = [#"\\\(UUID\(\)\.uuidString\)"#]
    } else {
        allowedPatterns = []
    }

    let tokenCount = interpolationToken.matches(in: visibleSource, range: sourceRange).count
    let hasEachAllowedExpression = try allowedPatterns.allSatisfy { pattern in
        let expression = try NSRegularExpression(pattern: pattern)
        return expression.matches(in: visibleSource, range: sourceRange).count == 1
    }
    guard tokenCount == allowedPatterns.count, hasEachAllowedExpression else {
        return [
            Finding(
                path: path,
                line: 1,
                message: "Executable string interpolation changed outside the exact reviewed expression allowlist"
            )
        ]
    }
    return []
}

private func architectureSemanticFindings(
    in source: String,
    path: String,
    identity: ReviewedSourceIdentity
) throws -> [Finding] {
    let visibleSource = sourceForStructure(source)
    let sourceRange = NSRange(visibleSource.startIndex..<visibleSource.endIndex, in: visibleSource)
    var results: [Finding] = []

    let shadowExpression = try NSRegularExpression(
        pattern: #"\b(?:typealias|class|struct|enum|protocol|actor|macro)\s+(?:\x{60})?(?:Foundation|Swift|Attribute|Relationship|Schema|ModelConfiguration|ModelContainer)(?:\x{60})?(?![\p{L}\p{N}_])|\b(?:func|let|var)\s+(?:\x{60})?(?:Schema|ModelConfiguration|ModelContainer)(?:\x{60})?(?![\p{L}\p{N}_])|\bextension\s+(?:(?:(?:\x{60})?SchemaV1(?:\x{60})?\s*\.\s*)?(?:\x{60})?Intervention(?:\x{60})?|(?:\x{60})?HippocratesStore(?:\x{60})?)(?![\p{L}\p{N}_])"#
    )
    if let match = shadowExpression.firstMatch(in: visibleSource, range: sourceRange) {
        results.append(
            Finding(
                path: path,
                line: lineNumber(in: visibleSource, at: match.range.location),
                message: "Shipping source may not shadow or extend reviewed SwiftData architecture symbols"
            )
        )
    }

    let vocabularyExpression = try NSRegularExpression(
        pattern: #"\b(?:typealias|class|struct|enum|protocol|actor|macro)\s+(?:\x{60})?SchemaV1Vocabulary(?:\x{60})?(?![\p{L}\p{N}_])"#
    )
    let vocabularyMatches = vocabularyExpression.matches(in: visibleSource, range: sourceRange)
    let canonicalVocabularyExpression = try NSRegularExpression(
        pattern: #"\benum\s+SchemaV1Vocabulary\b"#
    )
    let isCanonicalVocabularyDeclaration = identity == .domainEnums
        && vocabularyMatches.count == 1
        && canonicalVocabularyExpression.matches(in: visibleSource, range: sourceRange).count == 1
    if vocabularyMatches.isEmpty == false, isCanonicalVocabularyDeclaration == false {
        let match = vocabularyMatches[0]
        results.append(
            Finding(
                path: path,
                line: lineNumber(in: visibleSource, at: match.range.location),
                message: "SchemaV1Vocabulary may only be declared by the canonical domain-enum source"
            )
        )
    }

    let modelConfigurationExpression = try NSRegularExpression(pattern: #"\bModelConfiguration\b"#)
    let modelContainerExpression = try NSRegularExpression(pattern: #"\bModelContainer\b"#)
    let modelConfigurationCount = modelConfigurationExpression.matches(
        in: visibleSource,
        range: sourceRange
    ).count
    let modelContainerCount = modelContainerExpression.matches(
        in: visibleSource,
        range: sourceRange
    ).count
    let isStore = identity == .hippocratesStore
    let isApp = identity == .hippocratesApp

    if isStore {
        if modelConfigurationCount != 1 || modelContainerCount != 2 {
            results.append(
                Finding(
                    path: path,
                    line: 1,
                    message: "HippocratesStore owns exactly one configuration and one container construction"
                )
            )
        }
    } else {
        if modelConfigurationCount != 0 {
            results.append(
                Finding(
                    path: path,
                    line: 1,
                    message: "ModelConfiguration is owned exclusively by HippocratesStore"
                )
            )
        }

        let expectedAppContainer = try NSRegularExpression(
            pattern: #"\bprivate\s+let\s+modelContainer\s*:\s*ModelContainer\b"#
        )
        let expectedCount = expectedAppContainer.matches(in: visibleSource, range: sourceRange).count
        let containerSurfaceIsExact = isApp
            ? modelContainerCount == 1 && expectedCount == 1
            : modelContainerCount == 0
        if containerSurfaceIsExact == false {
            results.append(
                Finding(
                    path: path,
                    line: 1,
                    message: "ModelContainer may only appear in the canonical store and app-owned property seam"
                )
            )
        }
    }

    func declarationsAreExact(token: String, patterns: [String]) throws -> Bool {
        let tokenExpression = try NSRegularExpression(pattern: #"\b\#(token)\b"#)
        guard tokenExpression.matches(in: visibleSource, range: sourceRange).count == patterns.count else {
            return false
        }
        return try patterns.allSatisfy { pattern in
            let expression = try NSRegularExpression(pattern: pattern)
            return expression.matches(in: visibleSource, range: sourceRange).count == 1
        }
    }

    let allowedTypealiasPatterns: [String]
    if identity == .domainEnums {
        allowedTypealiasPatterns = [
            #"\btypealias\s+Acceptance\s*=\s*SchemaV1Vocabulary\.Acceptance\b"#,
            #"\btypealias\s+RequestorRole\s*=\s*SchemaV1Vocabulary\.RequestorRole\b"#,
            #"\btypealias\s+DIQuestionClass\s*=\s*SchemaV1Vocabulary\.DIQuestionClass\b"#,
            #"\btypealias\s+Urgency\s*=\s*SchemaV1Vocabulary\.Urgency\b"#,
            #"\btypealias\s+SourceTier\s*=\s*SchemaV1Vocabulary\.SourceTier\b"#
        ]
    } else if identity == .schemaV1 {
        allowedTypealiasPatterns = [
            #"\btypealias\s+Intervention\s*=\s*SchemaV1\.Intervention\b"#,
            #"\btypealias\s+InterventionType\s*=\s*SchemaV1\.InterventionType\b"#,
            #"\btypealias\s+DrugClass\s*=\s*SchemaV1\.DrugClass\b"#,
            #"\btypealias\s+ServiceLine\s*=\s*SchemaV1\.ServiceLine\b"#,
            #"\btypealias\s+DIQuestion\s*=\s*SchemaV1\.DIQuestion\b"#,
            #"\btypealias\s+Citation\s*=\s*SchemaV1\.Citation\b"#,
            #"\btypealias\s+AppConfig\s*=\s*SchemaV1\.AppConfig\b"#
        ]
    } else {
        allowedTypealiasPatterns = []
    }
    if try declarationsAreExact(token: "typealias", patterns: allowedTypealiasPatterns) == false {
        results.append(
            Finding(
                path: path,
                line: 1,
                message: "Shipping typealiases changed outside the reviewed architecture allowlist"
            )
        )
    }

    let allowedExtensionPatterns: [String]
    if identity == .backupArchive {
        allowedExtensionPatterns = [#"\bextension\s+BackupArchive\s*\{"#]
    } else if identity == .backupService {
        allowedExtensionPatterns = [
            #"\bextension\s+BackupArchive\.InterventionTypeRecord\s*:\s*Identifiable\s*\{\s*\}"#,
            #"\bextension\s+BackupArchive\.DrugClassRecord\s*:\s*Identifiable\s*\{\s*\}"#,
            #"\bextension\s+BackupArchive\.ServiceLineRecord\s*:\s*Identifiable\s*\{\s*\}"#,
            #"\bextension\s+BackupArchive\.InterventionRecord\s*:\s*Identifiable\s*\{\s*\}"#,
            #"\bextension\s+BackupArchive\.DIQuestionRecord\s*:\s*Identifiable\s*\{\s*\}"#,
            #"\bextension\s+BackupArchive\.CitationRecord\s*:\s*Identifiable\s*\{\s*\}"#
        ]
    } else {
        allowedExtensionPatterns = []
    }
    if try declarationsAreExact(token: "extension", patterns: allowedExtensionPatterns) == false {
        results.append(
            Finding(
                path: path,
                line: 1,
                message: "Shipping extensions changed outside the reviewed architecture allowlist"
            )
        )
    }
    return results
}

private func appConfigOwnershipFindings(
    in source: String,
    path: String,
    identity: ReviewedSourceIdentity
) throws -> [Finding] {
    let visibleSource = sourceForStructure(source)

    func count(_ pattern: String, in text: String = visibleSource) throws -> Int {
        let expression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).count
    }

    func hasExactlyOnce(_ pattern: String, in text: String = visibleSource) throws -> Bool {
        try count(pattern, in: text) == 1
    }

    func matchesEntire(_ pattern: String, in text: String) throws -> Bool {
        let expression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = expression.matches(in: text, range: range)
        guard matches.count == 1 else {
            return false
        }
        return matches[0].range.location == range.location
            && matches[0].range.length == range.length
    }

    let appConfigModelDeclaration = #"@Model\s+final\s+class\s+AppConfig\b"#
    let serviceDeclaration = #"@MainActor\s+enum\s+AppConfigService\b"#
    let appConfigExtension = #"\bextension\s+(?:SchemaV1\s*\.\s*)?AppConfig\b"#

    if identity == .schemaV1 {
        let declarationExpression = try NSRegularExpression(
            pattern: appConfigModelDeclaration
        )
        let sourceRange = NSRange(
            visibleSource.startIndex..<visibleSource.endIndex,
            in: visibleSource
        )
        let declarations = declarationExpression.matches(
            in: visibleSource,
            range: sourceRange
        )
        guard declarations.count == 1,
              let declarationRange = Range(declarations[0].range, in: visibleSource),
              let openingBrace = visibleSource[declarationRange.upperBound...].firstIndex(of: "{")
        else {
            return [
                Finding(
                    path: path,
                    line: 1,
                    message: "Canonical AppConfig model authority contract changed"
                )
            ]
        }

        var depth = 0
        var cursor = openingBrace
        var closingBrace: String.Index?
        while cursor < visibleSource.endIndex {
            let character = visibleSource[cursor]
            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    closingBrace = cursor
                    break
                }
            }
            cursor = visibleSource.index(after: cursor)
        }
        guard let closingBrace else {
            return [
                Finding(
                    path: path,
                    line: 1,
                    message: "Canonical AppConfig model authority contract changed"
                )
            ]
        }

        let body = String(visibleSource[openingBrace...closingBrace])
        let literalSource = sourceWithoutComments(source)
        let openingOffset = visibleSource.distance(
            from: visibleSource.startIndex,
            to: openingBrace
        )
        let closingOffset = visibleSource.distance(
            from: visibleSource.startIndex,
            to: closingBrace
        )
        guard literalSource.count == visibleSource.count,
              let literalOpeningBrace = literalSource.index(
                  literalSource.startIndex,
                  offsetBy: openingOffset,
                  limitedBy: literalSource.endIndex
              ),
              let literalClosingBrace = literalSource.index(
                  literalSource.startIndex,
                  offsetBy: closingOffset,
                  limitedBy: literalSource.endIndex
              )
        else {
            return [
                Finding(
                    path: path,
                    line: 1,
                    message: "Canonical AppConfig model authority contract changed"
                )
            ]
        }
        let literalBody = String(literalSource[literalOpeningBrace...literalClosingBrace])
        let bodyCharacters = Array(body)
        var topLevelCharacters = bodyCharacters
        var immediateChildOpeningOffsets: [Int] = []
        var bodyDepth = 0
        for index in bodyCharacters.indices {
            let character = bodyCharacters[index]
            if character == "{" {
                if bodyDepth == 1 {
                    immediateChildOpeningOffsets.append(index)
                }
                bodyDepth += 1
                topLevelCharacters[index] = " "
            } else if character == "}" {
                topLevelCharacters[index] = " "
                bodyDepth -= 1
            } else if bodyDepth != 1 && character != "\n" {
                topLevelCharacters[index] = " "
            }
        }
        let topLevelBody = String(topLevelCharacters)

        func callableSpan(
            matching signaturePattern: String
        ) throws -> (literal: String, openingOffset: Int)? {
            guard literalBody.count == body.count else {
                return nil
            }
            let expression = try NSRegularExpression(pattern: signaturePattern)
            let fullRange = NSRange(
                topLevelBody.startIndex..<topLevelBody.endIndex,
                in: topLevelBody
            )
            let matches = expression.matches(in: topLevelBody, range: fullRange)
            guard matches.count == 1,
                  let signatureRange = Range(matches[0].range, in: topLevelBody)
            else {
                return nil
            }

            let signatureStartOffset = topLevelBody.distance(
                from: topLevelBody.startIndex,
                to: signatureRange.lowerBound
            )
            let signatureEndOffset = topLevelBody.distance(
                from: topLevelBody.startIndex,
                to: signatureRange.upperBound
            )
            guard let bodyAfterSignature = body.index(
                body.startIndex,
                offsetBy: signatureEndOffset,
                limitedBy: body.endIndex
            ),
            let callableOpeningBrace = body[bodyAfterSignature...].firstIndex(of: "{"),
            body[bodyAfterSignature..<callableOpeningBrace].allSatisfy({ $0.isWhitespace })
            else {
                return nil
            }

            var callableDepth = 0
            var callableCursor = callableOpeningBrace
            var callableClosingBrace: String.Index?
            while callableCursor < body.endIndex {
                let character = body[callableCursor]
                if character == "{" {
                    callableDepth += 1
                } else if character == "}" {
                    callableDepth -= 1
                    if callableDepth == 0 {
                        callableClosingBrace = callableCursor
                        break
                    }
                }
                callableCursor = body.index(after: callableCursor)
            }
            guard let callableClosingBrace else {
                return nil
            }

            let callableOpeningOffset = body.distance(
                from: body.startIndex,
                to: callableOpeningBrace
            )
            let callableClosingOffset = body.distance(
                from: body.startIndex,
                to: callableClosingBrace
            )
            guard let literalSignatureStart = literalBody.index(
                literalBody.startIndex,
                offsetBy: signatureStartOffset,
                limitedBy: literalBody.endIndex
            ),
            let literalCallableEnd = literalBody.index(
                literalBody.startIndex,
                offsetBy: callableClosingOffset,
                limitedBy: literalBody.endIndex
            )
            else {
                return nil
            }
            return (
                String(literalBody[literalSignatureStart...literalCallableEnd]),
                callableOpeningOffset
            )
        }

        let requiredPropertyPatterns = [
            #"@Attribute\s*\(\s*\.unique\s*\)\s*private\s*\(\s*set\s*\)\s+var\s+singletonKey\s*:\s*String\b"#,
            #"private\s*\(\s*set\s*\)\s+var\s+stalenessIntervalMonths\s*:\s*Int\?"#,
            #"private\s*\(\s*set\s*\)\s+var\s+lastExportAt\s*:\s*Date\?"#
        ]
        let requiredInitializer = #"(?m)^[ \t]*init\s*\(\s*stalenessIntervalMonths\s*:\s*Int\?\s*,\s*lastExportAt\s*:\s*Date\?\s*,\s*authority\s*:\s*AppConfigService\s*\.\s*Authority\s*\)"#
        let requiredMutator = #"(?m)^[ \t]*func\s+updateStalenessIntervalMonths\s*\(\s*_\s+value\s*:\s*Int\?\s*,\s*authority\s*:\s*AppConfigService\s*\.\s*Authority\s*\)\s+throws\b"#
        let exactInitializer = #"(?s)[ \t]*init\s*\(\s*stalenessIntervalMonths\s*:\s*Int\?\s*,\s*lastExportAt\s*:\s*Date\?\s*,\s*authority\s*:\s*AppConfigService\s*\.\s*Authority\s*\)\s*\{\s*AppConfigService\s*\.\s*requireAuthority\s*\(\s*authority\s*\)\s*precondition\s*\(\s*stalenessIntervalMonths\s*\.\s*map\s*\{\s*\$0\s*>\s*0\s*\}\s*\?\?\s*true\s*,\s*"The staleness interval must be positive when configured\."\s*\)\s*self\s*\.\s*singletonKey\s*=\s*"app"\s*self\s*\.\s*stalenessIntervalMonths\s*=\s*stalenessIntervalMonths\s*self\s*\.\s*lastExportAt\s*=\s*lastExportAt\s*\}"#
        let exactMutator = #"(?s)[ \t]*func\s+updateStalenessIntervalMonths\s*\(\s*_\s+value\s*:\s*Int\?\s*,\s*authority\s*:\s*AppConfigService\s*\.\s*Authority\s*\)\s+throws\s*\{\s*AppConfigService\s*\.\s*requireAuthority\s*\(\s*authority\s*\)\s*try\s+AppConfigService\s*\.\s*validate\s*\(\s*stalenessIntervalMonths\s*:\s*value\s*\)\s*stalenessIntervalMonths\s*=\s*value\s*\}"#
        let initializerSpan = try callableSpan(matching: requiredInitializer)
        let mutatorSpan = try callableSpan(matching: requiredMutator)
        let callableBodiesAreExact: Bool
        if let initializerSpan, let mutatorSpan {
            let initializerIsExact = try matchesEntire(
                exactInitializer,
                in: initializerSpan.literal
            )
            let mutatorIsExact = try matchesEntire(
                exactMutator,
                in: mutatorSpan.literal
            )
            callableBodiesAreExact = initializerIsExact
                && mutatorIsExact
                && immediateChildOpeningOffsets
                    == [initializerSpan.openingOffset, mutatorSpan.openingOffset].sorted()
        } else {
            callableBodiesAreExact = false
        }
        let hasRequiredProperties = try requiredPropertyPatterns.allSatisfy {
            try hasExactlyOnce($0, in: topLevelBody)
        }
        let propertySurfaceIsExact = try count(#"\b(?:var|let)\b"#, in: topLevelBody) == 3
            && hasRequiredProperties
        let callableSurfaceIsExact = try count(#"\binit\s*\("#, in: topLevelBody) == 1
            && count(#"\bfunc\b"#, in: topLevelBody) == 1
            && count(#"\bsubscript\b"#, in: topLevelBody) == 0
            && count(#"\b(?:static|class)\s+(?:func|var|let|subscript)\b"#, in: topLevelBody) == 0
            && hasExactlyOnce(requiredInitializer, in: topLevelBody)
            && hasExactlyOnce(requiredMutator, in: topLevelBody)
            && callableBodiesAreExact
        let authorityTypeCount = try count(#"\bAuthority\b"#, in: body)
        let authorityValueCount = try count(#"\bauthority\b"#, in: body)
        let mutatorCount = try count(#"\bupdateStalenessIntervalMonths\b"#, in: body)
        let authorityCheckCount = try count(
            #"\bAppConfigService\s*\.\s*requireAuthority\s*\(\s*authority\s*\)"#,
            in: body
        )
        let validationCount = try count(#"\bAppConfigService\s*\.\s*validate\b"#, in: body)
        let stalenessAssignmentCount = try count(
            #"(?:self\s*\.\s*)?stalenessIntervalMonths\s*="#,
            in: body
        )
        let lastExportAssignmentCount = try count(
            #"self\s*\.\s*lastExportAt\s*="#,
            in: body
        )
        let singletonKeyAssignmentCount = try count(
            #"self\s*\.\s*singletonKey\s*="#,
            in: body
        )
        let extensionCount = try count(appConfigExtension)
        let modelBodyIsExact = propertySurfaceIsExact
            && callableSurfaceIsExact
            && authorityTypeCount == 2
            && authorityValueCount == 4
            && mutatorCount == 1
            && authorityCheckCount == 2
            && validationCount == 1
            && stalenessAssignmentCount == 2
            && lastExportAssignmentCount == 1
            && singletonKeyAssignmentCount == 1
            && extensionCount == 0
        if modelBodyIsExact == false {
            return [
                Finding(
                    path: path,
                    line: 1,
                    message: "Canonical AppConfig model authority contract changed"
                )
            ]
        }
        return []
    }

    if identity == .appConfigService {
        let requiredPatterns = [
            #"@MainActor\s+enum\s+AppConfigService\s*\{"#,
            #"final\s+class\s+Authority\s*:\s*Sendable\s*\{\s*fileprivate\s+static\s+let\s+canonical\s*=\s*Authority\s*\(\s*\)\s*fileprivate\s+init\s*\(\s*\)\s*\{\s*\}\s*\}"#,
            #"private\s+static\s+let\s+authority\s*=\s*Authority\s*\.\s*canonical"#,
            #"nonisolated\s+static\s+func\s+requireAuthority\s*\(\s*_\s+candidate\s*:\s*Authority\s*\)\s*\{\s*precondition\s*\(\s*candidate\s*===\s*Authority\s*\.\s*canonical\s*,\s*\)\s*\}"#,
            #"AppConfig\s*\(\s*stalenessIntervalMonths\s*:\s*nil\s*,\s*lastExportAt\s*:\s*nil\s*,\s*authority\s*:\s*authority\s*\)"#,
            #"AppConfig\s*\(\s*stalenessIntervalMonths\s*:\s*stalenessIntervalMonths\s*,\s*lastExportAt\s*:\s*lastExportAt\s*,\s*authority\s*:\s*authority\s*\)"#,
            #"configuration\s*\.\s*updateStalenessIntervalMonths\s*\(\s*stalenessIntervalMonths\s*,\s*authority\s*:\s*authority\s*\)"#
        ]
        let hasRequiredServicePatterns = try requiredPatterns.allSatisfy {
            try hasExactlyOnce($0)
        }
        let serviceIsExact = try count(serviceDeclaration) == 1
            && count(#"\bAuthority\b"#) == 5
            && count(#"\bauthority\b"#) == 7
            && count(#"\brequireAuthority\b"#) == 1
            && count(#"\bAppConfig\s*(?:\.\s*init\s*)?\("#) == 2
            && count(#"\bupdateStalenessIntervalMonths\b"#) == 1
            && count(#"\bcontext\s*\.\s*insert\s*\(\s*configuration\s*\)"#) == 2
            && hasRequiredServicePatterns
        if serviceIsExact == false {
            return [
                Finding(
                    path: path,
                    line: 1,
                    message: "AppConfig authority changed outside the reviewed service seam"
                )
            ]
        }
        return []
    }

    var results: [Finding] = []
    let explicitConstruction = try count(
        #"\b(?:SchemaV1\s*\.\s*)?AppConfig\s*(?:\.\s*init\s*)?\("#
    ) > 0
    let constructorReference = try count(
        #"\b(?:SchemaV1\s*\.\s*)?AppConfig\s*\.\s*(?:init|self|Type)\b"#
    ) > 0
    let appConfigAlias = try count(
        #"\btypealias\s+[A-Za-z_][A-Za-z0-9_]*\s*=\s*(?:SchemaV1\s*\.\s*)?AppConfig\b"#
    ) > 0
    if explicitConstruction || constructorReference || appConfigAlias {
        results.append(
            Finding(
                path: path,
                line: 1,
                message: "AppConfig construction is owned exclusively by AppConfigService"
            )
        )
    }
    if try count(#"\bupdateStalenessIntervalMonths\b"#) > 0 {
        results.append(
            Finding(
                path: path,
                line: 1,
                message: "AppConfig staleness mutation is owned exclusively by AppConfigService"
            )
        )
    }
    if try count(#"\bAppConfigService\s*\.\s*Authority\b"#) > 0 {
        results.append(
            Finding(
                path: path,
                line: 1,
                message: "AppConfig authority is reserved to the canonical model and service"
            )
        )
    }
    let shadowDeclaration = try count(
        #"\b(?:typealias|class|struct|enum|protocol|actor|macro|func|let|var)\s+(?:\x{60})?(?:SchemaV1|AppConfig|AppConfigService)(?:\x{60})?(?![\p{L}\p{N}_])"#
    ) > 0
    let appConfigExtensionCount = try count(appConfigExtension)
    if shadowDeclaration || appConfigExtensionCount > 0 {
        results.append(
            Finding(
                path: path,
                line: 1,
                message: "AppConfig ownership symbols may only be declared by the canonical model and service"
            )
        )
    }
    return results
}

private func persistentModelBackingFindings(
    in source: String,
    path: String
) throws -> [Finding] {
    let visibleSource = sourceForStructure(source)
    let expression = try NSRegularExpression(
        pattern: #"\b(?:BackingData|backingData|persistentBackingData|createBackingData|setValue|setTransformableValue)\b"#
    )
    let range = NSRange(
        visibleSource.startIndex..<visibleSource.endIndex,
        in: visibleSource
    )
    guard let match = expression.firstMatch(in: visibleSource, range: range) else {
        return []
    }
    return [
        Finding(
            path: path,
            line: lineNumber(in: visibleSource, at: match.range.location),
            message: "SwiftData backing-data APIs bypass reviewed model initialization"
        )
    ]
}

private enum BackupParityTransformation {
    case direct(record: String, field: String, type: String)
    case foreignUUID(record: String, field: String, targetModel: String)
    case inverse(forwardModel: String, forwardProperty: String)
    case constant(String)
}

private struct BackupParityFieldContract {
    let model: String
    let property: String
    let modelType: String
    let transformation: BackupParityTransformation
}

private struct BackupParityDeclaration {
    let name: String
    let body: String
}

private func bracedBody(
    in source: String,
    openingAt openingBrace: String.Index
) -> String? {
    var depth = 0
    var cursor = openingBrace
    while cursor < source.endIndex {
        let character = source[cursor]
        if character == "{" {
            depth += 1
        } else if character == "}" {
            depth -= 1
            if depth == 0 {
                let bodyStart = source.index(after: openingBrace)
                return String(source[bodyStart..<cursor])
            }
        }
        cursor = source.index(after: cursor)
    }
    return nil
}

private func backupParityDeclarations(
    in source: String,
    pattern: String,
    nameCapture: Int
) throws -> [BackupParityDeclaration]? {
    let expression = try NSRegularExpression(pattern: pattern)
    let range = NSRange(source.startIndex..<source.endIndex, in: source)
    var declarations: [BackupParityDeclaration] = []
    for match in expression.matches(in: source, range: range) {
        guard
            let matchRange = Range(match.range, in: source),
            let nameRange = Range(match.range(at: nameCapture), in: source),
            let openingBrace = source[matchRange].lastIndex(of: "{"),
            let body = bracedBody(in: source, openingAt: openingBrace)
        else {
            return nil
        }
        declarations.append(
            BackupParityDeclaration(name: String(source[nameRange]), body: body)
        )
    }
    return declarations
}

/// Retains only declaration-level text. Braced implementation bodies are
/// replaced with whitespace, while their boundary braces remain visible so a
/// computed property or custom initializer cannot masquerade as stored state.
private func backupParityTopLevelSurface(_ body: String) -> String {
    var result: [Character] = []
    result.reserveCapacity(body.count)
    var depth = 0
    for character in body {
        if character == "{" {
            result.append(depth == 0 ? character : " ")
            depth += 1
        } else if character == "}" {
            depth -= 1
            result.append(depth == 0 ? character : " ")
        } else if depth == 0 || character == "\n" {
            result.append(character)
        } else {
            result.append(" ")
        }
    }
    return String(result)
}

private enum BackupStoredPropertyMode {
    case model
    case synthesized(binding: String)
}

private func backupParityStoredProperties(
    in body: String,
    mode: BackupStoredPropertyMode
) throws -> [String: String] {
    let surface = backupParityTopLevelSurface(body)
    let bindingExpression = try NSRegularExpression(pattern: #"\b(?:var|let)\b"#)
    let staticExpression = try NSRegularExpression(pattern: #"\b(?:static|class)\b"#)
    let modelPropertyExpression = try NSRegularExpression(
        pattern: #"^(?:var|let)\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([^=;{}\n]+?)(?:\s*=\s*[^;{}\n]+)?\s*$"#
    )
    let synthesizedPropertyExpression: NSRegularExpression?
    switch mode {
    case .model:
        synthesizedPropertyExpression = nil
    case let .synthesized(binding):
        let escapedBinding = NSRegularExpression.escapedPattern(for: binding)
        synthesizedPropertyExpression = try NSRegularExpression(
            pattern: "^\(escapedBinding)\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*:\\s*([^=;{}\\n]+?)\\s*$"
        )
    }

    var properties: [String: String] = [:]

    for lineSlice in surface.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = String(lineSlice)
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            continue
        }
        let lineRange = NSRange(line.startIndex..<line.endIndex, in: line)
        let bindingMatches = bindingExpression.matches(in: line, range: lineRange)

        if let dtoPropertyExpression = synthesizedPropertyExpression {
            guard
                bindingMatches.count == 1,
                let bindingRange = Range(bindingMatches[0].range, in: line),
                line[..<bindingRange.lowerBound].trimmingCharacters(in: .whitespaces).isEmpty,
                let propertyMatch = dtoPropertyExpression.firstMatch(
                    in: trimmed,
                    range: NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
                ),
                propertyMatch.range == NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed),
                let nameRange = Range(propertyMatch.range(at: 1), in: trimmed),
                let typeRange = Range(propertyMatch.range(at: 2), in: trimmed)
            else {
                throw NSError(
                    domain: "BackupParityParser",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "DTO declaration is not synthesized-only"]
                )
            }
            let name = String(trimmed[nameRange])
            guard properties[name] == nil else {
                throw NSError(
                    domain: "BackupParityParser",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Duplicate DTO property"]
                )
            }
            properties[name] = String(trimmed[typeRange].filter { !$0.isWhitespace })
            continue
        }

        guard bindingMatches.isEmpty == false else {
            continue
        }
        guard bindingMatches.count == 1,
              let bindingRange = Range(bindingMatches[0].range, in: line) else {
            throw NSError(
                domain: "BackupParityParser",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Compound model property declaration"]
            )
        }
        let prefix = String(line[..<bindingRange.lowerBound])
        let prefixRange = NSRange(prefix.startIndex..<prefix.endIndex, in: prefix)
        if staticExpression.firstMatch(in: prefix, range: prefixRange) != nil {
            continue
        }
        let declaration = String(line[bindingRange.lowerBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let declarationRange = NSRange(declaration.startIndex..<declaration.endIndex, in: declaration)
        guard
            let propertyMatch = modelPropertyExpression.firstMatch(in: declaration, range: declarationRange),
            propertyMatch.range == declarationRange,
            let nameRange = Range(propertyMatch.range(at: 1), in: declaration),
            let typeRange = Range(propertyMatch.range(at: 2), in: declaration)
        else {
            throw NSError(
                domain: "BackupParityParser",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Model property declaration is not reviewable"]
            )
        }
        let name = String(declaration[nameRange])
        guard properties[name] == nil else {
            throw NSError(
                domain: "BackupParityParser",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Duplicate model property"]
            )
        }
        properties[name] = String(declaration[typeRange].filter { !$0.isWhitespace })
    }
    return properties
}

private func backupParityFindings(
    schemaSource: String,
    archiveSource: String,
    schemaPath: String,
    archivePath: String
) throws -> [Finding] {
    let schemaMessage = "SchemaV1 persisted-property surface changed without backup-format review"
    let archiveMessage = "BackupArchive v2 stored-property surface changed without backup-format review"
    let dtoMessage = "BackupArchive DTOs must retain synthesized Codable and memberwise initialization"
    let schema = sourceForStructure(schemaSource)
    let archive = sourceForStructure(archiveSource)
    let schemaRange = NSRange(schema.startIndex..<schema.endIndex, in: schema)
    let archiveRange = NSRange(archive.startIndex..<archive.endIndex, in: archive)
    let customCodableExpression = try NSRegularExpression(
        pattern: #"\bCodingKeys\b|\binit\s*\(\s*from(?:\s+(?:[A-Za-z_][A-Za-z0-9_]*|_))?\s*:|\bfunc\s+encode\s*\(\s*to(?:\s+(?:[A-Za-z_][A-Za-z0-9_]*|_))?\s*:"#
    )
    let customCodableWasDeclared =
        customCodableExpression.firstMatch(in: archive, range: archiveRange) != nil
    func schemaDriftFindings() -> [Finding] {
        var findings = [Finding(path: schemaPath, line: 1, message: schemaMessage)]
        if customCodableWasDeclared {
            findings.append(Finding(path: archivePath, line: 1, message: dtoMessage))
        }
        return findings
    }
    let transientExpression = try NSRegularExpression(pattern: #"@\s*Transient\b"#)
    guard transientExpression.firstMatch(in: schema, range: schemaRange) == nil else {
        return schemaDriftFindings()
    }

    let modelRecords: [String: String] = [
        "InterventionType": "InterventionTypeRecord",
        "DrugClass": "DrugClassRecord",
        "ServiceLine": "ServiceLineRecord",
        "Intervention": "InterventionRecord",
        "DIQuestion": "DIQuestionRecord",
        "Citation": "CitationRecord",
        "AppConfig": "AppConfigRecord"
    ]

    func direct(
        _ model: String,
        _ property: String,
        _ modelType: String,
        _ recordType: String
    ) -> BackupParityFieldContract {
        BackupParityFieldContract(
            model: model,
            property: property,
            modelType: modelType,
            transformation: .direct(
                record: modelRecords[model]!,
                field: property,
                type: recordType
            )
        )
    }

    func foreign(
        _ model: String,
        _ property: String,
        _ modelType: String,
        _ recordField: String,
        _ targetModel: String
    ) -> BackupParityFieldContract {
        BackupParityFieldContract(
            model: model,
            property: property,
            modelType: modelType,
            transformation: .foreignUUID(
                record: modelRecords[model]!,
                field: recordField,
                targetModel: targetModel
            )
        )
    }

    // Every persisted property is classified exactly once. Direct values map
    // to the same record field, object references map to portable UUIDs, the
    // two collection inverses are reconstructed from those forward UUIDs, and
    // AppConfig.singletonKey is restored as the canonical local constant.
    let contracts: [BackupParityFieldContract] = [
        direct("InterventionType", "id", "UUID", "UUID"),
        direct("InterventionType", "label", "String", "String"),
        direct("InterventionType", "defaultCostAvoidanceCents", "Int?", "Int?"),
        direct("InterventionType", "isActive", "Bool", "Bool"),
        direct("InterventionType", "sortOrder", "Int", "Int"),
        direct("DrugClass", "id", "UUID", "UUID"),
        direct("DrugClass", "label", "String", "String"),
        direct("DrugClass", "isActive", "Bool", "Bool"),
        direct("DrugClass", "sortOrder", "Int", "Int"),
        direct("ServiceLine", "id", "UUID", "UUID"),
        direct("ServiceLine", "label", "String", "String"),
        direct("ServiceLine", "isActive", "Bool", "Bool"),
        direct("ServiceLine", "sortOrder", "Int", "Int"),
        direct("Intervention", "id", "Foundation.UUID", "UUID"),
        direct("Intervention", "timestamp", "Foundation.Date", "Date"),
        foreign("Intervention", "type", "InterventionType?", "typeID", "InterventionType"),
        foreign("Intervention", "drugClass", "DrugClass?", "drugClassID", "DrugClass"),
        foreign("Intervention", "serviceLine", "ServiceLine?", "serviceLineID", "ServiceLine"),
        direct(
            "Intervention",
            "acceptance",
            "SchemaV1Vocabulary.Acceptance",
            "SchemaV1Vocabulary.Acceptance"
        ),
        direct("Intervention", "costAvoidanceCents", "Swift.Int?", "Int?"),
        direct("Intervention", "minutesSpent", "Swift.Int?", "Int?"),
        foreign("Intervention", "diQuestion", "DIQuestion?", "diQuestionID", "DIQuestion"),
        direct("DIQuestion", "id", "UUID", "UUID"),
        direct("DIQuestion", "createdAt", "Date", "Date"),
        direct("DIQuestion", "answeredAt", "Date?", "Date?"),
        direct("DIQuestion", "questionText", "String", "String"),
        direct("DIQuestion", "background", "String", "String"),
        direct("DIQuestion", "answerText", "String", "String"),
        direct("DIQuestion", "searchStrategy", "String", "String"),
        direct(
            "DIQuestion",
            "requestorRole",
            "SchemaV1Vocabulary.RequestorRole",
            "SchemaV1Vocabulary.RequestorRole"
        ),
        direct(
            "DIQuestion",
            "questionClass",
            "SchemaV1Vocabulary.DIQuestionClass",
            "SchemaV1Vocabulary.DIQuestionClass"
        ),
        direct(
            "DIQuestion",
            "urgency",
            "SchemaV1Vocabulary.Urgency",
            "SchemaV1Vocabulary.Urgency"
        ),
        direct("DIQuestion", "verifiedOn", "Date", "Date"),
        direct("DIQuestion", "reviewAfter", "Date", "Date"),
        direct("DIQuestion", "didFollowUp", "Bool", "Bool"),
        direct("DIQuestion", "tags", "[String]", "[String]"),
        direct("DIQuestion", "verificationHistory", "[Date]", "[Date]"),
        BackupParityFieldContract(
            model: "DIQuestion",
            property: "citations",
            modelType: "[Citation]",
            transformation: .inverse(forwardModel: "Citation", forwardProperty: "question")
        ),
        BackupParityFieldContract(
            model: "DIQuestion",
            property: "linkedInterventions",
            modelType: "[Intervention]",
            transformation: .inverse(forwardModel: "Intervention", forwardProperty: "diQuestion")
        ),
        direct("Citation", "id", "UUID", "UUID"),
        foreign("Citation", "question", "DIQuestion?", "questionID", "DIQuestion"),
        direct(
            "Citation",
            "tier",
            "SchemaV1Vocabulary.SourceTier",
            "SchemaV1Vocabulary.SourceTier"
        ),
        direct("Citation", "title", "String", "String"),
        direct("Citation", "locator", "String", "String"),
        direct("Citation", "accessedDate", "Date", "Date"),
        direct("Citation", "urlString", "String?", "String?"),
        BackupParityFieldContract(
            model: "AppConfig",
            property: "singletonKey",
            modelType: "String",
            transformation: .constant("app")
        ),
        direct("AppConfig", "stalenessIntervalMonths", "Int?", "Int?"),
        direct("AppConfig", "lastExportAt", "Date?", "Date?")
    ]

    var expectedModels: [String: [String: String]] = [:]
    var expectedRecords: [String: [String: String]] = [:]
    var contractByField: [String: BackupParityFieldContract] = [:]
    var contractIsCoherent = true
    for contract in contracts {
        let key = "\(contract.model).\(contract.property)"
        if contractByField.updateValue(contract, forKey: key) != nil
            || expectedModels[contract.model, default: [:]].updateValue(
                contract.modelType,
                forKey: contract.property
            ) != nil {
            contractIsCoherent = false
        }
        switch contract.transformation {
        case let .direct(record, field, type):
            if record != modelRecords[contract.model]
                || expectedRecords[record, default: [:]].updateValue(type, forKey: field) != nil {
                contractIsCoherent = false
            }
        case let .foreignUUID(record, field, targetModel):
            if record != modelRecords[contract.model]
                || modelRecords[targetModel] == nil
                || expectedRecords[record, default: [:]].updateValue("UUID?", forKey: field) != nil {
                contractIsCoherent = false
            }
        case .inverse, .constant:
            break
        }
    }
    for contract in contracts {
        switch contract.transformation {
        case let .inverse(forwardModel, forwardProperty):
            guard
                let forward = contractByField["\(forwardModel).\(forwardProperty)"],
                case let .foreignUUID(_, _, targetModel) = forward.transformation,
                targetModel == contract.model
            else {
                contractIsCoherent = false
                continue
            }
        case let .constant(literal):
            if contract.model != "AppConfig"
                || contract.property != "singletonKey"
                || literal != "app" {
                contractIsCoherent = false
            }
        case .direct, .foreignUUID:
            break
        }
    }
    guard contractIsCoherent,
          Set(expectedModels.keys) == Set(modelRecords.keys),
          Set(expectedRecords.keys) == Set(modelRecords.values) else {
        throw NSError(
            domain: "BackupParityContract",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Internal backup parity contract is incoherent"]
        )
    }

    let expectedModelOrder = [
        "Intervention", "InterventionType", "DrugClass", "ServiceLine",
        "DIQuestion", "Citation", "AppConfig"
    ]
    guard
        let schemaEnums = try backupParityDeclarations(
            in: schema,
            pattern: #"\benum\s+(SchemaV1)\s*:\s*VersionedSchema\s*\{"#,
            nameCapture: 1
        ),
        schemaEnums.count == 1
    else {
        return schemaDriftFindings()
    }
    let schemaBody = schemaEnums[0].body
    let modelListPattern = #"(?s)\bstatic\s+var\s+models\s*:\s*\[\s*any\s+PersistentModel\s*\.\s*Type\s*\]\s*\{\s*\[\s*Intervention\s*\.\s*self\s*,\s*InterventionType\s*\.\s*self\s*,\s*DrugClass\s*\.\s*self\s*,\s*ServiceLine\s*\.\s*self\s*,\s*DIQuestion\s*\.\s*self\s*,\s*Citation\s*\.\s*self\s*,\s*AppConfig\s*\.\s*self\s*\]\s*\}"#
    let modelListExpression = try NSRegularExpression(pattern: modelListPattern)
    let modelListTokenExpression = try NSRegularExpression(pattern: #"\bstatic\s+var\s+models\b"#)
    let schemaBodyRange = NSRange(schemaBody.startIndex..<schemaBody.endIndex, in: schemaBody)
    guard
        modelListExpression.matches(in: schemaBody, range: schemaBodyRange).count == 1,
        modelListTokenExpression.matches(in: schemaBody, range: schemaBodyRange).count == 1
    else {
        return schemaDriftFindings()
    }

    let modelPattern = #"@Model\s+final\s+class\s+([A-Za-z_][A-Za-z0-9_]*)\s*\{"#
    guard
        let modelDeclarations = try backupParityDeclarations(
            in: schemaBody,
            pattern: modelPattern,
            nameCapture: 1
        ),
        modelDeclarations.count == expectedModelOrder.count,
        Set(modelDeclarations.map(\.name)) == Set(expectedModelOrder)
    else {
        return schemaDriftFindings()
    }
    let allModelExpression = try NSRegularExpression(pattern: #"@Model\b"#)
    guard allModelExpression.matches(in: schema, range: schemaRange).count == expectedModelOrder.count else {
        return schemaDriftFindings()
    }
    for declaration in modelDeclarations {
        do {
            let actual = try backupParityStoredProperties(in: declaration.body, mode: .model)
            guard actual == expectedModels[declaration.name] else {
                return schemaDriftFindings()
            }
        } catch {
            return schemaDriftFindings()
        }
    }
    guard customCodableWasDeclared == false else {
        return [Finding(path: archivePath, line: 1, message: dtoMessage)]
    }

    guard
        let outerDeclarations = try backupParityDeclarations(
            in: archive,
            pattern: #"\bstruct\s+(BackupArchive)\s*:\s*Codable\s*,\s*Equatable\s*,\s*Sendable\s*\{"#,
            nameCapture: 1
        ),
        outerDeclarations.count == 1,
        (try? backupParityStoredProperties(in: outerDeclarations[0].body, mode: .model))
            == ["formatVersion": "Int", "createdAt": "Date", "payload": "Payload"]
    else {
        return [Finding(path: archivePath, line: 1, message: archiveMessage)]
    }
    let formatExpression = try NSRegularExpression(
        pattern: #"\bstatic\s+let\s+currentFormatVersion\s*=\s*2\b"#
    )
    guard formatExpression.matches(in: archive, range: archiveRange).count == 1 else {
        return [Finding(path: archivePath, line: 1, message: archiveMessage)]
    }

    guard
        let archiveExtensions = try backupParityDeclarations(
            in: archive,
            pattern: #"\bextension\s+(BackupArchive)\s*\{"#,
            nameCapture: 1
        ),
        archiveExtensions.count == 1
    else {
        return [Finding(path: archivePath, line: 1, message: archiveMessage)]
    }
    let extensionBody = archiveExtensions[0].body
    let expectedDTOs = Set(["Payload"] + Array(modelRecords.values))
    let extensionBodyRange = NSRange(extensionBody.startIndex..<extensionBody.endIndex, in: extensionBody)
    let anyStructExpression = try NSRegularExpression(
        pattern: #"\bstruct\s+([A-Za-z_][A-Za-z0-9_]*)\b"#
    )
    let structNames = anyStructExpression.matches(in: extensionBody, range: extensionBodyRange)
        .compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: extensionBody) else { return nil }
            return String(extensionBody[range])
        }
    guard structNames.count == expectedDTOs.count, Set(structNames) == expectedDTOs else {
        return [Finding(path: archivePath, line: 1, message: dtoMessage)]
    }
    guard
        let dtoDeclarations = try backupParityDeclarations(
            in: extensionBody,
            pattern: #"\bstruct\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*Codable\s*,\s*Equatable\s*,\s*Sendable\s*\{"#,
            nameCapture: 1
        ),
        dtoDeclarations.count == expectedDTOs.count,
        Set(dtoDeclarations.map(\.name)) == expectedDTOs
    else {
        return [Finding(path: archivePath, line: 1, message: dtoMessage)]
    }
    let dtoExtensionExpression = try NSRegularExpression(
        pattern: #"\bextension\s+BackupArchive\s*\.\s*(?:Payload|InterventionTypeRecord|DrugClassRecord|ServiceLineRecord|InterventionRecord|DIQuestionRecord|CitationRecord|AppConfigRecord)\b"#
    )
    guard dtoExtensionExpression.firstMatch(in: archive, range: archiveRange) == nil else {
        return [Finding(path: archivePath, line: 1, message: dtoMessage)]
    }

    let expectedPayload: [String: String] = [
        "interventionTypes": "[InterventionTypeRecord]",
        "drugClasses": "[DrugClassRecord]",
        "serviceLines": "[ServiceLineRecord]",
        "interventions": "[InterventionRecord]",
        "questions": "[DIQuestionRecord]",
        "citations": "[CitationRecord]",
        "appConfig": "AppConfigRecord?"
    ]
    for declaration in dtoDeclarations {
        do {
            let actual = try backupParityStoredProperties(
                in: declaration.body,
                mode: .synthesized(binding: "var")
            )
            let expected = declaration.name == "Payload"
                ? expectedPayload
                : expectedRecords[declaration.name]
            guard actual == expected else {
                return [Finding(path: archivePath, line: 1, message: archiveMessage)]
            }
        } catch {
            return [Finding(path: archivePath, line: 1, message: dtoMessage)]
        }
    }

    return []
}

private func immutableBackupV1Findings(
    in source: String,
    path: String
) throws -> [Finding] {
    let message = "BackupArchive v1 decoder changed outside immutable compatibility contract"
    let codec = sourceForStructure(source)
    let codecRange = NSRange(codec.startIndex..<codec.endIndex, in: codec)

    func finding() -> [Finding] {
        [Finding(path: path, line: 1, message: message)]
    }

    guard
        let codecDeclarations = try backupParityDeclarations(
            in: codec,
            pattern: #"\benum\s+(BackupCodec)\s*\{"#,
            nameCapture: 1
        ),
        codecDeclarations.count == 1
    else {
        return finding()
    }
    let codecBody = codecDeclarations[0].body
    let codecTopLevel = backupParityTopLevelSurface(codecBody)
    let codecTopLevelRange = NSRange(
        codecTopLevel.startIndex..<codecTopLevel.endIndex,
        in: codecTopLevel
    )
    let v1HeaderPattern =
        #"\bprivate\s+struct\s+(BackupArchiveV1)\s*:\s*Decodable\s*\{"#
    let directV1HeaderExpression = try NSRegularExpression(pattern: v1HeaderPattern)
    let anyV1DeclarationExpression = try NSRegularExpression(
        pattern: #"\b(?:struct|class|enum|typealias)\s+BackupArchiveV1\b"#
    )
    let extensionExpression = try NSRegularExpression(pattern: #"\bextension\b"#)
    guard
        directV1HeaderExpression.matches(
            in: codecTopLevel,
            range: codecTopLevelRange
        ).count == 1,
        anyV1DeclarationExpression.matches(in: codec, range: codecRange).count == 1,
        extensionExpression.firstMatch(in: codec, range: codecRange) == nil,
        let v1Declarations = try backupParityDeclarations(
            in: codecBody,
            pattern: v1HeaderPattern,
            nameCapture: 1
        ),
        v1Declarations.count == 1
    else {
        return finding()
    }
    let v1Body = v1Declarations[0].body

    let expectedOuter: [String: String] = [
        "formatVersion": "Int",
        "createdAt": "Date",
        "payload": "Payload"
    ]
    let expectedPayload: [String: String] = [
        "interventionTypes": "[InterventionTypeRecord]",
        "drugClasses": "[DrugClassRecord]",
        "serviceLines": "[ServiceLineRecord]",
        "interventions": "[InterventionRecord]",
        "questions": "[DIQuestionRecord]",
        "citations": "[CitationRecord]",
        "appConfig": "AppConfigRecord?"
    ]
    let expectedRecords: [String: [String: String]] = [
        "InterventionTypeRecord": [
            "id": "UUID",
            "label": "String",
            "defaultCostAvoidanceCents": "Int?",
            "isActive": "Bool",
            "sortOrder": "Int"
        ],
        "DrugClassRecord": [
            "id": "UUID",
            "label": "String",
            "isActive": "Bool",
            "sortOrder": "Int"
        ],
        "ServiceLineRecord": [
            "id": "UUID",
            "label": "String",
            "isActive": "Bool",
            "sortOrder": "Int"
        ],
        "InterventionRecord": [
            "id": "UUID",
            "timestamp": "Date",
            "typeID": "UUID?",
            "drugClassID": "UUID?",
            "serviceLineID": "UUID?",
            "acceptance": "SchemaV1Vocabulary.Acceptance",
            "costAvoidanceCents": "Int",
            "minutesSpent": "Int?",
            "diQuestionID": "UUID?"
        ],
        "DIQuestionRecord": [
            "id": "UUID",
            "createdAt": "Date",
            "answeredAt": "Date?",
            "questionText": "String",
            "background": "String",
            "answerText": "String",
            "searchStrategy": "String",
            "requestorRole": "SchemaV1Vocabulary.RequestorRole",
            "questionClass": "SchemaV1Vocabulary.DIQuestionClass",
            "urgency": "SchemaV1Vocabulary.Urgency",
            "verifiedOn": "Date",
            "reviewAfter": "Date",
            "didFollowUp": "Bool",
            "tags": "[String]",
            "verificationHistory": "[Date]"
        ],
        "CitationRecord": [
            "id": "UUID",
            "questionID": "UUID?",
            "tier": "SchemaV1Vocabulary.SourceTier",
            "title": "String",
            "locator": "String",
            "accessedDate": "Date",
            "urlString": "String?"
        ],
        "AppConfigRecord": [
            "costAvoidanceValues": "[String:Int]",
            "stalenessIntervalMonths": "Int",
            "lastExportAt": "Date?"
        ]
    ]
    let expectedNestedNames = Set(["Payload"] + Array(expectedRecords.keys))
    let nestedPattern =
        #"\bstruct\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*Decodable\s*\{"#
    guard
        let nestedDeclarations = try backupParityDeclarations(
            in: v1Body,
            pattern: nestedPattern,
            nameCapture: 1
        ),
        nestedDeclarations.count == expectedNestedNames.count,
        Set(nestedDeclarations.map(\.name)) == expectedNestedNames
    else {
        return finding()
    }

    let v1TopLevel = backupParityTopLevelSurface(v1Body)
    let v1TopLevelRange = NSRange(
        v1TopLevel.startIndex..<v1TopLevel.endIndex,
        in: v1TopLevel
    )
    let directNestedExpression = try NSRegularExpression(pattern: nestedPattern)
    let directNestedNames = directNestedExpression.matches(
        in: v1TopLevel,
        range: v1TopLevelRange
    ).compactMap { match -> String? in
        guard let range = Range(match.range(at: 1), in: v1TopLevel) else {
            return nil
        }
        return String(v1TopLevel[range])
    }
    let anyStructExpression = try NSRegularExpression(
        pattern: #"\bstruct\s+([A-Za-z_][A-Za-z0-9_]*)\b"#
    )
    let v1BodyRange = NSRange(v1Body.startIndex..<v1Body.endIndex, in: v1Body)
    let allStructNames = anyStructExpression.matches(
        in: v1Body,
        range: v1BodyRange
    ).compactMap { match -> String? in
        guard let range = Range(match.range(at: 1), in: v1Body) else {
            return nil
        }
        return String(v1Body[range])
    }
    guard
        directNestedNames.count == expectedNestedNames.count,
        Set(directNestedNames) == expectedNestedNames,
        allStructNames.count == expectedNestedNames.count,
        Set(allStructNames) == expectedNestedNames
    else {
        return finding()
    }

    var outerPropertySurface = directNestedExpression.stringByReplacingMatches(
        in: v1TopLevel,
        range: v1TopLevelRange,
        withTemplate: ""
    )
    outerPropertySurface = outerPropertySurface
        .replacingOccurrences(of: "{", with: "")
        .replacingOccurrences(of: "}", with: "")
    do {
        guard
            try backupParityStoredProperties(
                in: outerPropertySurface,
                mode: .synthesized(binding: "let")
            ) == expectedOuter
        else {
            return finding()
        }
    } catch {
        return finding()
    }

    for declaration in nestedDeclarations {
        let expected = declaration.name == "Payload"
            ? expectedPayload
            : expectedRecords[declaration.name]
        do {
            guard
                try backupParityStoredProperties(
                    in: declaration.body,
                    mode: .synthesized(binding: "let")
                ) == expected
            else {
                return finding()
            }
        } catch {
            return finding()
        }
    }

    return []
}

private func interventionArchitectureFindings(in source: String, path: String) throws -> [Finding] {
    let visibleSource = sourceForStructure(source)
    let sourceRange = NSRange(visibleSource.startIndex..<visibleSource.endIndex, in: visibleSource)
    let forbiddenSchemaExpression = try NSRegularExpression(
        pattern: #"(?m)^\s*#(?:if|elseif|else|endif)\b|\b(?:typealias|class|struct|enum|protocol|actor)\s+(?:\x{60})?(?:Foundation|Swift|SchemaV1Vocabulary)(?:\x{60})?\b"#
    )
    if let match = forbiddenSchemaExpression.firstMatch(in: visibleSource, range: sourceRange) {
        return [
            Finding(
                path: path,
                line: lineNumber(in: visibleSource, at: match.range.location),
                message: "SchemaV1 may not conditionally compile or shadow reviewed persisted-property types"
            )
        ]
    }
    let typealiasToken = try NSRegularExpression(pattern: #"\btypealias\b"#)
    let requiredTypealiasPatterns = [
        #"\btypealias\s+Intervention\s*=\s*SchemaV1\.Intervention\b"#,
        #"\btypealias\s+InterventionType\s*=\s*SchemaV1\.InterventionType\b"#,
        #"\btypealias\s+DrugClass\s*=\s*SchemaV1\.DrugClass\b"#,
        #"\btypealias\s+ServiceLine\s*=\s*SchemaV1\.ServiceLine\b"#,
        #"\btypealias\s+DIQuestion\s*=\s*SchemaV1\.DIQuestion\b"#,
        #"\btypealias\s+Citation\s*=\s*SchemaV1\.Citation\b"#,
        #"\btypealias\s+AppConfig\s*=\s*SchemaV1\.AppConfig\b"#
    ]
    let hasEachRequiredAlias = try requiredTypealiasPatterns.allSatisfy { pattern in
        let expression = try NSRegularExpression(pattern: pattern)
        return expression.matches(in: visibleSource, range: sourceRange).count == 1
    }
    let aliasesAreExact = typealiasToken.matches(in: visibleSource, range: sourceRange).count == 7
        && hasEachRequiredAlias
    guard aliasesAreExact else {
        return [
            Finding(path: path, line: 1, message: "SchemaV1 public model aliases changed outside architecture review")
        ]
    }
    let modelDeclarationExpression = try NSRegularExpression(
        pattern: #"@Model\s+final\s+class\s+Intervention\b"#
    )
    guard modelDeclarationExpression.matches(in: visibleSource, range: sourceRange).count == 1 else {
        return [
            Finding(
                path: path,
                line: 1,
                message: "Intervention must remain exactly one unconditional @Model class"
            )
        ]
    }
    let declarationExpression = try NSRegularExpression(pattern: #"\bfinal\s+class\s+Intervention\b"#)
    let declarationMatches = declarationExpression.matches(in: visibleSource, range: sourceRange)
    guard declarationMatches.count == 1, let declarationMatch = declarationMatches.first else {
        let message = declarationMatches.isEmpty
            ? "Intervention model declaration is missing"
            : "Exactly one unconditional Intervention model declaration is required"
        return [Finding(path: path, line: 1, message: message)]
    }
    guard let declarationRange = Range(declarationMatch.range, in: visibleSource) else {
        return [Finding(path: path, line: 1, message: "Intervention model declaration range is malformed")]
    }
    if visibleSource[declarationRange.upperBound...].contains("/") {
        return [
            Finding(
                path: path,
                line: 1,
                message: "Intervention may not contain bare slash operators or regex literals"
            )
        ]
    }
    guard let openingBrace = visibleSource[declarationRange.upperBound...].firstIndex(of: "{") else {
        return [Finding(path: path, line: 1, message: "Intervention model body is malformed")]
    }

    var depth = 0
    var cursor = openingBrace
    var closingBrace: String.Index?
    while cursor < visibleSource.endIndex {
        let character = visibleSource[cursor]
        if character == "{" {
            depth += 1
        } else if character == "}" {
            depth -= 1
            if depth == 0 {
                closingBrace = cursor
                break
            }
        }
        cursor = visibleSource.index(after: cursor)
    }

    guard let closingBrace else {
        return [Finding(path: path, line: 1, message: "Intervention model body is unbalanced")]
    }

    let body = String(visibleSource[openingBrace...closingBrace])
    let bodyCharacters = Array(body)
    var persistenceSurfaceCharacters = bodyCharacters
    var persistenceDepth = 0
    for index in bodyCharacters.indices {
        let character = bodyCharacters[index]
        if character == "{" {
            persistenceDepth += 1
            persistenceSurfaceCharacters[index] = " "
        } else if character == "}" {
            persistenceSurfaceCharacters[index] = " "
            persistenceDepth -= 1
        } else if persistenceDepth != 1 && character != "\n" {
            persistenceSurfaceCharacters[index] = " "
        }
    }
    let persistenceSurface = String(persistenceSurfaceCharacters)
    let bodyRange = NSRange(
        persistenceSurface.startIndex..<persistenceSurface.endIndex,
        in: persistenceSurface
    )
    let attributeExpression = try NSRegularExpression(pattern: #"@"#)
    let requiredAttributePatterns = [
        #"@Attribute\s*\(\s*\.unique\s*\)\s*var\s+id\s*:\s*Foundation\.UUID\b"#,
        #"@Relationship\s*\(\s*deleteRule\s*:\s*\.nullify\s*\)\s*var\s+type\s*:\s*InterventionType\?"#,
        #"@Relationship\s*\(\s*deleteRule\s*:\s*\.nullify\s*\)\s*var\s+drugClass\s*:\s*DrugClass\?"#,
        #"@Relationship\s*\(\s*deleteRule\s*:\s*\.nullify\s*\)\s*var\s+serviceLine\s*:\s*ServiceLine\?"#
    ]
    let hasEachRequiredAttribute = try requiredAttributePatterns.allSatisfy { pattern in
        let expression = try NSRegularExpression(pattern: pattern)
        return expression.matches(in: persistenceSurface, range: bodyRange).count == 1
    }
    let attributesAreExact = attributeExpression.matches(
        in: persistenceSurface,
        range: bodyRange
    ).count == 4 && hasEachRequiredAttribute
    guard attributesAreExact else {
        return [
            Finding(
                path: path,
                line: 1,
                message: "Intervention persistence attributes or relationship delete rules changed"
            )
        ]
    }

    let propertyExpression = try NSRegularExpression(
        pattern: #"^(?:var|let)\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([^=,;{}\n]+?)(?:\s*=\s*[^,;{}\n]+)?\s*$"#
    )
    var declaredProperties: [String: String] = [:]
    var bodyDepth = 0
    var bodyIndex = 0

    func beginsBindingKeyword(at index: Int, keyword: String) -> Bool {
        let keywordCharacters = Array(keyword)
        guard index + keywordCharacters.count <= bodyCharacters.count else {
            return false
        }
        for offset in keywordCharacters.indices
        where bodyCharacters[index + offset] != keywordCharacters[offset] {
            return false
        }
        let previous = index > 0 ? bodyCharacters[index - 1] : nil
        let nextIndex = index + keywordCharacters.count
        let next = nextIndex < bodyCharacters.count ? bodyCharacters[nextIndex] : nil
        let previousIsIdentifier = previous?.isLetter == true
            || previous?.isNumber == true
            || previous == "_"
        return previousIsIdentifier == false && next?.isWhitespace == true
    }

    while bodyIndex < bodyCharacters.count {
        let character = bodyCharacters[bodyIndex]
        if character == "{" {
            bodyDepth += 1
            bodyIndex += 1
            continue
        }
        if character == "}" {
            bodyDepth -= 1
            bodyIndex += 1
            continue
        }

        if bodyDepth == 1 {
            let forbiddenTypeKeywords = [
                "typealias",
                "class",
                "struct",
                "enum",
                "protocol",
                "actor",
                "extension"
            ]
            if forbiddenTypeKeywords.contains(where: {
                beginsBindingKeyword(at: bodyIndex, keyword: $0)
            }) {
                return [
                    Finding(
                        path: path,
                        line: 1,
                        message: "Intervention may not shadow persisted property types or declare nested types"
                    )
                ]
            }
        }

        let isVar = bodyDepth == 1 && beginsBindingKeyword(at: bodyIndex, keyword: "var")
        let isLet = bodyDepth == 1 && beginsBindingKeyword(at: bodyIndex, keyword: "let")
        guard isVar || isLet else {
            bodyIndex += 1
            continue
        }

        var statementEnd = bodyIndex
        while statementEnd < bodyCharacters.count {
            let statementCharacter = bodyCharacters[statementEnd]
            if statementCharacter == "\n"
                || statementCharacter == ";"
                || statementCharacter == "{"
                || statementCharacter == "}" {
                break
            }
            statementEnd += 1
        }
        let statement = String(bodyCharacters[bodyIndex..<statementEnd])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let statementRange = NSRange(statement.startIndex..<statement.endIndex, in: statement)
        guard
            statementEnd == bodyCharacters.count || bodyCharacters[statementEnd] != "{",
            let match = propertyExpression.firstMatch(in: statement, range: statementRange),
            match.range == statementRange,
            let nameRange = Range(match.range(at: 1), in: statement),
            let typeRange = Range(match.range(at: 2), in: statement)
        else {
            return [
                Finding(
                    path: path,
                    line: lineNumber(
                        in: body,
                        at: NSRange(body.startIndex..<body.index(body.startIndex, offsetBy: bodyIndex), in: body).length
                    ),
                    message: "Intervention contains an unparseable or compound stored-property declaration"
                )
            ]
        }

        let name = String(statement[nameRange])
        let type = String(statement[typeRange].filter { !$0.isWhitespace })
        guard declaredProperties[name] == nil else {
            return [Finding(path: path, line: 1, message: "Intervention declares property \(name) more than once")]
        }
        declaredProperties[name] = type
        bodyIndex = statementEnd
    }
    let allDeclaredPropertyNames = Set(declaredProperties.keys)
    let allowedProperties: [String: String] = [
        "id": "Foundation.UUID",
        "timestamp": "Foundation.Date",
        "type": "InterventionType?",
        "drugClass": "DrugClass?",
        "serviceLine": "ServiceLine?",
        "acceptance": "SchemaV1Vocabulary.Acceptance",
        "costAvoidanceCents": "Swift.Int?",
        "minutesSpent": "Swift.Int?",
        "diQuestion": "DIQuestion?"
    ]

    guard
        allDeclaredPropertyNames == Set(allowedProperties.keys),
        declaredProperties == allowedProperties
    else {
        let unexpected = allDeclaredPropertyNames.filter { allowedProperties[$0] == nil }.sorted()
        let missing = allowedProperties.keys.filter { allDeclaredPropertyNames.contains($0) == false }.sorted()
        let changedTypes = allowedProperties.keys.compactMap { name -> String? in
            guard
                let actualType = declaredProperties[name],
                let expectedType = allowedProperties[name],
                actualType != expectedType
            else {
                return nil
            }
            return "\(name): \(actualType) (expected \(expectedType))"
        }.sorted()
        let details = [
            unexpected.isEmpty ? nil : "unexpected: \(unexpected.joined(separator: ", "))",
            missing.isEmpty ? nil : "missing: \(missing.joined(separator: ", "))",
            changedTypes.isEmpty ? nil : "changed types: \(changedTypes.joined(separator: ", "))"
        ].compactMap { $0 }.joined(separator: "; ")
        return [
            Finding(
                path: path,
                line: lineNumber(
                    in: visibleSource,
                    at: NSRange(visibleSource.startIndex..<openingBrace, in: visibleSource).length
                ),
                message: "Intervention persisted properties changed without architecture review (\(details))"
            )
        ]
    }

    return []
}

private func storeArchitectureFindings(in source: String, path: String) throws -> [Finding] {
    let visibleSource = sourceWithoutComments(source)
    let sourceRange = NSRange(visibleSource.startIndex..<visibleSource.endIndex, in: visibleSource)
    let canonicalStore = try NSRegularExpression(
        pattern: #"(?s)^\s*import\s+SwiftData\s+@MainActor\s+enum\s+HippocratesStore\s*\{\s*static\s+func\s+makeContainer\s*\(\s*inMemory\s*:\s*Bool\s*=\s*false\s*\)\s*throws\s*->\s*ModelContainer\s*\{\s*let\s+schema\s*=\s*Schema\s*\(\s*versionedSchema\s*:\s*SchemaV1\.self\s*\)\s*let\s+configuration\s*=\s*ModelConfiguration\s*\(\s*"Hippocrates"\s*,\s*schema\s*:\s*schema\s*,\s*isStoredInMemoryOnly\s*:\s*inMemory\s*,\s*allowsSave\s*:\s*true\s*,\s*groupContainer\s*:\s*\.none\s*,\s*cloudKitDatabase\s*:\s*\.none\s*\)\s*return\s+try\s+ModelContainer\s*\(\s*for\s*:\s*schema\s*,\s*migrationPlan\s*:\s*HippocratesMigrationPlan\.self\s*,\s*configurations\s*:\s*\[\s*configuration\s*\]\s*\)\s*\}\s*\}\s*$"#
    )
    guard canonicalStore.matches(in: visibleSource, range: sourceRange).count == 1 else {
        return [
            Finding(
                path: path,
                line: 1,
                message: "HippocratesStore must remain the exact reviewed local-only SwiftData construction path"
            )
        ]
    }
    return []
}


private func testStoreArchitectureFindings(in source: String, path: String) throws -> [Finding] {
    let visibleSource = sourceWithoutComments(source)
    let sourceRange = NSRange(visibleSource.startIndex..<visibleSource.endIndex, in: visibleSource)
    let canonicalTestStore = try NSRegularExpression(
        pattern: #"(?s)\bprivate\s+func\s+makeFileBackedContainer\s*\(\s*at\s+storeLocation\s*:\s*URL\s*,\s*allowsSave\s*:\s*Bool\s*=\s*true\s*\)\s*throws\s*->\s*ModelContainer\s*\{\s*let\s+schema\s*=\s*Schema\s*\(\s*versionedSchema\s*:\s*SchemaV1\.self\s*\)\s*let\s+configuration\s*=\s*ModelConfiguration\s*\(\s*"HippocratesPersistenceTest"\s*,\s*schema\s*:\s*schema\s*,\s*url\s*:\s*storeLocation\s*,\s*allowsSave\s*:\s*allowsSave\s*,\s*cloudKitDatabase\s*:\s*\.none\s*\)\s*return\s+try\s+ModelContainer\s*\(\s*for\s*:\s*schema\s*,\s*migrationPlan\s*:\s*HippocratesMigrationPlan\.self\s*,\s*configurations\s*:\s*\[\s*configuration\s*\]\s*\)\s*\}"#
    )
    let modelConfigurationExpression = try NSRegularExpression(pattern: #"\bModelConfiguration\b"#)
    let modelContainerExpression = try NSRegularExpression(pattern: #"\bModelContainer\b"#)
    let hasExactSurface = canonicalTestStore.matches(in: visibleSource, range: sourceRange).count == 1
        && modelConfigurationExpression.matches(in: visibleSource, range: sourceRange).count == 1
        && modelContainerExpression.matches(in: visibleSource, range: sourceRange).count == 2
    guard hasExactSurface else {
        return [
            Finding(
                path: path,
                line: 1,
                message: "SchemaContractTests must keep its one explicit local-only file-backed SwiftData fixture"
            )
        ]
    }
    return []
}
private func testPersistenceBoundaryFindings(
    in source: String,
    path: String,
    identity: ReviewedSourceIdentity
) throws -> [Finding] {
    if identity == .schemaContractTests {
        return try testStoreArchitectureFindings(in: source, path: path)
    }

    let visibleSource = sourceForStructure(source)
    let sourceRange = NSRange(visibleSource.startIndex..<visibleSource.endIndex, in: visibleSource)
    let storeTypeExpression = try NSRegularExpression(
        pattern: #"\b(?:ModelConfiguration|ModelContainer)\b"#
    )
    guard let match = storeTypeExpression.firstMatch(in: visibleSource, range: sourceRange) else {
        return []
    }
    return [
        Finding(
            path: path,
            line: lineNumber(in: visibleSource, at: match.range.location),
            message: "Only SchemaContractTests may construct the one reviewed test-only SwiftData container"
        )
    ]
}

private struct FilesystemInventory {
    let regularFiles: [URL]
    let symbolicLinks: [URL]
}

private func fileIsSymbolicLink(_ file: URL) -> Bool {
    (try? FileManager.default.destinationOfSymbolicLink(atPath: file.path)) != nil
}

private func filesystemInventory(under root: URL) throws -> FilesystemInventory {
    var isDirectory: ObjCBool = false
    guard
        FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
        isDirectory.boolValue
    else {
        throw NSError(
            domain: "SourceInventory",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Required directory is missing: \(root.path)"]
        )
    }

    var enumerationFailure: Error?
    guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [],
        errorHandler: { _, error in
            enumerationFailure = error
            return false
        }
    ) else {
        throw NSError(
            domain: "SourceInventory",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Could not enumerate required directory: \(root.path)"]
        )
    }

    var files: [URL] = []
    var symbolicLinks: [URL] = []
    for case let fileURL as URL in enumerator {
        if enumerationFailure != nil {
            break
        }
        let values = try fileURL.resourceValues(
            forKeys: [.isRegularFileKey]
        )
        let isSymbolicLink = fileIsSymbolicLink(fileURL)
        if values.isRegularFile == true, isSymbolicLink == false {
            files.append(fileURL.standardizedFileURL)
        }
        if isSymbolicLink {
            symbolicLinks.append(fileURL.standardizedFileURL)
        }
    }

    if let enumerationFailure {
        throw NSError(
            domain: "SourceInventory",
            code: 3,
            userInfo: [
                NSUnderlyingErrorKey: enumerationFailure,
                NSLocalizedDescriptionKey: "Directory enumeration failed beneath \(root.path)"
            ]
        )
    }
    return FilesystemInventory(
        regularFiles: files.sorted { $0.path < $1.path },
        symbolicLinks: symbolicLinks.sorted { $0.path < $1.path }
    )
}

private func regularFiles(under root: URL) throws -> [URL] {
    try filesystemInventory(under: root).regularFiles
}

private func swiftFiles(under root: URL) throws -> [URL] {
    try regularFiles(under: root).filter { $0.pathExtension.lowercased() == "swift" }
}

private struct PBXLexState {
    var isInsideString = false
    var isEscapingStringCharacter = false
    var isInsideBlockComment = false
}

private func pbxWithoutComments(_ text: String) -> String {
    let characters = Array(text)
    var output: [Character] = []
    output.reserveCapacity(characters.count)
    var state = PBXLexState()
    var index = 0

    while index < characters.count {
        let current = characters[index]
        let next = index + 1 < characters.count ? characters[index + 1] : nil

        if state.isInsideBlockComment {
            if current == "*", next == "/" {
                output.append(contentsOf: [" ", " "])
                state.isInsideBlockComment = false
                index += 2
            } else {
                output.append(current == "\n" ? "\n" : " ")
                index += 1
            }
            continue
        }

        if state.isInsideString {
            output.append(current)
            if state.isEscapingStringCharacter {
                state.isEscapingStringCharacter = false
            } else if current == "\\" {
                state.isEscapingStringCharacter = true
            } else if current == "\"" {
                state.isInsideString = false
            }
            index += 1
            continue
        }

        if current == "/", next == "/" {
            output.append(contentsOf: [" ", " "])
            index += 2
            while index < characters.count, characters[index] != "\n" {
                output.append(" ")
                index += 1
            }
            continue
        }
        if current == "/", next == "*" {
            output.append(contentsOf: [" ", " "])
            state.isInsideBlockComment = true
            index += 2
            continue
        }
        if current == "\"" {
            state.isInsideString = true
        }
        output.append(current)
        index += 1
    }

    return String(output)
}

private func pbxObjects(in projectText: String) throws -> [String: String] {
    let visibleProjectText = pbxWithoutComments(projectText)
    let projectProperties = try pbxTopLevelProperties(in: visibleProjectText)
    let requiredProjectProperties = Set([
        "archiveVersion",
        "classes",
        "objectVersion",
        "objects",
        "rootObject"
    ])
    guard Set(projectProperties.keys) == requiredProjectProperties else {
        throw pbxParserError(42, "The PBX project root properties changed or could not be parsed")
    }
    guard
        let rawObjects = projectProperties["objects"],
        rawObjects.first == "{",
        rawObjects.last == "}"
    else {
        throw pbxParserError(43, "The PBX objects dictionary is missing or malformed")
    }

    let rawEntries = try pbxTopLevelProperties(in: rawObjects)
    let identifierExpression = try NSRegularExpression(pattern: #"^[A-Fa-f0-9]{24}$"#)
    var objects: [String: String] = [:]
    for (identifier, value) in rawEntries {
        let range = NSRange(identifier.startIndex..<identifier.endIndex, in: identifier)
        guard
            identifierExpression.firstMatch(in: identifier, range: range) != nil,
            value.first == "{",
            value.last == "}"
        else {
            throw pbxParserError(44, "The PBX objects dictionary contains an unreviewed entry")
        }
        objects[identifier] = value
    }
    guard objects.isEmpty == false else {
        throw pbxParserError(45, "The PBX objects dictionary is empty")
    }
    return objects
}

private func pbxParserError(_ code: Int, _ message: String) -> NSError {
    NSError(
        domain: "PBXProjectParser",
        code: code,
        userInfo: [NSLocalizedDescriptionKey: message]
    )
}

private func pbxTopLevelProperties(in object: String) throws -> [String: String] {
    let characters = Array(object)
    var properties: [String: String] = [:]
    var index = 0
    var braceDepth = 0
    var isInsideString = false
    var isEscaping = false

    func isIdentifierStart(_ character: Character) -> Bool {
        character == "_" || character.isLetter || character.isNumber
    }

    func isIdentifierContinuation(_ character: Character) -> Bool {
        isIdentifierStart(character) || character.isNumber
    }

    while index < characters.count {
        let current = characters[index]

        if isInsideString {
            if isEscaping {
                isEscaping = false
            } else if current == "\\" {
                isEscaping = true
            } else if current == "\"" {
                isInsideString = false
            }
            index += 1
            continue
        }

        if current == "\"" {
            if braceDepth == 1 {
                throw pbxParserError(46, "Quoted PBX property keys are forbidden")
            }
            isInsideString = true
            index += 1
            continue
        }
        if current == "{" {
            if braceDepth == 1 {
                throw pbxParserError(47, "Anonymous PBX dictionaries are forbidden at property depth")
            }
            braceDepth += 1
            index += 1
            continue
        }
        if current == "}" {
            braceDepth -= 1
            guard braceDepth >= 0 else {
                throw pbxParserError(3, "PBX object closes more braces than it opens")
            }
            index += 1
            continue
        }

        guard braceDepth == 1 else {
            index += 1
            continue
        }
        if current.isWhitespace {
            index += 1
            continue
        }
        guard isIdentifierStart(current) else {
            throw pbxParserError(48, "PBX object contains an unparseable top-level token")

        }
        let keyStart = index
        var cursor = index + 1
        while cursor < characters.count, isIdentifierContinuation(characters[cursor]) {
            cursor += 1
        }
        let key = String(characters[keyStart..<cursor])
        while cursor < characters.count, characters[cursor].isWhitespace {
            cursor += 1
        }
        guard cursor < characters.count, characters[cursor] == "=" else {
            throw pbxParserError(49, "PBX property \(key) is missing an equals sign")
        }

        cursor += 1
        while cursor < characters.count, characters[cursor].isWhitespace {
            cursor += 1
        }
        let valueStart = cursor
        var valueBraceDepth = braceDepth
        var parenthesisDepth = 0
        var valueIsInsideString = false
        var valueIsEscaping = false
        var terminator: Int?

        while cursor < characters.count {
            let valueCharacter = characters[cursor]
            if valueIsInsideString {
                if valueIsEscaping {
                    valueIsEscaping = false
                } else if valueCharacter == "\\" {
                    valueIsEscaping = true
                } else if valueCharacter == "\"" {
                    valueIsInsideString = false
                }
                cursor += 1
                continue
            }

            if valueCharacter == "\"" {
                valueIsInsideString = true
            } else if valueCharacter == "{" {
                valueBraceDepth += 1
            } else if valueCharacter == "}" {
                valueBraceDepth -= 1
                if valueBraceDepth < 1 {
                    break
                }
            } else if valueCharacter == "(" {
                parenthesisDepth += 1
            } else if valueCharacter == ")" {
                parenthesisDepth -= 1
                guard parenthesisDepth >= 0 else {
                    throw pbxParserError(4, "PBX property \(key) has unbalanced parentheses")
                }
            } else if valueCharacter == ";", valueBraceDepth == 1, parenthesisDepth == 0 {
                terminator = cursor
                break
            }
            cursor += 1
        }

        guard let terminator, valueIsInsideString == false else {
            throw pbxParserError(5, "PBX property \(key) is missing a top-level semicolon")
        }
        guard properties[key] == nil else {
            throw pbxParserError(6, "PBX object declares property \(key) more than once")
        }

        let value = String(characters[valueStart..<terminator])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty == false else {
            throw pbxParserError(7, "PBX property \(key) has an empty value")
        }
        properties[key] = value
        index = terminator + 1
    }

    guard braceDepth == 0, isInsideString == false else {
        throw pbxParserError(8, "PBX object structure is unbalanced")
    }
    return properties
}

private func pbxUnquotedValue(_ rawValue: String, property: String, allowingEscapes: Bool = false) throws -> String {
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard value.isEmpty == false else {
        throw pbxParserError(9, "PBX property \(property) has no value")
    }
    let unquotedValue: String
    if value.first == "\"" {
        guard value.count >= 2, value.last == "\"" else {
            throw pbxParserError(10, "PBX property \(property) has a malformed quoted value")
        }
        unquotedValue = String(value.dropFirst().dropLast())
    } else {
        guard value.contains("\"") == false else {
            throw pbxParserError(11, "PBX property \(property) contains an unexpected quote")
        }
        unquotedValue = value
    }
    guard allowingEscapes || unquotedValue.contains("\\") == false else {
        throw pbxParserError(40, "PBX property \(property) contains an unsupported escape")
    }
    return unquotedValue
}

private func pbxScalar(_ property: String, in object: String, allowingEscapes: Bool = false) throws -> String? {
    guard let rawValue = try pbxTopLevelProperties(in: object)[property] else {
        return nil
    }
    guard rawValue.first != "(", rawValue.first != "{" else {
        throw pbxParserError(12, "PBX property \(property) is not a scalar")
    }
    return try pbxUnquotedValue(rawValue, property: property, allowingEscapes: allowingEscapes)
}

private func pbxRequiredScalar(_ property: String, in object: String, allowingEscapes: Bool = false) throws -> String {
    guard let value = try pbxScalar(property, in: object, allowingEscapes: allowingEscapes) else {
        throw pbxParserError(13, "Required PBX scalar property \(property) is missing")
    }
    return value
}

private func pbxListItems(
    _ property: String,
    in object: String,
    required: Bool = true
) throws -> [String] {
    guard let rawValue = try pbxTopLevelProperties(in: object)[property] else {
        if required {
            throw pbxParserError(14, "Required PBX list property \(property) is missing")
        }
        return []
    }
    guard rawValue.first == "(", rawValue.last == ")" else {
        throw pbxParserError(15, "PBX property \(property) is not a list")
    }

    let interior = Array(rawValue.dropFirst().dropLast())
    var items: [String] = []
    var itemStart = 0
    var index = 0
    var isInsideString = false
    var isEscaping = false

    func appendItem(endingAt end: Int) throws {
        let rawItem = String(interior[itemStart..<end])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if rawItem.isEmpty == false {
            items.append(try pbxUnquotedValue(rawItem, property: property))
        }
    }

    while index < interior.count {
        let current = interior[index]
        if isInsideString {
            if isEscaping {
                isEscaping = false
            } else if current == "\\" {
                isEscaping = true
            } else if current == "\"" {
                isInsideString = false
            }
        } else if current == "\"" {
            isInsideString = true
        } else if current == "," {
            try appendItem(endingAt: index)
            itemStart = index + 1
        } else if current == "(" || current == ")" || current == "{" || current == "}" {
            throw pbxParserError(16, "PBX list \(property) contains an unsupported nested value")
        }
        index += 1
    }

    guard isInsideString == false else {
        throw pbxParserError(17, "PBX list \(property) contains an unterminated string")
    }
    try appendItem(endingAt: interior.count)
    return items
}

private func pbxIDs(
    inList property: String,
    in object: String,
    required: Bool = true
) throws -> [String] {
    let items = try pbxListItems(property, in: object, required: required)
    let expression = try NSRegularExpression(pattern: #"^[A-Fa-f0-9]{24}$"#)
    for item in items {
        let range = NSRange(item.startIndex..<item.endIndex, in: item)
        guard expression.firstMatch(in: item, range: range) != nil else {
            throw pbxParserError(18, "PBX list \(property) contains a non-object identifier")
        }
    }
    return items
}

private func pbxStringValues(inList property: String, in object: String) throws -> [String] {
    try pbxListItems(property, in: object)
}

private func pbxISA(in object: String) throws -> String {
    try pbxRequiredScalar("isa", in: object)
}

private struct BuildConfigurationContract {
    let label: String
    let ownerObject: String
    let debugKeys: Set<String>
    let releaseKeys: Set<String>
    let commonScalarValues: [String: String]
    let debugScalarValues: [String: String]
    let releaseScalarValues: [String: String]
    let debugListValues: [String: [String]]
    let releaseListValues: [String: [String]]
}

private func buildConfigurationFindings(projectText: String, path: String) -> [Finding] {
    do {
        let objects = try pbxObjects(in: projectText).mapValues(pbxWithoutComments)
        var isaByID: [String: String] = [:]
        for (identifier, object) in objects {
            isaByID[identifier] = try pbxISA(in: object)
        }

        let projects = objects.filter { isaByID[$0.key] == "PBXProject" }
        let nativeTargets = objects.filter { isaByID[$0.key] == "PBXNativeTarget" }
        let appTargets = try nativeTargets.filter {
            try pbxRequiredScalar("name", in: $0.value) == "Hippocrates"
                && pbxRequiredScalar("productType", in: $0.value)
                    == "com.apple.product-type.application"
        }
        let testTargets = try nativeTargets.filter {
            try pbxRequiredScalar("name", in: $0.value) == "HippocratesTests"
                && pbxRequiredScalar("productType", in: $0.value)
                    == "com.apple.product-type.bundle.unit-test"
        }
        guard
            projects.count == 1,
            appTargets.count == 1,
            testTargets.count == 1,
            let projectObject = projects.first?.value,
            let appObject = appTargets.first?.value,
            let testObject = testTargets.first?.value
        else {
            throw pbxParserError(60, "Build configurations cannot resolve the reviewed project and targets")
        }

        func keySet(_ text: String) -> Set<String> {
            Set(text.split(whereSeparator: { $0.isWhitespace }).map(String.init))
        }

        let projectDebugKeys = keySet(
            """
            ALWAYS_SEARCH_USER_PATHS
            CLANG_ANALYZER_NONNULL
            CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION
            CLANG_CXX_LANGUAGE_STANDARD
            CLANG_ENABLE_MODULES
            CLANG_ENABLE_OBJC_ARC
            CLANG_ENABLE_OBJC_WEAK
            CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING
            CLANG_WARN_BOOL_CONVERSION
            CLANG_WARN_COMMA
            CLANG_WARN_CONSTANT_CONVERSION
            CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS
            CLANG_WARN_DIRECT_OBJC_ISA_USAGE
            CLANG_WARN_DOCUMENTATION_COMMENTS
            CLANG_WARN_EMPTY_BODY
            CLANG_WARN_ENUM_CONVERSION
            CLANG_WARN_INFINITE_RECURSION
            CLANG_WARN_INT_CONVERSION
            CLANG_WARN_NON_LITERAL_NULL_CONVERSION
            CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF
            CLANG_WARN_OBJC_LITERAL_CONVERSION
            CLANG_WARN_OBJC_ROOT_CLASS
            CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER
            CLANG_WARN_RANGE_LOOP_ANALYSIS
            CLANG_WARN_STRICT_PROTOTYPES
            CLANG_WARN_SUSPICIOUS_MOVE
            CLANG_WARN_UNGUARDED_AVAILABILITY
            CLANG_WARN_UNREACHABLE_CODE
            CLANG_WARN__DUPLICATE_METHOD_MATCH
            COPY_PHASE_STRIP
            DEBUG_INFORMATION_FORMAT
            ENABLE_STRICT_OBJC_MSGSEND
            ENABLE_TESTABILITY
            ENABLE_USER_SCRIPT_SANDBOXING
            GCC_C_LANGUAGE_STANDARD
            GCC_NO_COMMON_BLOCKS
            GCC_OPTIMIZATION_LEVEL
            GCC_PREPROCESSOR_DEFINITIONS
            GCC_TREAT_WARNINGS_AS_ERRORS
            GCC_WARN_64_TO_32_BIT_CONVERSION
            GCC_WARN_ABOUT_RETURN_TYPE
            GCC_WARN_UNDECLARED_SELECTOR
            GCC_WARN_UNINITIALIZED_AUTOS
            GCC_WARN_UNUSED_FUNCTION
            GCC_WARN_UNUSED_VARIABLE
            IPHONEOS_DEPLOYMENT_TARGET
            LOCALIZATION_PREFERS_STRING_CATALOGS
            MTL_ENABLE_DEBUG_INFO
            MTL_FAST_MATH
            ONLY_ACTIVE_ARCH
            SDKROOT
            SWIFT_ACTIVE_COMPILATION_CONDITIONS
            SWIFT_OPTIMIZATION_LEVEL
            """
        )
        let projectReleaseKeys = keySet(
            """
            ALWAYS_SEARCH_USER_PATHS
            CLANG_ANALYZER_NONNULL
            CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION
            CLANG_CXX_LANGUAGE_STANDARD
            CLANG_ENABLE_MODULES
            CLANG_ENABLE_OBJC_ARC
            CLANG_ENABLE_OBJC_WEAK
            CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING
            CLANG_WARN_BOOL_CONVERSION
            CLANG_WARN_COMMA
            CLANG_WARN_CONSTANT_CONVERSION
            CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS
            CLANG_WARN_DIRECT_OBJC_ISA_USAGE
            CLANG_WARN_DOCUMENTATION_COMMENTS
            CLANG_WARN_EMPTY_BODY
            CLANG_WARN_ENUM_CONVERSION
            CLANG_WARN_INFINITE_RECURSION
            CLANG_WARN_INT_CONVERSION
            CLANG_WARN_NON_LITERAL_NULL_CONVERSION
            CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF
            CLANG_WARN_OBJC_LITERAL_CONVERSION
            CLANG_WARN_OBJC_ROOT_CLASS
            CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER
            CLANG_WARN_RANGE_LOOP_ANALYSIS
            CLANG_WARN_STRICT_PROTOTYPES
            CLANG_WARN_SUSPICIOUS_MOVE
            CLANG_WARN_UNGUARDED_AVAILABILITY
            CLANG_WARN_UNREACHABLE_CODE
            CLANG_WARN__DUPLICATE_METHOD_MATCH
            COPY_PHASE_STRIP
            DEBUG_INFORMATION_FORMAT
            ENABLE_NS_ASSERTIONS
            ENABLE_STRICT_OBJC_MSGSEND
            ENABLE_USER_SCRIPT_SANDBOXING
            GCC_C_LANGUAGE_STANDARD
            GCC_NO_COMMON_BLOCKS
            GCC_TREAT_WARNINGS_AS_ERRORS
            GCC_WARN_64_TO_32_BIT_CONVERSION
            GCC_WARN_ABOUT_RETURN_TYPE
            GCC_WARN_UNDECLARED_SELECTOR
            GCC_WARN_UNINITIALIZED_AUTOS
            GCC_WARN_UNUSED_FUNCTION
            GCC_WARN_UNUSED_VARIABLE
            IPHONEOS_DEPLOYMENT_TARGET
            LOCALIZATION_PREFERS_STRING_CATALOGS
            MTL_ENABLE_DEBUG_INFO
            MTL_FAST_MATH
            SDKROOT
            SWIFT_COMPILATION_MODE
            """
        )
        let appKeys = keySet(
            """
            CODE_SIGN_STYLE
            CURRENT_PROJECT_VERSION
            GENERATE_INFOPLIST_FILE
            INFOPLIST_KEY_CFBundleDisplayName
            INFOPLIST_KEY_LSApplicationCategoryType
            INFOPLIST_KEY_UIApplicationSceneManifest_Generation
            INFOPLIST_KEY_UILaunchScreen_Generation
            IPHONEOS_DEPLOYMENT_TARGET
            LD_RUNPATH_SEARCH_PATHS
            MARKETING_VERSION
            PRODUCT_BUNDLE_IDENTIFIER
            PRODUCT_NAME
            SUPPORTED_PLATFORMS
            SUPPORTS_MACCATALYST
            SWIFT_EMIT_LOC_STRINGS
            SWIFT_STRICT_CONCURRENCY
            SWIFT_TREAT_WARNINGS_AS_ERRORS
            SWIFT_VERSION
            TARGETED_DEVICE_FAMILY
            """
        )
        let testKeys = keySet(
            """
            BUNDLE_LOADER
            CODE_SIGN_STYLE
            CURRENT_PROJECT_VERSION
            GENERATE_INFOPLIST_FILE
            IPHONEOS_DEPLOYMENT_TARGET
            MARKETING_VERSION
            PRODUCT_BUNDLE_IDENTIFIER
            PRODUCT_NAME
            SUPPORTED_PLATFORMS
            SWIFT_STRICT_CONCURRENCY
            SWIFT_TREAT_WARNINGS_AS_ERRORS
            SWIFT_VERSION
            TARGETED_DEVICE_FAMILY
            TEST_HOST
            """
        )

        let projectCommonScalars = [
            "ALWAYS_SEARCH_USER_PATHS": "NO",
            "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
            "GCC_TREAT_WARNINGS_AS_ERRORS": "YES",
            "IPHONEOS_DEPLOYMENT_TARGET": "18.0",
            "SDKROOT": "iphoneos"
        ]
        let appScalars = [
            "CODE_SIGN_STYLE": "Automatic",
            "CURRENT_PROJECT_VERSION": "1",
            "GENERATE_INFOPLIST_FILE": "YES",
            "INFOPLIST_KEY_CFBundleDisplayName": "Hippocrates",
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.productivity",
            "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
            "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
            "IPHONEOS_DEPLOYMENT_TARGET": "18.0",
            "MARKETING_VERSION": "1.0",
            "PRODUCT_BUNDLE_IDENTIFIER": "com.ayyitskevin.hippocrates",
            "PRODUCT_NAME": "$(TARGET_NAME)",
            "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
            "SUPPORTS_MACCATALYST": "NO",
            "SWIFT_EMIT_LOC_STRINGS": "YES",
            "SWIFT_STRICT_CONCURRENCY": "complete",
            "SWIFT_TREAT_WARNINGS_AS_ERRORS": "YES",
            "SWIFT_VERSION": "6.0",
            "TARGETED_DEVICE_FAMILY": "1"
        ]
        let testScalars = [
            "BUNDLE_LOADER": "$(TEST_HOST)",
            "CODE_SIGN_STYLE": "Automatic",
            "CURRENT_PROJECT_VERSION": "1",
            "GENERATE_INFOPLIST_FILE": "YES",
            "IPHONEOS_DEPLOYMENT_TARGET": "18.0",
            "MARKETING_VERSION": "1.0",
            "PRODUCT_BUNDLE_IDENTIFIER": "com.ayyitskevin.hippocrates.tests",
            "PRODUCT_NAME": "$(TARGET_NAME)",
            "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
            "SWIFT_STRICT_CONCURRENCY": "complete",
            "SWIFT_TREAT_WARNINGS_AS_ERRORS": "YES",
            "SWIFT_VERSION": "6.0",
            "TARGETED_DEVICE_FAMILY": "1",
            "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/Hippocrates.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Hippocrates"
        ]

        let contracts = [
            BuildConfigurationContract(
                label: "project",
                ownerObject: projectObject,
                debugKeys: projectDebugKeys,
                releaseKeys: projectReleaseKeys,
                commonScalarValues: projectCommonScalars,
                debugScalarValues: [
                    "DEBUG_INFORMATION_FORMAT": "dwarf",
                    "ENABLE_TESTABILITY": "YES",
                    "ONLY_ACTIVE_ARCH": "YES",
                    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)",
                    "SWIFT_OPTIMIZATION_LEVEL": "-Onone"
                ],
                releaseScalarValues: [
                    "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
                    "ENABLE_NS_ASSERTIONS": "NO",
                    "SWIFT_COMPILATION_MODE": "wholemodule"
                ],
                debugListValues: [
                    "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"]
                ],
                releaseListValues: [:]
            ),
            BuildConfigurationContract(
                label: "app target",
                ownerObject: appObject,
                debugKeys: appKeys,
                releaseKeys: appKeys,
                commonScalarValues: appScalars,
                debugScalarValues: [:],
                releaseScalarValues: [:],
                debugListValues: [
                    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"]
                ],
                releaseListValues: [
                    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"]
                ]
            ),
            BuildConfigurationContract(
                label: "unit-test target",
                ownerObject: testObject,
                debugKeys: testKeys,
                releaseKeys: testKeys,
                commonScalarValues: testScalars,
                debugScalarValues: [:],
                releaseScalarValues: [:],
                debugListValues: [:],
                releaseListValues: [:]
            )
        ]

        func referencedID(_ property: String, in object: String) throws -> String {
            let value = try pbxRequiredScalar(property, in: object)
            guard let identifier = value.split(whereSeparator: { $0.isWhitespace }).first else {
                throw pbxParserError(61, "PBX property \(property) has no object identifier")
            }
            return String(identifier)
        }

        let configurationListIDs = try contracts.map {
            try referencedID("buildConfigurationList", in: $0.ownerObject)
        }
        let allConfigurationListIDs = Set(
            objects.filter { isaByID[$0.key] == "XCConfigurationList" }.map(\.key)
        )
        guard
            configurationListIDs.count == Set(configurationListIDs).count,
            Set(configurationListIDs) == allConfigurationListIDs,
            configurationListIDs.count == 3
        else {
            throw pbxParserError(62, "Project, app, and tests must own exactly three distinct configuration lists")
        }

        var referencedConfigurationIDs: [String] = []
        for (contract, listID) in zip(contracts, configurationListIDs) {
            guard let listObject = objects[listID] else {
                throw pbxParserError(63, "\(contract.label) configuration list is missing")
            }
            let listProperties = try pbxTopLevelProperties(in: listObject)
            guard Set(listProperties.keys) == Set([
                "isa",
                "buildConfigurations",
                "defaultConfigurationIsVisible",
                "defaultConfigurationName"
            ]) else {
                throw pbxParserError(64, "\(contract.label) configuration list contains unreviewed properties")
            }
            guard
                try pbxRequiredScalar("defaultConfigurationIsVisible", in: listObject) == "0",
                try pbxRequiredScalar("defaultConfigurationName", in: listObject) == "Release"
            else {
                throw pbxParserError(65, "\(contract.label) configuration defaults changed")
            }

            let configurationIDs = try pbxIDs(inList: "buildConfigurations", in: listObject)
            guard
                configurationIDs.count == 2,
                configurationIDs.count == Set(configurationIDs).count
            else {
                throw pbxParserError(66, "\(contract.label) must bind one Debug and one Release configuration")
            }
            referencedConfigurationIDs.append(contentsOf: configurationIDs)

            for (index, configurationID) in configurationIDs.enumerated() {
                guard
                    let configurationObject = objects[configurationID],
                    isaByID[configurationID] == "XCBuildConfiguration"
                else {
                    throw pbxParserError(67, "\(contract.label) references an invalid build configuration")
                }
                let configurationProperties = try pbxTopLevelProperties(in: configurationObject)
                guard Set(configurationProperties.keys) == Set(["isa", "buildSettings", "name"]) else {
                    throw pbxParserError(68, "\(contract.label) build configuration contains unreviewed properties")
                }

                let expectedName = index == 0 ? "Debug" : "Release"
                guard try pbxRequiredScalar("name", in: configurationObject) == expectedName else {
                    throw pbxParserError(69, "\(contract.label) configuration order must be Debug then Release")
                }
                guard
                    let rawSettings = configurationProperties["buildSettings"],
                    rawSettings.first == "{",
                    rawSettings.last == "}",
                    rawSettings.contains("\\") == false
                else {
                    throw pbxParserError(70, "\(contract.label) \(expectedName) build settings are malformed")
                }

                let settingProperties = try pbxTopLevelProperties(in: rawSettings)
                let expectedKeys = expectedName == "Debug" ? contract.debugKeys : contract.releaseKeys
                guard Set(settingProperties.keys) == expectedKeys else {
                    let unexpected = Set(settingProperties.keys).subtracting(expectedKeys).sorted()
                    let missing = expectedKeys.subtracting(Set(settingProperties.keys)).sorted()
                    throw pbxParserError(
                        71,
                        "\(contract.label) \(expectedName) setting keys changed; unexpected=\(unexpected), missing=\(missing)"
                    )
                }

                var expectedScalarValues = contract.commonScalarValues
                let configurationScalars = expectedName == "Debug"
                    ? contract.debugScalarValues
                    : contract.releaseScalarValues
                expectedScalarValues.merge(configurationScalars) { _, reviewed in reviewed }
                for (key, expectedValue) in expectedScalarValues {
                    guard try pbxRequiredScalar(key, in: rawSettings) == expectedValue else {
                        throw pbxParserError(72, "\(contract.label) \(expectedName) value for \(key) changed")
                    }
                }

                let expectedListValues = expectedName == "Debug"
                    ? contract.debugListValues
                    : contract.releaseListValues
                for (key, expectedValues) in expectedListValues {
                    guard try pbxStringValues(inList: key, in: rawSettings) == expectedValues else {
                        throw pbxParserError(73, "\(contract.label) \(expectedName) list \(key) changed")
                    }
                }
            }
        }

        let allBuildConfigurationIDs = Set(
            objects.filter { isaByID[$0.key] == "XCBuildConfiguration" }.map(\.key)
        )
        guard
            referencedConfigurationIDs.count == 6,
            referencedConfigurationIDs.count == Set(referencedConfigurationIDs).count,
            Set(referencedConfigurationIDs) == allBuildConfigurationIDs
        else {
            throw pbxParserError(74, "Exactly six bound Debug/Release build configurations are required")
        }
        return []
    } catch {
        return [
            Finding(
                path: path,
                line: 1,
                message: "Xcode build configurations changed outside the reviewed allowlist: \(error.localizedDescription)"
            )
        ]
    }
}
private func physicalFileIdentity(at path: String) throws -> String {
    let attributes = try FileManager.default.attributesOfItem(atPath: path)
    guard
        let device = attributes[.systemNumber] as? NSNumber,
        let inode = attributes[.systemFileNumber] as? NSNumber
    else {
        throw pbxParserError(50, "Regular source file has no stable device/inode identity")
    }
    return "\(device.uint64Value):\(inode.uint64Value)"
}
private struct TargetSourceInventory {
    let lexicalPaths: [String]
    let resolvedPaths: [String]
    let findings: [Finding]
    let physicalIdentities: [String]
}

private func pathIsBeneath(_ path: String, rootPath: String) -> Bool {
    path.hasPrefix(rootPath + "/")
}
private func isRegularNonSymlinkFile(_ file: URL, beneath root: URL) throws -> Bool {
    let values = try file.resourceValues(
        forKeys: [.isRegularFileKey]
    )
    let resolvedFile = file.resolvingSymlinksInPath().standardizedFileURL
    let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
    return values.isRegularFile == true
        && fileIsSymbolicLink(file) == false
        && pathIsBeneath(resolvedFile.path, rootPath: resolvedRoot.path)
}

private let privacyManifestContractMessage =
    "PrivacyInfo.xcprivacy must declare exactly no tracking and no collected data"

private struct PrivacyManifestContract: Decodable {
    let tracking: Bool
    let collectedDataTypes: [String]

    private enum CodingKeys: String, CodingKey {
        case tracking = "NSPrivacyTracking"
        case collectedDataTypes = "NSPrivacyCollectedDataTypes"
    }
}

private final class PrivacyManifestXMLDelegate: NSObject, XMLParserDelegate {
    private var elementStack: [String] = []
    private var currentRootKey: String?
    private(set) var rootKeyCounts: [String: Int] = [:]
    private(set) var failed = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard failed == false else { return }
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
        guard elementStack.last == elementName else {
            failed = true
            return
        }
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

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard currentRootKey != nil,
            let text = String(data: CDATABlock, encoding: .utf8) else {
            failed = true
            return
        }
        currentRootKey!.append(contentsOf: text)
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        failed = true
    }

    func parser(_ parser: XMLParser, validationErrorOccurred validationError: Error) {
        failed = true
    }

    var isComplete: Bool {
        failed == false && elementStack.isEmpty && currentRootKey == nil
    }
}

private func privacyManifestHasExactXMLKeys(_ data: Data) -> Bool {
    let delegate = PrivacyManifestXMLDelegate()
    let parser = XMLParser(data: data)
    parser.shouldProcessNamespaces = false
    parser.shouldReportNamespacePrefixes = false
    parser.shouldResolveExternalEntities = false
    parser.delegate = delegate
    let expectedCounts = [
        "NSPrivacyTracking": 1,
        "NSPrivacyCollectedDataTypes": 1
    ]
    return parser.parse()
        && delegate.isComplete
        && delegate.rootKeyCounts == expectedCounts
}

private func privacyManifestContractFinding(path: String) -> Finding {
    Finding(path: path, line: 1, message: privacyManifestContractMessage)
}

private func privacyManifestFindings(in data: Data, path: String) -> [Finding] {
    func violation() -> [Finding] {
        [privacyManifestContractFinding(path: path)]
    }

    let object: Any
    let contract: PrivacyManifestContract
    var format = PropertyListSerialization.PropertyListFormat.xml
    do {
        object = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: &format
        )
        contract = try PropertyListDecoder().decode(PrivacyManifestContract.self, from: data)
    } catch {
        return violation()
    }

    guard
        format == .xml,
        privacyManifestHasExactXMLKeys(data),
        let manifest = object as? [String: Any],
        Set(manifest.keys) == Set(["NSPrivacyTracking", "NSPrivacyCollectedDataTypes"]),
        contract.tracking == false,
        contract.collectedDataTypes.isEmpty
    else {
        return violation()
    }
    return []
}

private func privacyManifestFileFindings(at file: URL, beneath root: URL) throws -> [Finding] {
    var isDirectory: ObjCBool = false
    guard
        FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory),
        isDirectory.boolValue == false,
        try isRegularNonSymlinkFile(file, beneath: root)
    else {
        return []
    }
    guard let data = FileManager.default.contents(atPath: file.path) else {
        return [privacyManifestContractFinding(path: file.path)]
    }
    return privacyManifestFindings(in: data, path: file.path)
}

private let expectedBoundaryInputPaths = [
    "$(SRCROOT)",
    "$(SRCROOT)/Hippocrates",
    "$(SRCROOT)/Hippocrates/App",
    "$(SRCROOT)/Hippocrates/App/HippocratesApp.swift",
    "$(SRCROOT)/Hippocrates/App/RootView.swift",
    "$(SRCROOT)/Hippocrates/Backup",
    "$(SRCROOT)/Hippocrates/Backup/BackupArchive.swift",
    "$(SRCROOT)/Hippocrates/Backup/BackupCodec.swift",
    "$(SRCROOT)/Hippocrates/Backup/BackupDocument.swift",
    "$(SRCROOT)/Hippocrates/Backup/BackupService.swift",
    "$(SRCROOT)/Hippocrates/Export",
    "$(SRCROOT)/Hippocrates/Export/InterventionCSV.swift",
    "$(SRCROOT)/Hippocrates/Export/SummaryEngine.swift",
    "$(SRCROOT)/Hippocrates/Features",
    "$(SRCROOT)/Hippocrates/Features/Capture",
    "$(SRCROOT)/Hippocrates/Features/Capture/CaptureHomeView.swift",
    "$(SRCROOT)/Hippocrates/Features/Capture/CaptureSupport.swift",
    "$(SRCROOT)/Hippocrates/Features/Capture/CaptureView.swift",
    "$(SRCROOT)/Hippocrates/Features/Capture/RecentLedgerView.swift",
    "$(SRCROOT)/Hippocrates/Features/Onboarding",
    "$(SRCROOT)/Hippocrates/Features/Onboarding/FirstRunView.swift",
    "$(SRCROOT)/Hippocrates/Features/Settings",
    "$(SRCROOT)/Hippocrates/Features/Settings/TaxonomySettingsView.swift",
    "$(SRCROOT)/Hippocrates/Features/Summary",
    "$(SRCROOT)/Hippocrates/Features/Summary/SummaryView.swift",
    "$(SRCROOT)/Hippocrates/Models",
    "$(SRCROOT)/Hippocrates/Models/DomainEnums.swift",
    "$(SRCROOT)/Hippocrates/Persistence",
    "$(SRCROOT)/Hippocrates/Persistence/AppConfigService.swift",
    "$(SRCROOT)/Hippocrates/Persistence/HippocratesMigrationPlan.swift",
    "$(SRCROOT)/Hippocrates/Persistence/HippocratesStore.swift",
    "$(SRCROOT)/Hippocrates/Persistence/SchemaV1.swift",
    "$(SRCROOT)/Hippocrates/Resources",
    "$(SRCROOT)/Hippocrates/Resources/PrivacyInfo.xcprivacy",
    "$(SRCROOT)/Hippocrates/Services",
    "$(SRCROOT)/Hippocrates/Services/BootstrapPolicy.swift",
    "$(SRCROOT)/Hippocrates/Services/FrecencyRanking.swift",
    "$(SRCROOT)/Hippocrates/Services/InterventionCaptureService.swift",
    "$(SRCROOT)/Hippocrates/Services/InterventionLedgerService.swift",
    "$(SRCROOT)/Hippocrates/Services/StarterTaxonomy.swift",
    "$(SRCROOT)/Hippocrates/Services/SummarySnapshotService.swift",
    "$(SRCROOT)/Hippocrates/Services/TaxonomyService.swift",
    "$(SRCROOT)/HippocratesTests",
    "$(SRCROOT)/HippocratesTests/BackupRoundTripTests.swift",
    "$(SRCROOT)/HippocratesTests/CaptureAndLedgerTests.swift",
    "$(SRCROOT)/HippocratesTests/PrivacyManifestTests.swift",
    "$(SRCROOT)/HippocratesTests/SchemaContractTests.swift",
    "$(SRCROOT)/HippocratesTests/SummaryAndCSVTests.swift",
    "$(SRCROOT)/HippocratesTests/TaxonomyGovernanceTests.swift",
    "$(SRCROOT)/Hippocrates.xcodeproj",
    "$(SRCROOT)/Hippocrates.xcodeproj/project.pbxproj",
    "$(SRCROOT)/Hippocrates.xcodeproj/xcshareddata",
    "$(SRCROOT)/Hippocrates.xcodeproj/xcshareddata/xcschemes",
    "$(SRCROOT)/Hippocrates.xcodeproj/xcshareddata/xcschemes/Hippocrates.xcscheme",
    "$(SRCROOT)/Scripts",
    "$(SRCROOT)/Scripts/NetworkBoundaryScanner.swift"
]


/// The source folder alone is not the build boundary: Xcode can compile a file
/// from anywhere on disk. Resolve target source phases so off-tree files cannot
/// evade inspection.
private func appTargetSourceFindings(
    projectText: String,
    projectPath: String,
    repositoryRoot: URL,
    sourceRoot: URL
) throws -> [Finding] {
    let objects = try pbxObjects(in: projectText).mapValues(pbxWithoutComments)
    var isaByID: [String: String] = [:]
    for (id, object) in objects {
        isaByID[id] = try pbxISA(in: object)
    }

    let nativeTargets = objects.filter { isaByID[$0.key] == "PBXNativeTarget" }
    let applicationTargets = try nativeTargets.filter {
        try pbxRequiredScalar("productType", in: $0.value) == "com.apple.product-type.application"
    }
    guard applicationTargets.count == 1, let appTargetEntry = applicationTargets.first else {
        return [
            Finding(
                path: projectPath,
                line: 1,
                message: "The project must contain exactly one application target"
            )
        ]
    }

    let unitTestTargets = try nativeTargets.filter {
        try pbxRequiredScalar("productType", in: $0.value) == "com.apple.product-type.bundle.unit-test"
    }
    guard
        nativeTargets.count == 2,
        unitTestTargets.count == 1,
        let testTargetEntry = unitTestTargets.first,
        try pbxRequiredScalar("name", in: testTargetEntry.value) == "HippocratesTests"
    else {
        return [
            Finding(
                path: projectPath,
                line: 1,
                message: "The project is limited to one application target and one unit-test target"
            )
        ]
    }

    let appTargetID = appTargetEntry.key
    let appTarget = appTargetEntry.value
    let testTargetID = testTargetEntry.key
    let testTarget = testTargetEntry.value
    guard try pbxRequiredScalar("name", in: appTarget) == "Hippocrates" else {
        return [Finding(path: projectPath, line: 1, message: "The application target must be Hippocrates")]
    }

    let projectEntries = objects.filter { isaByID[$0.key] == "PBXProject" }
    guard projectEntries.count == 1, let projectEntry = projectEntries.first else {
        return [Finding(path: projectPath, line: 1, message: "The project must contain exactly one PBXProject object")]
    }
    let projectRootProperties = try pbxTopLevelProperties(in: pbxWithoutComments(projectText))
    guard
        let rawRootObject = projectRootProperties["rootObject"],
        try pbxUnquotedValue(rawRootObject, property: "rootObject")
            .split(separator: " ").first.map(String.init) == projectEntry.key
    else {
        return [
            Finding(
                path: projectPath,
                line: 1,
                message: "PBX rootObject must be the one validated project object"
            )
        ]
    }
    let projectTargetIDs = try pbxIDs(inList: "targets", in: projectEntry.value)
    guard
        projectTargetIDs.count == 2,
        Set(projectTargetIDs) == Set([appTargetID, testTargetID])
    else {
        return [
            Finding(
                path: projectPath,
                line: 1,
                message: "PBXProject target membership must be exactly Hippocrates and HippocratesTests"
            )
        ]
    }

    let mainGroupID = try pbxRequiredScalar("mainGroup", in: projectEntry.value)
        .split(separator: " ").first.map(String.init) ?? ""
    guard isaByID[mainGroupID] == "PBXGroup" else {
        return [Finding(path: projectPath, line: 1, message: "PBXProject mainGroup is missing or invalid")]
    }

    func phaseIDs(ofType type: String, in ids: [String]) -> [String] {
        ids.filter { isaByID[$0] == type }
    }

    let appPhaseIDs = try pbxIDs(inList: "buildPhases", in: appTarget)
    let shellPhaseIDs = phaseIDs(ofType: "PBXShellScriptBuildPhase", in: appPhaseIDs)
    let appSourcePhaseIDs = phaseIDs(ofType: "PBXSourcesBuildPhase", in: appPhaseIDs)
    let appFrameworkPhaseIDs = phaseIDs(ofType: "PBXFrameworksBuildPhase", in: appPhaseIDs)
    let appResourcePhaseIDs = phaseIDs(ofType: "PBXResourcesBuildPhase", in: appPhaseIDs)
    guard
        appPhaseIDs.count == Set(appPhaseIDs).count,
        appPhaseIDs.count == 4,
        shellPhaseIDs.count == 1,
        appSourcePhaseIDs.count == 1,
        appFrameworkPhaseIDs.count == 1,
        appResourcePhaseIDs.count == 1,
        appPhaseIDs == [
            shellPhaseIDs[0],
            appSourcePhaseIDs[0],
            appFrameworkPhaseIDs[0],
            appResourcePhaseIDs[0]
        ],
        let shellPhase = objects[shellPhaseIDs[0]],
        let appSourcePhase = objects[appSourcePhaseIDs[0]],
        let appFrameworkPhase = objects[appFrameworkPhaseIDs[0]],
        let appResourcePhase = objects[appResourcePhaseIDs[0]]
    else {
        return [
            Finding(
                path: projectPath,
                line: 1,
                message: "The app target build phases changed outside the reviewed offline architecture"
            )
        ]
    }

    let expectedShellScript = #"exec /usr/bin/env -i DEVELOPER_DIR=\"$DEVELOPER_DIR\" HOME=/var/empty PATH=/usr/bin:/bin:/usr/sbin:/sbin TMPDIR=\"$TMPDIR\" /usr/bin/xcrun --sdk macosx swift -module-cache-path \"$TMPDIR/HippocratesBoundaryModuleCache\" \"$SRCROOT/Scripts/NetworkBoundaryScanner.swift\" --sandboxed-build-check \"$SRCROOT\"\n"#
    guard
        try pbxRequiredScalar("name", in: shellPhase) == "Enforce Offline Boundary",
        try pbxRequiredScalar("alwaysOutOfDate", in: shellPhase) == "1",
        try pbxRequiredScalar("buildActionMask", in: shellPhase) == "2147483647",
        try pbxRequiredScalar("runOnlyForDeploymentPostprocessing", in: shellPhase) == "0",
        try pbxRequiredScalar("shellPath", in: shellPhase) == "/bin/sh",
        try pbxRequiredScalar("shellScript", in: shellPhase, allowingEscapes: true) == expectedShellScript,
        try pbxRequiredScalar("showEnvVarsInLog", in: shellPhase) == "0",
        try pbxIDs(inList: "files", in: shellPhase).isEmpty,
        try pbxStringValues(inList: "inputFileListPaths", in: shellPhase).isEmpty,
        try pbxStringValues(inList: "inputPaths", in: shellPhase) == expectedBoundaryInputPaths,
        try pbxStringValues(inList: "outputFileListPaths", in: shellPhase).isEmpty,
        try pbxStringValues(inList: "outputPaths", in: shellPhase).isEmpty
    else {
        return [Finding(path: projectPath, line: 1, message: "The offline boundary phase was altered or disabled")]
    }

    guard
        try pbxIDs(inList: "dependencies", in: appTarget).isEmpty,
        try pbxIDs(inList: "buildRules", in: appTarget).isEmpty,
        try pbxIDs(inList: "files", in: appFrameworkPhase).isEmpty
    else {
        return [
            Finding(
                path: projectPath,
                line: 1,
                message: "App dependencies, custom build rules, and linked frameworks are forbidden"
            )
        ]
    }

    let testPhaseIDs = try pbxIDs(inList: "buildPhases", in: testTarget)
    let testSourcePhaseIDs = phaseIDs(ofType: "PBXSourcesBuildPhase", in: testPhaseIDs)
    let testFrameworkPhaseIDs = phaseIDs(ofType: "PBXFrameworksBuildPhase", in: testPhaseIDs)
    let testResourcePhaseIDs = phaseIDs(ofType: "PBXResourcesBuildPhase", in: testPhaseIDs)
    guard
        testPhaseIDs.count == Set(testPhaseIDs).count,
        testPhaseIDs.count == 3,
        testSourcePhaseIDs.count == 1,
        testFrameworkPhaseIDs.count == 1,
        testResourcePhaseIDs.count == 1,
        testPhaseIDs == [
            testSourcePhaseIDs[0],
            testFrameworkPhaseIDs[0],
            testResourcePhaseIDs[0]
        ],
        let testSourcePhase = objects[testSourcePhaseIDs[0]],
        let testFrameworkPhase = objects[testFrameworkPhaseIDs[0]],
        let testResourcePhase = objects[testResourcePhaseIDs[0]],
        try pbxIDs(inList: "files", in: testFrameworkPhase).isEmpty,
        try pbxIDs(inList: "files", in: testResourcePhase).isEmpty,
        try pbxIDs(inList: "buildRules", in: testTarget).isEmpty
    else {
        return [
            Finding(
                path: projectPath,
                line: 1,
                message: "The unit-test target build topology changed outside review"
            )
        ]
    }

    func phaseRunsInNormalBuild(_ phase: String) throws -> Bool {
        let actionMask = try pbxRequiredScalar("buildActionMask", in: phase)
        let postprocessingOnly = try pbxRequiredScalar("runOnlyForDeploymentPostprocessing", in: phase)
        return actionMask == "2147483647" && postprocessingOnly == "0"
    }
    let canonicalPhases = [appSourcePhase, appFrameworkPhase, appResourcePhase, testSourcePhase, testFrameworkPhase, testResourcePhase]
    let canonicalPhasesAreEnabled = try canonicalPhases.allSatisfy { try phaseRunsInNormalBuild($0) }
    guard canonicalPhasesAreEnabled else {
        return [Finding(path: projectPath, line: 1, message: "A canonical source, framework, or resource phase was altered or disabled")]
    }


    let testDependencyIDs = try pbxIDs(inList: "dependencies", in: testTarget)
    guard
        testDependencyIDs.count == 1,
        let dependency = objects[testDependencyIDs[0]],
        isaByID[testDependencyIDs[0]] == "PBXTargetDependency",
        try pbxRequiredScalar("target", in: dependency).split(separator: " ").first.map(String.init) == appTargetID,
        let targetProxyID = try pbxRequiredScalar("targetProxy", in: dependency)
            .split(separator: " ").first.map(String.init),
        let targetProxy = objects[targetProxyID],
        isaByID[targetProxyID] == "PBXContainerItemProxy",
        try pbxRequiredScalar("containerPortal", in: targetProxy)
            .split(separator: " ").first.map(String.init) == projectEntry.key,
        try pbxRequiredScalar("proxyType", in: targetProxy) == "1",
        try pbxRequiredScalar("remoteGlobalIDString", in: targetProxy) == appTargetID
    else {
        return [
            Finding(
                path: projectPath,
                line: 1,
                message: "HippocratesTests must depend directly and only on the Hippocrates app target"
            )
        ]
    }

    var parentByChild: [String: String] = [:]
    for (groupID, object) in objects where isaByID[groupID] == "PBXGroup" {
        let childIDs = try pbxIDs(inList: "children", in: object)
        guard childIDs.count == Set(childIDs).count else {
            throw pbxParserError(19, "PBX group \(groupID) contains a child more than once")
        }
        for childID in childIDs {
            if let existingParent = parentByChild[childID] {
                throw pbxParserError(
                    20,
                    "PBX object \(childID) belongs to both \(existingParent) and \(groupID)"
                )
            }
            parentByChild[childID] = groupID
        }
    }
    guard parentByChild[mainGroupID] == nil else {
        throw pbxParserError(21, "PBXProject mainGroup cannot have a parent")
    }

    func resolvedFileURL(for fileReferenceID: String) throws -> URL {
        guard
            let fileReference = objects[fileReferenceID],
            isaByID[fileReferenceID] == "PBXFileReference"
        else {
            throw pbxParserError(22, "Build file refers to a missing or non-file PBX object")
        }

        let filePath = try pbxRequiredScalar("path", in: fileReference)
        guard try pbxRequiredScalar("sourceTree", in: fileReference) == "<group>" else {
            throw pbxParserError(23, "Compiled source and resource references must use the reviewed group tree")
        }
        guard parentByChild[fileReferenceID] != nil else {
            throw pbxParserError(24, "Compiled source or resource reference is detached from mainGroup")
        }

        var components = [filePath]
        var ancestorID = parentByChild[fileReferenceID]
        var visited: Set<String> = []
        while let groupID = ancestorID {
            guard visited.insert(groupID).inserted else {
                throw pbxParserError(25, "PBX group ancestry contains a cycle")
            }
            guard
                let group = objects[groupID],
                isaByID[groupID] == "PBXGroup",
                try pbxRequiredScalar("sourceTree", in: group) == "<group>"
            else {
                throw pbxParserError(26, "PBX group ancestry is missing or unsupported")
            }
            if let groupPath = try pbxScalar("path", in: group), groupPath.isEmpty == false {
                components.insert(groupPath, at: 0)
            }
            ancestorID = parentByChild[groupID]
        }
        guard visited.contains(mainGroupID) else {
            throw pbxParserError(27, "Compiled source or resource is outside PBXProject mainGroup")
        }

        return components.reduce(repositoryRoot.standardizedFileURL) { partialURL, component in
            partialURL.appendingPathComponent(component)
        }.standardizedFileURL
    }

    func buildFileReferenceID(_ buildFileID: String) throws -> String {
        guard
            let buildFile = objects[buildFileID],
            isaByID[buildFileID] == "PBXBuildFile"
        else {
            throw pbxParserError(28, "Source or resource phase contains a non-build-file object")
        }
        let properties = try pbxTopLevelProperties(in: buildFile)
        guard Set(properties.keys) == Set(["isa", "fileRef"]) else {
            throw pbxParserError(29, "PBXBuildFile \(buildFileID) contains unreviewed settings")
        }
        let fileReferenceID = try pbxRequiredScalar("fileRef", in: buildFile)
            .split(separator: " ").first.map(String.init) ?? ""
        guard fileReferenceID.range(of: #"^[A-Fa-f0-9]{24}$"#, options: .regularExpression) != nil else {
            throw pbxParserError(30, "PBXBuildFile \(buildFileID) has a malformed file reference")
        }
        return fileReferenceID
    }

    let standardizedRepositoryPath = repositoryRoot.standardizedFileURL.path
    let resolvedRepositoryPath = repositoryRoot.resolvingSymlinksInPath().standardizedFileURL.path
    let testSourceRoot = repositoryRoot.appendingPathComponent("HippocratesTests", isDirectory: true)
    let resourceRoot = sourceRoot.appendingPathComponent("Resources", isDirectory: true)
    for requiredRoot in [sourceRoot, testSourceRoot, resourceRoot] {
        let lexicalPath = requiredRoot.standardizedFileURL.path
        let resolvedPath = requiredRoot.resolvingSymlinksInPath().standardizedFileURL.path
        guard
            pathIsBeneath(lexicalPath, rootPath: standardizedRepositoryPath),
            pathIsBeneath(resolvedPath, rootPath: resolvedRepositoryPath)
        else {
            return [
                Finding(
                    path: requiredRoot.path,
                    line: 1,
                    message: "Required source/resource root escapes the canonical repository"
                )
            ]
        }
    }

    func targetSourceInventory(
        buildFileIDs: [String],
        allowedRoot: URL,
        targetLabel: String
    ) throws -> TargetSourceInventory {
        var findings: [Finding] = []
        let allowedLexicalPath = allowedRoot.standardizedFileURL.path
        let allowedResolvedPath = allowedRoot.resolvingSymlinksInPath().standardizedFileURL.path

        let duplicateBuildIDs = Dictionary(grouping: buildFileIDs, by: { $0 })
            .filter { $0.value.count > 1 }.keys.sorted()
        for duplicateID in duplicateBuildIDs {
            findings.append(
                Finding(
                    path: projectPath,
                    line: 1,
                    message: "\(targetLabel) repeats PBXBuildFile \(duplicateID)"
                )
            )
        }

        var lexicalPaths: [String] = []
        var resolvedPaths: [String] = []
        var physicalIdentities: [String] = []
        for buildFileID in buildFileIDs {
            let fileReferenceID: String
            do {
                fileReferenceID = try buildFileReferenceID(buildFileID)
            } catch {
                findings.append(
                    Finding(
                        path: projectPath,
                        line: 1,
                        message: "\(targetLabel) source reference is invalid: \(error.localizedDescription)"
                    )
                )
                continue
            }

            guard let fileReference = objects[fileReferenceID] else {
                findings.append(
                    Finding(path: projectPath, line: 1, message: "\(targetLabel) file reference is missing")
                )
                continue
            }
            let sourceURL: URL
            do {
                sourceURL = try resolvedFileURL(for: fileReferenceID)
            } catch {
                findings.append(
                    Finding(
                        path: projectPath,
                        line: 1,
                        message: "\(targetLabel) source reference could not be resolved: \(error.localizedDescription)"
                    )
                )
                continue
            }

            let lexicalSource = sourceURL.standardizedFileURL
            let resolvedSource = sourceURL.resolvingSymlinksInPath().standardizedFileURL
            guard pathIsBeneath(lexicalSource.path, rootPath: allowedLexicalPath) else {
                findings.append(
                    Finding(
                        path: sourceURL.path,
                        line: 1,
                        message: "\(targetLabel) source must live lexically beneath \(allowedRoot.lastPathComponent)/"
                    )
                )
                continue
            }
            guard pathIsBeneath(resolvedSource.path, rootPath: allowedResolvedPath) else {
                findings.append(
                    Finding(
                        path: sourceURL.path,
                        line: 1,
                        message: "\(targetLabel) source symlink escapes \(allowedRoot.lastPathComponent)/"
                    )
                )
                continue
            }

            guard
                lexicalSource.pathExtension.lowercased() == "swift",
                try pbxRequiredScalar("lastKnownFileType", in: fileReference) == "sourcecode.swift",
                try pbxScalar("explicitFileType", in: fileReference) == nil
            else {
                findings.append(
                    Finding(
                        path: sourceURL.path,
                        line: 1,
                        message: "Only PBX-declared Swift source may be compiled into the \(targetLabel)"
                    )
                )
                continue
            }

            lexicalPaths.append(lexicalSource.path)
            resolvedPaths.append(resolvedSource.path)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: lexicalSource.path, isDirectory: &isDirectory) == false {
                findings.append(
                    Finding(path: sourceURL.path, line: 1, message: "\(targetLabel) source file is missing")
                )
            } else if isDirectory.boolValue {
                findings.append(
                    Finding(path: sourceURL.path, line: 1, message: "\(targetLabel) source is not a regular file")
                )
            } else if try isRegularNonSymlinkFile(lexicalSource, beneath: allowedRoot) == false {
                findings.append(
                    Finding(
                        path: sourceURL.path,
                        line: 1,
                        message: "\(targetLabel) source must be a regular, non-symbolic-link file"
                    )
                )
            } else {
                physicalIdentities.append(try physicalFileIdentity(at: lexicalSource.path))
            }
        }

        for duplicatePath in Dictionary(grouping: lexicalPaths, by: { $0 })
            .filter({ $0.value.count > 1 }).keys.sorted() {
            findings.append(
                Finding(
                    path: duplicatePath,
                    line: 1,
                    message: "\(targetLabel) compiles one lexical source path more than once"
                )
            )
        }
        for duplicatePath in Dictionary(grouping: resolvedPaths, by: { $0 })
            .filter({ $0.value.count > 1 }).keys.sorted() {
            findings.append(
                Finding(
                    path: duplicatePath,
                    line: 1,
                    message: "\(targetLabel) compiles one canonical source more than once"
                )
            )
        }
        for duplicateIdentity in Dictionary(grouping: physicalIdentities, by: { $0 })
            .filter({ $0.value.count > 1 }).keys.sorted() {
            findings.append(
                Finding(
                    path: projectPath,
                    line: 1,
                    message: "\(targetLabel) compiles multiple paths to one physical source (\(duplicateIdentity))"
                )
            )
        }

        let diskInventory = try filesystemInventory(under: allowedRoot)
        let diskFiles = diskInventory.regularFiles.filter {
            $0.pathExtension.lowercased() == "swift"
        }
        for symbolicLink in diskInventory.symbolicLinks
        where symbolicLink.pathExtension.lowercased() == "swift" {
            findings.append(
                Finding(
                    path: symbolicLink.path,
                    line: 1,
                    message: "\(targetLabel) on-disk Swift source must be a regular file; symbolic links are forbidden"
                )
            )
        }
        var diskResolvedPaths: [String] = []
        var diskPhysicalIdentities: [String] = []
        for diskFile in diskFiles {
            let resolvedDiskFile = diskFile.resolvingSymlinksInPath().standardizedFileURL
            if pathIsBeneath(resolvedDiskFile.path, rootPath: allowedResolvedPath) == false {
                findings.append(
                    Finding(
                        path: diskFile.path,
                        line: 1,
                        message: "\(targetLabel) on-disk Swift symlink escapes \(allowedRoot.lastPathComponent)/"
                    )
                )
            }
            diskResolvedPaths.append(resolvedDiskFile.path)
            diskPhysicalIdentities.append(try physicalFileIdentity(at: diskFile.path))
        }
        for duplicatePath in Dictionary(grouping: diskResolvedPaths, by: { $0 })
            .filter({ $0.value.count > 1 }).keys.sorted() {
            findings.append(
                Finding(
                    path: duplicatePath,
                    line: 1,
                    message: "\(targetLabel) has multiple on-disk paths to one canonical Swift source"
                )
            )
        }
        for duplicateIdentity in Dictionary(grouping: diskPhysicalIdentities, by: { $0 })
            .filter({ $0.value.count > 1 }).keys.sorted() {
            findings.append(
                Finding(
                    path: allowedRoot.path,
                    line: 1,
                    message: "\(targetLabel) has multiple on-disk names for one physical Swift source (\(duplicateIdentity))"
                )
            )
        }

        let diskLexicalSet = Set(diskFiles.map { $0.standardizedFileURL.path })
        let compiledLexicalSet = Set(lexicalPaths)
        for missingPath in diskLexicalSet.subtracting(compiledLexicalSet).sorted() {
            findings.append(
                Finding(
                    path: missingPath,
                    line: 1,
                    message: "\(targetLabel) Swift source exists on disk but is missing from target Sources"
                )
            )
        }
        for extraPath in compiledLexicalSet.subtracting(diskLexicalSet).sorted() {
            findings.append(
                Finding(
                    path: extraPath,
                    line: 1,
                    message: "\(targetLabel) Sources references no matching on-disk Swift file"
                )
            )
        }

        return TargetSourceInventory(
            lexicalPaths: lexicalPaths,
            resolvedPaths: resolvedPaths,
            findings: findings,
            physicalIdentities: physicalIdentities
        )
    }

    let appBuildFileIDs = try pbxIDs(inList: "files", in: appSourcePhase)
    let testBuildFileIDs = try pbxIDs(inList: "files", in: testSourcePhase)
    guard appBuildFileIDs.isEmpty == false, testBuildFileIDs.isEmpty == false else {
        return [Finding(path: projectPath, line: 1, message: "App and test targets must each compile source")]
    }

    let appInventory = try targetSourceInventory(
        buildFileIDs: appBuildFileIDs,
        allowedRoot: sourceRoot,
        targetLabel: "App-target"
    )
    let testInventory = try targetSourceInventory(
        buildFileIDs: testBuildFileIDs,
        allowedRoot: testSourceRoot,
        targetLabel: "Unit-test target"
    )
    var findings = appInventory.findings + testInventory.findings
    for overlappingPath in Set(appInventory.resolvedPaths)
        .intersection(Set(testInventory.resolvedPaths)).sorted() {
        findings.append(
            Finding(
                path: overlappingPath,
                line: 1,
                message: "App and unit-test targets may not compile the same canonical Swift source"
            )
        )
    }
    for overlappingIdentity in Set(appInventory.physicalIdentities)
        .intersection(Set(testInventory.physicalIdentities)).sorted() {
        findings.append(
            Finding(
                path: projectPath,
                line: 1,
                message: "App and unit-test targets may not compile one physical source (\(overlappingIdentity))"
            )
        )
    }

    let resourceBuildFileIDs = try pbxIDs(inList: "files", in: appResourcePhase)
    if resourceBuildFileIDs.count != 1 || Set(resourceBuildFileIDs).count != 1 {
        findings.append(
            Finding(
                path: projectPath,
                line: 1,
                message: "App resources must contain exactly one reviewed privacy manifest"
            )
        )
    }

    var compiledResourcePaths: [String] = []
    for buildFileID in resourceBuildFileIDs {
        let fileReferenceID: String
        do {
            fileReferenceID = try buildFileReferenceID(buildFileID)
        } catch {
            findings.append(
                Finding(path: projectPath, line: 1, message: "App resource reference is invalid: \(error.localizedDescription)")
            )
            continue
        }
        guard let fileReference = objects[fileReferenceID] else {
            findings.append(Finding(path: projectPath, line: 1, message: "App resource file reference is missing"))
            continue
        }
        let resourceURL: URL
        do {
            resourceURL = try resolvedFileURL(for: fileReferenceID)
        } catch {
            findings.append(
                Finding(path: projectPath, line: 1, message: "App resource could not be resolved: \(error.localizedDescription)")
            )
            continue
        }
        let lexicalResource = resourceURL.standardizedFileURL
        let resolvedResource = resourceURL.resolvingSymlinksInPath().standardizedFileURL
        let resourceRootLexicalPath = resourceRoot.standardizedFileURL.path
        let resourceRootResolvedPath = resourceRoot.resolvingSymlinksInPath().standardizedFileURL.path
        guard
            pathIsBeneath(lexicalResource.path, rootPath: resourceRootLexicalPath),
            pathIsBeneath(resolvedResource.path, rootPath: resourceRootResolvedPath),
            lexicalResource.pathExtension.lowercased() == "xcprivacy",
            try pbxRequiredScalar("lastKnownFileType", in: fileReference) == "text.xml",
            try pbxScalar("explicitFileType", in: fileReference) == nil
        else {
            findings.append(
                Finding(
                    path: resourceURL.path,
                    line: 1,
                    message: "App resource must be the PBX-declared privacy manifest beneath Resources/"
                )
            )
            continue
        }

        compiledResourcePaths.append(lexicalResource.path)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: lexicalResource.path, isDirectory: &isDirectory) == false
            || isDirectory.boolValue {
            findings.append(Finding(path: resourceURL.path, line: 1, message: "Privacy manifest resource is missing"))
        } else if try isRegularNonSymlinkFile(lexicalResource, beneath: resourceRoot) == false {
            findings.append(
                Finding(
                    path: resourceURL.path,
                    line: 1,
                    message: "Privacy manifest must be a regular, non-symbolic-link file"
                )
            )
        }
    }

    let expectedManifestPath = resourceRoot.appendingPathComponent("PrivacyInfo.xcprivacy")
        .standardizedFileURL.path
    let diskResourceInventory = try filesystemInventory(under: resourceRoot)
    let diskResourcePaths = Set(
        diskResourceInventory.regularFiles.map { $0.standardizedFileURL.path }
    )
    let compiledResourceSet = Set(compiledResourcePaths)
    for symbolicLink in diskResourceInventory.symbolicLinks {
        findings.append(
            Finding(
                path: symbolicLink.path,
                line: 1,
                message: "Unreviewed symbolic link exists beneath Hippocrates/Resources"
            )
        )
    }
    if diskResourcePaths != Set([expectedManifestPath]) {
        for path in diskResourcePaths.subtracting(Set([expectedManifestPath])).sorted() {
            findings.append(
                Finding(path: path, line: 1, message: "Unreviewed file exists beneath Hippocrates/Resources")
            )
        }
        if diskResourcePaths.contains(expectedManifestPath) == false {
            findings.append(
                Finding(path: expectedManifestPath, line: 1, message: "Reviewed privacy manifest is missing from disk")
            )
        }
    }
    if compiledResourceSet != Set([expectedManifestPath]) {
        findings.append(
            Finding(
                path: projectPath,
                line: 1,
                message: "App resource phase must compile exactly PrivacyInfo.xcprivacy"
            )
        )
    }

    return findings
}

private enum SchemeXMLEvent: Equatable {
    case start(String, [String: String])
    case end(String)
}

private final class StrictSchemeXMLDelegate: NSObject, XMLParserDelegate {
    private let expectedEvents: [SchemeXMLEvent]
    private(set) var eventIndex = 0
    private(set) var failure: String?

    init(expectedEvents: [SchemeXMLEvent]) {
        self.expectedEvents = expectedEvents
    }

    private func consume(_ event: SchemeXMLEvent) {
        guard failure == nil else { return }
        guard eventIndex < expectedEvents.count, expectedEvents[eventIndex] == event else {
            failure = "Unexpected scheme XML event: \(event)"
            return
        }
        eventIndex += 1
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        consume(.start(elementName, attributeDict))
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        consume(.end(elementName))
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            failure = "Non-whitespace text is forbidden in the shared scheme"
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        failure = "CDATA is forbidden in the shared scheme"
    }

    func parser(_ parser: XMLParser, foundComment comment: String) {
        failure = "Comments are forbidden in the shared scheme"
    }

    func parser(
        _ parser: XMLParser,
        foundProcessingInstructionWithTarget target: String,
        data: String?
    ) {
        failure = "Processing instructions are forbidden in the shared scheme"
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        if failure == nil {
            failure = parseError.localizedDescription
        }
    }

    func parser(_ parser: XMLParser, validationErrorOccurred validationError: Error) {
        if failure == nil {
            failure = validationError.localizedDescription
        }
    }

    var consumedEveryExpectedEvent: Bool {
        failure == nil && eventIndex == expectedEvents.count
    }
}

private func strictXMLMatches(_ text: String, expectedEvents: [SchemeXMLEvent]) -> Bool {
    let declaration = #"<?xml version="1.0" encoding="UTF-8"?>"#
    let documentBody = text.dropFirst(declaration.count)
    guard
        text.hasPrefix(declaration),
        documentBody.contains("<?") == false,
        documentBody.contains("<!") == false,
        text.contains("&") == false,
        let data = text.data(using: .utf8)
    else {
        return false
    }

    let delegate = StrictSchemeXMLDelegate(expectedEvents: expectedEvents)
    let parser = XMLParser(data: data)
    parser.shouldProcessNamespaces = false
    parser.shouldReportNamespacePrefixes = false
    parser.shouldResolveExternalEntities = false
    parser.delegate = delegate
    return parser.parse() && delegate.consumedEveryExpectedEvent
}

private func schemePolicyFindings(
    projectText: String,
    schemeText: String,
    path: String
) throws -> [Finding] {
    let objects = try pbxObjects(in: projectText).mapValues(pbxWithoutComments)
    var isaByID: [String: String] = [:]
    for (identifier, object) in objects {
        isaByID[identifier] = try pbxISA(in: object)
    }
    let nativeTargets = objects.filter { isaByID[$0.key] == "PBXNativeTarget" }
    let applicationTargets = try nativeTargets.filter {
        try pbxRequiredScalar("productType", in: $0.value) == "com.apple.product-type.application"
    }
    let unitTestTargets = try nativeTargets.filter {
        try pbxRequiredScalar("productType", in: $0.value) == "com.apple.product-type.bundle.unit-test"
    }
    guard
        applicationTargets.count == 1,
        unitTestTargets.count == 1,
        let appTargetID = applicationTargets.first?.key,
        let testTargetID = unitTestTargets.first?.key
    else {
        return [
            Finding(
                path: path,
                line: 1,
                message: "The shared scheme cannot resolve the reviewed app and test targets"
            )
        ]
    }

    func referenceEvents(
        identifier: String,
        buildableName: String,
        blueprintName: String
    ) -> [SchemeXMLEvent] {
        [
            .start(
                "BuildableReference",
                [
                    "BuildableIdentifier": "primary",
                    "BlueprintIdentifier": identifier,
                    "BuildableName": buildableName,
                    "BlueprintName": blueprintName,
                    "ReferencedContainer": "container:Hippocrates.xcodeproj"
                ]
            ),
            .end("BuildableReference")
        ]
    }

    var expectedEvents: [SchemeXMLEvent] = [
        .start("Scheme", ["LastUpgradeVersion": "1600", "version": "1.7"]),
        .start(
            "BuildAction",
            [
                "parallelizeBuildables": "YES",
                "buildImplicitDependencies": "YES",
                "buildArchitectures": "Automatic"
            ]
        ),
        .start("BuildActionEntries", [:]),
        .start(
            "BuildActionEntry",
            [
                "buildForTesting": "YES",
                "buildForRunning": "YES",
                "buildForProfiling": "YES",
                "buildForArchiving": "YES",
                "buildForAnalyzing": "YES"
            ]
        )
    ]
    expectedEvents.append(
        contentsOf: referenceEvents(
            identifier: appTargetID,
            buildableName: "Hippocrates.app",
            blueprintName: "Hippocrates"
        )
    )
    expectedEvents.append(.end("BuildActionEntry"))
    expectedEvents.append(
        .start(
            "BuildActionEntry",
            [
                "buildForTesting": "YES",
                "buildForRunning": "NO",
                "buildForProfiling": "NO",
                "buildForArchiving": "NO",
                "buildForAnalyzing": "YES"
            ]
        )
    )
    expectedEvents.append(
        contentsOf: referenceEvents(
            identifier: testTargetID,
            buildableName: "HippocratesTests.xctest",
            blueprintName: "HippocratesTests"
        )
    )
    expectedEvents.append(contentsOf: [
        .end("BuildActionEntry"),
        .end("BuildActionEntries"),
        .end("BuildAction"),
        .start(
            "TestAction",
            [
                "buildConfiguration": "Debug",
                "selectedDebuggerIdentifier": "Xcode.DebuggerFoundation.Debugger.LLDB",
                "selectedLauncherIdentifier": "Xcode.DebuggerFoundation.Launcher.LLDB",
                "shouldUseLaunchSchemeArgsEnv": "YES",
                "shouldAutocreateTestPlan": "YES"
            ]
        ),
        .start("Testables", [:]),
        .start("TestableReference", ["skipped": "NO", "parallelizable": "NO"])
    ])
    expectedEvents.append(
        contentsOf: referenceEvents(
            identifier: testTargetID,
            buildableName: "HippocratesTests.xctest",
            blueprintName: "HippocratesTests"
        )
    )
    expectedEvents.append(contentsOf: [
        .end("TestableReference"),
        .end("Testables"),
        .end("TestAction"),
        .start(
            "LaunchAction",
            [
                "buildConfiguration": "Debug",
                "selectedDebuggerIdentifier": "Xcode.DebuggerFoundation.Debugger.LLDB",
                "selectedLauncherIdentifier": "Xcode.DebuggerFoundation.Launcher.LLDB",
                "launchStyle": "0",
                "useCustomWorkingDirectory": "NO",
                "ignoresPersistentStateOnLaunch": "NO",
                "debugDocumentVersioning": "YES",
                "debugServiceExtension": "internal",
                "allowLocationSimulation": "YES"
            ]
        ),
        .start("BuildableProductRunnable", ["runnableDebuggingMode": "0"])
    ])
    expectedEvents.append(
        contentsOf: referenceEvents(
            identifier: appTargetID,
            buildableName: "Hippocrates.app",
            blueprintName: "Hippocrates"
        )
    )
    expectedEvents.append(contentsOf: [
        .end("BuildableProductRunnable"),
        .end("LaunchAction"),
        .start(
            "ProfileAction",
            [
                "buildConfiguration": "Release",
                "shouldUseLaunchSchemeArgsEnv": "YES",
                "savedToolIdentifier": "",
                "useCustomWorkingDirectory": "NO",
                "debugDocumentVersioning": "YES"
            ]
        ),
        .start("BuildableProductRunnable", ["runnableDebuggingMode": "0"])
    ])
    expectedEvents.append(
        contentsOf: referenceEvents(
            identifier: appTargetID,
            buildableName: "Hippocrates.app",
            blueprintName: "Hippocrates"
        )
    )
    expectedEvents.append(contentsOf: [
        .end("BuildableProductRunnable"),
        .end("ProfileAction"),
        .start("AnalyzeAction", ["buildConfiguration": "Debug"]),
        .end("AnalyzeAction"),
        .start(
            "ArchiveAction",
            ["buildConfiguration": "Release", "revealArchiveInOrganizer": "YES"]
        ),
        .end("ArchiveAction"),
        .end("Scheme")
    ])

    guard strictXMLMatches(schemeText, expectedEvents: expectedEvents) else {
        return [
            Finding(
                path: path,
                line: 1,
                message: "The shared scheme no longer matches the exact reviewed execution tree"
            )
        ]
    }
    return []
}


private enum RepositoryInspectionMode {
    case direct
    case sandboxedXcode
}

private func repositoryFindings(
    at repositoryRoot: URL,
    mode: RepositoryInspectionMode
) throws -> [Finding] {
    let sourceRoot = repositoryRoot.appendingPathComponent("Hippocrates", isDirectory: true)
    let projectFile = repositoryRoot
        .appendingPathComponent("Hippocrates.xcodeproj", isDirectory: true)
        .appendingPathComponent("project.pbxproj")

    guard FileManager.default.fileExists(atPath: sourceRoot.path) else {
        return [Finding(path: sourceRoot.path, line: 1, message: "Shipping source directory is missing")]
    }

    var results: [Finding] = []
    let resourceRoot = sourceRoot.appendingPathComponent("Resources", isDirectory: true)
    let privacyManifest = resourceRoot.appendingPathComponent("PrivacyInfo.xcprivacy")
    results.append(
        contentsOf: try privacyManifestFileFindings(at: privacyManifest, beneath: resourceRoot)
    )

    let boundaryScanner = repositoryRoot
        .appendingPathComponent("Scripts", isDirectory: true)
        .appendingPathComponent("NetworkBoundaryScanner.swift")
    if FileManager.default.fileExists(atPath: boundaryScanner.path) == false {
        results.append(
            Finding(path: boundaryScanner.path, line: 1, message: "Offline boundary scanner is missing")
        )
    } else if try isRegularNonSymlinkFile(boundaryScanner, beneath: repositoryRoot) == false {
        results.append(
            Finding(
                path: boundaryScanner.path,
                line: 1,
                message: "Offline boundary scanner must be an in-repository regular file"
            )
        )
    }

    for file in try swiftFiles(under: sourceRoot) {
        let source = try String(contentsOf: file, encoding: .utf8)
        let identity = reviewedSourceIdentity(for: file, repositoryRoot: repositoryRoot)
        results.append(contentsOf: try appSourceFindings(in: source, path: file.path, identity: identity))
        results.append(contentsOf: try interpolationArchitectureFindings(in: source, path: file.path, identity: identity))
        results.append(contentsOf: try architectureSemanticFindings(in: source, path: file.path, identity: identity))
        results.append(contentsOf: try appConfigOwnershipFindings(in: source, path: file.path, identity: identity))
        results.append(contentsOf: try persistentModelBackingFindings(in: source, path: file.path))
        results.append(
            contentsOf: try importFindings(
                in: source,
                path: file.path,
                allowedModules: shippingAllowedImports
            )
        )

        let visibleSource = sourceForStructure(source)
        let clinicalTypePattern =
            #"\b(class|struct|enum|protocol)\s+[A-Za-z0-9_]*(Calculator|DoseRecommendation|PhysiologicUnit)[A-Za-z0-9_]*\b"#
        let clinicalTypeExpression = try NSRegularExpression(pattern: clinicalTypePattern)
        let visibleRange = NSRange(visibleSource.startIndex..<visibleSource.endIndex, in: visibleSource)
        if let match = clinicalTypeExpression.firstMatch(in: visibleSource, range: visibleRange) {
            results.append(
                Finding(
                    path: file.path,
                    line: lineNumber(in: visibleSource, at: match.range.location),
                    message: "Clinical calculation types are permanently outside Hippocrates"
                )
            )
        }
    }

    // Tests may use local filesystem URL values and one inert citation fixture at
    // example.invalid. Network-capable loaders, streams, APIs, UI, imports, and all
    // other external address literals remain forbidden.
    let testRoot = repositoryRoot.appendingPathComponent("HippocratesTests", isDirectory: true)
    for file in try swiftFiles(under: testRoot) {
        let source = try String(contentsOf: file, encoding: .utf8)
        let identity = reviewedSourceIdentity(for: file, repositoryRoot: repositoryRoot)
        results.append(contentsOf: try testFindings(in: source, path: file.path, identity: identity))
        results.append(contentsOf: try interpolationArchitectureFindings(in: source, path: file.path, identity: identity))
        results.append(contentsOf: try testPersistenceBoundaryFindings(in: source, path: file.path, identity: identity))
        results.append(contentsOf: try appConfigOwnershipFindings(in: source, path: file.path, identity: identity))
        results.append(contentsOf: try persistentModelBackingFindings(in: source, path: file.path))
        results.append(
            contentsOf: try importFindings(
                in: source,
                path: file.path,
                allowedModules: testAllowedImports
            )
        )
    }

    let schemaContractFile = testRoot.appendingPathComponent("SchemaContractTests.swift")
    if FileManager.default.fileExists(atPath: schemaContractFile.path) == false {
        results.append(
            Finding(path: schemaContractFile.path, line: 1, message: "Schema contract test source is missing")
        )
    }

    let schemaFile = sourceRoot
        .appendingPathComponent("Persistence", isDirectory: true)
        .appendingPathComponent("SchemaV1.swift")
    if FileManager.default.fileExists(atPath: schemaFile.path) {
        let schemaSource = try String(contentsOf: schemaFile, encoding: .utf8)
        results.append(contentsOf: try interventionArchitectureFindings(in: schemaSource, path: schemaFile.path))
    } else {
        results.append(Finding(path: schemaFile.path, line: 1, message: "Versioned schema source is missing"))
    }

    let backupArchiveFile = sourceRoot
        .appendingPathComponent("Backup", isDirectory: true)
        .appendingPathComponent("BackupArchive.swift")
    if FileManager.default.fileExists(atPath: backupArchiveFile.path) == false {
        results.append(
            Finding(path: backupArchiveFile.path, line: 1, message: "Versioned backup archive source is missing")
        )
    } else if FileManager.default.fileExists(atPath: schemaFile.path) {
        let schemaSource = try String(contentsOf: schemaFile, encoding: .utf8)
        let archiveSource = try String(contentsOf: backupArchiveFile, encoding: .utf8)
        results.append(
            contentsOf: try backupParityFindings(
                schemaSource: schemaSource,
                archiveSource: archiveSource,
                schemaPath: schemaFile.path,
                archivePath: backupArchiveFile.path
            )
        )
    }

    let backupCodecFile = sourceRoot
        .appendingPathComponent("Backup", isDirectory: true)
        .appendingPathComponent("BackupCodec.swift")
    if FileManager.default.fileExists(atPath: backupCodecFile.path) {
        let codecSource = try String(contentsOf: backupCodecFile, encoding: .utf8)
        results.append(
            contentsOf: try immutableBackupV1Findings(
                in: codecSource,
                path: backupCodecFile.path
            )
        )
    } else {
        results.append(
            Finding(path: backupCodecFile.path, line: 1, message: "Versioned backup codec source is missing")
        )
    }

    let storeFile = sourceRoot
        .appendingPathComponent("Persistence", isDirectory: true)
        .appendingPathComponent("HippocratesStore.swift")
    if FileManager.default.fileExists(atPath: storeFile.path) {
        let storeSource = try String(contentsOf: storeFile, encoding: .utf8)
        results.append(contentsOf: try storeArchitectureFindings(in: storeSource, path: storeFile.path))
    } else {
        results.append(
            Finding(path: storeFile.path, line: 1, message: "Canonical SwiftData store source is missing")
        )
    }


    guard FileManager.default.fileExists(atPath: projectFile.path) else {
        results.append(Finding(path: projectFile.path, line: 1, message: "Xcode project file is missing"))
        return results
    }

    guard try isRegularNonSymlinkFile(projectFile, beneath: repositoryRoot) else {
        results.append(
            Finding(path: projectFile.path, line: 1, message: "Xcode project must be an in-repository regular file")
        )
        return results
    }

    let projectText = try String(contentsOf: projectFile, encoding: .utf8)
    results.append(contentsOf: projectPolicyFindings(in: projectText, path: projectFile.path))
    results.append(contentsOf: buildConfigurationFindings(projectText: projectText, path: projectFile.path))
    results.append(
        contentsOf: try appTargetSourceFindings(
            projectText: projectText,
            projectPath: projectFile.path,
            repositoryRoot: repositoryRoot,
            sourceRoot: sourceRoot
        )
    )

    let schemeDirectory = repositoryRoot
        .appendingPathComponent("Hippocrates.xcodeproj", isDirectory: true)
        .appendingPathComponent("xcshareddata", isDirectory: true)
        .appendingPathComponent("xcschemes", isDirectory: true)
    let expectedScheme = schemeDirectory.appendingPathComponent("Hippocrates.xcscheme")
    let projectBundle = repositoryRoot.appendingPathComponent("Hippocrates.xcodeproj", isDirectory: true)
    if case .direct = mode {
        // Xcode creates project.xcworkspace during build planning. The build
        // sandbox does not grant recursive access to that generated directory,
        // so the clean checkout's whole-bundle inventory belongs to the direct
        // pre-Xcode scan. The sandboxed phase still validates the declared PBX
        // file, shared-scheme directory and file, sources, tests, and resources.
        let projectBundleInventory = try filesystemInventory(under: projectBundle)
        let schemeControlPaths = Set(
            (projectBundleInventory.regularFiles + projectBundleInventory.symbolicLinks)
                .filter { file in
                    file.pathExtension.lowercased() == "xcscheme"
                        || file.lastPathComponent == "xcschememanagement.plist"
                }
                .map { $0.standardizedFileURL.path }
        )
        if schemeControlPaths != Set([expectedScheme.standardizedFileURL.path])
            || projectBundleInventory.symbolicLinks.isEmpty == false {
            results.append(
                Finding(
                    path: projectBundle.path,
                    line: 1,
                    message: "Only the one reviewed shared scheme and no symbolic links may exist anywhere in the Xcode project bundle"
                )
            )
        }
    }

    var schemeDirectoryIsDirectory: ObjCBool = false
    if FileManager.default.fileExists(
        atPath: schemeDirectory.path,
        isDirectory: &schemeDirectoryIsDirectory
    ) == false || schemeDirectoryIsDirectory.boolValue == false {
        results.append(
            Finding(path: schemeDirectory.path, line: 1, message: "The shared Xcode scheme directory is missing")
        )
    } else {
        let schemeEntries = try FileManager.default.contentsOfDirectory(atPath: schemeDirectory.path)
        if Set(schemeEntries) != Set(["Hippocrates.xcscheme"]) {
            results.append(
                Finding(path: schemeDirectory.path, line: 1, message: "Exactly one reviewed shared Xcode scheme is allowed")
            )
        }
        if FileManager.default.fileExists(atPath: expectedScheme.path) {
            let values = try expectedScheme.resourceValues(forKeys: [.isRegularFileKey])
            let resolvedScheme = expectedScheme.resolvingSymlinksInPath().standardizedFileURL
            let projectRoot = repositoryRoot
                .appendingPathComponent("Hippocrates.xcodeproj", isDirectory: true)
                .resolvingSymlinksInPath().standardizedFileURL
            if values.isRegularFile != true
                || fileIsSymbolicLink(expectedScheme)
                || pathIsBeneath(resolvedScheme.path, rootPath: projectRoot.path) == false {
                results.append(
                    Finding(path: expectedScheme.path, line: 1, message: "The shared Xcode scheme must be one in-project regular file")
                )
            } else {
                let schemeText = try String(contentsOf: expectedScheme, encoding: .utf8)
                results.append(
                    contentsOf: try schemePolicyFindings(
                        projectText: projectText,
                        schemeText: schemeText,
                        path: expectedScheme.path
                    )
                )
            }
        }
    }


    // Actual Xcode package references are rejected above. Checking the root
    // names as well catches the ordinary Package.swift/Package.resolved entry
    // points without granting this build script recursive access to unrelated
    // repository files.
    let repositoryEntries = try FileManager.default.contentsOfDirectory(
        atPath: repositoryRoot.path
    )
    for forbiddenName in ["Package.swift", "Package.resolved"]
    where repositoryEntries.contains(forbiddenName) {
        let forbiddenFile = repositoryRoot.appendingPathComponent(forbiddenName)
            results.append(
                Finding(
                    path: forbiddenFile.path,
                    line: 1,
                    message: "Swift Package files are forbidden; the project has zero SPM dependencies"
                )
            )
    }
    return results
}

private func runSelfTests() throws {
    struct Case {
        let name: String
        let source: String
        let expectedFindingCount: Int
    }

    var completedChecks = 0
    func check(_ condition: Bool, _ message: String) throws {
        completedChecks += 1
        guard condition else {
            throw NSError(
                domain: "NetworkBoundaryScannerTests",
                code: completedChecks,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }

    func throwsError(_ operation: () throws -> Void) -> Bool {
        do {
            try operation()
            return false
        } catch {
            return true
        }
    }

    func replacingFirst(_ source: String, _ target: String, _ replacement: String) -> String {
        guard let range = source.range(of: target) else { return source }
        var result = source
        result.replaceSubrange(range, with: replacement)
        return result
    }

    let cases = [
        Case(name: "live URLSession", source: "let client = URLSession.shared", expectedFindingCount: 1),
        Case(name: "live NSURLConnection", source: "let client: NSURLConnection", expectedFindingCount: 1),
        Case(name: "live NWConnection", source: "let client: NWConnection", expectedFindingCount: 1),
        Case(name: "live CFSocket", source: "let handle: CFSocket", expectedFindingCount: 1),
        Case(name: "live WKWebView", source: "let browser = WKWebView()", expectedFindingCount: 1),
        Case(name: "live SFSafariViewController", source: "let browser: SFSafariViewController", expectedFindingCount: 1),
        Case(name: "live URLRequest", source: "let request: URLRequest", expectedFindingCount: 1),
        Case(name: "live openURL", source: "let action: OpenURLAction", expectedFindingCount: 1),
        Case(name: "SwiftUI onOpenURL", source: "content.onOpenURL { destination in handle(destination) }", expectedFindingCount: 1),
        Case(name: "external event scene", source: "scene.handlesExternalEvents(matching: identifiers)", expectedFindingCount: 1),
        Case(name: "live Link", source: "let view = Link(\"Source\", destination: value)", expectedFindingCount: 1),
        Case(name: "any ShareLink", source: "let view = ShareLink(item: document)", expectedFindingCount: 1),
        Case(name: "aliased UIApplication", source: "let app = UIApplication.shared; app.open(value)", expectedFindingCount: 1),
        Case(name: "URLComponents", source: "var pieces = URLComponents()", expectedFindingCount: 1),
        Case(name: "Foundation URL value", source: "let destination: URL", expectedFindingCount: 1),
        Case(name: "Foundation URL loader", source: "let data = Data(contentsOf: value)", expectedFindingCount: 1),
        Case(name: "NSArray URL loader", source: "let values = NSArray(contentsOf: file)", expectedFindingCount: 1),
        Case(name: "NSDictionary URL loader", source: "let values = NSDictionary(contentsOf: file)", expectedFindingCount: 1),
        Case(name: "contextual attributed-string URL loader", source: "let value: Foundation.NSAttributedString? = try? .init(url: file, options: [:], documentAttributes: nil)", expectedFindingCount: 1),
        Case(name: "URL-backed stream", source: "let stream = InputStream(url: value)", expectedFindingCount: 1),
        Case(name: "path-backed input stream", source: "let stream = InputStream(fileAtPath: path)", expectedFindingCount: 1),
        Case(name: "explicit path-backed stream initializer", source: "let stream = InputStream.init(fileAtPath: path)", expectedFindingCount: 1),
        Case(name: "contextual path-backed stream initializer", source: "let stream: InputStream? = .init(fileAtPath: path)", expectedFindingCount: 1),
        Case(name: "contextual URL-backed input stream initializer", source: "let stream: InputStream? = .init(url: file)", expectedFindingCount: 1),
        Case(name: "contextual URL-backed output stream initializer", source: "let stream: Foundation.OutputStream! = try? .init(url: file, append: false)", expectedFindingCount: 1),
        Case(name: "fail-closed contextual URL initializer", source: "let value: ReviewedValue = .init(url: file)", expectedFindingCount: 1),
        Case(name: "contextual URL initializer in inferred return", source: "func make() -> InputStream? { .init(url: file) }", expectedFindingCount: 1),
        Case(name: "contextual URL initializer in multi-binding", source: "let marker = 0, stream: InputStream? = .init(url: file)", expectedFindingCount: 1),
        Case(name: "SwiftUI file importer", source: "content.fileImporter(isPresented: flag, allowedContentTypes: []) { _ in }", expectedFindingCount: 1),
        Case(name: "SwiftUI file exporter", source: "content.fileExporter(isPresented: flag, document: document, contentType: type) { _ in }", expectedFindingCount: 1),
        Case(name: "SwiftUI file mover", source: "content.fileMover(isPresented: flag, file: file) { _ in }", expectedFindingCount: 1),
        Case(name: "document group scene", source: "DocumentGroup(newDocument: document) { _ in content }", expectedFindingCount: 1),
        Case(name: "document group launch scene", source: "DocumentGroupLaunchScene { content }", expectedFindingCount: 1),
        Case(name: "document launch view", source: "DocumentLaunchView()", expectedFindingCount: 1),
        Case(name: "document browser context menu", source: "content.documentBrowserContextMenu { _ in menu }", expectedFindingCount: 1),
        Case(name: "UIKit document picker", source: "let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)", expectedFindingCount: 1),
        Case(name: "UIKit document browser", source: "let browser = UIDocumentBrowserViewController(forOpening: types)", expectedFindingCount: 1),
        Case(name: "UIKit document interaction", source: "let controller = UIDocumentInteractionController()", expectedFindingCount: 1),
        Case(name: "SwiftUI onDrop", source: "content.onDrop(of: types, isTargeted: flag) { _ in true }", expectedFindingCount: 1),
        Case(name: "SwiftUI drop destination", source: "content.dropDestination(for: Payload.self) { _, _ in true }", expectedFindingCount: 1),
        Case(name: "SwiftUI paste destination", source: "content.pasteDestination(for: Payload.self) { _ in }", expectedFindingCount: 1),
        Case(name: "item provider", source: "let provider = NSItemProvider()", expectedFindingCount: 1),
        Case(name: "file representation load", source: "provider.loadFileRepresentation(forTypeIdentifier: type) { _, _ in }", expectedFindingCount: 1),
        Case(name: "data representation load", source: "provider.loadDataRepresentation(forTypeIdentifier: type) { _, _ in }", expectedFindingCount: 1),
        Case(name: "transferable load", source: "item.loadTransferable(type: Payload.self) { _ in }", expectedFindingCount: 1),
        Case(name: "paste button", source: "PasteButton(payloadType: Payload.self) { _ in }", expectedFindingCount: 1),
        Case(name: "imported transfer representation", source: "DataRepresentation(importedContentType: type) { data in payload }", expectedFindingCount: 1),
        Case(name: "paste command", source: "content.onPasteCommand(of: types) { _ in }", expectedFindingCount: 1),
        Case(name: "continued user activity", source: "content.onContinueUserActivity(activityType) { _ in }", expectedFindingCount: 1),
        Case(name: "Foundation user activity", source: "let activity = NSUserActivity(activityType: type)", expectedFindingCount: 1),
        Case(name: "security-scoped access", source: "file.startAccessingSecurityScopedResource()", expectedFindingCount: 1),
        Case(name: "Core Foundation security-scoped access", source: "CFURLStartAccessingSecurityScopedResource(file)", expectedFindingCount: 1),
        Case(name: "FileManager path read", source: "FileManager.default.contents(atPath: path)", expectedFindingCount: 1),
        Case(name: "FileManager path comparison", source: "FileManager.default.contentsEqual(atPath: first, andPath: second)", expectedFindingCount: 1),
        Case(name: "FileManager URL directory read", source: "FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)", expectedFindingCount: 1),
        Case(name: "FileManager URL enumeration", source: "FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)", expectedFindingCount: 1),
        Case(name: "aliased FileManager path read", source: "manager.contents(atPath: path)", expectedFindingCount: 1),
        Case(name: "inferred FileHandle read", source: "FileHandle(forReadingFrom: file)", expectedFindingCount: 1),
        Case(name: "FileWrapper URL read", source: "let wrapper = try FileWrapper(url: file)", expectedFindingCount: 1),
        Case(name: "contextual FileWrapper URL read", source: "let wrapper: FileWrapper = try .init(url: file)", expectedFindingCount: 1),
        Case(name: "aliased FileWrapper read", source: "try wrapper.read(from: file, options: [])", expectedFindingCount: 1),
        Case(name: "keyed archive path read", source: "NSKeyedUnarchiver.unarchiveObject(withFile: path)", expectedFindingCount: 1),
        Case(name: "contextual path loader", source: "let data: NSData = .init(contentsOfFile: path)", expectedFindingCount: 1),
        Case(name: "ubiquitous publishing surface", source: "manager.url(forPublishingUbiquitousItemAt: item, expiration: date)", expectedFindingCount: 1),
        Case(name: "coordinated file access", source: "let coordinator = NSFileCoordinator()", expectedFindingCount: 1),
        Case(name: "host-backed stream", source: "Stream.getStreamsToHost(withName: host)", expectedFindingCount: 1),
        Case(name: "low-level socket", source: "let descriptor = socket(domain, type, protocol)", expectedFindingCount: 1),
        Case(name: "explicit Data.init loader", source: "let data = Data.init(contentsOf: value)", expectedFindingCount: 1),
        Case(name: "contextual init loader", source: "let data: Data = .init(contentsOf: value)", expectedFindingCount: 1),
        Case(name: "XML parser loader", source: "let parser = XMLParser(contentsOf: value)", expectedFindingCount: 1),
        Case(name: "CFSocket constructor", source: "let handle = CFSocketCreate(nil, 0, 0, 0, 0, nil, nil)", expectedFindingCount: 1),
        Case(name: "CFNetService constructor", source: "let service = CFNetServiceCreate(nil, domain, type, name, port)", expectedFindingCount: 1),
        Case(name: "CFStream constructor", source: "CFStreamCreatePairWithSocket(nil, descriptor, nil, nil)", expectedFindingCount: 1),
        Case(name: "CFURL constructor", source: "let value = CFURLCreateWithString(nil, text, nil)", expectedFindingCount: 1),
        Case(name: "managed CloudKit disabled", source: "cloudKitDatabase: \n    .none", expectedFindingCount: 0),
        Case(name: "managed CloudKit enabled", source: "cloudKitDatabase: .automatic", expectedFindingCount: 1),
        Case(name: "model deletion call", source: "context.delete(configuration)", expectedFindingCount: 1),
        Case(name: "model deletion method reference", source: "let remove = context.delete", expectedFindingCount: 1),
        Case(name: "bare regex literal", source: "let regex = /harmless/", expectedFindingCount: 1),
        Case(name: "low-level socket alias", source: "let makeSocket = socket", expectedFindingCount: 1),
        Case(name: "host resolver alias", source: "let resolver = gethostbyaddr", expectedFindingCount: 1),
        Case(name: "alternate host resolver alias", source: "let resolver = gethostbyname2", expectedFindingCount: 1),
        Case(name: "implicit resource bytes", source: "let bytes = endpoint.resourceBytes", expectedFindingCount: 1),
        Case(name: "implicit resource lines", source: "let lines = endpoint.lines", expectedFindingCount: 1),
        Case(name: "AsyncImage loader", source: "AsyncImage(url: endpoint)", expectedFindingCount: 1),
        Case(name: "ubiquitous key-value store", source: "NSUbiquitousKeyValueStore.default", expectedFindingCount: 1),
        Case(name: "ubiquitous file downloader", source: "FileManager.default.startDownloadingUbiquitousItem(at: location)", expectedFindingCount: 1),
        Case(name: "localized rich text", source: "LocalizedStringKey(\"citation\")", expectedFindingCount: 1),
        Case(name: "attributed rich text", source: "AttributedString(markdown: text)", expectedFindingCount: 1),
        Case(name: "Markdown link literal", source: "Text(\"[citation](reference)\")", expectedFindingCount: 1),
        Case(
            name: "split dynamic Markdown link",
            source: #"let s = "ht" + "tps://example.invalid"; let m = "[x]" + "(" + s + ")"; Text(.init(m))"#,
            expectedFindingCount: 1
        ),
        Case(name: "plain dynamic Text", source: "Text(verbatim: message)", expectedFindingCount: 0),
        Case(
            name: "split-selector NSExpression",
            source: #"let selector = "start" + "DownloadingUbiquitousItemAtURL:"; NSExpression(forFunction: target, selectorName: selector, arguments: [])"#,
            expectedFindingCount: 1
        ),
        Case(name: "unmanaged reference", source: "let reference: Unmanaged<Decoy>", expectedFindingCount: 1),
        Case(name: "opaque reference recovery", source: "let value = box.fromOpaque(pointer)", expectedFindingCount: 1),
        Case(name: "unsafe downcast", source: "let value = unsafeDowncast(object, to: Target.self)", expectedFindingCount: 1),
        Case(name: "unsafe raw pointer", source: "let pointer: UnsafeRawPointer", expectedFindingCount: 1),
        Case(name: "unsafe byte access", source: "withUnsafeBytes(of: value) { bytes in consume(bytes) }", expectedFindingCount: 1),
        Case(name: "unsafe memory rebinding", source: "pointer.withMemoryRebound(to: Target.self, capacity: 1) { consume($0) }", expectedFindingCount: 1),
        Case(name: "unsafe raw buffer", source: "let bytes: UnsafeRawBufferPointer", expectedFindingCount: 1),
        Case(name: "unsafe uninitialized capacity", source: "Array(unsafeUninitializedCapacity: 1) { _, count in count = 0 }", expectedFindingCount: 1),
        Case(name: "contiguous storage access", source: "values.withContiguousStorageIfAvailable { consume($0) }", expectedFindingCount: 1),
        Case(name: "raw byte copy", source: "source.copyBytes(to: destination)", expectedFindingCount: 1),
        Case(name: "unsafe continuation is not memory access", source: "withUnsafeContinuation { continuation in continuation.resume() }", expectedFindingCount: 0),
        Case(name: "dynamic predicate", source: "let filter: NSPredicate", expectedFindingCount: 1),
        Case(name: "KVC lookup", source: "let result = object.value(forKey: key)", expectedFindingCount: 1),
        Case(name: "Unicode escape", source: #"let marker = "\u{5B}""#, expectedFindingCount: 1),
        Case(name: "backticked resource loader", source: "let bytes = endpoint.`resourceBytes`", expectedFindingCount: 1),
        Case(name: "SwiftUI managed container", source: ".modelContainer(for: SchemaV1.Intervention.self)", expectedFindingCount: 1),
        Case(name: "allowed plain citation text", source: "Text(citation.urlString ?? \"No source\")", expectedFindingCount: 0),
        Case(name: "line comment", source: "// URLSession.shared", expectedFindingCount: 0),
        Case(
            name: "nested block comments",
            source: "/* outer /* URLSession.shared */ still comment */ let value = 1",
            expectedFindingCount: 0
        ),
        Case(name: "web address literal", source: "let endpoint = \"https://example.invalid\"", expectedFindingCount: 1),
        Case(name: "websocket literal", source: "let endpoint = \"wss://example.invalid\"", expectedFindingCount: 1),
        Case(name: "external-action literal", source: "let endpoint = \"mailto:test@example.invalid\"", expectedFindingCount: 1),
        Case(name: "raw web address literal", source: "let endpoint = #\"https://example.invalid\"#", expectedFindingCount: 1),
        Case(
            name: "extended regex cannot hide live code",
            source: "let regex = #/x//#; let client = URLSession.shared",
            expectedFindingCount: 1
        ),
        Case(name: "citation storage is allowed", source: "var urlString: String?", expectedFindingCount: 0),
        Case(name: "Data transfer is allowed", source: "let payload: Data", expectedFindingCount: 0)
    ]

    for testCase in cases {
        let result = try findings(in: testCase.source, path: testCase.name)
        try check(
            result.count == testCase.expectedFindingCount,
            "\(testCase.name): expected \(testCase.expectedFindingCount) finding(s), got \(result.count)"
        )
    }
    let identityFixtureRoot = URL(fileURLWithPath: "/tmp/HippocratesIdentityFixture", isDirectory: true)
    let canonicalIdentities: [ReviewedSourceIdentity] = [
        .hippocratesApp,
        .domainEnums,
        .schemaV1,
        .appConfigService,
        .hippocratesStore,
        .backupArchive,
        .backupService,
        .schemaContractTests,
        .backupRoundTripTests,
        .privacyManifestTests
    ]
    try check(
        canonicalIdentities.allSatisfy { identity in
            let file = identityFixtureRoot.appendingPathComponent(identity.rawValue)
            return reviewedSourceIdentity(for: file, repositoryRoot: identityFixtureRoot) == identity
        },
        "An exact canonical repository-relative source identity was not recognized"
    )
    try check(
        canonicalIdentities.allSatisfy { identity in
            let collisionPrefix = identity.rawValue.hasPrefix("HippocratesTests/")
                ? "HippocratesTests/Collision/"
                : "Hippocrates/Collision/"
            let file = identityFixtureRoot.appendingPathComponent(collisionPrefix + identity.rawValue)
            return reviewedSourceIdentity(for: file, repositoryRoot: identityFixtureRoot) == .other
        },
        "A nested suffix-collision source inherited a canonical identity"
    )

    let compliantAppConfigModel = """
    @Model
    final class AppConfig {
        @Attribute(.unique) private(set) var singletonKey: String
        private(set) var stalenessIntervalMonths: Int?
        private(set) var lastExportAt: Date?

        init(
            stalenessIntervalMonths: Int?,
            lastExportAt: Date?,
            authority: AppConfigService.Authority
        ) {
            AppConfigService.requireAuthority(authority)
            precondition(
                stalenessIntervalMonths.map { $0 > 0 } ?? true,
                "The staleness interval must be positive when configured."
            )
            self.singletonKey = "app"
            self.stalenessIntervalMonths = stalenessIntervalMonths
            self.lastExportAt = lastExportAt
        }

        func updateStalenessIntervalMonths(
            _ value: Int?,
            authority: AppConfigService.Authority
        ) throws {
            AppConfigService.requireAuthority(authority)
            try AppConfigService.validate(stalenessIntervalMonths: value)
            stalenessIntervalMonths = value
        }
    }
    """
    try check(
        try appConfigOwnershipFindings(
            in: compliantAppConfigModel,
            path: "canonical AppConfig model",
            identity: .schemaV1
        ).isEmpty,
        "The canonical AppConfig model authority contract was rejected"
    )
    let defaultedAppConfigInitializer = compliantAppConfigModel.replacingOccurrences(
        of: "stalenessIntervalMonths: Int?,",
        with: "stalenessIntervalMonths: Int? = nil,"
    )
    try check(
        try appConfigOwnershipFindings(
            in: defaultedAppConfigInitializer,
            path: "defaulted AppConfig initializer",
            identity: .schemaV1
        ).isEmpty == false,
        "A defaulted AppConfig initializer escaped the authority contract"
    )
    let extraAppConfigInitializer = compliantAppConfigModel.replacingOccurrences(
        of: "    func updateStalenessIntervalMonths(",
        with: "    init(authority: AppConfigService.Authority) { fatalError() }\n\n    func updateStalenessIntervalMonths("
    )
    try check(
        try appConfigOwnershipFindings(
            in: extraAppConfigInitializer,
            path: "extra AppConfig initializer",
            identity: .schemaV1
        ).isEmpty == false,
        "An extra AppConfig initializer escaped the authority contract"
    )
    let unguardedAppConfigMutator = compliantAppConfigModel.replacingOccurrences(
        of: "        _ value: Int?,\n        authority: AppConfigService.Authority",
        with: "        _ value: Int?"
    )
    try check(
        try appConfigOwnershipFindings(
            in: unguardedAppConfigMutator,
            path: "unguarded AppConfig mutator",
            identity: .schemaV1
        ).isEmpty == false,
        "An AppConfig mutator without authority escaped the model contract"
    )
    let uncheckedAppConfigAuthority = compliantAppConfigModel.replacingOccurrences(
        of: "AppConfigService.requireAuthority(authority)\n",
        with: ""
    )
    try check(
        try appConfigOwnershipFindings(
            in: uncheckedAppConfigAuthority,
            path: "unchecked AppConfig authority",
            identity: .schemaV1
        ).isEmpty == false,
        "An AppConfig capability without identity checks escaped the model contract"
    )
    let relocatedAuthorityChecks = compliantAppConfigModel
        .replacingOccurrences(
            of: "        self.singletonKey = \"app\"",
            with: "        AppConfigService.requireAuthority(authority)\n        self.singletonKey = \"app\""
        )
        .replacingOccurrences(
            of: "    ) throws {\n        AppConfigService.requireAuthority(authority)\n        try AppConfigService.validate",
            with: "    ) throws {\n        try AppConfigService.validate"
        )
    try check(
        try appConfigOwnershipFindings(
            in: relocatedAuthorityChecks,
            path: "relocated AppConfig authority checks",
            identity: .schemaV1
        ).isEmpty == false,
        "Count-preserving relocation removed the AppConfig mutator's authority check"
    )
    let exactAppConfigBodyMutations: [(
        name: String,
        original: String,
        replacement: String
    )] = [
        (
            "singleton assignment",
            "        self.singletonKey = \"app\"",
            "        self.singletonKey = \"rogue\""
        ),
        (
            "initializer staleness assignment",
            "        self.stalenessIntervalMonths = stalenessIntervalMonths",
            "        self.stalenessIntervalMonths = nil"
        ),
        (
            "initializer export assignment",
            "        self.lastExportAt = lastExportAt",
            "        self.lastExportAt = nil"
        ),
        (
            "mutator assignment",
            "        stalenessIntervalMonths = value",
            "        stalenessIntervalMonths = nil"
        ),
        (
            "initializer validation predicate",
            "stalenessIntervalMonths.map { $0 > 0 } ?? true",
            "stalenessIntervalMonths.map { $0 >= 0 } ?? true"
        )
    ]
    for mutation in exactAppConfigBodyMutations {
        let mutatedModel = compliantAppConfigModel.replacingOccurrences(
            of: mutation.original,
            with: mutation.replacement
        )
        try check(
            try appConfigOwnershipFindings(
                in: mutatedModel,
                path: mutation.name,
                identity: .schemaV1
            ).isEmpty == false,
            "A changed AppConfig \(mutation.name) escaped the exact model contract"
        )
    }
    let canonicalInitializerText = """
    init(
        stalenessIntervalMonths: Int?,
        lastExportAt: Date?,
        authority: AppConfigService.Authority
    ) {
        AppConfigService.requireAuthority(authority)
        precondition(
            stalenessIntervalMonths.map { $0 > 0 } ?? true,
            "The staleness interval must be positive when configured."
        )
        self.singletonKey = "app"
        self.stalenessIntervalMonths = stalenessIntervalMonths
        self.lastExportAt = lastExportAt
    }
    """
    let smuggledCanonicalInitializer = compliantAppConfigModel.replacingOccurrences(
        of: "        self.singletonKey = \"app\"",
        with:
            "        self.singletonKey = \"rogue\"\n" +
            "        _ = #\"\"\"\n" +
            canonicalInitializerText +
            "\n        \"\"\"#"
    )
    guard smuggledCanonicalInitializer != compliantAppConfigModel else {
        throw NSError(
            domain: "NetworkBoundaryScannerTests",
            code: 13,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "The initializer-smuggling fixture did not change the canonical model"
            ]
        )
    }
    try check(
        try appConfigOwnershipFindings(
            in: smuggledCanonicalInitializer,
            path: "literal-smuggled AppConfig initializer",
            identity: .schemaV1
        ).isEmpty == false,
        "Canonical initializer text inside an inert literal hid executable body drift"
    )
    let observedAppConfigProperty = compliantAppConfigModel.replacingOccurrences(
        of: "    private(set) var stalenessIntervalMonths: Int?",
        with: """
            private(set) var stalenessIntervalMonths: Int? {
                didSet {
                    fatalError("unreviewed observer")
                }
            }
            """
    )
    try check(
        try appConfigOwnershipFindings(
            in: observedAppConfigProperty,
            path: "observed AppConfig property",
            identity: .schemaV1
        ).isEmpty == false,
        "An AppConfig property observer escaped the exact model contract"
    )

    let compliantAppConfigService = """
    @MainActor
    enum AppConfigService {
        final class Authority: Sendable {
            fileprivate static let canonical = Authority()

            fileprivate init() {}
        }

        private static let authority = Authority.canonical

        nonisolated static func requireAuthority(_ candidate: Authority) {
            precondition(
                candidate === Authority.canonical,
                "Only AppConfigService may construct or mutate AppConfig"
            )
        }

        static func create(in context: ModelContext) -> AppConfig {
            let configuration = AppConfig(
                stalenessIntervalMonths: nil,
                lastExportAt: nil,
                authority: authority
            )
            context.insert(configuration)
            return configuration
        }

        static func restore(
            stalenessIntervalMonths: Int?,
            lastExportAt: Date?,
            into context: ModelContext
        ) -> AppConfig {
            let configuration = AppConfig(
                stalenessIntervalMonths: stalenessIntervalMonths,
                lastExportAt: lastExportAt,
                authority: authority
            )
            context.insert(configuration)
            return configuration
        }

        static func mutate(
            _ stalenessIntervalMonths: Int?,
            on configuration: AppConfig
        ) throws {
            try configuration.updateStalenessIntervalMonths(
                stalenessIntervalMonths,
                authority: authority
            )
        }
    }
    """
    try check(
        try appConfigOwnershipFindings(
            in: compliantAppConfigService,
            path: "canonical AppConfig service",
            identity: .appConfigService
        ).isEmpty,
        "The canonical AppConfig service authority contract was rejected"
    )
    let forgeableAuthority = compliantAppConfigService.replacingOccurrences(
        of: "fileprivate init()",
        with: "init()"
    )
    try check(
        try appConfigOwnershipFindings(
            in: forgeableAuthority,
            path: "forgeable AppConfig authority",
            identity: .appConfigService
        ).isEmpty == false,
        "A forgeable AppConfig authority escaped the service contract"
    )
    let leakedAuthority = compliantAppConfigService.replacingOccurrences(
        of: "    private static let authority = Authority.canonical",
        with: "    private static let authority = Authority.canonical\n    static var leaked: Any { authority }"
    )
    try check(
        try appConfigOwnershipFindings(
            in: leakedAuthority,
            path: "leaked AppConfig authority",
            identity: .appConfigService
        ).isEmpty == false,
        "An AppConfig authority leak escaped the service contract"
    )
    let uncheckedServiceAuthority = compliantAppConfigService.replacingOccurrences(
        of: "candidate === Authority.canonical",
        with: "true"
    )
    try check(
        try appConfigOwnershipFindings(
            in: uncheckedServiceAuthority,
            path: "unchecked service authority",
            identity: .appConfigService
        ).isEmpty == false,
        "A service capability without identity validation escaped the contract"
    )
    let extraServiceConstruction = compliantAppConfigService.replacingOccurrences(
        of: "        context.insert(configuration)\n        return configuration",
        with: "        context.insert(configuration)\n        _ = AppConfig(stalenessIntervalMonths: nil, lastExportAt: nil, authority: authority)\n        return configuration"
    )
    try check(
        try appConfigOwnershipFindings(
            in: extraServiceConstruction,
            path: "extra service construction",
            identity: .appConfigService
        ).isEmpty == false,
        "An extra AppConfig construction escaped the service contract"
    )

    let ownershipUsageCases: [(name: String, source: String, message: String)] = [
        (
            "direct AppConfig construction",
            "let value = AppConfig(stalenessIntervalMonths: nil, lastExportAt: nil, authority: token)",
            "AppConfig construction is owned exclusively by AppConfigService"
        ),
        (
            "qualified AppConfig initializer reference",
            "let constructor = SchemaV1.AppConfig.init",
            "AppConfig construction is owned exclusively by AppConfigService"
        ),
        (
            "AppConfig metatype escape",
            "let modelType = AppConfig.self",
            "AppConfig construction is owned exclusively by AppConfigService"
        ),
        (
            "AppConfig typealias escape",
            "typealias Configuration = SchemaV1.AppConfig",
            "AppConfig construction is owned exclusively by AppConfigService"
        ),
        (
            "AppConfig authority use",
            "let token: AppConfigService.Authority",
            "AppConfig authority is reserved to the canonical model and service"
        ),
        (
            "bound AppConfig mutator",
            "let mutate = configuration.updateStalenessIntervalMonths",
            "AppConfig staleness mutation is owned exclusively by AppConfigService"
        ),
        (
            "AppConfig shadow declaration",
            "struct AppConfig {}",
            "AppConfig ownership symbols may only be declared by the canonical model and service"
        ),
        (
            "AppConfig extension factory",
            "extension SchemaV1.AppConfig { static func rogue() -> Self { fatalError() } }",
            "AppConfig ownership symbols may only be declared by the canonical model and service"
        )
    ]
    for usageCase in ownershipUsageCases {
        try check(
            try appConfigOwnershipFindings(
                in: usageCase.source,
                path: usageCase.name,
                identity: .other
            ).contains(where: { $0.message == usageCase.message }),
            "\(usageCase.name) escaped the AppConfig ownership boundary"
        )
    }
    let persistentBackingCases: [(name: String, source: String)] = [
        ("SwiftData backing protocol", "let storage: BackingData<Model>"),
        ("SwiftData backing initializer", ".init(backingData: storage)"),
        ("SwiftData persistent backing copy", "let storage = model.persistentBackingData"),
        ("SwiftData backing factory", "let make = AppConfig.createBackingData"),
        ("SwiftData direct value mutation", "model.setValue(forKey: key, to: value)"),
        ("SwiftData transformable mutation", "model.setTransformableValue(forKey: key, to: value)")
    ]
    for backingCase in persistentBackingCases {
        try check(
            try persistentModelBackingFindings(
                in: backingCase.source,
                path: backingCase.name
            ).count == 1,
            "\(backingCase.name) escaped the restricted SwiftData backing boundary"
        )
    }
    let opaqueAuthorityFabrication = """
    final class Decoy {}

    func fabricate<T: AnyObject>(_ object: AnyObject) -> T {
        Unmanaged<T>
            .fromOpaque(Unmanaged.passUnretained(object).toOpaque())
            .takeUnretainedValue()
    }

    func rogue() -> AppConfig {
        .init(
            stalenessIntervalMonths: 6,
            lastExportAt: nil,
            authority: fabricate(Decoy())
        )
    }
    """
    try check(
        try findings(
            in: opaqueAuthorityFabrication,
            path: "opaque AppConfig authority fabrication"
        ).contains(where: { $0.sourceRuleID == .dynamicInvocation }),
        "Unsafe opaque-pointer fabrication escaped the AppConfig authority boundary"
    )
    let inertOwnershipSource = #"""
    // AppConfig() Authority updateStalenessIntervalMonths backingData
    let note = "SchemaV1.AppConfig.init persistentBackingData"
    """#
    let inertAppConfigFindings = try appConfigOwnershipFindings(
        in: inertOwnershipSource,
        path: "inert ownership text",
        identity: .other
    )
    let inertBackingFindings = try persistentModelBackingFindings(
        in: inertOwnershipSource,
        path: "inert backing text"
    )
    try check(
        inertAppConfigFindings.isEmpty && inertBackingFindings.isEmpty,
        "Comments or strings triggered the AppConfig ownership boundary"
    )
    try check(
        try appConfigOwnershipFindings(
            in: "struct Authority {}; let descriptor = FetchDescriptor<AppConfig>(); let value = try AppConfigService.existing(in: context); _ = value?.stalenessIntervalMonths",
            path: "reviewed AppConfig reads",
            identity: .other
        ).isEmpty,
        "Legitimate AppConfig reads or service use were rejected"
    )
    let nestedAppConfigServiceFile = identityFixtureRoot.appendingPathComponent(
        "Hippocrates/Collision/Hippocrates/Persistence/AppConfigService.swift"
    )
    try check(
        try appConfigOwnershipFindings(
            in: compliantAppConfigService,
            path: nestedAppConfigServiceFile.path,
            identity: reviewedSourceIdentity(
                for: nestedAppConfigServiceFile,
                repositoryRoot: identityFixtureRoot
            )
        ).isEmpty == false,
        "A suffix-collision file inherited the AppConfig service authority"
    )

    let appInterpolationPath = "/tmp/Hippocrates/App/HippocratesApp.swift"
    let allowedAppInterpolation = #"let message = "\(error)""#
    try check(
        try interpolationArchitectureFindings(
            in: allowedAppInterpolation,
            path: appInterpolationPath,
            identity: .hippocratesApp
        ).isEmpty,
        "The exact reviewed app error interpolation was rejected"
    )
    let nestedAppFile = identityFixtureRoot.appendingPathComponent(
        "Hippocrates/Collision/Hippocrates/App/HippocratesApp.swift"
    )
    try check(
        try interpolationArchitectureFindings(
            in: allowedAppInterpolation,
            path: nestedAppFile.path,
            identity: reviewedSourceIdentity(for: nestedAppFile, repositoryRoot: identityFixtureRoot)
        ).count == 1,
        "A nested app-name collision inherited the reviewed interpolation seam"
    )

    let injectedAppInterpolation = allowedAppInterpolation
        + "\n"
        + #"let destination = "\(payload)""#
    try check(
        try interpolationArchitectureFindings(
            in: injectedAppInterpolation,
            path: appInterpolationPath,
            identity: .hippocratesApp
        ).count == 1,
        "An extra executable app interpolation escaped the exact allowlist"
    )
    try check(
        try interpolationArchitectureFindings(
            in: #"Text("\(payload)")"#,
            path: "/tmp/Hippocrates/Views/RootView.swift",
            identity: .other
        ).count == 1,
        "Executable interpolation escaped from a source with no reviewed interpolation seam"
    )

    let shadowFindings = try architectureSemanticFindings(
        in: "enum Foundation {}",
        path: "/tmp/Hippocrates/Views/Shadow.swift",
        identity: .other
    )
    try check(
        shadowFindings.contains(where: {
            $0.message == "Shipping source may not shadow or extend reviewed SwiftData architecture symbols"
        }),
        "A cross-file Foundation shadow escaped architecture validation"
    )
    let aliasExtensionFindings = try architectureSemanticFindings(
        in: "typealias Hidden = SchemaV1.Intervention\nextension Hidden {}",
        path: "/tmp/Hippocrates/Views/AliasExtension.swift",
        identity: .other
    )
    try check(
        aliasExtensionFindings.contains(where: {
            $0.message == "Shipping typealiases changed outside the reviewed architecture allowlist"
        }) && aliasExtensionFindings.contains(where: {
            $0.message == "Shipping extensions changed outside the reviewed architecture allowlist"
        }),
        "An alias-mediated extension seam escaped the exact declaration allowlists"
    )

    let canonicalStoreFixture = """
    import SwiftData

    @MainActor
    enum HippocratesStore {
        static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
            let schema = Schema(versionedSchema: SchemaV1.self)
            let configuration = ModelConfiguration(
                "Hippocrates",
                schema: schema,
                isStoredInMemoryOnly: inMemory,
                allowsSave: true,
                groupContainer: .none,
                cloudKitDatabase: .none
            )
            return try ModelContainer(
                for: schema,
                migrationPlan: HippocratesMigrationPlan.self,
                configurations: [configuration]
            )
        }
    }
    """
    try check(
        try storeArchitectureFindings(
            in: canonicalStoreFixture,
            path: "/tmp/Hippocrates/Persistence/HippocratesStore.swift"
        ).isEmpty,
        "The exact reviewed local-only store fixture was rejected"
    )
    try check(
        try storeArchitectureFindings(
            in: canonicalStoreFixture.replacingOccurrences(
                of: "\"Hippocrates\"",
                with: "\"Injected\""
            ),
            path: "/tmp/Hippocrates/Persistence/HippocratesStore.swift"
        ).count == 1,
        "A changed persistent-store identity escaped exact store validation"
    )
    try check(
        try storeArchitectureFindings(
            in: canonicalStoreFixture + "\nlet injected = ModelContainer.self\n",
            path: "/tmp/Hippocrates/Persistence/HippocratesStore.swift"
        ).count == 1,
        "Dead or extra container code escaped whole-file store validation"
    )
    let nestedStoreFile = identityFixtureRoot.appendingPathComponent(
        "Hippocrates/Collision/Hippocrates/Persistence/HippocratesStore.swift"
    )
    let nestedStoreFindings = try architectureSemanticFindings(
        in: canonicalStoreFixture,
        path: nestedStoreFile.path,
        identity: reviewedSourceIdentity(for: nestedStoreFile, repositoryRoot: identityFixtureRoot)
    )
    try check(
        nestedStoreFindings.contains(where: {
            $0.message == "ModelConfiguration is owned exclusively by HippocratesStore"
        }) && nestedStoreFindings.contains(where: {
            $0.message == "ModelContainer may only appear in the canonical store and app-owned property seam"
        }),
        "A nested store-name collision inherited canonical SwiftData privileges"
    )

    let canonicalTestStoreFixture = """
    private func makeFileBackedContainer(at storeLocation: URL, allowsSave: Bool = true) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration(
            "HippocratesPersistenceTest",
            schema: schema,
            url: storeLocation,
            allowsSave: allowsSave,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: HippocratesMigrationPlan.self,
            configurations: [configuration]
        )
    }
    """
    try check(
        try testStoreArchitectureFindings(
            in: canonicalTestStoreFixture,
            path: "/tmp/HippocratesTests/SchemaContractTests.swift"
        ).isEmpty,
        "The reviewed test-only file-backed store fixture was rejected"
    )
    try check(
        try testStoreArchitectureFindings(
            in: canonicalTestStoreFixture.replacingOccurrences(
                of: "cloudKitDatabase: .none",
                with: "cloudKitDatabase: .automatic"
            ),
            path: "/tmp/HippocratesTests/SchemaContractTests.swift"
        ).count == 1,
        "A CloudKit-enabled test store escaped the exact local-only seam"
    )
    try check(
        try testStoreArchitectureFindings(
            in: canonicalTestStoreFixture.replacingOccurrences(
                of: "allowsSave: Bool = true",
                with: "allowsSave: Bool = false"
            ),
            path: "/tmp/HippocratesTests/SchemaContractTests.swift"
        ).count == 1,
        "A disabled-by-default test store escaped the exact save-policy seam"
    )
    try check(
        try testStoreArchitectureFindings(
            in: canonicalTestStoreFixture.replacingOccurrences(
                of: "allowsSave: allowsSave",
                with: "allowsSave: true"
            ),
            path: "/tmp/HippocratesTests/SchemaContractTests.swift"
        ).count == 1,
        "A test store that ignored its save-policy parameter escaped exact validation"
    )
    let nestedTestStoreFile = identityFixtureRoot.appendingPathComponent(
        "HippocratesTests/Collision/HippocratesTests/SchemaContractTests.swift"
    )
    let nestedTestStoreIdentity = reviewedSourceIdentity(
        for: nestedTestStoreFile,
        repositoryRoot: identityFixtureRoot
    )
    try check(
        try testPersistenceBoundaryFindings(
            in: canonicalTestStoreFixture,
            path: nestedTestStoreFile.path,
            identity: nestedTestStoreIdentity
        ).contains(where: {
            $0.message == "Only SchemaContractTests may construct the one reviewed test-only SwiftData container"
        }),
        "A nested test-name collision inherited the reviewed test-store seam"
    )

    try check(
        try testPersistenceBoundaryFindings(
            in: "let injected: ModelContainer?",
            path: "/tmp/HippocratesTests/BackupRoundTripTests.swift",
            identity: .backupRoundTripTests
        ).count == 1,
        "A second test-owned SwiftData container escaped the persistence boundary"
    )

    let XMLHeader = #"<?xml version="1.0" encoding="UTF-8"?>"#
    let expectedXML: [SchemeXMLEvent] = [
        .start("Root", ["mode": "NO"]),
        .end("Root")
    ]
    let exactXML = XMLHeader + "\n<Root mode=\"NO\"></Root>"
    try check(
        strictXMLMatches(exactXML, expectedEvents: expectedXML),
        "The exact XML event tree was rejected"
    )
    let rejectedXMLDocuments = [
        XMLHeader + "\n<Root mode=\"YES\"></Root>",
        XMLHeader + "\n<Root mode=\"NO\" shadow=\"YES\"></Root>",
        XMLHeader + "\n<Root mode=\"&#78;O\"></Root>",
        XMLHeader + "\n<!-- shadow --><Root mode=\"NO\"></Root>",
        XMLHeader + "\n<?shadow value=\"1\"?><Root mode=\"NO\"></Root>",
        XMLHeader + "\n<Root mode=\"NO\">shadow</Root>"
    ]
    for document in rejectedXMLDocuments {
        try check(
            strictXMLMatches(document, expectedEvents: expectedXML) == false,
            "A structurally altered XML document matched the exact event tree"
        )
    }

    let localURLFixture =
        "    private func makeFileBackedContainer(at storeLocation: URL, allowsSave: Bool = true) throws -> ModelContainer {\n" +
        "        to storeLocation: URL,\n" +
        "        at storeLocation: URL,"
    let citationFixture = #"            urlString: "https://example.invalid/source""#
    let pendingDeleteFixture = "        destination.mainContext.delete(existing)"
    let backupBoundaryFixture = citationFixture + "\n" + pendingDeleteFixture
    let manifestReadFixture =
        "        let data = try XCTUnwrap(FileManager.default.contents(atPath: manifestPath))"
    try check(
        try testFindings(in: localURLFixture, path: "SchemaContractTests.swift", identity: .schemaContractTests).isEmpty,
        "The reviewed local URL value was rejected in SchemaContractTests.swift"
    )
    try check(
        try testFindings(in: backupBoundaryFixture, path: "BackupRoundTripTests.swift", identity: .backupRoundTripTests).isEmpty,
        "The reserved example.invalid citation was rejected in BackupRoundTripTests.swift"
    )
    try check(
        try testFindings(
            in: backupBoundaryFixture + "\n" + pendingDeleteFixture,
            path: "BackupRoundTripTests.swift",
            identity: .backupRoundTripTests
        ).contains(where: { $0.sourceRuleID == .modelDeletion }),
        "A duplicate pending-delete test seam inherited the exact deletion exception"
    )
    try check(
        try testFindings(
            in: manifestReadFixture,
            path: "PrivacyManifestTests.swift",
            identity: .privacyManifestTests
        ).isEmpty,
        "The exact bundled privacy-manifest read was rejected in PrivacyManifestTests.swift"
    )
    try check(
        try testFindings(
            in: localURLFixture,
            path: nestedTestStoreFile.path,
            identity: nestedTestStoreIdentity
        ).contains(where: { $0.sourceRuleID == .foundationURLValue }),
        "A nested test-name collision inherited the reviewed local-URL seams"
    )
    let nestedBackupTestFile = identityFixtureRoot.appendingPathComponent(
        "HippocratesTests/Collision/HippocratesTests/BackupRoundTripTests.swift"
    )
    try check(
        try testFindings(
            in: backupBoundaryFixture,
            path: nestedBackupTestFile.path,
            identity: reviewedSourceIdentity(for: nestedBackupTestFile, repositoryRoot: identityFixtureRoot)
        ).contains(where: { $0.sourceRuleID == .externalAddressLiteral }),
        "A nested backup-test-name collision inherited the reserved citation seam"
    )
    let nestedPrivacyTestFile = identityFixtureRoot.appendingPathComponent(
        "HippocratesTests/Collision/HippocratesTests/PrivacyManifestTests.swift"
    )
    try check(
        try testFindings(
            in: manifestReadFixture,
            path: nestedPrivacyTestFile.path,
            identity: reviewedSourceIdentity(
                for: nestedPrivacyTestFile,
                repositoryRoot: identityFixtureRoot
            )
        ).contains(where: { $0.sourceRuleID == .pathFileAccess }),
        "A nested privacy-test-name collision inherited the bundled-file read seam"
    )

    let remoteTestLoader =
        #"let payload = try Data(contentsOf: URL(string: "https://example.invalid/source")!)"#
    let remoteTestFindings = try testFindings(in: remoteTestLoader, path: "SchemaContractTests.swift", identity: .schemaContractTests)
    try check(
        remoteTestFindings.contains(where: { $0.sourceRuleID == .contentsOfLoader }),
        "A network-capable test Data(contentsOf:) loader escaped the boundary"
    )
    try check(
        try testFindings(
            in: #"let citation = "https://not-reviewed.invalid/source""#,
            path: "BackupRoundTripTests.swift",
            identity: .backupRoundTripTests
        ).contains(where: { $0.sourceRuleID == .externalAddressLiteral }),
        "An unreviewed test URL literal escaped the boundary"
    )
    try check(
        try testFindings(
            in: "let stream = InputStream(url: file)",
            path: "SchemaContractTests.swift",
            identity: .schemaContractTests
        ).contains(where: { $0.sourceRuleID == .urlBackedStream }),
        "A URL-backed test stream escaped the boundary"
    )

    try check(
        try importFindings(
            in: "import SwiftUI",
            path: "allowed shipping import",
            allowedModules: shippingAllowedImports
        ).isEmpty,
        "A reviewed shipping import was rejected"
    )
    try check(
        try importFindings(
            in: "import CloudKit",
            path: "CloudKit import",
            allowedModules: shippingAllowedImports
        ).count == 1,
        "CloudKit escaped the shipping import allowlist"
    )
    try check(
        try importFindings(
            in: "import struct Network.NWConnection",
            path: "selective Network import",
            allowedModules: shippingAllowedImports
        ).count == 1,
        "A selective Network import escaped the shipping import allowlist"
    )
    try check(
        try importFindings(
            in: "@preconcurrency import Network",
            path: "attributed Network import",
            allowedModules: shippingAllowedImports
        ).count == 1,
        "An attributed Network import escaped the shipping import allowlist"
    )
    try check(
        try importFindings(
            in: "import Foundation; import Network",
            path: "semicolon Network import",
            allowedModules: shippingAllowedImports
        ).count == 1,
        "A same-line Network import escaped the shipping import allowlist"
    )
    try check(
        try importFindings(
            in: "@testable import Hippocrates",
            path: "testable app import",
            allowedModules: testAllowedImports
        ).isEmpty,
        "The reviewed @testable app import was rejected"
    )

    let compliantIntervention = """
    @Model
    final class Intervention {
        @Attribute(.unique) var id: Foundation.UUID
        var timestamp: Foundation.Date
        @Relationship(deleteRule: .nullify)
        var type: InterventionType?
        @Relationship(deleteRule: .nullify)
        var drugClass: DrugClass?
        @Relationship(deleteRule: .nullify)
        var serviceLine: ServiceLine?
        var acceptance: SchemaV1Vocabulary.Acceptance
        var costAvoidanceCents: Swift.Int?
        var minutesSpent: Swift.Int?
        var diQuestion: DIQuestion?
    }
    typealias Intervention = SchemaV1.Intervention
    typealias InterventionType = SchemaV1.InterventionType
    typealias DrugClass = SchemaV1.DrugClass
    typealias ServiceLine = SchemaV1.ServiceLine
    typealias DIQuestion = SchemaV1.DIQuestion
    typealias Citation = SchemaV1.Citation
    typealias AppConfig = SchemaV1.AppConfig
    """
    try check(
        try interventionArchitectureFindings(
            in: compliantIntervention,
            path: "compliant intervention"
        ).isEmpty,
        "Compliant Intervention was rejected"
    )

    let unsafeIntervention = compliantIntervention.replacingOccurrences(
        of: "}",
        with: "let narrative: Optional<Swift.String>\n}"
    )
    try check(
        try interventionArchitectureFindings(
            in: unsafeIntervention,
            path: "unsafe intervention"
        ).count == 1,
        "Intervention free-text self-test did not fail"
    )
    let wrongTypeIntervention = compliantIntervention.replacingOccurrences(
        of: "var minutesSpent: Swift.Int?",
        with: "var minutesSpent: Optional<Swift.String>"
    )
    try check(
        try interventionArchitectureFindings(
            in: wrongTypeIntervention,
            path: "wrong-type intervention"
        ).count == 1,
        "Intervention property-type self-test did not fail"
    )
    let inferredTextIntervention = compliantIntervention.replacingOccurrences(
        of: "var minutesSpent: Swift.Int?",
        with: "var minutesSpent: Swift.Int?\nvar notes = \"\""
    )
    try check(
        try interventionArchitectureFindings(
            in: inferredTextIntervention,
            path: "inferred-text intervention"
        ).count == 1,
        "Inferred Intervention property self-test did not fail"
    )
    let braceTrapIntervention = compliantIntervention.replacingOccurrences(
        of: "\n}",
        with: "\nfunc trap() { _ = \"}\" }\nvar narrative: String\n}"
    )
    try check(
        try interventionArchitectureFindings(
            in: braceTrapIntervention,
            path: "literal brace trap"
        ).count == 1,
        "A brace inside a string hid a later persisted Intervention property"
    )

    let compliantBackupParitySchema = """
    enum SchemaV1: VersionedSchema {
        static var models: [any PersistentModel.Type] {
            [
                Intervention.self,
                InterventionType.self,
                DrugClass.self,
                ServiceLine.self,
                DIQuestion.self,
                Citation.self,
                AppConfig.self
            ]
        }

        @Model final class InterventionType {
            var id: UUID
            var label: String
            var defaultCostAvoidanceCents: Int?
            var isActive: Bool
            var sortOrder: Int
        }
        @Model final class DrugClass {
            var id: UUID
            var label: String
            var isActive: Bool
            var sortOrder: Int
        }
        @Model final class ServiceLine {
            var id: UUID
            var label: String
            var isActive: Bool
            var sortOrder: Int
        }
        @Model final class Intervention {
            var id: Foundation.UUID
            var timestamp: Foundation.Date
            var type: InterventionType?
            var drugClass: DrugClass?
            var serviceLine: ServiceLine?
            var acceptance: SchemaV1Vocabulary.Acceptance
            var costAvoidanceCents: Swift.Int?
            var minutesSpent: Swift.Int?
            var diQuestion: DIQuestion?
        }
        @Model final class DIQuestion {
            var id: UUID
            var createdAt: Date
            var answeredAt: Date?
            var questionText: String
            var background: String
            var answerText: String
            var searchStrategy: String
            var requestorRole: SchemaV1Vocabulary.RequestorRole
            var questionClass: SchemaV1Vocabulary.DIQuestionClass
            var urgency: SchemaV1Vocabulary.Urgency
            private(set) var verifiedOn: Date
            private(set) var reviewAfter: Date
            var didFollowUp: Bool
            var tags: [String]
            private(set) var verificationHistory: [Date]
            var citations: [Citation]
            var linkedInterventions: [Intervention]
        }
        @Model final class Citation {
            var id: UUID
            var question: DIQuestion?
            var tier: SchemaV1Vocabulary.SourceTier
            var title: String
            var locator: String
            var accessedDate: Date
            var urlString: String?
        }
        @Model final class AppConfig {
            private(set) var singletonKey: String
            private(set) var stalenessIntervalMonths: Int?
            private(set) var lastExportAt: Date?
        }
    }
    """
    let compliantBackupParityArchive = """
    struct BackupArchive: Codable, Equatable, Sendable {
        static let currentFormatVersion = 2
        var formatVersion: Int
        var createdAt: Date
        var payload: Payload
    }

    extension BackupArchive {
        struct Payload: Codable, Equatable, Sendable {
            var interventionTypes: [InterventionTypeRecord]
            var drugClasses: [DrugClassRecord]
            var serviceLines: [ServiceLineRecord]
            var interventions: [InterventionRecord]
            var questions: [DIQuestionRecord]
            var citations: [CitationRecord]
            var appConfig: AppConfigRecord?
        }
        struct InterventionTypeRecord: Codable, Equatable, Sendable {
            var id: UUID
            var label: String
            var defaultCostAvoidanceCents: Int?
            var isActive: Bool
            var sortOrder: Int
        }
        struct DrugClassRecord: Codable, Equatable, Sendable {
            var id: UUID
            var label: String
            var isActive: Bool
            var sortOrder: Int
        }
        struct ServiceLineRecord: Codable, Equatable, Sendable {
            var id: UUID
            var label: String
            var isActive: Bool
            var sortOrder: Int
        }
        struct InterventionRecord: Codable, Equatable, Sendable {
            var id: UUID
            var timestamp: Date
            var typeID: UUID?
            var drugClassID: UUID?
            var serviceLineID: UUID?
            var acceptance: SchemaV1Vocabulary.Acceptance
            var costAvoidanceCents: Int?
            var minutesSpent: Int?
            var diQuestionID: UUID?
        }
        struct DIQuestionRecord: Codable, Equatable, Sendable {
            var id: UUID
            var createdAt: Date
            var answeredAt: Date?
            var questionText: String
            var background: String
            var answerText: String
            var searchStrategy: String
            var requestorRole: SchemaV1Vocabulary.RequestorRole
            var questionClass: SchemaV1Vocabulary.DIQuestionClass
            var urgency: SchemaV1Vocabulary.Urgency
            var verifiedOn: Date
            var reviewAfter: Date
            var didFollowUp: Bool
            var tags: [String]
            var verificationHistory: [Date]
        }
        struct CitationRecord: Codable, Equatable, Sendable {
            var id: UUID
            var questionID: UUID?
            var tier: SchemaV1Vocabulary.SourceTier
            var title: String
            var locator: String
            var accessedDate: Date
            var urlString: String?
        }
        struct AppConfigRecord: Codable, Equatable, Sendable {
            var stalenessIntervalMonths: Int?
            var lastExportAt: Date?
        }
    }
    """

    func parityFindings(_ schema: String, _ archive: String) throws -> [Finding] {
        try backupParityFindings(
            schemaSource: schema,
            archiveSource: archive,
            schemaPath: "SchemaV1.swift",
            archivePath: "BackupArchive.swift"
        )
    }
    func hasSchemaDrift(_ schema: String, archive: String = compliantBackupParityArchive) throws -> Bool {
        try parityFindings(schema, archive).contains(where: {
            $0.message.contains("SchemaV1 persisted-property surface changed without backup-format review")
        })
    }

    try check(
        try parityFindings(compliantBackupParitySchema, compliantBackupParityArchive).isEmpty,
        "The compliant schema-to-backup parity fixture was rejected"
    )
    let addedScalarSchema = replacingFirst(
        compliantBackupParitySchema,
        "        var urlString: String?",
        "        var urlString: String?\n        var annotation: String"
    )
    try check(
        try hasSchemaDrift(addedScalarSchema),
        "An added persisted scalar escaped backup-format review"
    )
    let addedRelationshipSchema = replacingFirst(
        compliantBackupParitySchema,
        "        var linkedInterventions: [Intervention]",
        "        var linkedInterventions: [Intervention]\n        var reviewer: Citation?"
    )
    try check(
        try hasSchemaDrift(addedRelationshipSchema),
        "An added persisted relationship escaped backup-format review"
    )
    let changedTypeSchema = replacingFirst(
        compliantBackupParitySchema,
        "        var tags: [String]",
        "        var tags: Set<String>"
    )
    try check(
        try hasSchemaDrift(changedTypeSchema),
        "A persisted-property type change escaped backup-format review"
    )
    let transientPropertySchema = replacingFirst(
        compliantBackupParitySchema,
        "        var tags: [String]",
        "        @Transient\n        var tags: [String]"
    )
    try check(
        try hasSchemaDrift(transientPropertySchema),
        "A transient persistence modifier escaped backup-format review"
    )
    let addedDTOPropertyArchive = replacingFirst(
        compliantBackupParityArchive,
        "        var urlString: String?",
        "        var urlString: String?\n        var annotation: String"
    )
    try check(
        try parityFindings(compliantBackupParitySchema, addedDTOPropertyArchive).isEmpty == false,
        "An added backup DTO property escaped the parity contract"
    )
    let changedPayloadArchive = replacingFirst(
        compliantBackupParityArchive,
        "        var appConfig: AppConfigRecord?",
        "        var appConfig: AppConfigRecord?\n        var metadata: String"
    )
    try check(
        try parityFindings(compliantBackupParitySchema, changedPayloadArchive).isEmpty == false,
        "A Payload shape change escaped backup-format review"
    )
    let changedModelListSchema = replacingFirst(
        compliantBackupParitySchema,
        "            Citation.self,\n            AppConfig.self",
        "            AppConfig.self,\n            Citation.self"
    )
    try check(
        try hasSchemaDrift(changedModelListSchema),
        "A SchemaV1 model-list change escaped backup-format review"
    )

    let dtoInsertionPoint = "        var lastExportAt: Date?\n    }\n}"
    let customDTODeclarations = [
        "        enum CodingKeys: String, CodingKey { case lastExportAt }",
        "        init(lastExportAt: Date?) { self.lastExportAt = lastExportAt }",
        "        init(from decoder: Decoder) throws { fatalError() }",
        "        func encode(to encoder: Encoder) throws { fatalError() }",
        "        struct Helper {}"
    ]
    let customDTOsAreRejected = try customDTODeclarations.allSatisfy { declaration in
        let mutatedArchive = replacingFirst(
            compliantBackupParityArchive,
            dtoInsertionPoint,
            "        var lastExportAt: Date?\n\(declaration)\n    }\n}"
        )
        return try parityFindings(compliantBackupParitySchema, mutatedArchive).contains(where: {
            $0.message.contains("synthesized Codable and memberwise initialization")
        })
    }
    try check(
        customDTOsAreRejected,
        "Custom CodingKeys, initializer, Codable method, or nested DTO declaration escaped review"
    )

    let outerCustomCodableDeclarations = [
        "    private enum CodingKeys: String, CodingKey { case formatVersion = \"version\"; case createdAt; case payload }",
        "    init(from decoder: Decoder) throws { fatalError() }",
        "    func encode(to encoder: Encoder) throws { fatalError() }"
    ]
    let outerCustomCodableArchives = outerCustomCodableDeclarations.map { declaration in
        replacingFirst(
            compliantBackupParityArchive,
            "    var payload: Payload",
            "    var payload: Payload\n\(declaration)"
        )
    } + [
        replacingFirst(
            compliantBackupParityArchive,
            "extension BackupArchive {",
            "extension BackupArchive {\n    init(from decoder: Decoder) throws { fatalError() }"
        )
    ]
    let outerCustomCodableIsRejected = try outerCustomCodableArchives.allSatisfy { mutatedArchive in
        return try parityFindings(compliantBackupParitySchema, mutatedArchive).contains(where: {
            $0.message.contains("synthesized Codable and memberwise initialization")
        })
    }
    try check(
        outerCustomCodableIsRejected,
        "Outer BackupArchive custom CodingKeys, decoder, or encoder escaped review"
    )

    let coordinatedSchema = addedScalarSchema
    let coordinatedArchive = addedDTOPropertyArchive
    try check(
        try hasSchemaDrift(coordinatedSchema, archive: coordinatedArchive),
        "A coordinated schema-and-DTO addition bypassed explicit backup-format review"
    )
    let decoySchema = compliantBackupParitySchema + #"""
    // @Model final class Rogue { var annotation: String }
    let note = "@Model final class Rogue { var annotation: String }"
    """#
    let decoyArchive = compliantBackupParityArchive + #"""
    // struct Payload: Codable { var metadata: String }
    let note = "struct CitationRecord: Codable { var metadata: String }"
    """#
    try check(
        try parityFindings(decoySchema, decoyArchive).isEmpty,
        "A comment or string decoy changed the structural backup-parity result"
    )

    let compliantImmutableBackupV1 = """
    enum BackupCodec {
        private struct BackupArchiveV1: Decodable {
            let formatVersion: Int
            let createdAt: Date
            let payload: Payload

            struct Payload: Decodable {
                let interventionTypes: [InterventionTypeRecord]
                let drugClasses: [DrugClassRecord]
                let serviceLines: [ServiceLineRecord]
                let interventions: [InterventionRecord]
                let questions: [DIQuestionRecord]
                let citations: [CitationRecord]
                let appConfig: AppConfigRecord?
            }

            struct InterventionTypeRecord: Decodable {
                let id: UUID
                let label: String
                let defaultCostAvoidanceCents: Int?
                let isActive: Bool
                let sortOrder: Int
            }

            struct DrugClassRecord: Decodable {
                let id: UUID
                let label: String
                let isActive: Bool
                let sortOrder: Int
            }

            struct ServiceLineRecord: Decodable {
                let id: UUID
                let label: String
                let isActive: Bool
                let sortOrder: Int
            }

            struct InterventionRecord: Decodable {
                let id: UUID
                let timestamp: Date
                let typeID: UUID?
                let drugClassID: UUID?
                let serviceLineID: UUID?
                let acceptance: SchemaV1Vocabulary.Acceptance
                let costAvoidanceCents: Int
                let minutesSpent: Int?
                let diQuestionID: UUID?
            }

            struct DIQuestionRecord: Decodable {
                let id: UUID
                let createdAt: Date
                let answeredAt: Date?
                let questionText: String
                let background: String
                let answerText: String
                let searchStrategy: String
                let requestorRole: SchemaV1Vocabulary.RequestorRole
                let questionClass: SchemaV1Vocabulary.DIQuestionClass
                let urgency: SchemaV1Vocabulary.Urgency
                let verifiedOn: Date
                let reviewAfter: Date
                let didFollowUp: Bool
                let tags: [String]
                let verificationHistory: [Date]
            }

            struct CitationRecord: Decodable {
                let id: UUID
                let questionID: UUID?
                let tier: SchemaV1Vocabulary.SourceTier
                let title: String
                let locator: String
                let accessedDate: Date
                let urlString: String?
            }

            struct AppConfigRecord: Decodable {
                let costAvoidanceValues: [String: Int]
                let stalenessIntervalMonths: Int
                let lastExportAt: Date?
            }
        }
    }
    """

    func v1Findings(_ source: String) throws -> [Finding] {
        try immutableBackupV1Findings(in: source, path: "BackupCodec.swift")
    }
    let v1Message = "BackupArchive v1 decoder changed outside immutable compatibility contract"
    func hasV1Drift(_ source: String) throws -> Bool {
        try v1Findings(source).contains(where: { $0.message == v1Message })
    }
    func replacingV1(
        _ source: String,
        _ target: String,
        _ replacement: String
    ) throws -> String {
        guard
            source.components(separatedBy: target).count == 2,
            let range = source.range(of: target)
        else {
            throw NSError(
                domain: "NetworkBoundaryScannerTests",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Immutable v1 mutation anchor is not unique"]
            )
        }
        var result = source
        result.replaceSubrange(range, with: replacement)
        return result
    }

    try check(
        try v1Findings(compliantImmutableBackupV1).isEmpty,
        "The compliant immutable v1 backup fixture was rejected"
    )
    let addedV1Scalar = try replacingV1(
        compliantImmutableBackupV1,
        "            let label: String\n            let defaultCostAvoidanceCents: Int?",
        "            let label: String\n            let detail: String\n            let defaultCostAvoidanceCents: Int?"
    )
    try check(
        try hasV1Drift(addedV1Scalar),
        "A legacy record scalar addition escaped the immutable v1 contract"
    )
    let changedV1Type = try replacingV1(
        compliantImmutableBackupV1,
        "            let costAvoidanceCents: Int\n",
        "            let costAvoidanceCents: Int?\n"
    )
    try check(
        try hasV1Drift(changedV1Type),
        "A legacy record field-type change escaped the immutable v1 contract"
    )
    let renamedV1Record = try replacingV1(
        compliantImmutableBackupV1,
        "        struct CitationRecord: Decodable {",
        "        struct ReferenceRecord: Decodable {"
    )
    try check(
        try hasV1Drift(renamedV1Record),
        "A legacy record declaration change escaped the immutable v1 contract"
    )
    let changedV1Payload = try replacingV1(
        compliantImmutableBackupV1,
        "            let appConfig: AppConfigRecord?",
        "            let appConfig: AppConfigRecord?\n            let metadata: String"
    )
    try check(
        try hasV1Drift(changedV1Payload),
        "A legacy Payload shape change escaped the immutable v1 contract"
    )
    let changedV1Outer = try replacingV1(
        compliantImmutableBackupV1,
        "        let payload: Payload",
        "        let payload: Payload\n        let sourceBuild: String"
    )
    try check(
        try hasV1Drift(changedV1Outer),
        "A legacy outer archive shape change escaped the immutable v1 contract"
    )
    let mutableV1Field = try replacingV1(
        compliantImmutableBackupV1,
        "            let label: String\n            let defaultCostAvoidanceCents: Int?",
        "            var label: String\n            let defaultCostAvoidanceCents: Int?"
    )
    try check(
        try hasV1Drift(mutableV1Field),
        "A mutable legacy record field escaped the immutable v1 contract"
    )
    let defaultedV1Field = try replacingV1(
        compliantImmutableBackupV1,
        "            let label: String\n            let defaultCostAvoidanceCents: Int?",
        "            let label: String = \"legacy\"\n            let defaultCostAvoidanceCents: Int?"
    )
    try check(
        try hasV1Drift(defaultedV1Field),
        "A defaulted legacy record field escaped the synthesized v1 contract"
    )
    let reusedCurrentDTO = try replacingV1(
        compliantImmutableBackupV1,
        "            let interventionTypes: [InterventionTypeRecord]",
        "            let interventionTypes: [BackupArchive.InterventionTypeRecord]"
    )
    try check(
        try hasV1Drift(reusedCurrentDTO),
        "Current BackupArchive DTO reuse escaped the immutable v1 contract"
    )

    let v1CustomDecodingDeclarations = [
        "            enum CodingKeys: String, CodingKey { case lastExportAt }",
        "            init(from decoder: Decoder) throws { fatalError() }",
        "            func encode(to encoder: Encoder) throws { fatalError() }"
    ]
    let v1CustomDecodingIsRejected = try v1CustomDecodingDeclarations.allSatisfy {
        declaration in
        let mutation = try replacingV1(
            compliantImmutableBackupV1,
            "            let lastExportAt: Date?\n        }\n    }\n}",
            "            let lastExportAt: Date?\n\(declaration)\n        }\n    }\n}"
        )
        return try hasV1Drift(mutation)
    }
    try check(
        v1CustomDecodingIsRejected,
        "Custom v1 CodingKeys, decoder, or encoder escaped the synthesized contract"
    )

    let v1CustomMemberDeclarations = [
        "            init(lastExportAt: Date?) { self.lastExportAt = lastExportAt }",
        "            func helper() {}"
    ]
    let v1CustomMembersAreRejected = try v1CustomMemberDeclarations.allSatisfy {
        declaration in
        let mutation = try replacingV1(
            compliantImmutableBackupV1,
            "            let lastExportAt: Date?\n        }\n    }\n}",
            "            let lastExportAt: Date?\n\(declaration)\n        }\n    }\n}"
        )
        return try hasV1Drift(mutation)
    }
    try check(
        v1CustomMembersAreRejected,
        "A custom v1 initializer or method escaped the synthesized contract"
    )

    let nestedV1Extra = try replacingV1(
        compliantImmutableBackupV1,
        "            let lastExportAt: Date?\n        }\n    }\n}",
        "            let lastExportAt: Date?\n            struct Helper {}\n        }\n    }\n}"
    )
    let extendedV1Sources = [
        compliantImmutableBackupV1
            + "\nextension BackupCodec.BackupArchiveV1 {}\n",
        compliantImmutableBackupV1
            + "\ntypealias LegacyBackup = BackupCodec.BackupArchiveV1\n"
            + "extension LegacyBackup {}\n"
    ]
    let v1ExtensionsAreRejected = try extendedV1Sources.allSatisfy(hasV1Drift)
    try check(
        try hasV1Drift(nestedV1Extra) && v1ExtensionsAreRejected,
        "A nested v1 declaration or extension escaped the immutable compatibility contract"
    )

    let v1Decoys = compliantImmutableBackupV1 + #"""
    // private struct BackupArchiveV1: Decodable { let formatVersion: String }
    // extension BackupCodec.BackupArchiveV1 {}
    let note = "struct Payload: Decodable { var metadata: String }"
    """#
    try check(
        try v1Findings(v1Decoys).isEmpty,
        "A comment or string decoy changed the immutable v1 structural result"
    )

    let quotedPropertyTrap =
        #"{ isa = PBXNativeTarget; name = "productType = com.apple.product-type.application;"; }"#
    try check(
        try pbxScalar("productType", in: quotedPropertyTrap) == nil,
        "PBX scalar parser read a property from inside a quoted string"
    )
    let quotedListTrap =
        #"{ isa = PBXNativeTarget; name = "dependencies = (AAAAAAAAAAAAAAAAAAAAAAAA,);"; dependencies = (); }"#
    try check(
        try pbxIDs(inList: "dependencies", in: quotedListTrap).isEmpty,
        "PBX list parser read an object ID from inside a quoted string"
    )
    try check(
        throwsError {
            _ = try pbxScalar(
                "shellScript",
                in: #"{ isa = PBXShellScriptBuildPhase; shellScript = "one"; shellScript = "two"; }"#
            )
        },
        "Duplicate PBX scalar properties were accepted"
    )
    try check(
        throwsError {
            _ = try pbxIDs(inList: "files", in: "{ isa = PBXSourcesBuildPhase; }")
        },
        "A missing required PBX list was accepted as empty"
    )
    func policyProject(
        settings: String = "",
        configurationProperties: String = "",
        extraObjects: String = "",
        trailingComment: String = ""
    ) -> String {
        """
        {
            archiveVersion = 1;
            classes = {};
            objectVersion = 77;
            objects = {
                AAAAAAAAAAAAAAAAAAAAAAAA = {
                    isa = XCBuildConfiguration;
                    buildSettings = {
                        \(settings)
                    };
                    name = Debug;
                    \(configurationProperties)
                };
                \(extraObjects)
            };
            rootObject = AAAAAAAAAAAAAAAAAAAAAAAA;
        }
        \(trailingComment)
        """
    }
    try check(
        throwsError {
            _ = try pbxObjects(
                in: replacingFirst(policyProject(), "rootObject =", "\"rootObject\" =")
            )
        },
        "A quoted PBX root property key was accepted"
    )

    try check(
        projectPolicyFindings(
            in: policyProject(trailingComment: "/* Network.framework */"),
            path: "comment-only project token"
        ).isEmpty,
        "A PBX comment triggered a project policy rule"
    )
    let projectInjectionFixtures: [(label: String, project: String, message: String)] = [
        (
            "PBXFileSystemSynchronizedRootGroup",
            policyProject(
                extraObjects: "BBBBBBBBBBBBBBBBBBBBBBBB = { isa = PBXFileSystemSynchronizedRootGroup; };"
            ),
            "Synchronized filesystem groups are forbidden"
        ),
        (
            "SWIFT_OBJC_BRIDGING_HEADER",
            policyProject(settings: "SWIFT_OBJC_BRIDGING_HEADER = Bridge.h;"),
            "Objective-C bridging headers are forbidden"
        ),
        (
            "baseConfigurationReference",
            policyProject(configurationProperties: "baseConfigurationReference = BBBBBBBBBBBBBBBBBBBBBBBB;"),
            "XCConfig injection is forbidden"
        ),
        (
            "XCLocalSwiftPackageReference",
            policyProject(
                extraObjects: "BBBBBBBBBBBBBBBBBBBBBBBB = { isa = XCLocalSwiftPackageReference; };"
            ),
            "Local Swift Package dependencies are forbidden"
        ),
        (
            "SWIFT_DRIVER_FLAGS",
            policyProject(settings: "SWIFT_DRIVER_FLAGS = -module-alias Foundation=Injected;"),
            "Custom build tools, process environments, and source inclusion/exclusion settings are forbidden"
        ),
        (
            "SWIFT_DRIVER_SWIFT_FRONTEND_EXEC",
            policyProject(settings: "SWIFT_DRIVER_SWIFT_FRONTEND_EXEC = /tmp/injected;"),
            "Custom build tools, process environments, and source inclusion/exclusion settings are forbidden"
        ),
        (
            "CODE_SIGN_ENTITLEMENTS",
            policyProject(settings: "CODE_SIGN_ENTITLEMENTS = Hippocrates.entitlements;"),
            "Entitlements require explicit architecture review"
        )
    ]
    for fixture in projectInjectionFixtures {
        try check(
            projectPolicyFindings(in: fixture.project, path: fixture.label).contains(where: {
                $0.message == fixture.message
            }),
            "Project injection token \(fixture.label) was not rejected by its policy rule"
        )
    }

    func privacyManifest(_ root: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
        \(root)
        </plist>
        """
    }
    let compliantPrivacyManifest = privacyManifest(
        """
        <dict>
            <key>NSPrivacyTracking</key>
            <false/>
            <key>NSPrivacyCollectedDataTypes</key>
            <array/>
        </dict>
        """
    )
    try check(
        privacyManifestFindings(
            in: Data(compliantPrivacyManifest.utf8),
            path: "PrivacyInfo.xcprivacy"
        ).isEmpty,
        "The exact no-tracking, no-collected-data privacy manifest was rejected"
    )
    let binaryPrivacyManifest = try PropertyListSerialization.data(
        fromPropertyList: [
            "NSPrivacyTracking": false,
            "NSPrivacyCollectedDataTypes": [Any]()
        ] as [String: Any],
        format: .binary,
        options: 0
    )
    try check(
        privacyManifestFindings(
            in: binaryPrivacyManifest,
            path: "PrivacyInfo.xcprivacy"
        ).contains(where: { $0.message == privacyManifestContractMessage }),
        "A binary property list escaped the required XML privacy-manifest contract"
    )
    let rejectedPrivacyManifests = [
        ("malformed property list", "<plist"),
        ("non-dictionary root", privacyManifest("<array/>")),
        (
            "missing collected-data key",
            privacyManifest("<dict><key>NSPrivacyTracking</key><false/></dict>")
        ),
        (
            "tracking enabled",
            compliantPrivacyManifest.replacingOccurrences(of: "<false/>", with: "<true/>")
        ),
        (
            "non-Boolean tracking value",
            compliantPrivacyManifest.replacingOccurrences(of: "<false/>", with: "<integer>0</integer>")
        ),
        (
            "collected data",
            compliantPrivacyManifest.replacingOccurrences(
                of: "<array/>",
                with: "<array><dict/></array>"
            )
        ),
        (
            "duplicate tracking key",
            privacyManifest(
                "<dict><key>NSPrivacyTracking</key><true/><key>NSPrivacyTracking</key><false/><key>NSPrivacyCollectedDataTypes</key><array/></dict>"
            )
        ),
        (
            "duplicate collected-data key",
            privacyManifest(
                "<dict><key>NSPrivacyTracking</key><false/><key>NSPrivacyCollectedDataTypes</key><array><dict/></array><key>NSPrivacyCollectedDataTypes</key><array/></dict>"
            )
        ),
        (
            "tracking domains",
            compliantPrivacyManifest.replacingOccurrences(
                of: "</dict>",
                with: "<key>NSPrivacyTrackingDomains</key><array/></dict>"
            )
        ),
        (
            "accessed API reasons",
            compliantPrivacyManifest.replacingOccurrences(
                of: "</dict>",
                with: "<key>NSPrivacyAccessedAPITypes</key><array/></dict>"
            )
        )
    ]
    for fixture in rejectedPrivacyManifests {
        try check(
            privacyManifestFindings(
                in: Data(fixture.1.utf8),
                path: "PrivacyInfo.xcprivacy"
            ).contains(where: { $0.message == privacyManifestContractMessage }),
            "A \(fixture.0) privacy manifest escaped the exact semantic contract"
        )
    }

    let fixtureRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("HippocratesBoundaryScanner-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: fixtureRoot) }
    let appDirectory = fixtureRoot
        .appendingPathComponent("Hippocrates", isDirectory: true)
        .appendingPathComponent("App", isDirectory: true)
    let resourceDirectory = fixtureRoot
        .appendingPathComponent("Hippocrates", isDirectory: true)
        .appendingPathComponent("Resources", isDirectory: true)
    let testDirectory = fixtureRoot.appendingPathComponent("HippocratesTests", isDirectory: true)
    try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: resourceDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
    let appSourceURL = appDirectory.appendingPathComponent("App.swift")
    let testSourceURL = testDirectory.appendingPathComponent("AppTests.swift")
    let manifestURL = resourceDirectory.appendingPathComponent("PrivacyInfo.xcprivacy")
    try Data("struct FixtureApp {}\n".utf8).write(to: appSourceURL)
    try Data("struct FixtureTests {}\n".utf8).write(to: testSourceURL)
    try Data(compliantPrivacyManifest.utf8).write(to: manifestURL)
    try check(
        try isRegularNonSymlinkFile(appSourceURL, beneath: fixtureRoot),
        "An ordinary in-repository regular file failed the control-file identity gate"
    )
    let projectBundleFixture = fixtureRoot
        .appendingPathComponent("Fixture.xcodeproj", isDirectory: true)
    let sharedSchemeFixture = projectBundleFixture
        .appendingPathComponent("xcshareddata", isDirectory: true)
        .appendingPathComponent("xcschemes", isDirectory: true)
        .appendingPathComponent("Hippocrates.xcscheme")
    try FileManager.default.createDirectory(
        at: sharedSchemeFixture.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data("<Scheme/>\n".utf8).write(to: sharedSchemeFixture)
    let cleanProjectInventory = try filesystemInventory(under: projectBundleFixture)
    try check(
        cleanProjectInventory.symbolicLinks.isEmpty
            && cleanProjectInventory.regularFiles.contains(sharedSchemeFixture.standardizedFileURL),
        "A regular shared-scheme inventory was rejected"
    )

    let externalSchemeFixture = fixtureRoot.appendingPathComponent("External.xcscheme")
    try Data("<Scheme/>\n".utf8).write(to: externalSchemeFixture)
    let userDataFixture = projectBundleFixture
        .appendingPathComponent("xcuserdata", isDirectory: true)
    let userSchemeDirectory = userDataFixture
        .appendingPathComponent("attacker.xcuserdatad", isDirectory: true)
        .appendingPathComponent("xcschemes", isDirectory: true)
    try FileManager.default.createDirectory(
        at: userSchemeDirectory,
        withIntermediateDirectories: true
    )
    let userSchemeLink = userSchemeDirectory.appendingPathComponent("Hippocrates.xcscheme")
    try FileManager.default.createSymbolicLink(
        atPath: userSchemeLink.path,
        withDestinationPath: externalSchemeFixture.path
    )
    let fileLinkInventory = try filesystemInventory(under: projectBundleFixture)
    try check(
        fileLinkInventory.symbolicLinks.contains(where: { $0.path == userSchemeLink.path }),
        "A symlinked xcuserdata scheme escaped the project-bundle control inventory"
    )

    try FileManager.default.removeItem(at: userDataFixture)
    let externalUserDataFixture = fixtureRoot
        .appendingPathComponent("ExternalXcuserdata", isDirectory: true)
    let externalUserScheme = externalUserDataFixture
        .appendingPathComponent("attacker.xcuserdatad", isDirectory: true)
        .appendingPathComponent("xcschemes", isDirectory: true)
        .appendingPathComponent("Hippocrates.xcscheme")
    try FileManager.default.createDirectory(
        at: externalUserScheme.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data("<Scheme/>\n".utf8).write(to: externalUserScheme)
    try FileManager.default.createSymbolicLink(
        atPath: userDataFixture.path,
        withDestinationPath: externalUserDataFixture.path
    )
    let directoryLinkInventory = try filesystemInventory(under: projectBundleFixture)
    try check(
        directoryLinkInventory.symbolicLinks.contains(where: { $0.path == userDataFixture.path }),
        "A symlinked xcuserdata directory escaped the project-bundle control inventory"
    )

    let fixtureBoundaryInputs = expectedBoundaryInputPaths
        .map { "\"\($0)\"," }
        .joined(separator: " ")
    let topologyFixture = #"""
    {
        archiveVersion = 1;
        classes = {};
        objectVersion = 77;
        objects = {
        AAAAAAAAAAAAAAAAAAAAAAAA = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = App.swift; sourceTree = "<group>"; };
        BBBBBBBBBBBBBBBBBBBBBBBB = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AppTests.swift; sourceTree = "<group>"; };
        CCCCCCCCCCCCCCCCCCCCCCCC = {isa = PBXFileReference; lastKnownFileType = text.xml; path = PrivacyInfo.xcprivacy; sourceTree = "<group>"; };
        DDDDDDDDDDDDDDDDDDDDDDDD = {isa = PBXBuildFile; fileRef = AAAAAAAAAAAAAAAAAAAAAAAA; };
        EEEEEEEEEEEEEEEEEEEEEEEE = {isa = PBXBuildFile; fileRef = BBBBBBBBBBBBBBBBBBBBBBBB; };
        FFFFFFFFFFFFFFFFFFFFFFFF = {isa = PBXBuildFile; fileRef = CCCCCCCCCCCCCCCCCCCCCCCC; };
        111111111111111111111111 = {isa = PBXGroup; children = (222222222222222222222222, 555555555555555555555555,); sourceTree = "<group>"; };
        222222222222222222222222 = {isa = PBXGroup; children = (333333333333333333333333, 444444444444444444444444,); path = Hippocrates; sourceTree = "<group>"; };
        333333333333333333333333 = {isa = PBXGroup; children = (AAAAAAAAAAAAAAAAAAAAAAAA,); path = App; sourceTree = "<group>"; };
        444444444444444444444444 = {isa = PBXGroup; children = (CCCCCCCCCCCCCCCCCCCCCCCC,); path = Resources; sourceTree = "<group>"; };
        555555555555555555555555 = {isa = PBXGroup; children = (BBBBBBBBBBBBBBBBBBBBBBBB,); path = HippocratesTests; sourceTree = "<group>"; };
        666666666666666666666666 = {isa = PBXShellScriptBuildPhase; alwaysOutOfDate = 1; buildActionMask = 2147483647; files = (); inputFileListPaths = (); inputPaths = (\#(fixtureBoundaryInputs)); name = "Enforce Offline Boundary"; outputFileListPaths = (); outputPaths = (); runOnlyForDeploymentPostprocessing = 0; shellPath = /bin/sh; shellScript = "exec /usr/bin/env -i DEVELOPER_DIR=\"$DEVELOPER_DIR\" HOME=/var/empty PATH=/usr/bin:/bin:/usr/sbin:/sbin TMPDIR=\"$TMPDIR\" /usr/bin/xcrun --sdk macosx swift -module-cache-path \"$TMPDIR/HippocratesBoundaryModuleCache\" \"$SRCROOT/Scripts/NetworkBoundaryScanner.swift\" --sandboxed-build-check \"$SRCROOT\"\n"; showEnvVarsInLog = 0; };
        777777777777777777777777 = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (DDDDDDDDDDDDDDDDDDDDDDDD,); runOnlyForDeploymentPostprocessing = 0; };
        888888888888888888888888 = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };
        999999999999999999999999 = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (FFFFFFFFFFFFFFFFFFFFFFFF,); runOnlyForDeploymentPostprocessing = 0; };
        121212121212121212121212 = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (EEEEEEEEEEEEEEEEEEEEEEEE,); runOnlyForDeploymentPostprocessing = 0; };
        131313131313131313131313 = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };
        141414141414141414141414 = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; };
        151515151515151515151515 = {isa = PBXNativeTarget; buildPhases = (666666666666666666666666, 777777777777777777777777, 888888888888888888888888, 999999999999999999999999,); buildRules = (); dependencies = (); name = Hippocrates; productType = "com.apple.product-type.application"; };
        161616161616161616161616 = {isa = PBXNativeTarget; buildPhases = (121212121212121212121212, 131313131313131313131313, 141414141414141414141414,); buildRules = (); dependencies = (181818181818181818181818,); name = HippocratesTests; productType = "com.apple.product-type.bundle.unit-test"; };
        171717171717171717171717 = {isa = PBXProject; mainGroup = 111111111111111111111111; targets = (151515151515151515151515, 161616161616161616161616,); };
        181818181818181818181818 = {isa = PBXTargetDependency; target = 151515151515151515151515; targetProxy = 191919191919191919191919; };
        191919191919191919191919 = {isa = PBXContainerItemProxy; containerPortal = 171717171717171717171717; proxyType = 1; remoteGlobalIDString = 151515151515151515151515; };
        };
        rootObject = 171717171717171717171717;
    }
    """#

    func topologyFindings(_ projectText: String = topologyFixture) throws -> [Finding] {
        try appTargetSourceFindings(
            projectText: projectText,
            projectPath: fixtureRoot.appendingPathComponent("project.pbxproj").path,
            repositoryRoot: fixtureRoot,
            sourceRoot: fixtureRoot.appendingPathComponent("Hippocrates", isDirectory: true)
        )
    }

    try check(try topologyFindings().isEmpty, "A complete physical PBX topology fixture was rejected")

    try Data(
        compliantPrivacyManifest.replacingOccurrences(of: "<false/>", with: "<true/>").utf8
    ).write(to: manifestURL)
    try check(
        try privacyManifestFileFindings(
            at: manifestURL,
            beneath: resourceDirectory
        ).contains(where: { $0.message == privacyManifestContractMessage }),
        "A privacy manifest with tracking enabled escaped repository semantic inspection"
    )
    try Data(compliantPrivacyManifest.utf8).write(to: manifestURL)

    let physicalAliasURL = appDirectory.appendingPathComponent("PhysicalAlias.swift")
    try FileManager.default.linkItem(at: appSourceURL, to: physicalAliasURL)
    try check(
        try topologyFindings().contains(where: {
            $0.message.contains("multiple on-disk names for one physical Swift source")
        }),
        "A hard-linked physical source alias escaped topology validation"
    )
    try FileManager.default.removeItem(at: physicalAliasURL)

    let orphanDirectory = appDirectory.appendingPathComponent("Nested", isDirectory: true)
    try FileManager.default.createDirectory(at: orphanDirectory, withIntermediateDirectories: true)
    let orphanAppURL = orphanDirectory.appendingPathComponent("Orphan.swift")
    try Data("struct Orphan {}\n".utf8).write(to: orphanAppURL)
    try check(
        try topologyFindings().contains(where: {
            $0.message.contains("App-target Swift source exists on disk but is missing")
        }),
        "An unlisted nested app Swift file escaped target membership"
    )
    try FileManager.default.removeItem(at: orphanDirectory)

    let orphanTestURL = testDirectory.appendingPathComponent("OrphanTests.swift")
    try Data("struct OrphanTests {}\n".utf8).write(to: orphanTestURL)
    try check(
        try topologyFindings().contains(where: {
            $0.message.contains("Unit-test target Swift source exists on disk but is missing")
        }),
        "An unlisted test Swift file escaped target membership"
    )
    try FileManager.default.removeItem(at: orphanTestURL)

    let repeatedBuildFixture = replacingFirst(
        topologyFixture,
        "files = (DDDDDDDDDDDDDDDDDDDDDDDD,);",
        "files = (DDDDDDDDDDDDDDDDDDDDDDDD, DDDDDDDDDDDDDDDDDDDDDDDD,);"
    )
    try check(
        try topologyFindings(repeatedBuildFixture).contains(where: {
            $0.message.contains("repeats PBXBuildFile")
        }),
        "A repeated source build-file ID escaped topology validation"
    )

    let aliasBuildFixture = replacingFirst(
        replacingFirst(
            topologyFixture,
            "files = (DDDDDDDDDDDDDDDDDDDDDDDD,);",
            "files = (DDDDDDDDDDDDDDDDDDDDDDDD, ABABABABABABABABABABABAB,);"
        ),
        "\n    };",
        "\n    ABABABABABABABABABABABAB = {isa = PBXBuildFile; fileRef = AAAAAAAAAAAAAAAAAAAAAAAA; };\n    };"
    )
    try check(
        try topologyFindings(aliasBuildFixture).contains(where: {
            $0.message.contains("compiles one lexical source path more than once")
        }),
        "Two PBX build files targeting one source escaped validation"
    )

    let wrongTypeFixture = replacingFirst(
        topologyFixture,
        "lastKnownFileType = sourcecode.swift",
        "lastKnownFileType = sourcecode.c.objc"
    )
    try check(
        try topologyFindings(wrongTypeFixture).contains(where: {
            $0.message.contains("Only PBX-declared Swift source")
        }),
        "A .swift file declared as Objective-C escaped validation"
    )

    let wrongDependencyFixture = replacingFirst(
        topologyFixture,
        "target = 151515151515151515151515; targetProxy",
        "target = 161616161616161616161616; targetProxy"
    )
    try check(
        try topologyFindings(wrongDependencyFixture).contains(where: {
            $0.message.contains("depend directly and only")
        }),
        "A unit-test dependency on the wrong target escaped validation"
    )

    let externalSourceFixture = replacingFirst(
        topologyFixture,
        "path = App; sourceTree",
        "path = ../External; sourceTree"
    )
    try check(
        try topologyFindings(externalSourceFixture).contains(where: {
            $0.message.contains("must live lexically beneath")
        }),
        "An app source outside Hippocrates escaped validation"
    )

    let extraResourceURL = resourceDirectory.appendingPathComponent("Unexpected.txt")
    try Data("unexpected\n".utf8).write(to: extraResourceURL)
    try check(
        try topologyFindings().contains(where: {
            $0.message.contains("Unreviewed file exists beneath Hippocrates/Resources")
        }),
        "An unreviewed app resource escaped validation"
    )
    try FileManager.default.removeItem(at: extraResourceURL)

    let outsideSourceURL = fixtureRoot.appendingPathComponent("Outside.swift")
    try Data("struct Outside {}\n".utf8).write(to: outsideSourceURL)
    try FileManager.default.removeItem(at: appSourceURL)
    try FileManager.default.createSymbolicLink(
        atPath: appSourceURL.path,
        withDestinationPath: outsideSourceURL.path
    )
    try check(
        try isRegularNonSymlinkFile(appSourceURL, beneath: fixtureRoot) == false,
        "An external control-file symlink passed the regular in-repository file gate"
    )
    try check(
        try topologyFindings().contains(where: { $0.message.contains("source symlink escapes") }),
        "A source symlink escaping its reviewed root was accepted"
    )
    try FileManager.default.removeItem(at: appSourceURL)
    try Data("struct FixtureApp {}\n".utf8).write(to: appSourceURL)

    let missingListFixture = replacingFirst(
        topologyFixture,
        "buildRules = (); dependencies = (); name = Hippocrates;",
        "dependencies = (); name = Hippocrates;"
    )
    try check(
        throwsError { _ = try topologyFindings(missingListFixture) },
        "A missing required target list did not fail closed"
    )
    let duplicateShellFixture = replacingFirst(
        topologyFixture,
        "showEnvVarsInLog = 0;",
        "shellScript = \"disabled\"; showEnvVarsInLog = 0;"
    )
    try check(
        throwsError { _ = try topologyFindings(duplicateShellFixture) },
        "A duplicate shellScript property did not fail closed"
    )

    guard completedChecks == 270 else {
        throw NSError(
            domain: "NetworkBoundaryScannerTests",
            code: 12,
            userInfo: [
                NSLocalizedDescriptionKey:
                    "Scanner check inventory changed: expected 270, completed \(completedChecks)"
            ]
        )
    }
    print("Architecture boundary scanner self-tests passed (\(completedChecks) checks).")
}

private func emit(_ findings: [Finding]) {
    for finding in findings {
        let diagnostic = "\(finding.path):\(finding.line): error: \(finding.message)\n"
        FileHandle.standardError.write(Data(diagnostic.utf8))
    }
}

private func printUsageAndExit() -> Never {
    let usage = "Usage: NetworkBoundaryScanner.swift --self-test | --build-check <repository-root> | --sandboxed-build-check <repository-root>\n"
    FileHandle.standardError.write(Data(usage.utf8))
    exit(2)
}

let arguments = Array(CommandLine.arguments.dropFirst())

do {
    switch arguments.first {
    case "--self-test" where arguments.count == 1:
        try runSelfTests()

    case "--build-check" where arguments.count == 2:
        try runSelfTests()
        let repositoryRoot = URL(fileURLWithPath: arguments[1], isDirectory: true)
        let results = try repositoryFindings(at: repositoryRoot, mode: .direct)
        guard results.isEmpty else {
            emit(results)
            exit(1)
        }
        print("Hippocrates no-network and zero-dependency checks passed.")

    case "--sandboxed-build-check" where arguments.count == 2:
        try runSelfTests()
        let repositoryRoot = URL(fileURLWithPath: arguments[1], isDirectory: true)
        let results = try repositoryFindings(at: repositoryRoot, mode: .sandboxedXcode)
        guard results.isEmpty else {
            emit(results)
            exit(1)
        }
        print("Hippocrates no-network and zero-dependency checks passed.")

    default:
        printUsageAndExit()
    }
} catch {
    FileHandle.standardError.write(Data("Network boundary scanner failed: \(error)\n".utf8))
    exit(2)
}
