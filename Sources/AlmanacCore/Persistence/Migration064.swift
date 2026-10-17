import Foundation

/// Migration 064 — a custom drink's caffeine.
///
/// BRD §6.2: caffeine per drink type. Catalog drinks carry theirs in code
/// (`CatalogDrinks`); a drink the person adds is a `hydration_drink` row
/// (Migration 013), which had no caffeine column. 0 for every drink saved
/// before, which is what they recorded: none.
public enum Migration064_CustomDrinkCaffeine: Migration {
    public static let version = 64
    public static let name = "custom_drink_caffeine"

    public static func up(_ db: Database) throws {
        try db.execute("""
        ALTER TABLE hydration_drink ADD COLUMN caffeine_mg REAL NOT NULL DEFAULT 0 CHECK (caffeine_mg >= 0);
        """)
    }
}
