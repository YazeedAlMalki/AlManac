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
- The separate Technical Spec / BRD is not present in this checkout.

To verify the modified core on yamal after importing this branch:

```sh
cd ~/projects/almanac
source env.sh
swift build
swift test
```
