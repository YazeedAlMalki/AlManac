import Foundation

/// Migration 027 — `nutrition_food_factor`, the reconciliation `nutrition.md`
/// §8 flagged as unstarted: the bundle's `nutrition_portion` carries three
/// kinds (`household_measure`, `specific_gravity`, `edible_proportion`,
/// Processing Design v0.1 §4), but AlmanacCore's own `nutrition_portion`
/// (Migration010) only has columns shaped for the first — `amount`/`gram_weight`
/// are a genuine "N of this unit weighs M grams" quantity, and a density or a
/// proportion is neither.
///
/// `specific_gravity` and `edible_proportion` are **per reference food** —
/// thousands of CoFID rows, not just the user's own dishes — which is why
/// they cannot simply reuse `nutrition_dish.edible_proportion` either: that
/// column is one row per `almanac:` dish, keyed as the device-authored fact
/// it is (Migration010's own doc comment). This table is the bundle-imported
/// counterpart for ordinary reference foods; `nutrition_dish` keeps owning
/// the dish case exactly as before, so there is still exactly one home for
/// "is this food's edible proportion known" per food, never two.
///
/// Schema mirrors the bundle's `nutrition_portion` for these two kinds
/// (`tools/nutrition/almanac_nutrition/bundle.py`), including its
/// qualifier/value CHECK — repeated here the same way Migration008 repeats
/// it for `nutrition_value`, so a token (CoFID's `N`) cannot be coerced into
/// a number by any route, including a bundle that never went through the
/// pipeline.
public enum Migration027_NutritionFoodFactor: Migration {
    public static let version = 27
    public static let name = "nutrition_food_factor"

    public static func up(_ db: Database) throws {
        try db.execute("""
        CREATE TABLE nutrition_food_factor (
            food_ref      TEXT NOT NULL REFERENCES nutrition_food (food_ref) ON DELETE CASCADE,
            kind          TEXT NOT NULL CHECK (kind IN ('specific_gravity', 'edible_proportion')),
            value         REAL CHECK (value IS NULL OR value >= 0),
            qualifier     TEXT NOT NULL CHECK (qualifier IN (
                              'measured', 'trace', 'not_analysed', 'below_loq', 'borrowed',
                              'calculated_recipe', 'calculated_factor', 'zero_reported')),
            source_value  TEXT NOT NULL CHECK (source_value <> ''),
            source_record TEXT NOT NULL,
            licence_group TEXT NOT NULL CHECK (licence_group IN ('A', 'B', 'N')),
            PRIMARY KEY (food_ref, kind, source_record),
            CHECK ((qualifier IN ('trace', 'not_analysed')) = (value IS NULL)),
            CHECK (qualifier <> 'zero_reported' OR value = 0)
        ) STRICT;
        """)
    }
}
