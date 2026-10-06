import Foundation

/// Migration 053 — pantry suggestions the person turned down.
///
/// The owner's Kitchen call (2026-10-06): the pantry stays declared, but
/// Kitchen may *offer* to add foods he logs often, and he approves or dismisses
/// each. A dismissal is stored so the same food is not offered again; without a
/// table it would come back on the next launch, which is nagging, not offering.
///
/// One row per food. `food_ref` carries no foreign key, for the reason
/// `kitchen_pantry_item.food_ref` carries none (Migration 051).
public enum Migration053_PantrySuggestionDismissal: Migration {
    public static let version = 53
    public static let name = "pantry_suggestion_dismissal"

    public static func up(_ db: Database) throws {
        try db.execute("""
        CREATE TABLE kitchen_pantry_dismissal (
            food_ref     TEXT PRIMARY KEY,
            dismissed_at TEXT NOT NULL
        ) STRICT;
        """)
    }
}
