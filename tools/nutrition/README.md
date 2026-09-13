# Almanac nutrition pipeline

Builds the calorie reference database from the licence-cleared food-composition
sources in the food-data lake (`~/ALManac-food-data`, override with
`ALMANAC_FOOD_DATA` or `--lake`). This file is the contract every stage and
every source module honours. The design it implements is
`~/ALManac-food-data/PROCESSING_DESIGN.md` (Processing Design v0.1); section
references below (§n) point there.

## Scope of this phase

| Source | Namespace | Group | What is canonicalised |
|---|---|---|---|
| USDA FoodData Central 2026-04-30 | `usda` | A | Foundation Foods listed in `foundation_food.csv` (395). Branded, SR Legacy, FNDDS and the 74 unlisted Foundation records are extracted or left in raw, not canonicalised. |
| ANSES-CIQUAL 2025 | `ciqual` | B | All 3,484 foods |
| CoFID 2021 | `cofid` | B | All 2,887 rows of `1.3 Proximates` |
| AFCD Release 3 | `afcd` | B | All 1,588 foods, per 100 g and (213 liquids) per 100 mL |
| Almanac-native | `almanac` | N | Nothing yet — awaits Saudi/Gulf dish data |

Canonical nutrients are only what calorie calculation needs (energy, protein,
fat, carbohydrate, fibre, alcohol). The dictionary splits some of these into
more than one canonical nutrient where sources publish different quantities
under the same name — see "Carbohydrate" below.

Group C and D sources (Open Food Facts, SFDA, NEVO, TBCA, IFCT, FAO/INFOODS,
Bahrain, Tunisia, Lebanon, INNTA) are never read by this pipeline.

## Stages

```
raw/  (0444, checksummed in manifests/)
  │ extract       per source; verifies every input's sha256 against the
  │               collection manifest first; no renaming, no typing
processed/extracted/{namespace}/     source's own shape, every cell a string
  │ canonicalise  per source, still separate; applies dictionary/ only
processed/canonical/{namespace}/     foods.csv, food_names.csv, values.csv, manifest.json
  │ union         every canonical/{namespace}/ present, re-validated
processed/union/
  │ bundle        the licence assertion, then SQLite
build/almanac.sqlite
```

Each stage writes only its own directory, via a scratch directory that
replaces the previous output only when the stage finishes (`lake.staged_directory`).
Deleting any `canonical/{namespace}/` and re-running `union` + `bundle` removes
that source completely — the property §5 exists to protect.

```sh
cd tools/nutrition
python3 -m almanac_nutrition extract usda        # or ciqual | cofid | afcd
python3 -m almanac_nutrition canonicalise usda
python3 -m almanac_nutrition union
python3 -m almanac_nutrition bundle
python3 -m almanac_nutrition all                 # every source, then union + bundle
python3 -m almanac_nutrition qa                  # independent re-read of every raw cell
python3 -m almanac_nutrition fixture             # regenerate fixtures/bundle_v1.sql
python3 -m unittest discover -s tests -t .       # fast; synthetic fixtures only
ALMANAC_NUTRITION_INTEGRATION=1 python3 -m unittest discover -s tests -t .   # + real lake
```

Needs Python ≥ 3.11 with `openpyxl` and `lxml`. Nothing else.

`qa` (`almanac_nutrition/qa.py`) re-reads every mapped raw cell with readers of
its own — it imports no source module — and writes `processed/qa/report.md`.
It exits 1 if any hard check fails: raw-to-canonical fidelity, a token carrying
an amount, a 0 without a raw 0, or a licence group out of place. Energy against
each publisher's own figure and macronutrient sums over 105 g are reported for
review, not enforced.

`fixtures/bundle_v1.sql` is a small synthetic bundle made by the real union and
bundle stages; AlmanacCore's tests import it, so it is the contract between the
two languages. `tests/test_fixture.py` fails if it is stale.

## Dictionary — data, not code (`dictionary/`)

| File | Holds |
|---|---|
| `nutrients.csv` | Canonical nutrients: `nutrient_id`, INFOODS tag, name, unit, description. |
| `nutrient_map.csv` | `(source, source_nutrient_id) → nutrient_id`, with `priority` (when several source columns feed one canonical nutrient), `unit_conversion` (`""` or `kj_to_kcal`), and `numeric_qualifier_override`. |
| `qualifiers.csv` | The closed qualifier vocabulary (§2) and, per qualifier, whether an amount is `null` or `required`. Must equal `NutrientQualifier` in AlmanacCore — a Swift test checks this. |
| `licence_groups.csv` | A, B, C, D, N and whether each may ship. Must agree with `LicenceGroup.isShippable` — a Swift test checks this. |
| `sources.csv` | One row per namespace: dataset id, release, licence, licence group, attribution text. The licence group of every row is taken from here, never from a source module. |
| `derivation_qualifiers.csv` | A source's own per-value derivation code → qualifier (USDA's 80 codes; AFCD's food-level derivation). |
| `value_tokens.csv` | Exact non-numeric cell tokens → qualifier (`cofid Tr`, `cofid N`, `ciqual traces`, `ciqual -`). Tokens may only map to qualifiers whose amount is `null`. |

`dictionary.load()` cross-checks all seven and fails with every problem at
once. Its SHA-256 is recorded in every canonical manifest; `union` refuses a
canonical directory built against a different dictionary.

## Canonical format (`processed/canonical/{namespace}/`)

UTF-8 CSV, header row, `\n` line endings, rows sorted by key. Empty string
means absent.

`foods.csv` — `food_ref, namespace, local_id, licence_group, food_group_code, food_group_name, source_record`
- `food_ref` is `namespace:local_id` (§3). `local_id` is the publisher's
  identifier, verbatim. If a publisher repeats an identifier within one
  release, **every** occurrence becomes `{id}@row{n}` (`n` = spreadsheet row);
  nothing is dropped or merged. (CoFID 2021 reuses `13-669` for two foods.)
- `licence_group` must equal `sources.csv` for the namespace.
- `source_record` says where the row came from (`food.csv fdc_id=321358`,
  `1.3 Proximates!row 674`, …).

`food_names.csv` — `food_ref, language, name, is_primary`
- One name per language; exactly one primary (`1`) per food. Languages are
  lower-case ISO 639 codes (`en`, `fr`, later `ar`).

`values.csv` — `food_ref, nutrient_id, basis, amount, qualifier, confidence, source_value, source_nutrient_id, source_unit, licence_group`
- The value model of §2 plus `basis`. Unique on `(food_ref, nutrient_id, basis)`.
- `basis` is `per_100g` or `per_100ml` — a column, never an assumption (§4).
- `amount` is in the canonical unit, `repr(float)`, empty only for
  qualifiers whose amount rule is `null` (`trace`, `not_analysed`).
- `source_value` is the original cell, unparsed (whitespace trimmed; XLSX
  numeric cells as the shortest round-trip decimal of the stored double).
  It is never empty.
- `source_nutrient_id` / `source_unit` are the source's own, verbatim.
- `confidence` is the source's own per-value quality or derivation marker,
  verbatim: USDA derivation code (`A`, `NC`), CIQUAL `code_confiance` (`A`–`D`),
  AFCD food-level derivation (`Analysed`), empty for CoFID.

`manifest.json` — namespace, dataset, release, licence group, dictionary
SHA-256, inputs with SHA-256, output SHA-256s, counts by nutrient / qualifier /
basis, and `notes` (exclusions with reasons, collisions, anything a reviewer
must see).

### Blank cells produce no row

A blank cell (or an absent USDA `food_nutrient` row) means the source says
nothing, and produces **no value row**. A token that says "no number" (`N`,
`-`) produces a row with `amount` empty. Those are different facts and both
survive.

## Qualifying a value — one function, in this order (`values.qualify`)

1. Exact token from `value_tokens.csv` → that qualifier, `amount` empty.
   **A token never becomes 0.**
2. Bound prefix (CIQUAL `< x`) → `below_loq`, `amount` = x (the bound).
3. Anything that is not a plain finite decimal → **the stage fails**
   (`UnrecognisedValue`). No cell is guessed at. The one exception is a
   negative number (`NegativeAmount`): it is not a quantity, so it produces
   no row and the source module records it in `notes.rejected_values`. It is
   never stored and never clamped to 0. (USDA publishes negative
   "carbohydrate, by difference" when the other proximates exceed 100 g.)
4. Explicit zero → `zero_reported`, `amount` 0.
5. `numeric_qualifier_override` from the mapping row (all published energy
   values are `calculated_factor` — no food table measures energy).
6. The source's derivation code via `derivation_qualifiers.csv`.
7. Otherwise `measured`.

Then `unit_conversion` (kJ → kcal is ÷ 4.184). Where several source columns
map to one canonical nutrient, the lowest `priority` that carries a quantity
wins; if none does, the lowest priority's marker is kept (`values.select`).

Every canonical row set is re-validated before it is written
(`model.validate`), including an independent check that **an amount of 0
only ever comes from a cell that says 0**.

## Source rules

### USDA (`sources/usda.py`) — reference implementation
- Inputs: `FoodData Central United States/FoodData_Central_csv_2026-04-30/*.csv`
  (manifest `usda`).
- Extract: `food.csv` rows with `data_type = foundation_food` (469), their
  `food_nutrient` and `food_portion` rows, plus the lookup tables whole.
- Canonicalise: foods listed in `foundation_food.csv` (395). The other 74 are
  recorded in `manifest.json` `notes.excluded` (68 share a description with a
  listed record — superseded versions). Values per 100 g; qualifier from
  `derivation_id` → code → `derivation_qualifiers.csv`; blank code →
  `measured` (Foundation Foods are analytical); `confidence` = the code.

### CIQUAL (`sources/ciqual.py`)
- Inputs: `raw/ciqual/2025/{alim,alim_grp,compo,const,sources}_2025_11_03.xml`
  (UTF-8 with BOM, CRLF). Extract each to CSV, one column per element, text
  trimmed, `missing=" "` → empty.
- Foods: every `alim_code`; names `en` (primary, `alim_nom_eng`) and `fr`.
- Values: `teneur` of mapped `const_code`s; decimal comma; tokens `traces`,
  `-`; `< x` → `below_loq`; `confidence` = `code_confiance`. Per 100 g.

### CoFID (`sources/cofid.py`)
- Inputs: `raw/cofid/2021/McCance_Widdowsons_Composition_of_Foods_Integrated_Dataset_2021.xlsx`.
  Extract every sheet verbatim (all three header rows kept).
- Foods: `1.3 Proximates` rows 4+ with a Food Code; name `en`; group code.
- Columns are identified by the code row (row 2: `KCALS`, `PROT`, `FAT`,
  `CHO`, `AOACFIB`, `ALCO`). `Tr` → `trace`, `N` → `not_analysed`, blank → no
  row. Bracketed values `(0.07)` appear only in fatty-acid sheets; one in a
  mapped column fails the stage.
- Basis: `per_100ml` for group codes starting `Q` (alcoholic beverages; user
  guide p.7), otherwise `per_100g`.

### AFCD (`sources/afcd.py`)
- Inputs: `raw/ausnut/release-3/*.xlsx` (manifest `ausnut`). Extract every sheet.
- Foods: `All solids & liquids per 100 g`; name `en`; `Classification` code.
- Values from that sheet (`per_100g`) and from `Liquids only per 100 mL`
  (`per_100ml`). Columns identified by header text with whitespace collapsed.
  Qualifier from the food-level `Derivation` via `derivation_qualifiers.csv`;
  `confidence` = that derivation. Energy is kJ → kcal.

## Licence guard and bundle

`bundle` fails the build — before any output exists — if any food or value
row has a licence group outside `licence_groups.csv` `shippable = true`
(A, B, N), or a licence group that disagrees with `sources.csv` for its
namespace. It then re-checks the written database and runs
`integrity_check` / `foreign_key_check`. The bundle's own tables also carry
`CHECK (licence_group IN ('A','B','N'))`, so a restricted row cannot be
inserted into it by any route.

Bundle schema version 1 (`bundle.schema_sql`): `bundle_meta`,
`nutrition_source`, `nutrition_nutrient`, `nutrition_qualifier`,
`nutrition_food`, `nutrition_food_name`, `nutrition_value`. AlmanacCore's
`NutritionReferenceImporter` reads exactly this and re-asserts the licence
groups itself.

## Energy: stored vs calculated

The bundle stores what publishers said: `energy_kcal` (each publisher's
headline figure, using its own factors — not comparable across publishers)
and `energy_general_atwater_kcal` (USDA's own general-Atwater figure).
Almanac's calorie number — general Atwater, 4/4/9/7 kcal/g — is calculated in
AlmanacCore (`GeneralAtwater`), not here, so native entries and reference
foods go through one implementation.

### Carbohydrate

General Atwater applies 4 kcal/g to **total** carbohydrate (by difference,
fibre included). Sources publish different quantities under "carbohydrate",
so the dictionary keeps them apart:

| Canonical | Meaning | From |
|---|---|---|
| `carbohydrate_by_difference` | total, fibre included | USDA 1005 |
| `carbohydrate_available` | sugars + starch (+ polyols) by weight, no fibre — the EU 1169/2011 definition | CIQUAL 31000, AFCD "with sugar alcohols", USDA 1050 |
| `carbohydrate_available_monosaccharide` | same, as monosaccharide equivalents | CoFID CHO |
| `fibre_total_dietary` | AOAC total dietary fibre | USDA 1079/2033, CIQUAL, CoFID AOACFIB, AFCD |

Collapsing them into one "carbohydrate" would under-count every fibre-rich
food outside USDA by 4 kcal per gram of fibre. CoFID's Englyst NSP is a
different measurement and is not mapped.
