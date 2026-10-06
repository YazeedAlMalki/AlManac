import Foundation

/// Migration 052 — how many servings a dish makes.
///
/// The owner's Kitchen call (2026-10-06): choosing a recipe pre-fills **one
/// serving**. `nutrition_dish` held the finished weight (`yield_grams`) but not
/// how many people it feeds, so "one serving" had nothing to divide by.
///
/// Nullable, and null is not zero: a dish nobody has given a count is treated as
/// **one serving — the whole dish** — until it is set
/// (`NutritionDishEditor.oneServingGrams`). Additive: no existing row changes.
public enum Migration052_DishServingCount: Migration {
    public static let version = 52
    public static let name = "dish_serving_count"

    public static func up(_ db: Database) throws {
        try db.execute("""
        ALTER TABLE nutrition_dish ADD COLUMN serving_count INTEGER
            CHECK (serving_count IS NULL OR serving_count > 0);
        """)
    }
}
