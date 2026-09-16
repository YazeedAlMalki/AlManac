import Foundation

/// Migration 017 — meal type on the food log.
///
/// Appended; 001-016 are untouched.
///
/// `meal_type` is nullable, same reasoning as `nutrition_log.grams`: "logged
/// this, didn't say which meal" is a real entry, not an error, and every row
/// written before this migration is exactly that. No CHECK constraint here —
/// `ALTER TABLE ... ADD COLUMN` follows the plain-column convention already
/// used for `hydration_log` (Migration013) and `lab_report` (Migration006);
/// the closed set of values (`NutritionMealType`) is enforced in Swift, at
/// `NutritionLogStore`, the same way `nutrition_log_revision.changed_fields`
/// is validated at the call site rather than in SQL.
public enum Migration017_NutritionMealType: Migration {
    public static let version = 17
    public static let name = "nutrition_meal_type"

    public static func up(_ db: Database) throws {
        try db.execute("ALTER TABLE nutrition_log ADD COLUMN meal_type TEXT;")
        try db.execute("ALTER TABLE nutrition_log_revision ADD COLUMN meal_type TEXT;")
    }
}
