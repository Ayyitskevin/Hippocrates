import Foundation

/// Presentation-ready values for one portfolio entry. Labels arrive
/// pre-rendered so this formatter stays pure text over Sendable values.
struct PortfolioCitation: Equatable, Sendable {
    let tierLabel: String
    let title: String
    let locator: String
    let accessedDate: Date
    let urlText: String?
}

struct PortfolioQuestion: Equatable, Sendable {
    let createdAt: Date
    let answeredAt: Date?
    let questionText: String
    let background: String
    let requestorLabel: String
    let classLabel: String
    let urgencyLabel: String
    let searchStrategy: String
    let answerText: String
    let citations: [PortfolioCitation]
    let didFollowUp: Bool
    let verifiedOn: Date
    let reviewAfter: Date
}

/// The DI portfolio: a plain-text document in the standard response order —
/// question, background, classification, search strategy, answer, references,
/// follow-up, verification. Deterministic: entries sort by creation date and
/// identical inputs produce identical bytes.
enum DIPortfolio {
    static func document(questions: [PortfolioQuestion]) -> String {
        let formatter = makeDateFormatter()
        let sorted = questions.sorted { left, right in
            if left.createdAt != right.createdAt {
                return left.createdAt < right.createdAt
            }
            return left.questionText < right.questionText
        }
        let entries = sorted.map { entry(for: $0, formatter: formatter) }
        return entries.joined(separator: "\n\n")
    }

    private static func entry(
        for question: PortfolioQuestion,
        formatter: ISO8601DateFormatter
    ) -> String {
        var lines: [String] = []
        lines.append("=== Drug Information Record ===")
        lines.append("Recorded: " + formatter.string(from: question.createdAt))
        lines.append("")
        lines.append("Question:")
        lines.append(question.questionText)
        lines.append("")
        lines.append("Background:")
        lines.append(question.background)
        lines.append("")
        lines.append(
            "Classification: " + question.classLabel
                + " | Requestor: " + question.requestorLabel
                + " | Urgency: " + question.urgencyLabel
        )
        lines.append("")
        lines.append("Search strategy:")
        lines.append(question.searchStrategy)
        lines.append("")
        lines.append("Answer:")
        lines.append(question.answerText)
        lines.append("")
        lines.append("References:")
        if question.citations.isEmpty {
            lines.append("None recorded")
        }
        for (index, citation) in question.citations.enumerated() {
            var line = String(index + 1) + ". [" + citation.tierLabel + "] " + citation.title
            if citation.locator.isEmpty == false {
                line += " - " + citation.locator
            }
            line += " (accessed " + formatter.string(from: citation.accessedDate) + ")"
            if let urlText = citation.urlText, urlText.isEmpty == false {
                line += " " + urlText
            }
            lines.append(line)
        }
        lines.append("")
        lines.append("Follow-up completed: " + (question.didFollowUp ? "Yes" : "No"))
        if question.answeredAt == nil {
            lines.append("Status: Draft")
        } else {
            lines.append("Verified: " + formatter.string(from: question.verifiedOn))
            lines.append("Review after: " + formatter.string(from: question.reviewAfter))
        }
        return lines.joined(separator: "\n")
    }

    /// Date-only UTC output keeps the document device-independent. The
    /// formatter is constructed per document; it is a non-Sendable class.
    private static func makeDateFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }
}
