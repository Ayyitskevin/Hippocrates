#!/usr/bin/env swift

import Foundation

private struct Finding: Equatable {
    let path: String
    let line: Int
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
private func sourceWithoutComments(_ source: String) -> String {
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
                    output.append(contentsOf: characters[index...cursor])
                    index = cursor + 1
                    regexHashCount = rawHashes
                    mode = .extendedRegex
                    continue
                }

                let quotes = quoteCount(at: cursor)
                if quotes > 0 {
                    output.append(contentsOf: characters[index..<(cursor + quotes)])
                    index = cursor + quotes
                    stringHashCount = rawHashes
                    stringQuoteCount = quotes
                    mode = .string
                    continue
                }
            }

            let quotes = quoteCount(at: index)
            if quotes > 0 {
                output.append(contentsOf: characters[index..<(index + quotes)])
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
                output.append(current)
                output.append(characters[index + 1])
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
                    output.append(contentsOf: characters[index..<end])
                    index = end
                    mode = .code
                    continue
                }
            }

            output.append(current)
            index += 1

        case .extendedRegex:
            if current == "\\", character(at: index + 1) != nil {
                output.append(current)
                output.append(characters[index + 1])
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
                    output.append(contentsOf: characters[index..<end])
                    index = end
                    mode = .code
                    continue
                }
            }

            output.append(current)
            index += 1
        }
    }

    return String(output)
}

private let sourceRules: [(pattern: String, message: String)] = [
    (#"\bURLSession[A-Za-z0-9_]*\b"#, "URLSession violates the no-network boundary"),
    (#"\bNSURLConnection\b"#, "NSURLConnection violates the no-network boundary"),
    (#"\bNWConnection\b"#, "NWConnection violates the no-network boundary"),
    (#"\bCFSocket\b"#, "CFSocket violates the no-network boundary"),
    (#"\bWKWebView\b"#, "WKWebView violates the no-network boundary"),
    (#"\bSFSafariViewController\b"#, "SFSafariViewController can open a network surface"),
    (#"\bURLRequest\b"#, "URLRequest violates the no-network boundary"),
    (#"\b(openURL|OpenURLAction)\b"#, "openURL violates the no-network boundary"),
    (#"\bLink\b"#, "Link can open a network surface; use plain citation text"),
    (
        #"\bShareLink\s*\(\s*item\s*:\s*[^,\n]*(?:URL|url)"#,
        "ShareLink must transfer Data or a reviewed file document, never a URL"
    ),
    (#"UIApplication\s*\.\s*shared\s*\.\s*open"#, "UIApplication.open can open a network surface"),
    (#"\b(?:URL|NSURL)\b"#, "Foundation URL values are forbidden in shipping code; use FileDocument or Data transfer"),
    (
        #"\b(?:Data|NSData|String)\s*\(\s*contentsOf\s*:"#,
        "contentsOf URL loading is forbidden in shipping code"
    ),
    (#"\b(?:InputStream|NSInputStream)\s*\(\s*url\s*:"#, "URL-backed streams are forbidden in shipping code"),
    (#"\bimport\s+(Network|WebKit|CFNetwork)\b"#, "A networking framework import is forbidden"),
    (#"https?://"#, "Hard-coded web address literals are forbidden in shipping source")
]

private let projectRules: [(token: String, message: String)] = [
    ("Network.framework", "Network.framework must not be linked"),
    ("WebKit.framework", "WebKit.framework must not be linked"),
    ("CFNetwork.framework", "CFNetwork.framework must not be linked"),
    ("OTHER_LDFLAGS", "Custom linker flags require explicit offline-boundary review"),
    ("wrapper.framework", "Binary frameworks are forbidden"),
    ("wrapper.xcframework", "Binary XCFrameworks are forbidden"),
    ("wrapper.pb-project", "Xcode subprojects are forbidden"),
    ("PBXReferenceProxy", "Xcode subproject products are forbidden"),
    ("isa = PBXBuildRule;", "Custom build rules are forbidden"),
    ("XCRemoteSwiftPackageReference", "Swift Package dependencies are forbidden"),
    ("XCSwiftPackageProductDependency", "Swift Package dependencies are forbidden")
]

private func lineNumber(in text: String, at utf16Location: Int) -> Int {
    guard let range = Range(NSRange(location: 0, length: utf16Location), in: text) else {
        return 1
    }
    return text[range].reduce(into: 1) { line, character in
        if character == "\n" { line += 1 }
    }
}

private func findings(in source: String, path: String) throws -> [Finding] {
    let visibleSource = sourceWithoutComments(source)
    let fullRange = NSRange(visibleSource.startIndex..<visibleSource.endIndex, in: visibleSource)
    var results: [Finding] = []

    for rule in sourceRules {
        let expression = try NSRegularExpression(pattern: rule.pattern)
        for match in expression.matches(in: visibleSource, range: fullRange) {
            results.append(
                Finding(
                    path: path,
                    line: lineNumber(in: visibleSource, at: match.range.location),
                    message: rule.message
                )
            )
        }
    }

    return results
}

private func interventionArchitectureFindings(in source: String, path: String) throws -> [Finding] {
    let visibleSource = sourceWithoutComments(source)
    let declarationExpression = try NSRegularExpression(pattern: #"\bfinal\s+class\s+Intervention\b"#)
    let sourceRange = NSRange(visibleSource.startIndex..<visibleSource.endIndex, in: visibleSource)
    guard
        let declarationMatch = declarationExpression.firstMatch(in: visibleSource, range: sourceRange),
        let declarationRange = Range(declarationMatch.range, in: visibleSource)
    else {
        return [Finding(path: path, line: 1, message: "Intervention model declaration is missing")]
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
    let anyPropertyExpression = try NSRegularExpression(
        pattern: #"\b(?:var|let)\s+(`?[A-Za-z_][A-Za-z0-9_]*`?)"#
    )
    let propertyExpression = try NSRegularExpression(
        pattern: #"\b(?:var|let)\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([^=\n]+?)(?=\s*(?:=|\n|$))"#
    )
    let bodyRange = NSRange(body.startIndex..<body.endIndex, in: body)
    let allDeclaredPropertyNames = Set(
        anyPropertyExpression.matches(in: body, range: bodyRange).compactMap { match -> String? in
            guard let nameRange = Range(match.range(at: 1), in: body) else { return nil }
            return String(body[nameRange]).replacingOccurrences(of: "`", with: "")
        }
    )
    var declaredProperties: [String: String] = [:]
    for match in propertyExpression.matches(in: body, range: bodyRange) {
        guard
            match.numberOfRanges == 3,
            let nameRange = Range(match.range(at: 1), in: body),
            let typeRange = Range(match.range(at: 2), in: body)
        else {
            continue
        }
        let name = String(body[nameRange])
        let type = String(body[typeRange].filter { !$0.isWhitespace })
        if declaredProperties[name] != nil {
            return [Finding(path: path, line: 1, message: "Intervention declares property \(name) more than once")]
        }
        declaredProperties[name] = type
    }
    let allowedProperties: [String: String] = [
        "id": "UUID",
        "timestamp": "Date",
        "type": "InterventionType?",
        "drugClass": "DrugClass?",
        "serviceLine": "ServiceLine?",
        "acceptance": "Acceptance",
        "costAvoidanceCents": "Int",
        "minutesSpent": "Int?",
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

private func swiftFiles(under root: URL) -> [URL] {
    guard let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: []
    ) else {
        return []
    }

    var files: [URL] = []
    for case let fileURL as URL in enumerator where fileURL.pathExtension.lowercased() == "swift" {
        files.append(fileURL)
    }
    return files.sorted { $0.path < $1.path }
}

/// The source folder alone is not the build boundary: Xcode can compile a file
/// from anywhere on disk. Resolve the app target's PBXSourcesBuildPhase so a
/// source added outside `Hippocrates/` cannot evade inspection.
private struct PBXLexState {
    var isInsideString = false
    var isEscapingStringCharacter = false
    var isInsideBlockComment = false
}

private func pbxBraceDelta(in line: String, state: inout PBXLexState) -> Int {
    let characters = Array(line)
    var index = 0
    var delta = 0

    while index < characters.count {
        let current = characters[index]
        let next = index + 1 < characters.count ? characters[index + 1] : nil

        if state.isInsideBlockComment {
            if current == "*", next == "/" {
                state.isInsideBlockComment = false
                index += 2
            } else {
                index += 1
            }
            continue
        }

        if state.isInsideString {
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
            break
        }
        if current == "/", next == "*" {
            state.isInsideBlockComment = true
            index += 2
            continue
        }
        if current == "\"" {
            state.isInsideString = true
            index += 1
            continue
        }
        if current == "{" { delta += 1 }
        if current == "}" { delta -= 1 }
        index += 1
    }

    return delta
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
    let objectStart = try NSRegularExpression(
        pattern: #"^\s*([A-Fa-f0-9]{24})(?:\s+/\*.*\*/)?\s*=\s*\{"#
    )
    var objects: [String: String] = [:]
    var activeID: String?
    var activeLines: [String] = []
    var braceDepth = 0
    var lexState = PBXLexState()

    for lineSlice in projectText.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = String(lineSlice)

        if activeID != nil {
            activeLines.append(line)
            braceDepth += pbxBraceDelta(in: line, state: &lexState)
            if braceDepth == 0, let completedID = activeID {
                guard objects[completedID] == nil else {
                    throw NSError(
                        domain: "PBXProjectParser",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Duplicate PBX object ID \(completedID)"]
                    )
                }
                objects[completedID] = activeLines.joined(separator: "\n")
                activeID = nil
                activeLines = []
            }
            continue
        }

        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard
            let match = objectStart.firstMatch(in: line, range: range),
            let idRange = Range(match.range(at: 1), in: line)
        else {
            continue
        }

        let id = String(line[idRange])
        activeID = id
        activeLines = [line]
        lexState = PBXLexState()
        braceDepth = pbxBraceDelta(in: line, state: &lexState)
        if braceDepth == 0 {
            guard objects[id] == nil else {
                throw NSError(
                    domain: "PBXProjectParser",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Duplicate PBX object ID \(id)"]
                )
            }
            objects[id] = line
            activeID = nil
            activeLines = []
        }
    }

    guard activeID == nil, braceDepth == 0 else {
        throw NSError(
            domain: "PBXProjectParser",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Unbalanced PBX object braces"]
        )
    }

    return objects
}

private func pbxScalar(_ property: String, in object: String) throws -> String? {
    let escapedProperty = NSRegularExpression.escapedPattern(for: property)
    let expression = try NSRegularExpression(
        pattern: #"\b"# + escapedProperty + #"\s*=\s*(?:\"((?:\\.|[^\"\\])*)\"|([^;\n]+));"#
    )
    let range = NSRange(object.startIndex..<object.endIndex, in: object)
    guard let match = expression.firstMatch(in: object, range: range) else {
        return nil
    }

    for captureIndex in 1...2 where match.range(at: captureIndex).location != NSNotFound {
        guard let captureRange = Range(match.range(at: captureIndex), in: object) else {
            continue
        }
        return object[captureRange].trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return nil
}

private func pbxIDs(inList property: String, in object: String) throws -> [String] {
    let escapedProperty = NSRegularExpression.escapedPattern(for: property)
    let listExpression = try NSRegularExpression(
        pattern: #"\b"# + escapedProperty + #"\s*=\s*\((.*?)\);"#,
        options: [.dotMatchesLineSeparators]
    )
    let objectRange = NSRange(object.startIndex..<object.endIndex, in: object)
    guard
        let listMatch = listExpression.firstMatch(in: object, range: objectRange),
        let listRange = Range(listMatch.range(at: 1), in: object)
    else {
        return []
    }

    let list = String(object[listRange])
    let idExpression = try NSRegularExpression(pattern: #"\b[A-Fa-f0-9]{24}\b"#)
    let range = NSRange(list.startIndex..<list.endIndex, in: list)
    return idExpression.matches(in: list, range: range).compactMap { match in
        guard let matchRange = Range(match.range, in: list) else { return nil }
        return String(list[matchRange])
    }
}

private func appTargetSourceFindings(
    projectText: String,
    projectPath: String,
    repositoryRoot: URL,
    sourceRoot: URL
) throws -> [Finding] {
    let objects = try pbxObjects(in: projectText).mapValues(pbxWithoutComments)
    let nativeTargets = objects.values.filter { $0.contains("isa = PBXNativeTarget;") }
    let applicationTargets = try nativeTargets.filter { object in
        return try pbxScalar("productType", in: object) == "com.apple.product-type.application"
    }
    guard applicationTargets.count == 1, let target = applicationTargets.first else {
        return [
            Finding(
                path: projectPath,
                line: 1,
                message: "The project must contain exactly one application target"
            )
        ]
    }
    let unitTestTargets = try nativeTargets.filter { object in
        return try pbxScalar("productType", in: object) == "com.apple.product-type.bundle.unit-test"
    }
    guard
        nativeTargets.count == 2,
        unitTestTargets.count == 1,
        let unitTestTarget = unitTestTargets.first,
        try pbxScalar("name", in: unitTestTarget) == "HippocratesTests"
    else {
        return [
            Finding(
                path: projectPath,
                line: 1,
                message: "The project is limited to one application target and one unit-test target"
            )
        ]
    }
    guard try pbxScalar("name", in: target) == "Hippocrates" else {
        return [Finding(path: projectPath, line: 1, message: "The application target must be Hippocrates")]
    }

    let phaseIDs = try pbxIDs(inList: "buildPhases", in: target)
    let shellPhaseIDs = phaseIDs.filter { objects[$0]?.contains("isa = PBXShellScriptBuildPhase;") == true }
    let sourcePhaseIDs = phaseIDs.filter { id in
        objects[id]?.contains("isa = PBXSourcesBuildPhase;") == true
    }
    let frameworkPhaseIDs = phaseIDs.filter { objects[$0]?.contains("isa = PBXFrameworksBuildPhase;") == true }
    let resourcePhaseIDs = phaseIDs.filter { objects[$0]?.contains("isa = PBXResourcesBuildPhase;") == true }
    guard
        phaseIDs.count == 4,
        shellPhaseIDs.count == 1,
        sourcePhaseIDs.count == 1,
        frameworkPhaseIDs.count == 1,
        resourcePhaseIDs.count == 1,
        phaseIDs.first == shellPhaseIDs.first,
        let shellPhase = shellPhaseIDs.first.flatMap({ objects[$0] }),
        let sourcePhase = sourcePhaseIDs.first.flatMap({ objects[$0] }),
        let frameworkPhase = frameworkPhaseIDs.first.flatMap({ objects[$0] })
    else {
        return [
            Finding(
                path: projectPath,
                line: 1,
                message: "The app target build phases changed outside the reviewed offline architecture"
            )
        ]
    }
    let expectedShellScript = #"exec xcrun swift -module-cache-path \"$DERIVED_FILE_DIR/HippocratesBoundaryModuleCache\" \"$SRCROOT/Scripts/NetworkBoundaryScanner.swift\" --build-check \"$SRCROOT\"\n"#
    guard
        try pbxScalar("name", in: shellPhase) == "Enforce Offline Boundary",
        try pbxScalar("alwaysOutOfDate", in: shellPhase) == "1",
        try pbxScalar("buildActionMask", in: shellPhase) == "2147483647",
        try pbxScalar("runOnlyForDeploymentPostprocessing", in: shellPhase) == "0",
        try pbxScalar("shellPath", in: shellPhase) == "/bin/sh",
        try pbxScalar("shellScript", in: shellPhase) == expectedShellScript
    else {
        return [Finding(path: projectPath, line: 1, message: "The offline boundary phase was altered or disabled")]
    }
    guard
        try pbxIDs(inList: "dependencies", in: target).isEmpty,
        try pbxIDs(inList: "buildRules", in: target).isEmpty,
        try pbxIDs(inList: "files", in: frameworkPhase).isEmpty
    else {
        return [
            Finding(
                path: projectPath,
                line: 1,
                message: "App dependencies, custom build rules, and linked frameworks are forbidden"
            )
        ]
    }

    let testPhaseIDs = try pbxIDs(inList: "buildPhases", in: unitTestTarget)
    let testSourcePhaseIDs = testPhaseIDs.filter { objects[$0]?.contains("isa = PBXSourcesBuildPhase;") == true }
    let testFrameworkPhaseIDs = testPhaseIDs.filter {
        objects[$0]?.contains("isa = PBXFrameworksBuildPhase;") == true
    }
    let testResourcePhaseIDs = testPhaseIDs.filter {
        objects[$0]?.contains("isa = PBXResourcesBuildPhase;") == true
    }
    guard
        testPhaseIDs.count == 3,
        testSourcePhaseIDs.count == 1,
        testFrameworkPhaseIDs.count == 1,
        testResourcePhaseIDs.count == 1,
        let testSourcePhase = testSourcePhaseIDs.first.flatMap({ objects[$0] }),
        let testFrameworkPhase = testFrameworkPhaseIDs.first.flatMap({ objects[$0] }),
        try pbxIDs(inList: "files", in: testFrameworkPhase).isEmpty,
        try pbxIDs(inList: "buildRules", in: unitTestTarget).isEmpty,
        try pbxIDs(inList: "dependencies", in: unitTestTarget).count == 1
    else {
        return [
            Finding(
                path: projectPath,
                line: 1,
                message: "The unit-test target build topology changed outside review"
            )
        ]
    }

    var parentByChild: [String: String] = [:]
    for (groupID, object) in objects where object.contains("isa = PBXGroup;") {
        for childID in try pbxIDs(inList: "children", in: object) {
            if let existingParent = parentByChild[childID], existingParent != groupID {
                return [
                    Finding(
                        path: projectPath,
                        line: 1,
                        message: "PBX object \(childID) belongs to more than one group"
                    )
                ]
            }
            parentByChild[childID] = groupID
        }
    }

    func resolvedFileURL(for fileReferenceID: String) throws -> URL? {
        guard
            let fileReference = objects[fileReferenceID],
            fileReference.contains("isa = PBXFileReference;"),
            let filePath = try pbxScalar("path", in: fileReference)
        else {
            return nil
        }

        let sourceTree = try pbxScalar("sourceTree", in: fileReference)
        guard sourceTree == "<group>" || sourceTree == "SOURCE_ROOT" else {
            return nil
        }

        if sourceTree == "SOURCE_ROOT" {
            return repositoryRoot.appendingPathComponent(filePath).standardizedFileURL
        }

        var components = [filePath]
        var ancestorID = parentByChild[fileReferenceID]
        var visited: Set<String> = []
        while let groupID = ancestorID {
            guard visited.insert(groupID).inserted else { return nil }
            guard let group = objects[groupID] else { return nil }
            guard (try pbxScalar("sourceTree", in: group)) == "<group>" else { return nil }
            if let groupPath = try pbxScalar("path", in: group), !groupPath.isEmpty {
                components.insert(groupPath, at: 0)
            }
            ancestorID = parentByChild[groupID]
        }

        return components.reduce(repositoryRoot) { partialURL, component in
            partialURL.appendingPathComponent(component)
        }.standardizedFileURL
    }

    let appBuildFileIDs = try pbxIDs(inList: "files", in: sourcePhase)
    let testBuildFileIDs = try pbxIDs(inList: "files", in: testSourcePhase)
    guard !appBuildFileIDs.isEmpty, !testBuildFileIDs.isEmpty else {
        return [Finding(path: projectPath, line: 1, message: "Hippocrates app target has no compiled source")]
    }

    func compiledSourceFindings(
        buildFileIDs: [String],
        allowedRoot: URL,
        targetLabel: String
    ) throws -> [Finding] {
        let allowedRootPath = allowedRoot.resolvingSymlinksInPath().standardizedFileURL.path
        var findings: [Finding] = []

        for buildFileID in buildFileIDs {
            guard
                let buildFile = objects[buildFileID],
                buildFile.contains("isa = PBXBuildFile;"),
                let fileReferenceID = try pbxScalar("fileRef", in: buildFile)?
                    .split(separator: " ").first.map(String.init),
                let sourceURL = try resolvedFileURL(for: fileReferenceID)
            else {
                findings.append(
                    Finding(path: projectPath, line: 1, message: "A \(targetLabel) source reference could not be resolved")
                )
                continue
            }

            let resolvedSource = sourceURL.resolvingSymlinksInPath().standardizedFileURL
            let isInsideSourceRoot = resolvedSource.path.hasPrefix(allowedRootPath + "/")
            if !isInsideSourceRoot {
                findings.append(
                    Finding(
                        path: sourceURL.path,
                        line: 1,
                        message: "\(targetLabel) source must live beneath \(allowedRoot.lastPathComponent)/"
                    )
                )
                continue
            }

            guard resolvedSource.pathExtension.lowercased() == "swift" else {
                findings.append(
                    Finding(
                        path: sourceURL.path,
                        line: 1,
                        message: "Only Swift source may be compiled into the \(targetLabel)"
                    )
                )
                continue
            }

            if !FileManager.default.fileExists(atPath: resolvedSource.path) {
                findings.append(Finding(path: sourceURL.path, line: 1, message: "\(targetLabel) source file is missing"))
            }
        }

        return findings
    }

    let testSourceRoot = repositoryRoot.appendingPathComponent("HippocratesTests", isDirectory: true)
    return try compiledSourceFindings(
        buildFileIDs: appBuildFileIDs,
        allowedRoot: sourceRoot,
        targetLabel: "App-target"
    ) + compiledSourceFindings(
        buildFileIDs: testBuildFileIDs,
        allowedRoot: testSourceRoot,
        targetLabel: "Unit-test target"
    )
}

private func repositoryFindings(at repositoryRoot: URL) throws -> [Finding] {
    let sourceRoot = repositoryRoot.appendingPathComponent("Hippocrates", isDirectory: true)
    let projectFile = repositoryRoot
        .appendingPathComponent("Hippocrates.xcodeproj", isDirectory: true)
        .appendingPathComponent("project.pbxproj")

    guard FileManager.default.fileExists(atPath: sourceRoot.path) else {
        return [Finding(path: sourceRoot.path, line: 1, message: "Shipping source directory is missing")]
    }

    var results: [Finding] = []
    for file in swiftFiles(under: sourceRoot) {
        let source = try String(contentsOf: file, encoding: .utf8)
        results.append(contentsOf: try findings(in: source, path: file.path))

        let visibleSource = sourceWithoutComments(source)
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

    // Tests may carry citation URL fixtures, but they may not contain actual
    // networking APIs or network-opening UI. This keeps "zero networking code"
    // repo-wide without rejecting a valid Citation.urlString round-trip case.
    let testRoot = repositoryRoot.appendingPathComponent("HippocratesTests", isDirectory: true)
    for file in swiftFiles(under: testRoot) {
        let source = try String(contentsOf: file, encoding: .utf8)
        let allowedTestMessages: Set<String> = [
            "Hard-coded web address literals are forbidden in shipping source",
            "Foundation URL values are forbidden in shipping code; use FileDocument or Data transfer",
            "contentsOf URL loading is forbidden in shipping code",
            "URL-backed streams are forbidden in shipping code"
        ]
        results.append(
            contentsOf: try findings(in: source, path: file.path).filter {
                !allowedTestMessages.contains($0.message)
            }
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

    guard FileManager.default.fileExists(atPath: projectFile.path) else {
        results.append(Finding(path: projectFile.path, line: 1, message: "Xcode project file is missing"))
        return results
    }

    let projectText = try String(contentsOf: projectFile, encoding: .utf8)
    for rule in projectRules where projectText.contains(rule.token) {
        results.append(Finding(path: projectFile.path, line: 1, message: rule.message))
    }
    results.append(
        contentsOf: try appTargetSourceFindings(
            projectText: projectText,
            projectPath: projectFile.path,
            repositoryRoot: repositoryRoot,
            sourceRoot: sourceRoot
        )
    )

    let forbiddenPackageFiles = ["Package.swift", "Package.resolved"]
    if let enumerator = FileManager.default.enumerator(
        at: repositoryRoot,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) {
        for case let fileURL as URL in enumerator
        where forbiddenPackageFiles.contains(fileURL.lastPathComponent) {
            results.append(
                Finding(
                    path: fileURL.path,
                    line: 1,
                    message: "Swift Package files are forbidden; the project has zero SPM dependencies"
                )
            )
        }
    }

    return results
}

private func runSelfTests() throws {
    struct Case {
        let name: String
        let source: String
        let expectedFindingCount: Int
    }

    let cases = [
        Case(name: "live URLSession", source: "let client = URLSession.shared", expectedFindingCount: 1),
        Case(name: "live NSURLConnection", source: "let client: NSURLConnection", expectedFindingCount: 1),
        Case(name: "live NWConnection", source: "let client: NWConnection", expectedFindingCount: 1),
        Case(name: "live CFSocket", source: "let socket: CFSocket", expectedFindingCount: 1),
        Case(name: "live WKWebView", source: "let browser = WKWebView()", expectedFindingCount: 1),
        Case(
            name: "live SFSafariViewController",
            source: "let browser: SFSafariViewController",
            expectedFindingCount: 1
        ),
        Case(name: "live URLRequest", source: "let request: URLRequest", expectedFindingCount: 1),
        Case(name: "live openURL", source: "let action: OpenURLAction", expectedFindingCount: 1),
        Case(name: "live Link", source: "let view = Link(\"Source\", destination: value)", expectedFindingCount: 1),
        Case(
            name: "URL-backed ShareLink",
            source: "let view = ShareLink(item: runtimeURL)",
            expectedFindingCount: 1
        ),
        Case(
            name: "live UIApplication.open",
            source: "UIApplication.shared.open(value)",
            expectedFindingCount: 1
        ),
        Case(name: "live framework import", source: "import Network", expectedFindingCount: 1),
        Case(name: "Foundation URL value", source: "let destination: URL", expectedFindingCount: 1),
        Case(name: "Foundation URL loader", source: "let data = Data(contentsOf: value)", expectedFindingCount: 1),
        Case(name: "line comment", source: "// URLSession.shared", expectedFindingCount: 0),
        Case(
            name: "nested block comments",
            source: "/* outer /* URLSession.shared */ still comment */ let value = 1",
            expectedFindingCount: 0
        ),
        Case(
            name: "web address literal",
            source: "let endpoint = \"https://example.invalid\"",
            expectedFindingCount: 1
        ),
        Case(
            name: "raw web address literal",
            source: "let endpoint = #\"https://example.invalid\"#",
            expectedFindingCount: 1
        ),
        Case(
            name: "extended regex cannot hide live code",
            source: "let regex = #/x//#; let client = URLSession.shared",
            expectedFindingCount: 1
        ),
        Case(name: "ShareLink is allowed", source: "let view = ShareLink(item: document)", expectedFindingCount: 0),
        Case(name: "citation storage is allowed", source: "var urlString: String?", expectedFindingCount: 0)
    ]

    for testCase in cases {
        let result = try findings(in: testCase.source, path: testCase.name)
        guard result.count == testCase.expectedFindingCount else {
            throw NSError(
                domain: "NetworkBoundaryScannerTests",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "\(testCase.name): expected \(testCase.expectedFindingCount) finding(s), got \(result.count)"
                ]
            )
        }
    }

    let compliantIntervention = """
    final class Intervention {
        var id: UUID
        var timestamp: Date
        var type: InterventionType?
        var drugClass: DrugClass?
        var serviceLine: ServiceLine?
        var acceptance: Acceptance
        var costAvoidanceCents: Int
        var minutesSpent: Int?
        var diQuestion: DIQuestion?
    }
    """
    guard try interventionArchitectureFindings(
        in: compliantIntervention,
        path: "compliant intervention"
    ).isEmpty else {
        throw NSError(
            domain: "NetworkBoundaryScannerTests",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Compliant Intervention was rejected"]
        )
    }

    let unsafeIntervention = compliantIntervention.replacingOccurrences(
        of: "}",
        with: "let narrative: Optional<Swift.String>\n}"
    )
    guard try interventionArchitectureFindings(
        in: unsafeIntervention,
        path: "unsafe intervention"
    ).count == 1 else {
        throw NSError(
            domain: "NetworkBoundaryScannerTests",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Intervention free-text self-test did not fail"]
        )
    }

    let wrongTypeIntervention = compliantIntervention.replacingOccurrences(
        of: "var minutesSpent: Int?",
        with: "var minutesSpent: Optional<Swift.String>"
    )
    guard try interventionArchitectureFindings(
        in: wrongTypeIntervention,
        path: "wrong-type intervention"
    ).count == 1 else {
        throw NSError(
            domain: "NetworkBoundaryScannerTests",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "Intervention property-type self-test did not fail"]
        )
    }

    let inferredTextIntervention = compliantIntervention.replacingOccurrences(
        of: "var minutesSpent: Int?",
        with: "var minutesSpent: Int?\nvar notes = \"\""
    )
    guard try interventionArchitectureFindings(
        in: inferredTextIntervention,
        path: "inferred-text intervention"
    ).count == 1 else {
        throw NSError(
            domain: "NetworkBoundaryScannerTests",
            code: 5,
            userInfo: [NSLocalizedDescriptionKey: "Inferred Intervention property self-test did not fail"]
        )
    }

    let backtickedTextIntervention = compliantIntervention.replacingOccurrences(
        of: "var minutesSpent: Int?",
        with: "var minutesSpent: Int?\nvar `notes`: String"
    )
    guard try interventionArchitectureFindings(
        in: backtickedTextIntervention,
        path: "backticked-text intervention"
    ).count == 1 else {
        throw NSError(
            domain: "NetworkBoundaryScannerTests",
            code: 6,
            userInfo: [NSLocalizedDescriptionKey: "Backticked Intervention property self-test did not fail"]
        )
    }

    let targetMembershipFixture = #"""
    objects = {
        AAAAAAAAAAAAAAAAAAAAAAAA = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = External.swift; sourceTree = "<group>"; };
        BBBBBBBBBBBBBBBBBBBBBBBB = {isa = PBXFileReference; lastKnownFileType = sourcecode.c.objc; path = Unsafe.m; sourceTree = "<group>"; };
        888888888888888888888888 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = FixtureTests.swift; sourceTree = "<group>"; };
        CCCCCCCCCCCCCCCCCCCCCCCC = {isa = PBXBuildFile; fileRef = AAAAAAAAAAAAAAAAAAAAAAAA; };
        DDDDDDDDDDDDDDDDDDDDDDDD = {isa = PBXBuildFile; fileRef = BBBBBBBBBBBBBBBBBBBBBBBB; };
        999999999999999999999999 = {isa = PBXBuildFile; fileRef = 888888888888888888888888; };
        EEEEEEEEEEEEEEEEEEEEEEEE = {isa = PBXGroup; children = (AAAAAAAAAAAAAAAAAAAAAAAA, FFFFFFFFFFFFFFFFFFFFFFFF, 000000000000000000000000,); sourceTree = "<group>"; };
        FFFFFFFFFFFFFFFFFFFFFFFF = {isa = PBXGroup; children = (BBBBBBBBBBBBBBBBBBBBBBBB,); path = Hippocrates; sourceTree = "<group>"; };
        000000000000000000000000 = {isa = PBXGroup; children = (888888888888888888888888,); path = HippocratesTests; sourceTree = "<group>"; };
        111111111111111111111111 = {isa = PBXSourcesBuildPhase; files = (CCCCCCCCCCCCCCCCCCCCCCCC, DDDDDDDDDDDDDDDDDDDDDDDD,); };
        222222222222222222222222 = {isa = PBXNativeTarget; buildPhases = (333333333333333333333333, 111111111111111111111111, 444444444444444444444444, 555555555555555555555555,); buildRules = (); dependencies = (); name = Hippocrates; productType = "com.apple.product-type.application"; };
        333333333333333333333333 = {isa = PBXShellScriptBuildPhase; alwaysOutOfDate = 1; buildActionMask = 2147483647; name = "Enforce Offline Boundary"; runOnlyForDeploymentPostprocessing = 0; shellPath = /bin/sh; shellScript = "exec xcrun swift -module-cache-path \"$DERIVED_FILE_DIR/HippocratesBoundaryModuleCache\" \"$SRCROOT/Scripts/NetworkBoundaryScanner.swift\" --build-check \"$SRCROOT\"\n"; };
        444444444444444444444444 = {isa = PBXFrameworksBuildPhase; files = (); };
        555555555555555555555555 = {isa = PBXResourcesBuildPhase; files = (); };
        777777777777777777777777 = {isa = PBXNativeTarget; buildPhases = (1234567890ABCDEF12345678, 234567890ABCDEF123456789, 34567890ABCDEF1234567890,); buildRules = (); dependencies = (4567890ABCDEF12345678901,); name = HippocratesTests; productType = "com.apple.product-type.bundle.unit-test"; };
        1234567890ABCDEF12345678 = {isa = PBXSourcesBuildPhase; files = (999999999999999999999999,); };
        234567890ABCDEF123456789 = {isa = PBXFrameworksBuildPhase; files = (); };
        34567890ABCDEF1234567890 = {isa = PBXResourcesBuildPhase; files = (); };
        4567890ABCDEF12345678901 = {isa = PBXTargetDependency; };
    };
    """#
    let fixtureRoot = URL(fileURLWithPath: "/tmp/HippocratesBoundaryScannerFixture", isDirectory: true)
    let targetFindings = try appTargetSourceFindings(
        projectText: targetMembershipFixture,
        projectPath: "/tmp/project.pbxproj",
        repositoryRoot: fixtureRoot,
        sourceRoot: fixtureRoot.appendingPathComponent("Hippocrates", isDirectory: true)
    )
    guard
        targetFindings.contains(where: { $0.message.contains("must live beneath") }),
        targetFindings.contains(where: { $0.message.contains("Only Swift source") })
    else {
        throw NSError(
            domain: "NetworkBoundaryScannerTests",
            code: 7,
            userInfo: [NSLocalizedDescriptionKey: "App-target membership self-test did not fail closed"]
        )
    }

    let duplicateAppFixture = targetMembershipFixture.replacingOccurrences(
        of: "\n};",
        with: "\n666666666666666666666666 = {isa = PBXNativeTarget; name = Decoy; productType = \"com.apple.product-type.application\"; };\n};"
    )
    let duplicateAppFindings = try appTargetSourceFindings(
        projectText: duplicateAppFixture,
        projectPath: "/tmp/project.pbxproj",
        repositoryRoot: fixtureRoot,
        sourceRoot: fixtureRoot.appendingPathComponent("Hippocrates", isDirectory: true)
    )
    guard duplicateAppFindings.contains(where: { $0.message.contains("exactly one application target") }) else {
        throw NSError(
            domain: "NetworkBoundaryScannerTests",
            code: 8,
            userInfo: [NSLocalizedDescriptionKey: "Duplicate app-target self-test did not fail"]
        )
    }

    let disabledPhaseFixture = targetMembershipFixture.replacingOccurrences(
        of: "exec xcrun swift",
        with: "echo scanner-disabled"
    )
    let disabledPhaseFindings = try appTargetSourceFindings(
        projectText: disabledPhaseFixture,
        projectPath: "/tmp/project.pbxproj",
        repositoryRoot: fixtureRoot,
        sourceRoot: fixtureRoot.appendingPathComponent("Hippocrates", isDirectory: true)
    )
    guard disabledPhaseFindings.contains(where: { $0.message.contains("altered or disabled") }) else {
        throw NSError(
            domain: "NetworkBoundaryScannerTests",
            code: 9,
            userInfo: [NSLocalizedDescriptionKey: "Disabled boundary-phase self-test did not fail"]
        )
    }

    let commentTrap = #"/* shellScript = "expected"; */ shellScript = "disabled";"#
    guard try pbxScalar("shellScript", in: pbxWithoutComments(commentTrap)) == "disabled" else {
        throw NSError(
            domain: "NetworkBoundaryScannerTests",
            code: 10,
            userInfo: [NSLocalizedDescriptionKey: "PBX comment sanitization self-test failed"]
        )
    }

    let externalTestFixture = targetMembershipFixture.replacingOccurrences(
        of: "path = HippocratesTests;",
        with: "path = ExternalTests;"
    )
    let externalTestFindings = try appTargetSourceFindings(
        projectText: externalTestFixture,
        projectPath: "/tmp/project.pbxproj",
        repositoryRoot: fixtureRoot,
        sourceRoot: fixtureRoot.appendingPathComponent("Hippocrates", isDirectory: true)
    )
    guard externalTestFindings.contains(where: { $0.message.contains("Unit-test target source must live") }) else {
        throw NSError(
            domain: "NetworkBoundaryScannerTests",
            code: 11,
            userInfo: [NSLocalizedDescriptionKey: "External unit-test source self-test did not fail"]
        )
    }

    print("Architecture boundary scanner self-tests passed (\(cases.count + 10) cases).")
}

private func emit(_ findings: [Finding]) {
    for finding in findings {
        let diagnostic = "\(finding.path):\(finding.line): error: \(finding.message)\n"
        FileHandle.standardError.write(Data(diagnostic.utf8))
    }
}

private func printUsageAndExit() -> Never {
    let usage = "Usage: NetworkBoundaryScanner.swift --self-test | --build-check <repository-root>\n"
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
        let results = try repositoryFindings(at: repositoryRoot)
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
