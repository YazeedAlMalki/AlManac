import Foundation
import Testing
@testable import AlmanacCore

/// The open-format export of a person's own records (remediation P1-5).
@Suite("Data export (P1-5)")
struct DataExportTests {
    private func migrated() throws -> Database {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        return db
    }

    private func tempFile() -> String {
        NSTemporaryDirectory() + "almanac-export-\(UUID().uuidString)/export.json"
    }

    private func export(_ db: Database) throws -> (json: [String: Any], summary: DataExport.Summary, path: String) {
        let path = tempFile()
        let summary = try DataExport(db: db).write(to: path)
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any],
                                "the export is not a JSON object")
        return (json, summary, path)
    }

    private func table(_ json: [String: Any], _ name: String) -> (columns: [String], rows: [[Any]])? {
        guard let tables = json["tables"] as? [String: Any],
              let entry = tables[name] as? [String: Any],
              let columns = entry["columns"] as? [String],
              let rows = entry["rows"] as? [[Any]] else { return nil }
        return (columns, rows)
    }

    @Test("The file is valid JSON with its header, and the counts add up")
    func shape() throws {
        let db = try migrated()
        let result = try export(db)
        defer { try? FileManager.default.removeItem(atPath: (result.path as NSString).deletingLastPathComponent) }
        #expect(result.json["format"] as? String == "almanac-export")
        #expect(result.json["formatVersion"] as? Int == 1)
        let head = try db.query("SELECT MAX(version) AS v FROM schema_migrations;").first?.int("v")
        #expect(result.json["schemaVersion"] as? Int == head.map(Int.init))
        #expect((result.json["exportedAt"] as? String)?.hasSuffix("Z") == true)
        #expect((result.json["notes"] as? String)?.contains("not encrypted") == true)
        let tables = try #require(result.json["tables"] as? [String: Any])
        #expect(tables.count == result.summary.tableCount)
        var rows = 0
        for name in tables.keys {
            let entry = try #require(tables[name] as? [String: Any])
            let list = try #require(entry["rows"] as? [[Any]])
            #expect(entry["rowCount"] as? Int == list.count, "\(name): rowCount disagrees with rows")
            let columns = try #require(entry["columns"] as? [String])
            #expect(list.allSatisfy { $0.count == columns.count }, "\(name): a row is not as wide as its columns")
            rows += list.count
        }
        #expect(rows == result.summary.rowCount)
    }

    @Test("Reference data and bookkeeping are left out; the person's own tables are in")
    func whatIsIncluded() throws {
        let db = try migrated()
        let result = try export(db)
        defer { try? FileManager.default.removeItem(atPath: (result.path as NSString).deletingLastPathComponent) }
        let tables = Set((result.json["tables"] as? [String: Any])?.keys.map { $0 } ?? [])
        for excluded in ["schema_migrations", "sync_anchor", "backup_manifest", "nutrition_source",
                         "lab_catalog_analyte", "prayer_times_cache"] {
            #expect(!tables.contains(excluded), "\(excluded) should not be exported")
        }
        for included in ["profile", "nutrition_log", "hydration_log", "lab_report", "fasting_session"] {
            #expect(tables.contains(included), "\(included) is missing from the export")
        }
        #expect(!tables.contains(where: { $0.hasPrefix("sqlite_") }))
    }

    @Test("Profile details come out as the person entered them")
    func profileRow() throws {
        let db = try migrated()
        try ProfileStore(db: db).updateEmail("name@example.com")
        let result = try export(db)
        defer { try? FileManager.default.removeItem(atPath: (result.path as NSString).deletingLastPathComponent) }
        let profile = try #require(table(result.json, "profile"))
        let column = try #require(profile.columns.firstIndex(of: "email"))
        #expect(profile.rows.count == 1)
        #expect(profile.rows[0][column] as? String == "name@example.com")
    }

    @Test("Every SQLite type, and awkward text, survives the trip")
    func valueTypes() throws {
        let db = try migrated()
        try db.execute("CREATE TABLE export_probe (a INTEGER, b REAL, c TEXT, d BLOB, e);")
        try db.run("INSERT INTO export_probe VALUES (?, ?, ?, ?, ?);",
                   [.integer(Int64.max), .real(1.5e300),
                    .text("quote \" backslash \\ newline \n tab \t slash / emoji 🙂 Arabic مرحبا"),
                    .blob([0, 1, 255]), .null])
        try db.run("INSERT INTO export_probe VALUES (NULL, NULL, NULL, x'', NULL);")
        let result = try export(db)
        defer { try? FileManager.default.removeItem(atPath: (result.path as NSString).deletingLastPathComponent) }
        let probe = try #require(table(result.json, "export_probe"))
        #expect(probe.columns == ["a", "b", "c", "d", "e"])
        #expect(probe.rows.count == 2)
        let first = probe.rows[0]
        #expect((first[0] as? NSNumber)?.int64Value == Int64.max)
        #expect((first[1] as? NSNumber)?.doubleValue == 1.5e300)
        #expect(first[2] as? String == "quote \" backslash \\ newline \n tab \t slash / emoji 🙂 Arabic مرحبا")
        #expect((first[3] as? [String: String])?["base64"] == Data([0, 1, 255]).base64EncodedString())
        #expect(first[4] is NSNull)
        let second = probe.rows[1]
        #expect(second[0] is NSNull && second[1] is NSNull && second[2] is NSNull && second[4] is NSNull)
        #expect((second[3] as? [String: String])?["base64"] == "")
    }

    @Test("Of the mixed food tables only the person's own namespace is exported")
    func ownDishesOnly() throws {
        let db = try migrated()
        let ref = try NutritionDishEditor(db: db).create(localID: "export-test-dish", nameText: "My \"own\" dish")
        let result = try export(db)
        defer { try? FileManager.default.removeItem(atPath: (result.path as NSString).deletingLastPathComponent) }
        let foods = try #require(table(result.json, "nutrition_food"))
        let namespace = try #require(foods.columns.firstIndex(of: "namespace"))
        let foodRef = try #require(foods.columns.firstIndex(of: "food_ref"))
        #expect(foods.rows.contains { $0[foodRef] as? String == ref.description })
        #expect(foods.rows.allSatisfy { $0[namespace] as? String == "almanac" })
        let names = try #require(table(result.json, "nutrition_food_name"))
        let nameColumn = try #require(names.columns.firstIndex(of: "name"))
        #expect(names.rows.contains { $0[nameColumn] as? String == "My \"own\" dish" })
    }

    @Test("A second export replaces the first")
    func overwrites() throws {
        let db = try migrated()
        let path = tempFile()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }
        try DataExport(db: db).write(to: path)
        let first = try Data(contentsOf: URL(fileURLWithPath: path)).count
        try DataExport(db: db).write(to: path)
        let second = try Data(contentsOf: URL(fileURLWithPath: path)).count
        #expect(first > 0 && abs(first - second) < 200, "second export did not replace the first (\(first) vs \(second))")
        _ = try JSONSerialization.jsonObject(with: try Data(contentsOf: URL(fileURLWithPath: path)))
    }
}
