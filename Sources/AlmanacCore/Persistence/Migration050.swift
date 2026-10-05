import Foundation

/// Migration 050 — Kitchen's pantry: the foods a person has said are in the
/// house, so recipes can be matched against them.
///
/// **This is the only table Kitchen adds.** A recipe here is an `almanac:` dish
/// (Migration 010): a name, components by `food_ref`, a yield, and per-100 g
/// values that `NutritionDishEditor.setRecipe` already reduces from those
/// components. The standalone Kitchen design (never committed to this
/// repository) described six `ak_*` tables of its own, including
/// `ak_ingredients` and `ak_logged_meals_recipe_link`. Each restated something
/// this schema already holds — an ingredient is a `food_ref`, a logged recipe is
/// a `nutrition_log` row whose `food_ref` is the dish — and a second copy of a
/// recipe is a recipe that can disagree with itself. docs/features/kitchen.md
/// has the mapping.
///
/// `food_ref` carries no foreign key, for the reason `nutrition_log.food_ref`
/// carries none (Migration 009): this is the person's record, not the
/// publisher's, and removing a source must not reach into it.
/// `food_name_text` keeps an orphaned row readable. There is no `user_id`:
/// Almanac holds one person.
public enum Migration050_KitchenPantry: Migration {
    public static let version = 50
    public static let name = "kitchen_pantry"

    public static func up(_ db: Database) throws {
        try db.execute("""
        CREATE TABLE kitchen_pantry_item (
            food_ref       TEXT PRIMARY KEY,
            food_name_text TEXT,
            added_at       TEXT NOT NULL
        ) STRICT;
        """)
    }
}
