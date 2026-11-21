import Foundation

/// A person's own records in an open, documented format (remediation P1-5, the
/// portability half of GDPR Art. 20 and PDPL's access right; see
/// `SECURITY_PRIVACY_AUDIT.md` §7).
///
/// One UTF-8 JSON file:
///
/// ```
/// { "format": "almanac-export", "formatVersion": 1,
///   "exportedAt": "2026-10-22T09:30:00Z", "schemaVersion": 68,
///   "notes": "...",
///   "tables": {
///     "<table>": { "columns": ["a", "b"], "rowCount": 2, "rows": [[1, "x"], [2, null]] },
///     ... } }
/// ```
///
/// A row is an array in the order of `columns`. SQLite's types map to JSON as
/// `NULL` → `null`, `INTEGER`/`REAL` → number (a non-finite real → `null`, which
/// JSON cannot hold), `TEXT` → string, `BLOB` → `{"base64": "..."}`.
///
/// ## What is in it, and what is not
///
/// Every table the person's records live in, in full. Left out, and said so in the
/// file's `notes`:
///
/// - **Reference data shipped with the app or taken from public datasets**: food
///   and nutrient composition, the laboratory test catalogue, exercise sources,
///   recipe sources. These are credited under Settings → Attributions, are not the
///   person's, and make up nearly all of the database's size. Log rows refer to a
///   food by its reference, so the pairing is kept without repeating the dataset.
/// - **The app's own machinery and derived caches**: migrations, sync anchors,
///   backup manifest, prayer-time cache, trend and correlation snapshots.
/// - In the mixed food tables, only the rows of the `almanac` namespace, which is
///   where the person's own dishes are kept (the app also ships a few regional
///   dishes under it).
///
/// The file is **not encrypted**: it exists so the data can be read by people and
/// other software. The screen that offers it says so.
public struct DataExport {
    private let db: Database
    private let clock: any Clock

    public init(db: Database, clock: any Clock = SystemClock()) {
        self.db = db
        self.clock = clock
    }

    public struct Summary: Equatable, Sendable {
        public let tableCount: Int
        public let rowCount: Int
    }

    public enum ExportError: Error, CustomStringConvertible, Sendable {
        case cannotWrite(String)
        public var description: String {
            switch self {
            case .cannotWrite(let path): return localized("Could not write the export at %@", path)
            }
        }
    }

    /// Reference data and machinery, not the person's records (see the type's notes).
    static let excludedTables: Set<String> = [
        "schema_migrations", "backup_manifest", "sync_anchor",
        "nutrition_reference_import", "nutrition_food_merge", "nutrition_food_merge_import",
        "nutrition_source", "nutrition_nutrient", "nutrition_qualifier",
        "kitchen_ingredient", "kitchen_ingredient_food", "kitchen_recipe_source", "kitchen_recipe_import",
        "lab_catalog_alias", "lab_catalog_analyte", "lab_catalog_external_code", "lab_catalog_localization",
        "lab_panel", "lab_panel_member", "food_allergen",
        "exerciseSource", "exerciseMuscle",
        "prayer_times_cache", "trend_snapshot", "correlation_pair",
    ]

    /// Mixed tables, reduced to the rows a person can have made: those of the
    /// `almanac` namespace. Each predicate names a column; if the table has no such
    /// column the predicate is dropped and the whole table exported, which errs on
    /// the side of completeness.
    static let ownRowsOnly: [String: (column: String, predicate: String)] = [
        "nutrition_food": ("namespace", "\"namespace\" = 'almanac'"),
        "nutrition_food_name": ("food_ref", "\"food_ref\" LIKE 'almanac:%'"),
        "nutrition_value": ("food_ref", "\"food_ref\" LIKE 'almanac:%'"),
        "nutrition_portion": ("food_ref", "\"food_ref\" LIKE 'almanac:%'"),
        "nutrition_food_factor": ("food_ref", "\"food_ref\" LIKE 'almanac:%'"),
        "nutrition_dish": ("food_ref", "\"food_ref\" LIKE 'almanac:%'"),
        "nutrition_dish_component": ("dish_ref", "\"dish_ref\" LIKE 'almanac:%'"),
    ]

    static let notes = "Your own records. Food, nutrient, laboratory-catalogue and exercise reference data "
        + "from public datasets is not repeated here (see Attributions in the app); log rows refer to it "
        + "by reference. Internal bookkeeping tables and caches are left out. Rows are arrays in the order "
        + "of each table's columns; BLOB values are {\"base64\": ...}. This file is not encrypted."

    /// Writes the export to `path` (replaced if it exists) and returns what it holds.
    @discardableResult
    public func write(to path: String) throws -> Summary {
        let fm = FileManager.default
        let directory = (path as NSString).deletingLastPathComponent
        if !directory.isEmpty { try fm.createDirectory(atPath: directory, withIntermediateDirectories: true) }
        guard fm.createFile(atPath: path, contents: nil), let handle = FileHandle(forWritingAtPath: path) else {
            throw ExportError.cannotWrite(path)
        }
        defer { try? handle.close() }
        func text(_ value: String) -> String { Self.jsonString(value) }
        func put(_ string: String) throws { try handle.write(contentsOf: Data(string.utf8)) }

        let schemaVersion = try db.query("SELECT COALESCE(MAX(version), 0) AS v FROM schema_migrations;")
            .first?.int("v") ?? 0
        let exportedAt = ISO8601DateFormatter().string(from: clock.now)
        try put("{\n\"format\": \"almanac-export\",\n\"formatVersion\": 1,\n")
        try put("\"exportedAt\": \(text(exportedAt)),\n\"schemaVersion\": \(schemaVersion),\n")
        try put("\"notes\": \(text(Self.notes)),\n\"tables\": {")

        var tableCount = 0
        var rowCount = 0
        for table in try tableNames() {
            let columns = try columnNames(of: table)
            guard !columns.isEmpty else { continue }
            var sql = "SELECT * FROM \(quote(table))"
            if let own = Self.ownRowsOnly[table], columns.contains(own.column) {
                sql += " WHERE \(own.predicate)"
            }
            let rows = try db.query(sql + ";")
            var lines: [String] = []
            lines.reserveCapacity(rows.count)
            for row in rows {
                let cells = columns.map { cell(row[$0]) }
                lines.append("[" + cells.joined(separator: ",") + "]")
            }
            try put(tableCount == 0 ? "\n" : ",\n")
            try put("\(text(table)): {\"columns\": [\(columns.map(text).joined(separator: ","))], ")
            try put("\"rowCount\": \(rows.count), \"rows\": [\n" + lines.joined(separator: ",\n") + "\n]}")
            tableCount += 1
            rowCount += rows.count
        }
        try put("\n}\n}\n")
        return Summary(tableCount: tableCount, rowCount: rowCount)
    }

    // MARK: Internals

    private func tableNames() throws -> [String] {
        try db.query("""
            SELECT name FROM sqlite_master
            WHERE type = 'table' AND name NOT LIKE 'sqlite!_%' ESCAPE '!'
            ORDER BY name;
            """)
            .compactMap { $0.string("name") }
            .filter { !Self.excludedTables.contains($0) }
    }

    private func columnNames(of table: String) throws -> [String] {
        try db.query("PRAGMA table_info(\(quote(table)));").compactMap { $0.string("name") }
    }

    /// An identifier from `sqlite_master`, quoted for SQL. These are the app's own
    /// table names, not input; quoting is for correctness, not defence.
    private func quote(_ identifier: String) -> String {
        "\"" + identifier.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// A JSON string literal. Written by hand because `JSONEncoder` per cell made a
    /// populated database take over a minute to export. Escapes what JSON requires
    /// (quote, backslash, control characters); everything else, including non-ASCII
    /// text, is written as UTF-8.
    static func jsonString(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case _ where scalar.value < 0x20:
                out += String(format: "\\u%04x", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }

    private func cell(_ value: SQLValue?) -> String {
        switch value {
        case .none, .some(.null):
            return "null"
        case .some(.integer(let number)):
            return String(number)
        case .some(.real(let number)):
            return number.isFinite ? String(number) : "null"
        case .some(.text(let string)):
            return Self.jsonString(string)
        case .some(.blob(let bytes)):
            return "{\"base64\":\"" + Data(bytes).base64EncodedString() + "\"}"
        }
    }
}
