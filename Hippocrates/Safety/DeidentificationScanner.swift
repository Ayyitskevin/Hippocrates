import Foundation

/// One potential identifier found in DI free text. The scan reports what it
/// matched and where; the review sheet requires an explicit disposition for
/// every finding before a save proceeds. Nothing is ever silently scrubbed.
struct DeidentificationFinding: Equatable, Sendable {
    enum Category: String, CaseIterable, Sendable {
        case phoneNumber
        case date
        case roomOrBed
        case ageOver89
        case medicalRecordNumber
    }

    let category: Category
    let fieldName: String
    let matchedText: String
    /// UTF-16 offset and length within the scanned field, for highlighting.
    let location: Int
    let length: Int
}

/// Pure pattern scan over DI text fields. Deliberately over-inclusive: a
/// false positive costs one "Not an identifier" tap, while a false negative
/// puts patient information in the store. The compliance controls remain the
/// schema (no identifier properties) and the user's judgment; this scan is a
/// safety aid, not a guarantee (see README).
enum DeidentificationScanner {
    /// When two patterns claim overlapping text, the earlier category in this
    /// order wins and the contained span is not reported twice.
    static let orderedCategories: [DeidentificationFinding.Category] = [
        .phoneNumber,
        .date,
        .roomOrBed,
        .ageOver89,
        .medicalRecordNumber,
    ]

    /// Literal parentheses are spelled as character classes ([(] and [)])
    /// because the boundary parser counts every backslash-parenthesis pair in
    /// source, including string contents, as executable interpolation.
    static let patternsByCategory: [DeidentificationFinding.Category: [String]] = [
        .phoneNumber: [
            "(?:[+]?1[-. ]?)?(?:[(]\\d{3}[)][-. ]?|\\b\\d{3}[-. ])\\d{3}[-. ]?\\d{4}\\b",
        ],
        .date: [
            "\\b\\d{1,2}/\\d{1,2}(?:/\\d{2,4})?\\b",
            "\\b\\d{1,2}-\\d{1,2}-\\d{2,4}\\b",
            "\\b\\d{4}-\\d{1,2}-\\d{1,2}\\b",
            "(?i)\\b(?:january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sept?|oct|nov|dec)[.]?\\s+\\d{1,2}(?:st|nd|rd|th)?(?:[,]?\\s+\\d{2,4})?\\b",
        ],
        .roomOrBed: [
            "(?i)\\b(?:room|rm|bed)\\s*[#:]?\\s*\\d{1,4}[a-z]?\\b",
        ],
        .ageOver89: [
            "(?i)\\b(?:9\\d|1[0-4]\\d)\\s*[-]?\\s*(?:years?|yrs?|yo|y/o)(?:\\s*[-]?\\s*old)?\\b",
            "(?i)\\bage[d]?\\s*[:]?\\s*(?:9\\d|1[0-4]\\d)\\b",
        ],
        .medicalRecordNumber: [
            "(?i)\\b(?:mrn|medical\\s+record(?:\\s+number)?|record\\s+no[.]?)\\s*[#:]?\\s*\\d{4,10}\\b",
            "(?<![\\d-])\\d{6,10}(?![\\d-])",
        ],
    ]

    /// The four guarded DI fields are scanned together at the save boundary.
    /// Field names travel with each finding so the review sheet can highlight
    /// the right editor.
    static func findings(
        in fields: [(fieldName: String, text: String)]
    ) -> [DeidentificationFinding] {
        fields.flatMap { findings(fieldName: $0.fieldName, text: $0.text) }
    }

    static func findings(fieldName: String, text: String) -> [DeidentificationFinding] {
        guard text.isEmpty == false else {
            return []
        }
        var results: [DeidentificationFinding] = []
        var claimedSpans: [Span] = []
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)

        for category in orderedCategories {
            for pattern in patternsByCategory[category] ?? [] {
                guard let expression = try? NSRegularExpression(pattern: pattern) else {
                    // Patterns are static source constants; compilation is
                    // proven by a dedicated test, so this branch is dead in a
                    // correct build and still fails safe by matching nothing.
                    continue
                }
                for match in expression.matches(in: text, range: fullRange) {
                    let span = Span(location: match.range.location, length: match.range.length)
                    guard claimedSpans.contains(where: { $0.contains(span) }) == false else {
                        continue
                    }
                    guard let textRange = Range(match.range, in: text) else {
                        continue
                    }
                    claimedSpans.append(span)
                    results.append(
                        DeidentificationFinding(
                            category: category,
                            fieldName: fieldName,
                            matchedText: String(text[textRange]),
                            location: span.location,
                            length: span.length
                        )
                    )
                }
            }
        }

        return results.sorted { left, right in
            if left.location != right.location {
                return left.location < right.location
            }
            return left.length > right.length
        }
    }

    private struct Span: Equatable {
        let location: Int
        let length: Int

        /// A span already claimed by a higher-priority category absorbs any
        /// span it fully contains, so one identifier is reported once.
        func contains(_ other: Span) -> Bool {
            other.location >= location
                && other.location + other.length <= location + length
        }
    }
}
