# Nutrition — calorie reference database, v1

**Status:** the production reference bundle, importer, food logging and Nutrition
UI ship in the app as of 2026-09-25. The bundled SQLite resource is installed on
first launch and replaced only when its SHA-256 changes. Almanac-native dish
data remains unavailable.
**Decisions it implements:** the 2026-09-13 handoff (licence group N; general
Atwater 4/4/9/7; calorie-only canonical set; Branded Foods held out; SFDA never
stored) and Processing Design v0.1 in the food-data lake.

---

## 1. What exists

| Part | Where |
|---|---|
| Pipeline: extract → canonicalise → union → bundle → qa | `tools/nutrition/` (Python; `README.md` there is the contract) |
| Nutrient dictionary, qualifiers, licence groups, sources — as data | `tools/nutrition/dictionary/*.csv` |
| Bundle (what ships) | `Sources/AlmanacCore/Nutrition/Resources/almanac.sqlite`, schema version 1 |
| Reference tables | `Migration008_NutritionReference` (`nutrition_*`) |
| Bundle import, with the licence assertion run again | `NutritionReferenceImporter` |
| Read seam: food, values, bases, calories, search | `NutritionCatalog` |
| Calorie calculation | `GeneralAtwater`, `EnergyEstimate` |

The bundle holds 8,354 foods and 49,036 values from four sources:

| Source | Namespace | Group | Foods | Values |
|---|---|---|---:|---:|
| USDA FoodData Central 2026-04-30, Foundation Foods | `usda` | A | 395 | 1,867 |
| ANSES-CIQUAL 2025 | `ciqual` | B | 3,484 | 20,904 |
| CoFID 2021 | `cofid` | B | 2,887 | 15,459 |
| AFCD Release 3 | `afcd` | B | 1,588 | 10,806 |
| Almanac-native | `almanac` | N | 0 — awaiting dish data | |

## 2. The value

Every value is the §2 value model plus a basis: amount, qualifier, the source's
own confidence or derivation marker, the original cell text, the source's
nutrient id and unit, licence group, and `per_100g` or `per_100ml`.

- **A token never becomes a number.** CoFID `Tr` and CIQUAL `traces` are
  `trace`; CoFID `N` and CIQUAL `-` are `not_analysed`; both keep an empty
  amount and their original text. The pipeline refuses such a row with an
  amount, the bundle's and the device's tables refuse it (`CHECK`), and QA
  re-reads every raw cell to prove it.
- **A blank cell is no row.** "The source says nothing" and "the source says it
  has no number" are different facts, and both survive.
- **A 0 is only ever a published 0** (`zero_reported`).
- **A negative published amount is not a quantity** — no row, recorded in the
  source's manifest, never clamped to 0.
- **Per 100 g and per 100 mL never mix.** CoFID alcoholic beverages and AFCD's
  213 liquids carry `per_100ml`; AFCD liquids have both bases.

## 3. Identity

A reference food is the publisher's identifier in its namespace —
`usda:2346403`, `ciqual:1000`, `cofid:13-145`, `afcd:F002258` — never a
surrogate, because a food log must keep pointing at the same food across bundle
updates. When a publisher reuses an identifier within one release, every
occurrence becomes `{id}@row{n}` (CoFID 2021 uses `13-669` for two foods).

## 4. Licence enforcement, in four places

1. **Pipeline bundle step** — every row's group must be shippable (A, B, N) and
   agree with `dictionary/sources.csv`, or the build fails before any output
   exists.
2. **The bundle file** — its tables carry `CHECK (licence_group IN ('A','B','N'))`.
3. **Device import** — `NutritionReferenceImporter` re-runs `BundleGuard` over
   every source, food and value row and checks each group against
   `SourceIdentifier.Namespace.licenceGroup`. A restricted row throws
   `LicenceViolation` naming the row; a shippable group that disagrees with its
   namespace throws too. Nothing is written unless everything passes.
4. **Device tables** — migration 008 repeats the `CHECK`s, so no route inserts a
   restricted row.

A Swift test reads `tools/nutrition/dictionary/` and fails if the pipeline and
AlmanacCore ever disagree about qualifiers, licence groups or a source's group.

## 5. Calories

Almanac's calorie number is **general Atwater**: 4 kcal/g protein, 4 kcal/g
total carbohydrate, 9 kcal/g fat, 7 kcal/g alcohol — computed in AlmanacCore,
never stored, so native entries and reference foods share one implementation.

General Atwater assumes *total* carbohydrate (by difference, fibre included).
The term is chosen per food:

| Published | Carbohydrate term | Sources |
|---|---|---|
| Carbohydrate by difference | as published | USDA |
| Available carbohydrate + dietary fibre | sum | CIQUAL, AFCD |
| Available carbohydrate as monosaccharide equivalents + fibre | × 3.75/4 to weight, then sum | CoFID |

CoFID's monosaccharide equivalents count starch as the glucose it hydrolyses to
(×1.10) and disaccharides likewise (×1.05), which is why CoFID prices them at
3.75 kcal/g. Until 2026-10-07 they were taken at 4 kcal/g as a weight, which
overstated every CoFID food: median +8.3 kcal/100 g against the publisher, white
bread +10 %, white sugar 420 kcal/100 g from "105 g of carbohydrate per 100 g".
`GeneralAtwater.monosaccharideEquivalentsToWeight` converts first, so one
4 kcal/g factor holds for every source, and `totalCarbohydrateGrams` is the one
cross-source reading of "carbs" for anything that sums or shows them. The
coverage table below predates the change; its counts are unaffected.

Fibre is never assumed: available carbohydrate without a fibre value gives no
total. A trace or a "< x" enters the sum as 0, and so does absent or unanalysed
alcohol; `EnergyEstimate.inputsTakenAsZero` names every such input. When general
Atwater cannot be computed, `EnergyEstimate.preferred` falls back to the
publisher's own energy, marked `publisherReported`. It never shows a trace, an
unanalysed value or a bound as a calorie figure.

Coverage on the current bundle (food–basis pairs):

| Source | General Atwater | Publisher's figure | Neither |
|---|---:|---:|---:|
| USDA | 312 | 8 | 48 |
| CIQUAL | 3,367 | 31 | 86 |
| CoFID | 1,533 | 1,318 | 36 |
| AFCD | 1,801 | 0 | 0 |

CoFID leaves AOAC fibre blank for 46 % of its foods, hence its fallback share.
Against USDA's own published general-Atwater figure, Almanac's differs by a
median of 0.0 kcal over 311 foods. The largest differences from publishers'
own figures are high-fibre and sugar-free foods, where general factors count
fibre and polyols at 4 kcal/g; per-food factors are the decided v2 refinement.

## 6. Search

`NutritionCatalog.search` matches any language's name, folded with Laboratory's
`TextFold` (case, accents, Arabic letter variants), each food once, ordered by
primary name. Names are folded once, at import.

## 7. Not done

- **Almanac-native foods** — the pipeline slot and group N exist, and §9
  authoring is built; the Saudi/Gulf dish data itself does not exist.
- SR Legacy, FNDDS, Branded Foods, Frida, Oman FCT 2024.
- **Per-food Atwater factors** (v2).

## 8. Portions (built and imported, 2026-09-25)

`tools/nutrition/README.md` "Canonical format" and "Source rules" are the
contract; this is the summary. A fourth canonical file, `portions.csv`,
carries household-measure-to-gram conversion (Processing Design v0.1 §4),
validated independently of `values.csv` (`model.validate_portions`) so a
source with none is unaffected:

| Kind | Source | What it says |
|---|---|---|
| `household_measure` | USDA `food_portion` | `amount` of a named unit (e.g. "cup") weighs `value` grams |
| `specific_gravity` | CoFID "1.2 Factors" | the food's density, grams per mL |
| `edible_proportion` | CoFID "1.2 Factors" | the fraction of a gross weight that is edible |

The bundle's `nutrition_portion` table (schema v1, still version 1 — an
additive table) carries all three. QA (`portion_fidelity`) independently
re-reads USDA's `food_portion.csv` and CoFID's Factors sheet and compares
against canonical, the same discipline as the nutrient fidelity check; on the
full lake it re-reads 3,064 raw cells (123 household measures, 2,887 edible
proportions, 54 specific gravities) with 0 problems.

**Device import.** `NutritionReferenceImporter` maps `household_measure` rows
into AlmanacCore's `nutrition_portion` table and the two food-level factors into
`nutrition_food_factor` (migration 027). Reimport replaces imported portions and
factors with their reference food while preserving every device-authored dish
and that dish's own portions. The importer tests cover household conversion,
factor qualifiers, reimport deduplication and dish preservation.

## 9. Household measures, native dishes and the food log (AlmanacCore, 2026-09-15)

Migrations 009-011; `Database.transaction` nesting; `NutritionDishEditor`;
`NutritionLogStore`/`NutritionSummary`. Full account, including the defects
found and the judgement calls behind them, is in
`docs/implementation-status.md` under the same date — this is the pointer, not
a second copy.

In one line each: household measures are stored per food
(`NutritionCatalog.addPortion`/`portion(of:)`/`grams(of:)`, English-plural
matching, ambiguity returned rather than guessed); `almanac:` dishes are
authored and edited through `NutritionDishEditor`, with recipe reduction to
per-100-g values, cycle detection, and missing-ingredient/unmeasured/unit-
conflict reporting; what was eaten is recorded in `NutritionLogStore`
(revision-tracked, timeline-integrated) and totalled against the catalog by
`NutritionSummary`, joined at read time so a corrected reference value
corrects every meal already logged against it.

**Cross-source recipes (2026-10-07).** The reduction sums a nutrient only when
every ingredient reports that id, and publishers state carbohydrate under
different ids, so a USDA-plus-CIQUAL recipe lost its carbohydrate and with it
Almanac's calorie figure. `NutritionDishEditor.crossSourceValues` now adds, per
ingredient and then summed: total carbohydrate (stored as
`carbohydrate_by_difference`) when the same-id sums left none, alcohol with
absent taken as zero when any ingredient has some, and `energy_kcal` as the sum
of each ingredient's `EnergyEstimate.preferred`. Logging a dish now counts what
logging its ingredients would. `create` also registers the `almanac` source
row itself: no shipped bundle carries one, so dish creation previously failed
its foreign key on every real device while tests that hand-seeded it passed.

A `nutrition_dish` row marks a `nutrition_food` row as device-authored. On
reimport, pipeline foods, portions and food-level factors are replaced together,
while a person's own dish and its portions remain untouched.

## 10. Edible mass and `edibleGrams` (AlmanacCore, 2026-09-27)

`EdibleYieldCalculator` (`NutritionEdibleYield.swift`) is the one place a gross
(as-purchased) mass becomes an edible one. It is the port of the source branch's
`edibleGrams`, left out of the 2026-09-15 pass because it needs the
reference-food edible-proportion data §8 describes.

**The result is a four-way split, not a `Double?`.** CoFID states a proportion
for 2,887 of the bundle's 8,354 foods, so "nobody published one" is the common
case. An optional would sit that case next to a genuine "not analysed" and invite
the two wrong defaults — `?? 1.0` invents "nothing is discarded" for ~65% of the
catalogue, `?? gross` reports a gross mass as an edible one — and both return a
plausible number for a food the data says nothing about. So:

| Case | Means |
|---|---|
| `.known(edibleGrams:source:)` | a proportion was stated and applied; the mass and its provenance travel together |
| `.notAnalysed(source:)` | a factor row exists carrying CoFID's `N` — the source said it does not know |
| `.unstated` | no factor row at all: the majority of the catalogue, and every food outside CoFID |
| `.unusable(reason:)` | a proportion outside `(0, 1]`, or a density that is not a positive number of g/mL — the bundle's bug, not a missing fact |

Out-of-range values are refused rather than clamped. A bad *input* mass (NaN,
infinite, zero, negative) throws `NutritionError`, because that is the caller's
mistake, not a gap in the data.

A dish's own authored `nutrition_dish.edible_proportion` beats the bundle's
`nutrition_food_factor` row for the same food: it is the figure a person decided,
and `NutritionDishEditor` is the only writer of `nutrition_dish`.

`grams(fromVolumeMillilitres:for:)` applies `specific_gravity` and exists for the
one case that reaches it — a volume someone typed. A household measure does not:
`nutrition_portion.gram_weight` already converts "1 cup" straight to grams, so
that path stays in `NutritionCatalog.grams(of:amount:unit:modifier:)`.

**No production caller yet, and that is honest rather than forgotten.** Nothing in
the device schema has a slot for an as-purchased mass — `nutrition_log.grams` is
the mass the food was eaten at, and no screen asks a user to say "this is raw".
The derivation is built and tested so the answer is ready at the point a screen
starts asking; the thing missing is the column, not the calculation.

## 11. `NutritionSummary` coverage (2026-09-27)

`DayEnergyTests` builds `NutritionTotals` by hand, so the arithmetic that
actually produces them had no coverage. `NutritionSummaryTests` now runs the real
read against a real catalogue and pins the four ways a total declines to be
complete — the fields the UI has to be able to show, each one a place where the
tempting shortcut silently reports a smaller, wrong number:

- a meal with no stated amount is *named* (`mealsWithoutAmount`), never zeroed
- a meal whose food the catalogue does not hold is named by its `foodRef`
- a nutrient reported as `not_analysed` marks the day incomplete rather than
  adding zero, and is listed in `incompleteNutrients`
- a nutrient only some meals report is *absent* from `nutrients`, not smaller in
  it
- a nutrient reported on two different bases is dropped rather than added
- a day with no computable energy is partial under the energy sentinel, and says
  which routes (`energyBases`) the figure it does have came from
- a soft-deleted meal leaves the day rather than zeroing it

The logical-day read is covered both ways, not once: because a Riyadh day opens
at 04:00 local (01:00Z), one meal at `2026-09-17T00:30Z` belongs to the 16th and
one at `2026-09-18T00:30Z` belongs to the 17th. A naive `yyyy-MM-dd` range files
both under the opposite day, so the test asserts the two meals are on *opposite*
sides and that the right one is on each.
