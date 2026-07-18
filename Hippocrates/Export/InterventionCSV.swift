import Foundation

/// Deterministic RFC 4180 CSV for the intervention ledger (A-010). Columns and
/// their order are versioned: changing either requires bumping `formatVersion`
/// and an explicit review, because managers' saved spreadsheets depend on it.
enum InterventionCSV {
    static let formatVersion = 1

    /// Column order is part of the v1 contract.
    static let header = "timestamp_utc,intervention_type,drug_class,service_line,acceptance,cost_avoidance_cents,minutes_spent"

    /// UTC internet date-time keeps the export locale- and device-independent.
    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    /// Rows are sorted by every column so identical inputs always produce
    /// identical bytes regardless of fetch order. Lines end with CRLF per
    /// RFC 4180, including a trailing terminator on the final row.
    static func document(rows: [SummaryInputRow]) -> String {
        let sorted = rows.sorted(by: rowOrder)
        var lines: [String] = [header]
        for row in sorted {
            lines.append(line(for: row))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    static func line(for row: SummaryInputRow) -> String {
        let fields = [
            timestampFormatter.string(from: row.timestamp),
            textField(row.typeLabel ?? ""),
            textField(row.drugClassLabel ?? ""),
            textField(row.serviceLineLabel ?? ""),
            row.acceptance.rawValue,
            row.costAvoidanceCents.map(String.init) ?? "",
            row.minutesSpent.map(String.init) ?? ""
        ]
        return fields.joined(separator: ",")
    }

    /// Text cells are neutralized against spreadsheet formula execution, then
    /// RFC 4180-quoted. The stored taxonomy value itself is never changed.
    static func textField(_ raw: String) -> String {
        quoted(neutralized(raw))
    }

    /// A leading formula marker gets an apostrophe prefix so spreadsheet
    /// applications treat the cell as text instead of executing it.
    static func neutralized(_ raw: String) -> String {
        guard let first = raw.first else {
            return raw
        }
        if first == "=" || first == "+" || first == "-" || first == "@" {
            return "'" + raw
        }
        return raw
    }

    /// RFC 4180: fields containing commas, quotes, or line breaks are wrapped
    /// in quotes with interior quotes doubled.
    static func quoted(_ raw: String) -> String {
        let needsQuoting = raw.contains(",")
            || raw.contains("\"")
            || raw.contains("\r")
            || raw.contains("\n")
        guard needsQuoting else {
            return raw
        }
        let doubled = raw.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"" + doubled + "\""
    }

    private static func rowOrder(_ left: SummaryInputRow, _ right: SummaryInputRow) -> Bool {
        if left.timestamp != right.timestamp {
            return left.timestamp < right.timestamp
        }
        let leftKey = comparisonKey(left)
        let rightKey = comparisonKey(right)
        if leftKey != rightKey {
            return leftKey < rightKey
        }
        return false
    }

    /// Newline is a safe tie-breaker separator: taxonomy labels are validated
    /// single-line and acceptance raw values never contain line breaks. (The
    /// boundary parser forbids Unicode escapes, so no control-character
    /// separator is spelled here.)
    private static func comparisonKey(_ row: SummaryInputRow) -> String {
        [
            row.typeLabel ?? "",
            row.drugClassLabel ?? "",
            row.serviceLineLabel ?? "",
            row.acceptance.rawValue,
            row.costAvoidanceCents.map(String.init) ?? "",
            row.minutesSpent.map(String.init) ?? ""
        ].joined(separator: "\n")
    }
}
