# Kitchen — recipes from the pantry, the food log, or by name

**Status:** core and screens built 2026-10-05; made merge-ready 2026-10-06
(Migration 051 — renumbered from 050, see §5 — `Sources/AlmanacCore/Kitchen/`,
`Native/Almanac/KitchenRecipesView.swift`). No recipe data ships: Kitchen
works over the person's own dishes until an import is licensed (§4).

## 1. What exists

| Piece | Where |
|---|---|
| Pantry table | `kitchen_pantry_item` — Migration 051, the only table Kitchen adds |
| Pantry store | `KitchenPantry` — add / remove / items |
| Recipe lookup | `RecipeFinder` — `fromPantry`, `fromRecentLog(from:to:)`, `browse(_:)`, and the general `recipes(using:)` |
| App wiring | `NutritionModel+Kitchen.swift`; **Recipes** button beside **Saved meals** on the Nutrition screen |
| Tests | `KitchenTests` (11), `KitchenSeedPlanTests` (3); UI: `KitchenUITests` (4, **not yet run** — see §4) |
| UI-test seed | `KitchenSeedPlan` — `-AlmanacSeedKitchen recipes[,peanuts|,noallergens]`, DEBUG- and argument-gated like `VitalsSeedPlan`, because no screen creates a recipe |

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

**Matching — superseded 2026-10-06 by the owner's call: build the ingredient
table.** Was exact `food_ref`; now through `IngredientTable`. See §6, step 4.

**"Recent" is the last 7 days, and a logged dish counts its ingredients.**
`NutritionModel.recentRecipeWindow`; `RecipeFinder.throughRecipes`. Without the
expansion, someone who mostly logs saved meals gets no suggestions.
*Overrule by:* changing the constant, or removing the expansion call.

**The pantry is declared, never inferred from the log.** "I logged the last
egg" and "I logged an egg" are the same entry. *Overrule by:* not doing it.
**Confirmed by the owner 2026-10-06, with suggestions he approves** — see §6,
step 3.

**Allergens — superseded 2026-10-06 by the owner's call ("withhold and add a
warning", "same rule everywhere"); see §6.** A recipe is withheld when its name
or any ingredient name — through nested dishes — declares one of the person's
allergens. Everything else is `.noDeclaration`, and the screen shows the
disclaimer whenever allergens are recorded. A failed read of the allergen list is
an error on screen, not an empty set — an empty set drops the filter *and* the
disclaimer, which is an unfiltered list with nothing to say so.

**Default amount — superseded 2026-10-06 by the owner's call: one serving.**
See §6, step 2.

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
- **UI tests written, not run (2026-10-06).** `KitchenUITests` covers: opening
  Recipes from the Nutrition screen; adding and removing a pantry item; choosing
  a recipe and seeing it in the logging form; and a recipe whose ingredient
  declares a recorded allergen being withheld, with the disclaimer shown. They
  were written in a Linux container with no Xcode, so they have never been
  compiled or driven. The first Mac run is the check.
- **Dish creation was broken on a device, and is fixed (2026-10-06).** The
  shipped `almanac.sqlite` carries no `almanac` row in `nutrition_source`, and
  `nutrition_food.namespace` references it, so `NutritionDishEditor.create`
  failed its foreign key on every real install. `NutritionDishTests` seeded the
  row by hand with a comment saying the bundle always carries it. `create` now
  writes the row when it is absent;
  `NutritionBundleImportTests.testADishCanBeCreatedOnTheShippedReference` fails
  without that and passes with it. Nothing in the app created a dish before
  Kitchen's seed, which is why it never showed.

## 5. Coordination notes

- **Renumbered 050 → 051 on 2026-10-06** (`Migration051_KitchenPantry`, file
  `Migration051.swift`). 050 belongs to the fasting and prayer work (prayer
  preferences), which was still uncommitted on the iMac and lands on master
  first. Until it does, the migration list has a gap at 050, which the runner
  tolerates on a fresh database. It does **not** tolerate the reverse: once a
  database has applied 051, `MigrationRunner` refuses a pending 050 as
  `outOfOrder`. So merge the fasting work first, and do not run this branch on
  a device that will later need it. `BodyMeasurementTests.migrationUpgrade`
  lists `[41 … 49, 51]` here and gains the 50 when the fasting work merges.
- The contiguity checks (`CoreDailySchemaTests`, `MigrationFixtureTests`) were
  kept, not loosened: they subtract `reservedUnmergedMigrationVersions` (`[50]`,
  in `Tests/AlmanacCoreTests/MigrationReservation.swift`), and
  `testNoReservedVersionHasLanded` fails as soon as a 050 is in the list. **On
  merging the fasting work, empty that set** — the failing test says so.
- `project.pbxproj` gained four `KC…` entries. Its group and sources-phase
  lists are single lines, so a parallel branch adding Native files will conflict
  there; keep both sides' IDs.

## 6. The owner's six calls (2026-10-06), and how each was built

| Call | Built |
|---|---|
| Recipes: import TheMealDB, if its terms permit bundling and redistribution | **Gate shut.** The terms could not be read from the session's network (`docs/features/themealdb-terms.md`); nothing imported, no import tool. |
| Matching: build the ingredient table now | Step 4 — see below. |
| "Recent": last 7 days, as built | Unchanged. |
| Pantry: declared, with suggestions he approves | Step 3 — see below. |
| Allergens: withhold and add a warning, on the recipe itself; same rule on Saved meals | Step 1 — `DishAllergenCheck`, shared. |
| Default amount: one serving | Step 2 — see below. |

Meal planning: still not decided, not built.

### Step 1 — one allergen check for Kitchen and Saved meals

`DishAllergenCheck` (`Sources/AlmanacCore/Nutrition/`) is the single
implementation: `RecipeFinder.finish` and `SavedMeals.list` both call it, because
a recipe and a saved meal are the same `almanac:` row. On both screens:

- a dish naming a recorded allergen is **hidden by default**;
- a collapsed **"Hidden because of your allergens (N)"** entry
  (`HiddenDishesSection`, shared) lists them;
- opened, each dish has **its own page** (`HiddenDishPage`) with the warning
  first — "Allergen warning: this names Peanuts, which you have recorded as an
  allergen. Found in: Peanut sauce." — its ingredients, and the disclaimer;
- **"Log anyway…" asks for confirmation** before handing the dish to the logging
  form (unconfirmed, `CONTEXT.md`);
- an unreadable allergen list is an error on screen, on both
  (`SavedMeals.list()` reads it and throws; Kitchen's model already did).

Food search is unchanged. Tests: `DishAllergenCheckTests` (6) — hidden by
default, through nested dishes, reachable with a warning naming the allergen and
where it was found, nothing hidden or said with no allergens recorded, a failed
read is an error, and Kitchen and Saved meals giving the same judgement for the
same dish. `KitchenUITests.testARecipeDeclaringARecordedAllergenIsWithheld` now
opens the hidden entry, the page and the confirmation — **not run**.

### Step 2 — one serving is the default amount

Dishes carried no serving count, so Migration **052** adds
`nutrition_dish.serving_count` (nullable, `> 0`). Nobody's count set means **the
whole dish is one serving** until it is, as the handoff asked.
`NutritionDishEditor.oneServingGrams` and `RecipeMatch.oneServingGrams` are the
one rule: the finished weight (stated yield, else the sum of the ingredients)
over the count. A food with no recipe and no yield has no serving weight, and
nothing is pre-filled.

Choosing a recipe **and choosing a saved meal** pre-fill one serving, still
editable. Saved meals used to pre-fill the whole stated yield; it is the same
row, so it now takes the same default. The pre-filled figure is rounded rather
than truncated. `DishEdit.servingCount` sets a count; **no screen sets one yet**,
because no screen edits a dish at all.

Imported recipes (when there is an import — §4): TheMealDB's records are
believed to carry no serving count; that was not checkable from this session
(`docs/features/themealdb-terms.md`). The decision for them is in `CONTEXT.md`
(Kitchen, 2026-10-06): ask, not estimate.

Tests: `DishServingTests` (5) — no count is the whole dish, a count divides the
finished weight (yield when stated), clearing goes back, a label food has none,
a count of 0 is refused by the editor and the column, and Kitchen's match agrees
with the editor. `KitchenUITests.testChoosingARecipeHandsItToTheLoggingForm` now
also checks the 200 g pre-fill — not run.

### Step 3 — pantry suggestions, approved one at a time

`PantrySuggestions` (`Sources/AlmanacCore/Kitchen/`) offers a food when it was
logged on at least **3 distinct logical days in the last 14** (today included),
is not in the pantry, has not been dismissed, and is not itself a recipe. The
Pantry screen lists the offers above the pantry under "Logged often — add to
your pantry?", each with **Add** and **Dismiss**. Add puts it in the pantry;
Dismiss is stored in `kitchen_pantry_dismissal` (Migration **053**) so the food
is never offered again. Nothing is added without a tap. The thresholds and the
"not a recipe" rule are unconfirmed (`CONTEXT.md`).

Tests: `PantrySuggestionTests` (6) — days not entries, the 14-day window edge,
nothing added on its own and accept adds it, a stored dismissal survives a new
instance, recipes not offered, most-logged first. The screen is not compiled
here and has no UI test.

### Step 4 — the ingredient table

Migration **054** adds `kitchen_ingredient` (a canonical ingredient: id, name)
and `kitchen_ingredient_food` (`food_ref` → ingredient, with `source` =
`normalised` or `curated`). `IngredientTable.rebuild` fills it from every
primary name in the catalog — USDA, CIQUAL, CoFID, AFCD and the person's own
dishes — and runs after the reference bundle installs (`NutritionModel`), and
once on a database that predates the table.

**The merge rule** (`IngredientNormaliser`, unconfirmed — `CONTEXT.md`): set
aside how a food was prepared (raw, roasted, grilled, frozen, organic…) and its
cut-and-skin qualifiers (meat only, without skin, lean flesh…); keep words that
change what it is in a kitchen (dried, canned, smoked, salted, juice, powder);
and **never merge a name that says something was added** — coated, breaded,
battered, sauce, stuffed, marinated, glazed, filled, nuggets, ready meal. What
remains, folded and singularised, is the key. Curated overrides: three aliases
in `IngredientTable.curatedAliases` (CIQUAL's "Egg, raw" is a whole hen's egg;
breast strips are breast), plus per-food `curate(_:as:)` rows that a rebuild
never touches.

Measured on the shipped lake: 8,354 foods → 5,816 keys; 871 keys hold more than
one food, 251 of them across sources; 1,184 foods are held back by the
composition guard and match only themselves.

**Everything goes through it.** `RecipeFinder` matches pantry, log and recipe
ingredients by match key — the ingredient id when mapped, else the ref itself,
so an unmapped food (a new dish, a guarded food) matches exactly as before.
The allergen check (`DishAllergenCheck`) reads each food's own names **plus**
its canonical ingredient's name; it never reads fewer names than before, so it
cannot get weaker.

Tests: `IngredientTableTests` (9) — raw and roasted chicken breast are one
ingredient, a breaded or coated variant never merges, form words are kept,
pantry and log match through the table, an unmapped food matches itself,
curated rows survive a rebuild, the allergen check still hides a recipe when the
canonical name is silent, and reads a canonical name that declares; and
`IngredientTableShippedLakeTests` (1) against the real bundle.
