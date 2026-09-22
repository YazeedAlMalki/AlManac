import Foundation

/// Import automation for laboratory report data: CSV → `LabReportDraft` and
/// `LabObservationDraft` rows, written through the same `LabStore` seams a
/// person uses (`upsertReport` / `record`). Arrival-order rules, conflict
/// holding and revision fingerprints therefore apply to imports exactly as
/// they do to manual entry.
///
/// Deliberately conservative, per `docs/features/laboratory.md`:
/// - Source text is preserved verbatim (each value's `sourceValueText`, units,
///   ranges and flags are stored exactly as supplied, never parsed apart).
/// - Unknown is a value: a blank date stays unknown; a blank value is recorded
///   as an absent observation with `notReportedBySource`, never invented.
/// - A numeric value with a leading comparator (`<`, `≤`, `>`, `≥`, `~`) is
///   stored quantitative with that comparator and the parsed number; any
///   non-numeric value is stored as `.text` with the exact source string.
///   This classifies the value; it never edits the reported fact.
/// - Rows are grouped into one report by `source_report_id`; the group's first
///   row carries the report-level fields.
/// - Every observation receives a stable `source_observation_id` (the column's
///   value, or a deterministic group-row key), so re-importing the same file
///   is a no-op through the existing fingerprint machinery instead of
///   duplicating rows.
public enum LabReportCSVImport {

    /// Column order of the CSV. Eleven columns; no header row.
    ///
    /// `source_report_id`, `report_date`, `laboratory_name`, `header_text`,
    /// `test_name`, `value`, `unit`, `range`, `flag`, `comment`,
    /// `source_observation_id`
    public static let columnCount = 11

    /// The `sourceSystem` stamped on reports and observations created here.
    public static let importSourceSystem = "almanac.csv-import"

    /// Parses `csv` and writes every well-formed row through `store`.
    ///
    /// Returns an aggregate result; invalid rows are collected, not dropped
    /// silently. A report whose metadata changed since the last import is
    /// flagged `conflict` and held for a person to resolve — arrival order is
    /// not authority.
    public static func importReports(csv: String,
                                     into store: LabStore,
                                     sourceSystem: String = importSourceSystem) throws -> LabCSVImportResult {
        var result = LabCSVImportResult()
        let rows = parse(csv)

        // Group rows by report key, preserving first-seen order. Rows for the
        // same report may be interleaved with another report's rows.
        var groupOrder: [String] = []
        var groups: [String: [[String]]] = [:]
        for cells in rows {
            guard cells.count == columnCount, let reportID = clean(cells[0]) else {
                result.invalidRows.append(shortened(cells.joined(separator: ",")))
                continue
            }
            if groups[reportID] == nil { groupOrder.append(reportID) }
            groups[reportID, default: []].append(cells)
        }

        for reportID in groupOrder {
            guard let reportRows = groups[reportID] else { continue }
            result.groups += 1

            // Report-level fields come from the group's first row.
            let first = reportRows[0]
            var draft = LabReportDraft()
            draft.sourceSystem = sourceSystem
            draft.sourceReportID = reportID
            draft.laboratoryNameText = clean(first[2])
            draft.headerText = clean(first[3])
            if let date = clean(first[1]) {
                draft.reportedAt = PartialDateTime(text: date, precision: .day)
            }
            draft.entryOrigin = "csv-import"

            let outcome = try store.upsertReport(draft)
            switch outcome {
            case .created: result.reportsCreated += 1
            case .unchanged: result.reportsUnchanged += 1
            case .conflict: result.reportConflicts += 1
            case .updated, .replayIgnored, .staleIgnored: break
            }

            for (rowIndex, cells) in reportRows.enumerated() {
                guard let testName = clean(cells[4]) else {
                    result.invalidRows.append(shortened(cells.joined(separator: ",")))
                    continue
                }

                var observation = LabObservationDraft()
                observation.reportID = outcome.reportID
                observation.sourceSystem = sourceSystem
                observation.sourceObservationID = clean(cells[10]) ?? "\(reportID)#\(rowIndex + 1)"
                observation.collectedAt = draft.reportedAt

                var content = LabRevisionContent()
                content.contentOrigin = .sourceExtraction
                content.actor = "csv-import"
                content.sourceAnalyteText = testName
                content.sourceValueText = clean(cells[5])
                content.unitText = clean(cells[6])
                content.rangeText = clean(cells[7])
                content.flagText = clean(cells[8])
                content.commentText = clean(cells[9])

                if let value = content.sourceValueText, !value.isEmpty {
                    if let parsed = parseNumeric(value) {
                        content.valueType = .quantitative
                        content.comparator = parsed.comparator
                        content.numericValue = parsed.value
                    } else {
                        content.valueType = .text
                        content.textValue = value
                    }
                } else {
                    content.valueType = .absent
                    content.missingReason = .notReportedBySource
                }

                let recorded = try store.record(observation, content: content)
                switch recorded {
                case .created: result.observationsCreated += 1
                case .unchanged: result.observationsUnchanged += 1
                case .revised: result.observationsRevised += 1
                }
            }
        }
        return result
    }

    // MARK: - CSV parsing (RFC 4180-lite: quoted fields, doubled quotes,
    // embedded commas and newlines, CRLF, BOM).

    static func parse(_ text: String) -> [[String]] {
        var source = text
        if source.hasPrefix("\u{FEFF}") { source.removeFirst() }

        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let characters = Array(source)
        var index = 0

        func finishRow() {
            row.append(field)
            field = ""
            if row != [""] { rows.append(row) }
            row = []
        }

        while index < characters.count {
            let c = characters[index]
            if inQuotes {
                if c == "\"" {
                    if index + 1 < characters.count && characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 2
                        continue
                    }
                    inQuotes = false
                    index += 1
                    continue
                }
                field.append(c)
                index += 1
                continue
            }
            switch c {
            case "\"":
                inQuotes = true
                index += 1
            case ",":
                row.append(field)
                field = ""
                index += 1
            case "\n":
                finishRow()
                index += 1
            case "\r":
                if index + 1 < characters.count && characters[index + 1] == "\n" { index += 1 }
                finishRow()
                index += 1
            default:
                field.append(c)
                index += 1
            }
        }
        finishRow()
        return rows
    }

    // MARK: - Value classification

    private struct NumericParts {
        let comparator: LabComparator
        let value: Double
    }

    private static func parseNumeric(_ cell: String) -> NumericParts? {
        var text = cell.trimmingCharacters(in: .whitespacesAndNewlines)
        var comparator = LabComparator.none
        let markers: [(String, LabComparator)] = [
            ("~", .approx), ("<=", .lte), (">=", .gte),
            ("<", .lt), (">", .gt),
            ("\u{2264}", .lte), ("\u{2265}", .gte),
        ]
        for (symbol, kind) in markers where text.hasPrefix(symbol) {
            comparator = kind
            text = String(text.dropFirst(symbol.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        guard let value = Double(text) else { return nil }
        return NumericParts(comparator: comparator, value: value)
    }

    private static func clean(_ cell: String) -> String? {
        let trimmed = cell.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func shortened(_ text: String, limit: Int = 120) -> String {
        text.count <= limit ? text : String(text.prefix(limit)) + "…"
    }
}

/// Aggregate outcome of one `LabReportCSVImport.importReports` call.
public struct LabCSVImportResult: Sendable, Equatable {
    public var groups = 0
    public var reportsCreated = 0
    public var reportsUnchanged = 0
    public var reportConflicts = 0
    public var observationsCreated = 0
    public var observationsUnchanged = 0
    public var observationsRevised = 0
    public var invalidRows: [String] = []

    public init() {}

    public var invalidRowCount: Int { invalidRows.count }
    public var needsHumanResolution: Bool { reportConflicts > 0 }
}