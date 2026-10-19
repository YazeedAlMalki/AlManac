import Foundation

/// Migration 067 — Open Food Facts products, in tables of their own.
///
/// The owner chose Open Food Facts for packaged products and barcodes on
/// 2026-10-19. Its data is under the ODbL (share-alike on an adapted
/// database), so it does not enter the nutrition reference tables, whose
/// `licence_group` CHECKs admit A, B and N only: every row here is group C,
/// and `OpenFoodFactsBundle` installs them from their own bundled file.
/// `off_barcode` maps every barcode of a merged record to that record, so a
/// logged `off:<barcode>` keeps resolving.
public enum Migration067_OpenFoodFacts: Migration {
    public static let version = 67
    public static let name = "open_food_facts"

    public static func up(_ db: Database) throws {
        try db.execute("""
        CREATE TABLE off_product (
            food_ref       TEXT PRIMARY KEY,
            name           TEXT NOT NULL,
            name_fold      TEXT NOT NULL,
            brands         TEXT,
            quantity_text  TEXT,
            serving_text   TEXT,
            serving_grams  REAL,
            basis          TEXT NOT NULL CHECK (basis IN ('per_100g', 'per_100ml')),
            url            TEXT NOT NULL,
            last_modified  INTEGER,
            licence_group  TEXT NOT NULL CHECK (licence_group = 'C')
        ) STRICT;
        CREATE INDEX idx_off_product_name ON off_product (name_fold);

        CREATE TABLE off_barcode (
            code      TEXT PRIMARY KEY,
            food_ref  TEXT NOT NULL REFERENCES off_product (food_ref) ON DELETE CASCADE
        ) STRICT;

        CREATE TABLE off_value (
            food_ref      TEXT NOT NULL REFERENCES off_product (food_ref) ON DELETE CASCADE,
            nutrient_id   TEXT NOT NULL,
            amount        REAL,
            qualifier     TEXT NOT NULL,
            source_value  TEXT NOT NULL,
            source_field  TEXT NOT NULL,
            source_unit   TEXT NOT NULL,
            PRIMARY KEY (food_ref, nutrient_id)
        ) STRICT;

        CREATE TABLE off_import (
            bundle_sha256  TEXT NOT NULL,
            product_count  INTEGER NOT NULL,
            imported_at    TEXT NOT NULL
        ) STRICT;
        """)
    }
}
