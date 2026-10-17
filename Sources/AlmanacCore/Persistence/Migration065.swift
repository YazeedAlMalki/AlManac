import Foundation

/// Migration 065 — the person's own caffeine figure for a catalog drink.
///
/// BRD §6.2: caffeine presets per drink type, editable. Catalog drinks live in
/// code (`CatalogDrinks`) with typical figures; a row here replaces one drink's
/// caffeine with the person's number, and deleting it returns the typical one.
/// Only caffeine: the catalog's other figures are not editable.
public enum Migration065_DrinkCaffeinePreset: Migration {
    public static let version = 65
    public static let name = "drink_caffeine_preset"

    public static func up(_ db: Database) throws {
        try db.execute("""
        CREATE TABLE drink_caffeine_preset (
            drink_id     TEXT PRIMARY KEY,
            caffeine_mg  REAL NOT NULL CHECK (caffeine_mg >= 0),
            updated_at   TEXT NOT NULL
        ) STRICT;
        """)
    }
}
