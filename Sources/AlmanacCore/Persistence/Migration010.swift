import Foundation

/// Migration 010 — household measures, and Almanac's own dishes.
///
/// Appended; 001-009 are untouched.
///
/// **Reconciliation note.** The 2026-09-14 handoff and a second, independent
/// branch each authored `nutrition_food`/`nutrition_value` while unaware of
/// the other. Migration 008 (`codex/manual-entry`) mirrors the bundle schema
/// — namespaced, per-basis, multi-language names — and is already populated
/// with 8,354 imported foods; that definition wins. The other branch's
/// `nutrition_food`/`nutrition_value` are not reused. Its `nutrition_portion`
/// and `nutrition_dish_component` needed no schema change to sit on top of
/// migration 008's `nutrition_food` — both already key on `food_ref` alone —
/// so they are carried over as they were. What did need a new home is the
/// pair of facts (`yield_grams`, `edible_proportion`) the other branch kept on
/// `nutrition_food` itself: migration 008's copy of that table mirrors the
/// bundle schema on purpose, and a dish-only column would break that mirror.
/// They live in `nutrition_dish` instead, one row per `almanac:` food.
///
/// Three things worth stating about the shape:
///
/// 1. **A portion is per 100 g of edible portion**, same as every value row.
///    `nutrition_dish.edible_proportion` is the separate CoFID-style fact that
///    converts an as-purchased weight into that edible weight; it is not a
///    nutrient and does not belong in `nutrition_value`.
/// 2. **A dish's yield is its finished weight**, when cooking makes it differ
///    from the sum of its components — `nutrition_dish.yield_grams`. Nil means
///    the sum.
/// 3. **Portions are not unique per (food, unit).** USDA genuinely carries
///    several, and this codebase already returns ambiguous candidates rather
///    than picking one (`lab_catalog_alias`, `PortionMatch.ambiguous`). A
///    `LIMIT 1` here would silently choose a gram weight.
public enum Migration010_NutritionPortionsAndDishes: Migration {
    public static let version = 10
    public static let name = "nutrition_portions_and_dishes"

    public static func up(_ db: Database) throws {
        try db.execute("""
        CREATE TABLE nutrition_dish (
            food_ref          TEXT PRIMARY KEY
                                   REFERENCES nutrition_food (food_ref) ON DELETE CASCADE,
            yield_grams       REAL,
            edible_proportion REAL,
            created_at        TEXT NOT NULL,
            updated_at        TEXT NOT NULL
        ) STRICT;

        CREATE TABLE nutrition_portion (
            id            TEXT    PRIMARY KEY,
            food_ref      TEXT    NOT NULL
                              REFERENCES nutrition_food (food_ref) ON DELETE CASCADE,
            amount        REAL    NOT NULL,
            unit_text     TEXT    NOT NULL,
            unit_fold     TEXT    NOT NULL,
            modifier_text TEXT,
            gram_weight   REAL    NOT NULL,
            sequence      INTEGER NOT NULL DEFAULT 0,
            licence_group TEXT    NOT NULL CHECK (licence_group IN ('A', 'B', 'N')),
            source_value  TEXT
        ) STRICT;
        CREATE INDEX idx_nutrition_portion_lookup ON nutrition_portion (food_ref, unit_fold);

        -- A dish's recipe. `component_ref` carries no foreign key for the same
        -- reason `nutrition_log.food_ref` does not: removing a source must stay
        -- a one-line delete, and it must not cascade into a dish the user
        -- wrote. A dish whose component has gone is reported as incomplete,
        -- never silently recomputed as though the component weighed nothing.
        CREATE TABLE nutrition_dish_component (
            id            TEXT    PRIMARY KEY,
            dish_ref      TEXT    NOT NULL
                              REFERENCES nutrition_food (food_ref) ON DELETE CASCADE,
            component_ref TEXT    NOT NULL,
            grams         REAL    NOT NULL,
            sequence      INTEGER NOT NULL,
            note_text     TEXT
        ) STRICT;
        CREATE UNIQUE INDEX idx_nutrition_dish_component_order
            ON nutrition_dish_component (dish_ref, sequence);
        """)
    }
}
