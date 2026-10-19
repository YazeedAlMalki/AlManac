import Foundation

/// Migration 067 — one record per real food (owner, 2026-10-19).
///
/// The reference sources overlap: CoFID, CIQUAL, AFCD and USDA each publish
/// "Honey". `tools/nutrition`'s merge stage decides which foods are the same
/// food and writes `food-merges.json`; this table is that map, `food_ref` →
/// `record_ref`, the member the search shows. Nothing else changes: every
/// member keeps its own names, values, portions and licence, so a person's
/// logged food still resolves to the row they logged, and removing a source is
/// still removing its rows. No foreign key, for that reason, as with
/// `nutrition_log.food_ref`.
///
/// `nutrition_food_merge_import` holds the SHA-256 of the map last installed,
/// so it installs once per file, as `nutrition_reference_import` does.
public enum Migration067_FoodMerge: Migration {
    public static let version = 67
    public static let name = "food_merge"

    public static func up(_ db: Database) throws {
        try db.execute("""
        CREATE TABLE nutrition_food_merge (
            food_ref    TEXT PRIMARY KEY,
            record_ref  TEXT NOT NULL,
            kind        TEXT NOT NULL CHECK (kind IN ('code', 'same', 'unsure')),
            score       REAL NOT NULL CHECK (score >= 0 AND score <= 1)
        ) STRICT;
        CREATE INDEX idx_nutrition_food_merge_record ON nutrition_food_merge (record_ref);

        CREATE TABLE nutrition_food_merge_import (
            id             INTEGER PRIMARY KEY CHECK (id = 1),
            bundle_sha256  TEXT NOT NULL,
            merge_count    INTEGER NOT NULL,
            imported_at    TEXT NOT NULL
        ) STRICT;
        """)
    }
}
