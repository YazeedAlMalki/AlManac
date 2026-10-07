import Foundation

/// A food a person has said is in the house.
public struct PantryItem: Sendable, Hashable {
    public let ref: SourceIdentifier
    /// What the food was called when it was added. Survives the reference row
    /// being removed, the same way `nutrition_log.food_name_text` does.
    public let nameText: String?
    public let addedAt: String
}

/// The declared pantry Kitchen matches recipes against.
///
/// **Declared, not inferred.** Nothing here is added by logging a meal or
/// removed by eating one. "I logged the last egg" and "I logged an egg" are the
/// same log entry, so a pantry the log maintained would be wrong in a way the
/// person could not see — and suggestions built on it would be wrong with it.
/// The log has its own, separate route into Kitchen
/// (`RecipeFinder.fromRecentLog`), which says what it is.
public struct KitchenPantry: Sendable {
    private let db: Database
    private let clock: any Clock

    public init(db: Database, clock: any Clock = SystemClock()) {
        self.db = db
        self.clock = clock
    }

    private var nowText: String { ISO8601DateFormatter().string(from: clock.now) }

    /// Adds a food, or refreshes its name if it is already there. Adding twice
    /// is not two of it: the pantry records presence, not quantity.
    public func add(_ ref: SourceIdentifier, nameText: String?) throws {
        try db.run("""
        INSERT INTO kitchen_pantry_item (food_ref, food_name_text, added_at)
        VALUES (?, ?, ?)
        ON CONFLICT(food_ref) DO UPDATE SET
            food_name_text = COALESCE(excluded.food_name_text, food_name_text);
        """, [.text(ref.description), nameText.map { SQLValue.text($0) } ?? .null,
              .text(nowText)])
    }

    /// Removes a food. Returns false when it was not there.
    @discardableResult
    public func remove(_ ref: SourceIdentifier) throws -> Bool {
        try db.run("DELETE FROM kitchen_pantry_item WHERE food_ref = ?;",
                   [.text(ref.description)]) == 1
    }

    public func items() throws -> [PantryItem] {
        try db.query("""
            SELECT food_ref, food_name_text, added_at FROM kitchen_pantry_item
            ORDER BY food_name_text COLLATE NOCASE, food_ref;
            """).compactMap { row in
            guard let ref = row.string("food_ref").flatMap(SourceIdentifier.init(parsing:))
            else { return nil }
            return PantryItem(ref: ref, nameText: row.string("food_name_text"),
                              addedAt: row.string("added_at") ?? "")
        }
    }

    public func refs() throws -> Set<SourceIdentifier> {
        Set(try items().map(\.ref))
    }
}
