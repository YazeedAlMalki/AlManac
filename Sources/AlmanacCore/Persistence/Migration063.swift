import Foundation

/// Migration 063 — the caffeine a logged drink carried, tied to that drink.
///
/// BRD §6.2: one drink entry fills hydration, caffeine and nutrition. A drink
/// is a `hydration_log` row; its caffeine is a `caffeine_log` row (Migration
/// 015), and until now nothing linked the two, so deleting or resizing the
/// drink could not reach its caffeine. `drinkEntryId` (015) points at
/// `drink_entry`, which nothing writes.
public enum Migration063_CaffeineHydrationLink: Migration {
    public static let version = 63
    public static let name = "caffeine_hydration_link"

    public static func up(_ db: Database) throws {
        try db.execute("""
        ALTER TABLE caffeine_log ADD COLUMN hydrationLogId TEXT REFERENCES hydration_log(id);
        CREATE INDEX idx_caffeine_log_hydration ON caffeine_log(hydrationLogId);
        """)
    }
}
