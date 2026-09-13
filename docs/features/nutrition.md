# Nutrition — calorie reference database, v1

**Status:** built 2026-09-13. Reference data and calorie calculation only; no
food logging, portions or UI yet.
**Decisions it implements:** the 2026-09-13 handoff (licence group N; general
Atwater 4/4/9/7; calorie-only canonical set; Branded Foods held out; SFDA never
stored) and Processing Design v0.1 in the food-data lake.

---

## 1. What exists

| Part | Where |
|---|---|
| Pipeline: extract → canonicalise → union → bundle → qa | `tools/nutrition/` (Python; `README.md` there is the contract) |
| Nutrient dictionary, qualifiers, licence groups, sources — as data | `tools/nutrition/dictionary/*.csv` |
| Bundle (what ships) | `~/ALManac-food-data/build/almanac.sqlite`, schema version 1 |
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
| Available carbohydrate as monosaccharide equivalents + fibre | sum | CoFID |

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

- **Almanac-native foods** — the pipeline slot and group N exist; the Saudi/Gulf
  dish data does not.
- **App wiring** — the app target must ship `almanac.sqlite` as a resource and
  call `importBundle(at:)` on first launch and after an update. Not done here:
  no Apple toolchain in this environment.
- **Food logging, portions and household measures** (USDA `food_portion`, CoFID
  specific gravity), SR Legacy, FNDDS, Branded Foods, Frida, Oman FCT 2024.
- **Per-food Atwater factors** (v2).
