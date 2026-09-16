# Almanac implementation status

Updated 2026-09-13. Work continues from `8836166` on `codex/manual-entry`; all
preceding commits are preserved. The nutrition work below is uncommitted in the
working tree. Nothing pushed.

## Verified core

Swift 6.3.3 on x86_64 Linux (`yamal`, `source env.sh`): **115 XCTest tests —
114 pass, 1 opt-in test skipped, zero failures.** Plain `swift build && swift
test`; the default parallel build works on this machine. The skipped test
imports the real bundle, and passes when enabled:

```sh
ALMANAC_NUTRITION_BUNDLE=~/ALManac-food-data/build/almanac.sqlite \
    swift test --filter NutritionRealBundleTests
```

Python 3.14, `tools/nutrition`: **101 unittest tests, zero failures**, including
the real-lake integration tests:

```sh
cd tools/nutrition && ALMANAC_NUTRITION_INTEGRATION=1 python3 -m unittest discover -s tests -t .
```

Earlier records: 85 tests on Swift 6.0.3 in the 2026-09-08 session container
(`-j 1 -Xswiftc -disable-batch-mode`); 79 on Swift 6.3.3 per the user log. No
change has been run on an Apple platform.

## Nutrition module (2026-09-13)

The 2026-09-13 handoff's build order, steps 1–6:

1. Nutrient dictionary and qualifier vocabulary as data: `tools/nutrition/dictionary/`.
2. USDA Foundation Foods extracted, and 3. canonicalised (395 foods).
4. Bundle step with the failing licence assertion (`A`, `B`, `N` or the build
   fails), built while USDA was the only source.
5. CIQUAL 2025, CoFID 2021 and AFCD R3 extracted and canonicalised; union; the
   bundle holds 8,354 foods and 49,036 values. `qa` re-reads every mapped raw
   cell with independent readers: passed, 0 tokens coerced.
6. AlmanacCore: `LicenceGroup.native` (`N`, ships; the `almanac` namespace moved
   from `A` to `N`); `NutrientValue.basis`; migration 008 (`nutrition_*`
   reference tables with licence and qualifier CHECKs);
   `NutritionReferenceImporter` (re-runs the licence assertion against Swift's
   own registry before copying anything, in one transaction); `NutritionCatalog`
   (food, values, bases, calories, folded search); `GeneralAtwater` and
   `EnergyEstimate` (4/4/9/7 on total carbohydrate, publisher's figure as a
   labelled fallback).

Details: `docs/features/nutrition.md`. Pipeline contract:
`tools/nutrition/README.md`. Findings in the data:
`~/ALManac-food-data/PROCESSING-LOG-2026-09-13.md`.

Not done: Almanac-native dish data (blocked on Yazeed); wiring the bundle
import into the app target (needs the Apple toolchain); food logging and portions.

## Nutrition portions, pipeline side (2026-09-15)

`tools/nutrition/` step 1 of the 2026-09-14 handoff's build order: a fourth
canonical file (`portions.csv`) and bundle table (`nutrition_portion`)
carrying USDA `food_portion` (household measures) and CoFID "1.2 Factors"
(specific gravity, edible proportion). Details: `docs/features/nutrition.md`
§8; contract: `tools/nutrition/README.md` "Canonical format".

Python 3.14, `tools/nutrition`: **102 unittest tests, zero failures**,
including the real-lake integration tests and a new fidelity check
(`qa.portion_fidelity`) that re-reads every raw portion cell independently —
0 problems against the full 8,354-food lake (3,064 raw cells re-read: 123
household measures, 2,887 edible proportions, 54 specific gravities).

**Not reconciled with AlmanacCore.** A concurrent branch (uncommitted at the
time of writing) independently built its own `nutrition_portion` table
(migration 010) scoped to household measures only, with `edible_proportion`
living on a separate `nutrition_dish` table for the user's own `almanac:`
dishes — it has no slot for CoFID's per-reference-food edible proportion or
specific gravity. `NutritionReferenceImporter` was deliberately left
untouched here rather than risk clobbering that in-progress, uncommitted
work; the Swift test counts above predate it and were not re-verified this
session. See `docs/features/nutrition.md` §8 before starting that
reconciliation.

## Nutrition: transactions, portions, native dishes, the food log (2026-09-15)

The AlmanacCore side of the 2026-09-14 `claude/ponytail-anxf91` handoff,
reconciled onto `codex/manual-entry`'s bundle-imported schema (migration 008
wins over that branch's competing `nutrition_food`/`nutrition_value` — richer,
namespaced, per-basis, already populated with 8,354 real foods). Its own
migration 008 comment called this "a mechanical merge, but a real one"; in
practice the two schemas differed enough (namespace, basis, multi-language
names vs. a flat single-language table) that every ported file needed
rewriting against `NutritionCatalog`'s actual shape, not just repointing.

- **`Database.transaction` nests** (`Database.swift`): a call made while one is
  already open now uses a `SAVEPOINT` instead of failing, guarded by a
  per-connection `NSRecursiveLock` so a second thread mid-transaction gets a
  genuine outer transaction rather than silently attaching to the first
  thread's work. `DatabaseTests.swift`, 9 tests, ported unchanged — it never
  depended on the nutrition schema.
- **Migrations 009-011**: `nutrition_log`/`nutrition_log_revision` (009, the
  food log — untyped `food_ref`, no foreign key, so removing a reference
  source can never erase a meal); `nutrition_dish` + `nutrition_portion` +
  `nutrition_dish_component` (010); the portion-identity unique index (011).
  `nutrition_dish` holds `yield_grams`/`edible_proportion` for `almanac:`
  foods in its own table rather than widening migration 008's `nutrition_food`
  — that table intentionally mirrors the bundle schema, and a dish-only column
  would break the mirror. (§8 above names the still-open question these three
  tables don't answer: CoFID ships edible-proportion/specific-gravity for
  *every* reference food, not just dishes, and that doesn't fit here either.)
- **`NutritionDishEditor`** (`NutritionDish.swift`): create/edit/delete for
  `almanac:` foods; `setRecipe`/`recompute` with cycle detection and
  missing-ingredient/unmeasured-nutrient/unit-conflict reporting
  (`RecipeReduction`). Reduction always writes basis `.per100g` (a dish is
  solid) and `ref.namespace.licenceGroup` for the value rows — the source
  branch hardcoded licence group A there, which would have mislabelled every
  computed dish value.
- **`NutritionCatalog`** gained portion read/write (`addPortion`, `portion(of:
  unit:modifier:)`, `grams(of:...)`, English-plural matching, ambiguity
  returned rather than guessed) — ported as-is, schema-independent.
  `edibleGrams`/`removeSource` were not ported: the first needs the
  reference-food edible-proportion CoFID data §8 is about, the second is
  already subsumed by the importer fix below.
- **`NutritionLogStore`/`NutritionSummary`** (food log, revisions, timeline
  integration, day totals): ported with call sites adjusted to
  `values(for:basis:)`/`EnergyEstimate.preferred(from:basis:)` instead of the
  source branch's single-basis catalog. `EnergyEstimate.scaled(toGrams:)` and
  `NutrientValue.scaled(toGrams:)` (`NutritionScaling.swift`) needed adding —
  this codebase's `EnergyEstimate` had no scaling method yet.
- **Defect found and fixed: `NutritionReferenceImporter` blanket-deleted and
  reimported every table on every `importBundle` call.** The bundle already
  carries an `almanac` source row and, per the fixture, can carry `almanac:`
  food rows of its own — a curated native food is ordinary reference data,
  replaced on reimport like any other. A user-authored dish is not, and the
  blanket delete would have erased every dish on the next bundle update, with
  nothing to distinguish the two: both are `namespace = 'almanac'`. Fixed by
  scoping the delete to `food_ref NOT IN (SELECT food_ref FROM
  nutrition_dish)` — only `NutritionDishEditor.create` ever inserts a
  `nutrition_dish` row, so its presence is exactly "a person authored this
  here," regardless of namespace. `nutrition_source`/`nutrition_nutrient` are
  upserted row-by-row rather than replaced, because a preserved dish's values
  still reference both and SQLite enforces foreign keys per-statement, not at
  transaction end — deleting either out from under a surviving row fails
  immediately, even mid-transaction. (SQLite also refuses `ON CONFLICT` after
  an `INSERT ... SELECT`; only a `VALUES`-sourced insert accepts it, hence the
  per-row loop instead of a set-based upsert.)
  `NutritionBundleImportTests.testReimportingReplacesAndDropsARemovedSource`
  and a new `NutritionDishTests` case
  (`testReimportingTheBundlePreservesADeviceAuthoredDishAndReplacesABundleShippedOne`)
  cover both directions.
- **Arabic search-folding regression coverage** added to
  `NutritionReferenceTests.swift` (hamza/harakat/tatweel folding, internal and
  surrounding whitespace, Arabic-Indic digits) against `NutritionCatalog.search`
  — `TextFold` itself is unchanged and shared with Laboratory; these three
  tests just pin that `NutritionCatalog` exercises it the same way.

**Verified:** `swift build && swift test` on Swift 6.3.3 (`yamal`, `source
env.sh`) — 174 tests, 0 failures, 1 opt-in test skipped (unchanged from
before). Satisfies the ponytail handoff's outstanding item 3 ("test on
6.3.3"); its item 2 (populate the catalog) was already done independently on
this branch (8,354 foods); its item 1 (the schema duplication) is this
section.

**Still open, not attempted here** — flagged rather than guessed at, per the
existing rule that publicly accessible is not the same as reconciled:
1. Unifying `nutrition_portion` (this section) with the pipeline's
   three-kind portion table (§8) — needs that work to land first; both are
   uncommitted and it would be reconciling against a moving target.
2. `edibleGrams` and any specific-gravity lookup — blocked on the same thing.
3. The Saudi/Gulf native dish *data* — unchanged, still blocked on supply, not
   a build task; `NutritionDishEditor` can author dishes today, there just
   aren't any yet.
4. Portions/dish-components on a *non-native* reference food do not survive
   that food's own reimport (`ON DELETE CASCADE` from `nutrition_food`, which
   a bundle-namespace food is still fully replaced on) — pre-existing
   behaviour of the "replace on reimport" design, not introduced here, and
   out of scope for this pass.
5. A second, apparently unrelated concurrent session added hydration tracking
   (`Sources/AlmanacCore/Hydration/`, migration 012) to this same working tree
   while this work was in progress. No collision occurred — its migration
   number was claimed after this session's 009-011 — but it is a reminder this
   checkout had two sessions writing to it at once.

## Targeted corrections

- Unranked report imports default to `holdAsConflict`. Incoming report content
  is retained. `resolveReportConflict` accepts/rejects atomically, requiring an
  actor and reason and recording resolution time. Resolved proposals no longer
  count as unresolved, including replays of rejected equal-version content.
  Resolution fields are available through `reportRevisions`.
- Explicit observation corrections compare only with the current revision.
  A → B → deliberate A creates three attributable revision events. Import
  replay detection still searches historical fingerprints and creates no copy.
- Unchanged report content advances a newer source ordering marker. A/v1 →
  A/v3 → B/v2 retains A/v3. Conflicting equal versions are held for review.
  Overlapping partial issue dates do not establish ordering.
- Date-only strings have no textual offset. Time, calendar and offset syntax
  are validated. Unknown-offset local times remain unknown; timeline filtering
  conservatively widens the possible span and labels it potential.
- `saveManualEdit` commits value and metadata together. A failed metadata
  change rolls back the content revision too.

`RequestedFixTests` covers these regressions. Existing laboratory, import,
manual-entry, timeline, migration, catalog and synchronization tests also pass.
The earlier file-backed create/reopen/edit/history test remains in the suite.

## Schema and integrity

Migration 007 is appended; migrations 001–006 are unchanged. It removes the
unique observation fingerprint constraint (needed for deliberate reverts),
keeps the lookup index, and adds report-conflict resolution attribution.
Observation identity, revision numbering and the one-current-revision rule
remain intact. Catalog IDs and existing data are preserved.

The repository contains a reusable catalog, aliases, panels, reports,
observations with revisions, metadata correction history, module-provided
timeline queries, and the existing body-mass sample store. No additional
tracker or import automation was added.

The catalog coverage document remains the inventory of seeded and unseeded
tests. The catalog is not complete. Reference intervals remain result-specific;
no global intervals, medical interpretation or automatic conversion were added.

## Interface status

Native manual-entry code is authored in `Native/Almanac`, with an iOS 17+
Xcode app target and shared scheme in `Native/Almanac.xcodeproj`. It uses the
existing local `AlmanacCore` package.

Implemented screens: report list/create/edit/detail; result entry/editing with
canonical and alias search; longitudinal test history and source-report links;
separate content/metadata revision history; and report-conflict accept/reject.
Original units, source text, comparators, laboratory ranges, specimens and
unknown/partial dates remain visible and editable. Saving a correction requires
a reason and uses the atomic core edit API.

Linux Swift parsing passes for all four UI source files. Project references,
local package path and shared-scheme XML pass consistency checks. This does not
establish SwiftUI type correctness or a usable running Apple application.
See `Native/README.md` for the Apple build command and outstanding interactive
acceptance steps. No screenshots or runtime verification are claimed.

## Remaining boundaries

- Apple SDK compilation, Simulator launch and interactive UI verification have
  not been performed in this Linux environment.
- Document import and document-file backup/restore remain deferred. The SQLite
  snapshot does not include document files.
- The current storage model is a local personal database. There is no multi-user
  account boundary or server authorization layer; do not claim cross-user RLS.
- Timeline filtering still runs in Swift over current records.
- No automatic unit conversion, OCR, AI interpretation or new tracker.
- The Technical Spec is not in this checkout, but it is not lost: the full
  2026-08-05 original is one directory above the repository root at
  `../almanac-tech-spec-v1.0.md`. See
  `docs/architecture/spec-reconciliation.md`.

To verify the modified core on yamal after importing this branch:

```sh
cd ~/projects/almanac
source env.sh
swift build
swift test
```

---

## 2026-09-15 — Technical Spec recovered; Slice 2 (Core Daily) built

**The spec was never lost.** `../almanac-tech-spec-v1.0.md`, 96 KB, dated
2026-08-05: the 48-table schema, readiness formula v1.0, sleep classification,
circadian and fasting engines, notification suppression matrix, HealthKit
permission map. Everything this codebase has been declining to infer.
`docs/architecture/spec-reconciliation.md` records what that changes.

### Added

- **Migration 014 — `core_daily_schema`.** Fourteen §5 tables transcribed
  verbatim: `profile`, `day_record`, `circadian_context`, `shift_schedule`,
  `shift_occurrence`, `shift_recurrence_pattern`, `sleep_episode`,
  `readiness_cycle`, `vitals_record`, `mood_log`, `soreness_log`,
  `injury_note`, `readiness_record`, `readiness_baseline`. Column names are
  the spec's camelCase, which does not match migrations 001-013 — deliberate,
  see the reconciliation doc.
- **`Sources/AlmanacCore/Sleep/`** — §8 episode detection (30-minute merge
  rule), primary-sleep determination (user correction → shift-aware →
  post-shift elevation → general 26-hour window → none), episode typing,
  multi-source priority with no duration summing.
- **`Sources/AlmanacCore/Readiness/`** — §9 and Appendix A: five input
  scorers, provisional (capped at 90) and final weights, proportional
  redistribution of missing inputs, confidence tiers, colour grades, text
  bands with context suffixes, recommendation precedence, calibration and
  baseline rules.
- **`Sources/AlmanacCore/Circadian/`** — §13 context determination.

### Corrected

- **`TimeModel`'s default boundary is 04:00** (§7.1). It was `.midnight`, a
  documented placeholder chosen while the spec was believed lost, and
  `Native/Almanac/HydrationModel.swift` had silently taken it — hydration was
  being grouped by calendar date, not by Almanac's logical day.
- `Tests/…/TimeModelTests.swift`: the four calendar-arithmetic tests now ask
  for `.midnight` explicitly instead of relying on the default, and a new test
  pins the default at 04:00.
- `Tests/…/HydrationFeatureTests.swift:46`: added `?? 0` to an optional passed
  to `XCTAssertEqual(_:_:accuracy:)`. It compiles under the 6.3.3 toolchain on
  `yamal` but not under 6.1.2; the fix is valid on both.

### Verified

Swift 6.1.2 on x86_64 Linux: **258 XCTest tests — 257 pass, 1 opt-in test
skipped, zero failures.** 54 of those are new (16 sleep, 22 readiness, 9
circadian, 6 schema, 1 time model).

Note the toolchain: this run used 6.1.2, not the 6.3.3 in `env.sh`, because it
was executed from a Linux VM that has no access to `~/.local/swift` on the
host. Re-running `source env.sh && swift test` on `yamal` itself is the
confirmation that matters.

### Not built yet in Slice 2

- Stores for `profile`, `mood_log`, `soreness_log`, `injury_note`,
  `vitals_record`, and §8.4 readiness-cycle linking of mood and soreness.
- HealthKit sleep and vitals import (the `.water`-only provider is the pattern).
- Check-in UI and dashboard.

