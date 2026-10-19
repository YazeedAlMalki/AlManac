import Testing
import Foundation
@testable import AlmanacCore

/// One record per real food (owner, 2026-10-19; Migration 068). The matching
/// is tested in `tools/nutrition/tests/test_merge.py`; these pin what the map
/// does to the catalog.
@Suite("Food merge map")
struct FoodMergeTests {
    let db = try! TestDatabase()
    var catalog: NutritionCatalog { NutritionCatalog(db: db) }

    private func food(_ ref: String, _ name: String) throws {
        let namespace = String(ref.split(separator: ":")[0])
        let group = namespace == "usda" ? "A" : "B"
        try db.run("""
            INSERT OR IGNORE INTO nutrition_source (namespace, dataset_id, name, release, licence,
                                                    licence_group, attribution, url)
            VALUES (?, ?, ?, '', '', ?, '', '');
            """, [.text(namespace), .text(namespace), .text(namespace), .text(group)])
        try db.run("""
            INSERT INTO nutrition_food (food_ref, namespace, local_id, licence_group, food_group_code,
                                        food_group_name, source_record)
            VALUES (?, ?, ?, ?, '', '', 'test');
            """, [.text(ref), .text(namespace), .text(String(ref.split(separator: ":")[1])), .text(group)])
        try db.run("""
            INSERT INTO nutrition_food_name (food_ref, language, name, is_primary, name_fold)
            VALUES (?, 'en', ?, 1, ?);
            """, [.text(ref), .text(name), .text(TextFold.fold(name))])
    }

    private func install(_ merges: [(String, String)]) throws -> Int {
        let rows = merges.map { #"{"foodRef": "\#($0.0)", "recordRef": "\#($0.1)", "kind": "same", "score": 1}"# }
        let data = Data(#"{"merges": [\#(rows.joined(separator: ","))]}"#.utf8)
        return try FoodMergeBundle.install(data, sha256: "test", into: db)
    }

    private func seed() throws {
        try food("usda:1", "Honey")
        try food("cofid:1", "Honey")
        try food("ciqual:1", "Honey, liquid")
        try food("afcd:1", "Honeydew melon, raw")
        _ = try install([("usda:1", "usda:1"), ("cofid:1", "usda:1"), ("ciqual:1", "usda:1")])
    }

    @Test("The search lists a merged food once, as its record")
    func searchListsTheRecordOnce() throws {
        try seed()
        #expect(try catalog.search("honey").map(\.ref.description) == ["usda:1", "afcd:1"])
    }

    @Test("A member's own name still finds its record")
    func memberNamesFindTheRecord() throws {
        try seed()
        #expect(try catalog.search("liquid").map(\.ref.description) == ["usda:1"])
    }

    @Test("A member whose record is not in the catalog lists as itself")
    func orphanedMemberStillLists() throws {
        try food("cofid:2", "Ghee")
        _ = try install([("cofid:2", "usda:999")])
        #expect(try catalog.search("ghee").map(\.ref.description) == ["cofid:2"])
    }

    @Test("Every member is kept and reachable from any of them, record first")
    func membersAreReachable() throws {
        try seed()
        let expected = ["usda:1", "ciqual:1", "cofid:1"]
        #expect(try catalog.members(of: SourceIdentifier(parsing: "cofid:1")!).map(\.ref.description) == expected)
        #expect(try catalog.members(of: SourceIdentifier(parsing: "usda:1")!).map(\.ref.description) == expected)
        #expect(try catalog.members(of: SourceIdentifier(parsing: "afcd:1")!).map(\.ref.description) == ["afcd:1"])
        #expect(try catalog.food(SourceIdentifier(parsing: "cofid:1")!) != nil, "a merged food keeps its own row")
    }

    @Test("The bundled map installs once per file and every row is well formed")
    func bundledMapInstallsOnce() throws {
        let installed = try #require(try FoodMergeBundle.installIfNeeded(into: db))
        #expect(installed > 0)
        #expect(try FoodMergeBundle.installIfNeeded(into: db) == nil)
        #expect(try db.query("SELECT COUNT(*) AS n FROM nutrition_food_merge;").first?.int("n") == Int64(installed))
        // Every record is one of its own members.
        #expect(try db.query("""
            SELECT 1 FROM nutrition_food_merge m
            WHERE NOT EXISTS (SELECT 1 FROM nutrition_food_merge r
                              WHERE r.food_ref = m.record_ref AND r.record_ref = m.record_ref);
            """).isEmpty)
    }

    @Test("On the shipped reference, Honey from three sources is one search row")
    func shippedReferenceHoneyIsOneRow() throws {
        try NutritionReferenceBundle.installIfNeeded(into: db)
        try FoodMergeBundle.installIfNeeded(into: db)
        let honey = try catalog.search("honey", limit: 200).filter { $0.primaryName == "Honey" }
        #expect(honey.count == 1)
        #expect(try catalog.members(of: try #require(honey.first).ref).count == 3)
    }
}
