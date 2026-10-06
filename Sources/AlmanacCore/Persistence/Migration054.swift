import Foundation

/// Migration 054 — Kitchen's ingredient table: a canonical ingredient, and which
/// foods are that ingredient.
///
/// The owner's Kitchen call (2026-10-06): "build the ingredient table now",
/// instead of matching recipes by exact `food_ref`. USDA's "Chicken, breast,
/// boneless, skinless, raw" and CoFID's "Chicken, breast, casseroled, meat only"
/// are different catalog rows and the same thing to have in the house.
///
/// `kitchen_ingredient_food.food_ref` carries no foreign key, as every Kitchen
/// `food_ref` does not (Migration 051). `source` says who decided the mapping:
/// `normalised` rows are rebuilt from names (`IngredientTable.rebuild`) and
/// `curated` rows are the overrides, which a rebuild never touches.
public enum Migration054_KitchenIngredient: Migration {
    public static let version = 54
    public static let name = "kitchen_ingredient"

    public static func up(_ db: Database) throws {
        try db.execute("""
        CREATE TABLE kitchen_ingredient (
            id   TEXT PRIMARY KEY,
            name TEXT NOT NULL
        ) STRICT;

        CREATE TABLE kitchen_ingredient_food (
            food_ref      TEXT PRIMARY KEY,
            ingredient_id TEXT NOT NULL REFERENCES kitchen_ingredient (id) ON DELETE CASCADE,
            source        TEXT NOT NULL CHECK (source IN ('normalised', 'curated'))
        ) STRICT;
        CREATE INDEX idx_kitchen_ingredient_food_ingredient
            ON kitchen_ingredient_food (ingredient_id);
        """)
    }
}
