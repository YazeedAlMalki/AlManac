import Foundation

/// Migration 062 — where an imported recipe came from, and which bundle of them
/// is installed.
///
/// The owner chose the Wikibooks Cookbook for Kitchen's recipes (T04,
/// 2026-10-16). An imported recipe is an ordinary `almanac:` dish, so logging,
/// serving counts, the ingredient table and the allergen check all apply
/// unchanged; this table is what says it is not the person's own. It carries
/// what CC BY-SA 4.0 asks for on every recipe shown — the page's title, a link
/// to it, the revision used and the licence — and the serving count the page
/// itself states, if any. One row per imported dish, removed with it.
///
/// `kitchen_recipe_import` holds the SHA-256 of the bundle last installed, per
/// source, so the install runs once per bundle, as the nutrition reference
/// does with `nutrition_reference_import`.
public enum Migration062_KitchenRecipeSource: Migration {
    public static let version = 62
    public static let name = "kitchen_recipe_source"

    public static func up(_ db: Database) throws {
        try db.execute("""
        CREATE TABLE kitchen_recipe_source (
            food_ref         TEXT PRIMARY KEY
                                 REFERENCES nutrition_food (food_ref) ON DELETE CASCADE,
            source           TEXT NOT NULL CHECK (source IN ('wikibooks')),
            source_id        TEXT NOT NULL,
            title            TEXT NOT NULL,
            url              TEXT NOT NULL CHECK (url LIKE 'https://%'),
            revision         INTEGER NOT NULL,
            licence          TEXT NOT NULL,
            stated_servings  INTEGER CHECK (stated_servings IS NULL OR stated_servings > 0),
            UNIQUE (source, source_id)
        ) STRICT;

        CREATE TABLE kitchen_recipe_import (
            source         TEXT PRIMARY KEY CHECK (source IN ('wikibooks')),
            bundle_sha256  TEXT NOT NULL,
            recipe_count   INTEGER NOT NULL,
            imported_at    TEXT NOT NULL
        ) STRICT;
        """)
    }
}
