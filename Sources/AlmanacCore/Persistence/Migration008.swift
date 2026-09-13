import Foundation

/// Migration 008 — the nutrition reference tables a bundle is imported into.
///
/// Mirrors bundle schema v1 (tools/nutrition/almanac_nutrition/bundle.py),
/// module-prefixed per docs/architecture/health-data-foundation.md §12. The
/// licence and qualifier constraints repeat the bundle's on purpose: a
/// restricted row, or a token coerced to a number, cannot be inserted here by
/// any route — including a bundle that never went through the pipeline.
///
/// Reference foods are keyed by the publisher's namespaced identifier
/// (Processing Design v0.1 §3), not a surrogate: a food log must keep pointing
/// at the same food across bundle updates, and a surrogate would change on
/// every import. These rows are not user records.
public enum Migration008_NutritionReference: Migration {
    public static let version = 8
    public static let name = "nutrition_reference"

    public static func up(_ db: Database) throws {
        try db.execute("""
        CREATE TABLE nutrition_source (
            namespace     TEXT PRIMARY KEY,
            dataset_id    TEXT NOT NULL,
            name          TEXT NOT NULL,
            release       TEXT NOT NULL,
            licence       TEXT NOT NULL,
            licence_group TEXT NOT NULL CHECK (licence_group IN ('A', 'B', 'N')),
            attribution   TEXT NOT NULL,
            url           TEXT NOT NULL
        ) STRICT;

        CREATE TABLE nutrition_nutrient (
            nutrient_id TEXT PRIMARY KEY,
            infoods_tag TEXT NOT NULL,
            name        TEXT NOT NULL,
            unit        TEXT NOT NULL,
            description TEXT NOT NULL
        ) STRICT;

        CREATE TABLE nutrition_food (
            food_ref        TEXT PRIMARY KEY,
            namespace       TEXT NOT NULL REFERENCES nutrition_source (namespace),
            local_id        TEXT NOT NULL,
            licence_group   TEXT NOT NULL CHECK (licence_group IN ('A', 'B', 'N')),
            food_group_code TEXT NOT NULL,
            food_group_name TEXT NOT NULL,
            source_record   TEXT NOT NULL,
            UNIQUE (namespace, local_id),
            CHECK (food_ref = namespace || ':' || local_id)
        ) STRICT;

        CREATE TABLE nutrition_food_name (
            food_ref   TEXT NOT NULL REFERENCES nutrition_food (food_ref),
            language   TEXT NOT NULL,
            name       TEXT NOT NULL CHECK (name <> ''),
            is_primary INTEGER NOT NULL CHECK (is_primary IN (0, 1)),
            name_fold  TEXT NOT NULL DEFAULT '',
            PRIMARY KEY (food_ref, language)
        ) STRICT;

        CREATE INDEX idx_nutrition_food_name_fold ON nutrition_food_name (name_fold);

        CREATE TABLE nutrition_value (
            food_ref           TEXT NOT NULL REFERENCES nutrition_food (food_ref),
            nutrient_id        TEXT NOT NULL REFERENCES nutrition_nutrient (nutrient_id),
            basis              TEXT NOT NULL CHECK (basis IN ('per_100g', 'per_100ml')),
            amount             REAL CHECK (amount IS NULL OR amount >= 0),
            qualifier          TEXT NOT NULL CHECK (qualifier IN (
                                   'measured', 'trace', 'not_analysed', 'below_loq', 'borrowed',
                                   'calculated_recipe', 'calculated_factor', 'zero_reported')),
            confidence         TEXT,
            source_value       TEXT NOT NULL CHECK (source_value <> ''),
            source_nutrient_id TEXT NOT NULL,
            source_unit        TEXT NOT NULL,
            licence_group      TEXT NOT NULL CHECK (licence_group IN ('A', 'B', 'N')),
            PRIMARY KEY (food_ref, nutrient_id, basis),
            CHECK ((qualifier IN ('trace', 'not_analysed')) = (amount IS NULL)),
            CHECK (qualifier <> 'zero_reported' OR amount = 0)
        ) STRICT;

        CREATE TABLE nutrition_reference_import (
            id                INTEGER PRIMARY KEY AUTOINCREMENT,
            imported_at       TEXT    NOT NULL,
            bundle_sha256     TEXT    NOT NULL,
            schema_version    INTEGER NOT NULL,
            dictionary_sha256 TEXT    NOT NULL,
            namespaces        TEXT    NOT NULL,
            food_count        INTEGER NOT NULL,
            value_count       INTEGER NOT NULL
        ) STRICT;
        """)
    }
}
