# Kitchen — recipes from the pantry, the food log, or by name

**Status:** core and screens built 2026-10-05 (Migration 050, `Sources/AlmanacCore/Kitchen/`,
`Native/Almanac/KitchenRecipesView.swift`). No recipe data ships: Kitchen
works over the person's own dishes until an import is licensed (§4).

## 1. What exists

| Piece | Where |
|---|---|
| Pantry table | `kitchen_pantry_item` — Migration 050, the only table Kitchen adds |
| Pantry store | `KitchenPantry` — add / remove / items |
| Recipe lookup | `RecipeFinder` — `fromPantry`, `fromRecentLog(from:to:)`, `browse(_:)`, and the general `recipes(using:)` |
| App wiring | `NutritionModel+Kitchen.swift`; **Recipes** button beside **Saved meals** on the Nutrition screen |
| Tests | `KitchenTests` (11) |

A recipe is an `almanac:` dish with at least one component — the same row the
**Saved meals** list shows. Choosing one in the Recipes picker hands the dish
back to `NutritionQuickEntryView`, which logs it through `NutritionModel.log`,
so totals, revisions and the §7.2 night window all apply unchanged.

## 2. Where the standalone module's integration points landed

The handoff of 2026-10-05 described a Node/better-sqlite3 module
("Almanac Kitchen") with six `ak_*` tables and four marked integration points.
Its tarball was never on this machine, and a Node runtime cannot ship in the
iOS app, so Kitchen was built natively instead. Each integration point
resolved to something this schema already had:

| Integration point | Resolution |
|---|---|
| `ak_ingredients.canonical_food_id` → nutrition lake | An ingredient is a `food_ref` (`usda:…`, `cofid:…`, `almanac:…`) in `nutrition_dish_component.component_ref`. No FK, per Migration 009/010. The lake is USDA/CIQUAL/CoFID/AFCD; there is no Open Food Facts data. |
| `getIngredientNutritionPer100g()` stub | Not needed. `NutritionDishEditor.setRecipe` already reduces components to per-100 g values (`RecipeReduction`), and it refuses to treat a missing or unmeasured value as zero. |
| `ak_logged_meals_recipe_link.logged_meal_id` → food log | Not needed. `nutrition_log` is one row per food with a TEXT id; a logged recipe is a row whose `food_ref` is the dish. That row *is* the link. |
| `created_by_user_id` / `user_id` → users | Dropped. Almanac holds one person; there is no users table, only `profile`. |

## 3. Decisions taken without an answer

None of these has been confirmed. Each can be overruled in one place.

**Matching is by exact `food_ref`.** Pantry, log and recipe components all come
from the same catalog search, so the match is a set intersection in SQL. The cost:
USDA "Chicken breast, raw" and CoFID "Chicken breast, roasted" do not match.
*Overrule by:* adding a canonical-ingredient table (`food_ref` → ingredient)
and joining through it in `RecipeFinder.load` — the natural home for the
standalone module's `ak_ingredients`.

**"Recent" is the last 7 days, and a logged dish counts its ingredients.**
`NutritionModel.recentRecipeWindow`; `RecipeFinder.throughRecipes`. Without the
expansion, someone who mostly logs saved meals gets no suggestions.
*Overrule by:* changing the constant, or removing the expansion call.

**The pantry is declared, never inferred from the log.** "I logged the last
egg" and "I logged an egg" are the same entry. *Overrule by:* not doing it.

**Allergens withhold recipes, same rule as food search.** A recipe is withheld
when its name or any ingredient name — through nested dishes — declares one of
the person's allergens. Everything else is `.noDeclaration`, and the screen
shows the disclaimer whenever allergens are recorded. This covers Kitchen's
suggestions; it does *not* close the saved-meals gap recorded in `CONTEXT.md`,
because that is a different screen.

**No default amount when a recipe is chosen.** A recipe's total weight is
usually several servings. *Overrule by:* passing a weight in
`KitchenRecipesView.choose`.

## 4. Not done, and why

- **No recipe import.** The standalone module ingested 793 TheMealDB recipes.
  That data is not here, and shipping it is an R-FOOD question first: TheMealDB's
  terms have not been checked for bundling or redistribution, and
  `docs/attribution-requirement.md` requires an Attributions entry for any
  bundled source. An import, once licensed, belongs in `tools/` beside the
  nutrition pipeline. It would write `almanac:` dishes whose components are
  resolved `food_ref`s, and would need the canonical-ingredient table from §3
  to resolve "2 chicken breasts" to a ref.
- **No meal planning.** The handoff named it as a third matching mode, but
  none of the four functions it asked to be wired was a planner.
- **Ingredient names are the only allergen evidence.** As for food search: a
  name can be silent about an allergen.
- **Unrun:** the UI test suite. The screens were compiled (`xcodebuild build`)
  but not driven; no `AlmanacUITests` case covers Kitchen yet.

## 5. Coordination notes

- Migration **050** is taken by `Migration050_KitchenPantry`. A branch that also
  adds a 050 must renumber before merging; `BodyMeasurementTests.migrationUpgrade`
  lists every migration since 041 and will fail until it is updated.
- `project.pbxproj` gained four `KC…` entries. Its group and sources-phase
  lists are single lines, so a parallel branch adding Native files will conflict
  there; keep both sides' IDs.
