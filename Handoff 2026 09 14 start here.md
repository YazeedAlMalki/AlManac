# Handoff — Almanac nutrition module, next steps

**Context:** Almanac is a free body-monitor app (sleep/food/energy/activity).
The 2026-09-13 handoff's calorie-database build order is done: nutrient
dictionary, USDA/CIQUAL/CoFID/AFCD extraction and canonicalisation, the
licence-guard bundle step, and the AlmanacCore wiring (migration, importer,
catalog, calorie calculation). None of that is repeated here — read the
referenced docs directly.

**Where the code is:** committed on `codex/manual-entry`, commit `9445a51`.
**Not pushed** — nothing has gone to a remote or been opened as a PR.

## What's actually built and verified

| | |
|---|---|
| Pipeline | `tools/nutrition/` (Python 3.14 + stdlib, openpyxl, lxml). `python3 -m almanac_nutrition all` runs extract→canonicalise→union→bundle for every source; `qa` re-reads every raw cell independently; `fixture` regenerates the cross-language test fixture. |
| Bundle | `~/ALManac-food-data/build/almanac.sqlite`, schema v1. 8,354 foods, 49,036 values, groups A/B only. Not in git — it's a lake artefact, rebuild it from `tools/nutrition` whenever needed. |
| AlmanacCore | `LicenceGroup.native` (group N), `Migration008_NutritionReference` (`nutrition_*` tables), `NutritionReferenceImporter` (re-asserts the licence guard before writing anything), `NutritionCatalog` (food/values/bases/search), `GeneralAtwater`/`EnergyEstimate` (4/4/9/7 kcal/g, publisher-reported fallback). |
| Tests | Swift: `source env.sh && swift test` → 115 tests, 114 pass, 1 skipped (opt-in `NutritionRealBundleTests`, enable with `ALMANAC_NUTRITION_BUNDLE=~/ALManac-food-data/build/almanac.sqlite`). Python: `cd tools/nutrition && python3 -m unittest discover -s tests -t .` → 101 pass; add `ALMANAC_NUTRITION_INTEGRATION=1` for the real-lake checks. |
| Docs | `docs/features/nutrition.md` (what shipped, coverage, energy-vs-publisher numbers), `tools/nutrition/README.md` (pipeline contract — read this before touching any source module), `~/ALManac-food-data/PROCESSING-LOG-2026-09-13.md` (findings in the data), `docs/implementation-status.md` (updated). |

QA is clean: 0 fidelity problems against the raw files, 0 tokens (`Tr`/`N`/
`traces`/`-`) turned into a number, 0 unexplained zeros, 0 licence problems.

## Two things genuinely blocked — not build tasks, don't re-attempt them

1. **Saudi/Gulf dish data for Almanac-native (`almanac:`) entries.** The
   schema, licence group N, and bundle slot all exist and are tested (see the
   `almanac:fixture-dish` rows in `tools/nutrition/fixtures/bundle_v1.sql`).
   What's missing is the actual dish data — recipes, personal knowledge, or a
   chosen reference. Has to come from Yazeed.
2. **SFDA licence question.** Long thread on 2026-09-14, fully written up at
   `~/ALManac-food-data/licenses/sfda/SDAIA-OPEN-DATA-LICENSE-RESEARCH-2026-09-14.md`.
   Short version: SDAIA's real Open Data Use License v2.0 and Terms of Use
   PDFs were read primary-source; the terms are favourable (attribution-based,
   and Almanac being free resolves the sale/rental prohibition in the Terms of
   Use); but **neither document names or lists the Saudi Food Composition
   Tables**, and no evidence was found that SFCT is actually published through
   `open.data.gov.sa` rather than just `sfda.gov.sa`'s press pages. SFDA stays
   **Group D, quarantined, unclear** until that specific link is confirmed —
   by finding SFCT listed on the open-data portal, a written SFDA reply (draft
   already sits at `~/ALManac-food-data/licenses/sfda/ENQUIRY-DRAFT.md`), or
   law-firm sign-off. Don't reopen the research — read the file, then either
   the confirmation exists or it doesn't.

## Suggested build order for next session

Nothing here depends on either blocked item above. Proceed under these unless
Yazeed redirects:

1. **Portions and household measures.** Processing Design v0.1 §4 already
   worked out that this is solved for Group A/B without the (Group D) FAO
   density database: USDA's `food_portion` table (`fdc_id` + `measure_unit` →
   `gram_weight`, CC0, already in the extracted USDA CSVs) and CoFID's
   `Specific gravity` / `Edible proportion` columns (`1.2 Factors` sheet,
   already extracted, not yet canonicalised). Add a `nutrition_portion` table
   and canonicalise both into it. This is the natural next data slice and
   reuses everything already built.
2. **Food logging.** The catalog can answer "what's in this food" and "how
   many calories" — nothing yet records "the user ate 150 g of this." Follow
   the existing per-module-table pattern (`lab_*`, `health_sample`): a
   `nutrition_log` table, source-scoped identity, revision-friendly, feeding
   the shared timeline the same way Laboratory and HealthSampleStore already
   do. `mattpocock-skills:tdd` for this, same as the reference-database work.
3. **Native manual-entry scaffolding**, mirroring Laboratory's
   (`FieldEdit`, `ManualEntryTests`, audited edits): the *mechanism* for
   entering an `almanac:` dish (per-100g values, or a recipe of other
   reference foods that `GeneralAtwater`-style logic reduces to per-100g) can
   be built and tested now, entirely independent of having real dish content.
   The moment dish data arrives, only data entry remains — not a design or
   schema task.

Optional, parallel, not code: a re-review of the Group C/D quarantine list in
`~/ALManac-food-data/LICENSES.md` now that "Almanac is free" is confirmed —
some entries were quarantined citing commercial redistribution specifically
(e.g. CC BY-NC-SA sources), which a free app may clear; others (ODbL
share-alike, request-only access) are unaffected by price and shouldn't be
re-litigated. Flagged, not started — say if you want it done.

## Suggested skills

- `mattpocock-skills:tdd` — for the portions table and food-logging module,
  same red-green-refactor pattern as the reference database.
- `data:explore-data` / `data:sql-queries` — for the USDA `food_portion` /
  CoFID Factors canonicalisation.
- `data:validate-data` — QA pass on portion gram-weights before wiring them
  in, same discipline as the nutrient QA pass.

## Don't do

- Don't re-run the SFDA/SDAIA licence research — it's written up, read it.
- Don't touch USDA Branded Foods, SR Legacy, FNDDS, Frida, or Oman FCT 2024
  without a reason; they're deliberately out of this phase.
- Don't ship or use SFDA, NEVO, TBCA, IFCT, FAO/INFOODS, Bahrain, Tunisia, or
  Open Food Facts data — all still Group C/D, quarantined.
- Don't open with clarifying questions about the two blocked items above;
  build the next-session order and flag anything that comes up.

## References

- `tools/nutrition/README.md` — pipeline contract, read before touching a source module
- `docs/features/nutrition.md` — what shipped
- `docs/implementation-status.md` — current test counts and toolchain notes
- `~/ALManac-food-data/PROCESSING-LOG-2026-09-13.md` — findings in the raw data
- `~/ALManac-food-data/licenses/sfda/SDAIA-OPEN-DATA-LICENSE-RESEARCH-2026-09-14.md` — the licence thread, in full
- `~/ALManac-food-data/PROCESSING_DESIGN.md` §4 — the portions/density-database reasoning for item 1 above

No secrets, credentials, or personal data in scope for this handoff.

---

## Starter prompt — paste this to open the next session

```
@"/home/yamal/Handoff 2026 09 14 start here.md"
/mattpocock-skills:tdd
/data:explore-data
/data:sql-queries
/data:validate-data

Attached is the handoff doc from the last Almanac session — read it and start
building, don't re-open it as a discussion. Follow its suggested build order:
portions/household measures (USDA food_portion + CoFID Factors), then food
logging, then native manual-entry scaffolding. Proceed under the existing
defaults; don't re-litigate anything already decided.

Use mattpocock-skills:tdd for the Swift module work (portions table, food log,
manual-entry scaffolding), matching how Laboratory, HealthSampleStore and the
nutrition reference module were built. Use data:explore-data / data:sql-queries
for the USDA food_portion / CoFID Factors canonicalisation scripts, and
data:validate-data for QA on the portion gram-weights before wiring them in.
Use mattpocock-skills:domain-modeling only if food logging introduces a
concept that genuinely doesn't fit the existing model.

Don't open with a battery of clarifying questions — build against the defaults,
flag issues as they come up. Only stop and ask me about the two items the
handoff names as blocked (Saudi/Gulf dish data, the SFDA licence question) or
anything genuinely not covered in the doc.
```
