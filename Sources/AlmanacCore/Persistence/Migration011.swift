import Foundation

/// Migration 011 — a portion is not duplicated by re-importing it.
///
/// Appended; 001-010 are untouched, on the rule this repository already
/// follows that a committed migration is treated the same as an applied one.
///
/// **The defect.** `nutrition_portion` carried no uniqueness at all, so calling
/// `addPortion` twice with the same row — which is what re-running an importer
/// does — stored it twice. Two identical "1 cup" rows are then reported as
/// `PortionMatch.ambiguous`, and `grams(of:amount:unit:)` returns nil rather
/// than the weight. A phantom disagreement between a row and itself, presented
/// to the user as a measure that cannot be resolved.
///
/// The key is everything that makes two measures genuinely different: the
/// food, the folded unit, the modifier, the stated amount and the gram
/// weight. USDA really does carry several "1 cup" rows per food with
/// different weights, and those must still coexist — this rejects only a row
/// identical to one already held. `COALESCE(modifier_text, '')` is not
/// decoration: SQLite treats NULLs as distinct in a unique index, so without
/// it the unmodified rows — the common case — would go on duplicating.
public enum Migration011_PortionIdentity: Migration {
    public static let version = 11
    public static let name = "portion_identity"

    public static func up(_ db: Database) throws {
        // Any duplicate already stored is collapsed before the index is built,
        // keeping the first by id so the choice is not row order.
        try db.execute("""
        DELETE FROM nutrition_portion WHERE id NOT IN (
            SELECT MIN(id) FROM nutrition_portion
            GROUP BY food_ref, unit_fold, COALESCE(modifier_text, ''), amount, gram_weight
        );
        """)
        try db.execute("""
        CREATE UNIQUE INDEX idx_nutrition_portion_identity
            ON nutrition_portion (food_ref, unit_fold, COALESCE(modifier_text, ''),
                                  amount, gram_weight);
        """)
    }
}
