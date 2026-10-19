import Foundation

/// Installs `food-merges.json`, the one-record-per-real-food map
/// `tools/nutrition` writes (`python3 -m almanac_nutrition merge`;
/// `docs/features/food-merge-log.md` lists every merge and conflict).
/// Migration 068 says what the map is and is not.
public enum FoodMergeBundle {
    public static var resourceURL: URL {
        Bundle.module.bundleURL.appendingPathComponent("food-merges.json")
    }

    struct File: Decodable {
        struct Merge: Decodable {
            let foodRef: String
            let recordRef: String
            let kind: String
            let score: Double
        }
        let merges: [Merge]
    }

    /// Installs the bundled map when it is missing or changed. Returns the
    /// number of merged foods installed, or nil when the installed map already
    /// has the same SHA-256.
    @discardableResult
    public static func installIfNeeded(into db: Database,
                                       clock: any Clock = SystemClock()) throws -> Int? {
        let data = try Data(contentsOf: resourceURL)
        let sha256 = SHA256File.hex(of: Array(data))
        let installed = try db.query("SELECT bundle_sha256 FROM nutrition_food_merge_import WHERE id = 1;")
            .first?.string("bundle_sha256")
        guard installed != sha256 else { return nil }
        return try install(data, sha256: sha256, into: db, clock: clock)
    }

    /// Replaces the whole map with `data`'s, in one transaction.
    @discardableResult
    public static func install(_ data: Data, sha256: String, into db: Database,
                               clock: any Clock = SystemClock()) throws -> Int {
        let merges = try JSONDecoder().decode(File.self, from: data).merges
        return try db.transaction { () throws -> Int in
            try db.run("DELETE FROM nutrition_food_merge;")
            try db.run("""
                INSERT INTO nutrition_food_merge (food_ref, record_ref, kind, score) VALUES (?, ?, ?, ?);
                """, each: merges.map { [.text($0.foodRef), .text($0.recordRef), .text($0.kind), .real($0.score)] })
            try db.run("""
                INSERT INTO nutrition_food_merge_import (id, bundle_sha256, merge_count, imported_at)
                VALUES (1, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET bundle_sha256 = excluded.bundle_sha256,
                    merge_count = excluded.merge_count, imported_at = excluded.imported_at;
                """, [.text(sha256), .integer(Int64(merges.count)),
                      .text(ISO8601DateFormatter().string(from: clock.now))])
            return merges.count
        }
    }
}
