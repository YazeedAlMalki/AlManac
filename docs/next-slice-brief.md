# Next slice brief — Lab import automation (POC), with HealthKit non-water annex

**Date:** 2026-09-22
**Status:** M1 + M2 implemented, tested and committed 2026-09-22 (see
`docs/implementation-status.md`). §5's format decision (CSV) was the one made;
the paste-sheet placement was chosen as the native surface. The HealthKit
annex (§4) is still blocked on the spec text.
**Prepared from:** live-code evidence, file:line cited throughout.

---

## 1. Which slice, and why this one

Two candidates were offered: HealthKit non-water domains, or Lab import automation.
This brief recommends **Lab import automation** and preps both.

Why Lab first:

1. **The conflict machinery already exists end-to-end; only the producer is missing.** The
   README's "no import automation creating these proposals" is the single gap between
   "review UI exists" and "review UI is exercisable". Closing it lights up an existing,
   tested surface instead of inventing one.
2. **Spec-independent.** The v1 spec §6.6 limits labs to manual entry, so import is an
   extension the owner defines — no blocked "must not guess" mapping. The HealthKit slice
   is blocked on spec text (§4).
3. **Fully verifiable on this Mac.** Core tests + native build + simulator manual check,
   no HealthKit, no device, no auth.

## 2. What already exists (evidence)

| Piece | Where | State |
|---|---|---|
| Single inbound write seam | `LabStore.upsertReport(LabReportDraft)` — `Sources/AlmanacCore/Laboratory/LabStore.swift:155` | Live. Dedupes by `(source_system, source_report_id)` fingerprint; outcomes `unchanged` / `conflict` / `superseded…` / `staleIgnored` |
| Conflict flagging | `recordReportConflict` (`LabStore.swift:193`), outcome `.conflict` | Live |
| Conflict resolution (accept/reject + reason) | `resolveReportConflict(id:accept:actor:reason:)` | Live |
| Conflict review UI | `ReportConflictView` — `Native/Almanac/HistoryViews.swift:140` (proposals = `reportRevisions(of:).filter { $0.kind == "conflict" }`) | Live, but **never has anything to show** |
| Reports list entry point | `ReportListView` (`ReportViews.swift:5`), attached in `AlmanacApp.swift:22` | Live |
| Launch-time seeding pattern | `LabCatalogSeed.seed` / `WgerCC0Seed.seed` in `AlmanacApp.swift:83-84` | The pattern a dev fixture should mirror |
| Report draft model | `LabReportDraft` (name, date, header, observations; optional `sourceSystem` / `sourceReportID` / `sourceOrdering`) | Live — this is the import format's target |

## 3. The slice in two milestones (each small, each TDD)

### M1 — Development fixture: a real conflict to review

A DEBUG-only launch step (idempotent: skip if any `lab_report` row exists) that calls
`upsertReport` twice with the same `sourceSystem`/`sourceReportID` but a different
header/value — producing a genuine `.conflict` proposal, exactly as a reissued report
from the same lab would. Result: open Reports → conflict row → Accept/Reject is actually
exercisable in the simulator, satisfying the README's "use a development fixture to
exercise its UI" note.

Why M1 first: it is the smallest possible thing that turns the empty screen real, and it
doubles as the harness for M2's tests (the fixture's second upsert is literally the
behaviour an import triggers).

**M1 tests** (core, no UI):
- Re-upsert with same source key + changed fingerprint → `.conflict`, revision row with
  `kind = "conflict"` (guard: likely already covered by LabStore conflict tests — extend
  only if a gap shows).
- Fixture idempotence: run the seed twice → second run adds nothing.

**M1 files:** new `Native/Almanac/LabReportFixture.swift` (DEBUG-only) + `AlmanacApp.swift`
(wire after catalog seed) + test additions.

### M2 — CSV import: the minimal real producer

Parse a CSV (the recommended first format; decision §5.1) of lab results into
`LabReportDraft`s and run them through `upsertReport`. Column set mirrors the preserve-
first rules in `docs/features/laboratory.md` §1: source text kept verbatim, unknown is a
value, `sourceSystem`+`sourceReportID` carried so re-imports hit the fingerprint/conflict
machinery instead of duplicating. Matched/unknown analytes stay annotative
(`catalog_analyte_id` resolution untouched).

**M2 tests** (core, table-driven):
- Well-formed rows → observations with verbatim source text, no invention (no unit
  normalization, no flag derivation).
- Same file imported twice → second run: `.unchanged` (or conflict if amended), no dupes.
- Malformed row (missing value, comparator-only) → row captured, not dropped (§2 failure
  classes: `<0.01`, `Not detected`, `Haemolysed — not reportable`).
- Unknown analyte → stored unmatched, `catalog_analyte_id` nil, not blocked (§4.8/4.9).

**M2 files:** `Sources/AlmanacCore/Laboratory/LabReportCSVImport.swift` (+ shared draft
builder) + Native affordance (file picker or paste sheet in Reports tab) + tests.

## 4. HealthKit non-water domains — annex (unblocked, shipped 2026-09-24)

**Status: built.** The block recorded below was resolved without the spec's
§6/Appendix C map, because the map turned out to be already encoded in the
codebase: `HealthDomain` names all eleven domains, the three bridges each
declare the metric and unit their samples land under, and `SleepStage` is
defined in terms of `HKCategoryValueSleepAnalysis`. What was missing was only
the `HealthDomain` → HealthKit identifier mapping in the iOS adapter, which is
a 1:1 reading of those names.

Shipped:

- **`HealthKitProvider`** — every read domain mapped: sleep, heart rate, HRV,
  steps, active and resting energy, body mass, body fat and lean mass. Water
  remains the only write-back.
- **`SleepEpisodeHealthBridge`** — the one domain with no writer at all.
  Composes `HealthSampleStore` and re-classifies via `SleepClassifier`.
- **`VitalsRecordHealthBridge` / `BodyCompositionMeasurementHealthBridge`** —
  already built and tested, previously never called. Now wired.
- **`HealthModel` / `HealthView`** (Settings → Health data) — the display
  surface §4 originally flagged as missing, via `HealthSummaryStore`.
- `HealthModel` syncs on foreground and refreshes the readiness dashboard
  afterwards, so sleep and vitals actually reach the Today screen.

**Workouts: done too, 2026-09-25.** `WorkoutSessionHealthBridge` and
`Migration036_WorkoutSessionSource` closed the whole of
`docs/features/training.md` §6 step 1. An unmatched workout becomes its
own session; a workout the user also logged is *claimed* rather than
duplicated. See that document for the merge-confidence rule, which is
stricter than "any overlap" for a reason worth reading.

Two mappings are not the obvious identifier and are documented in
`HealthKitProvider`: `.heartRate` reads *resting* heart rate (the readiness
score averages `rhr` over 28 days and would be wrecked by all-day readings),
and `.restingEnergy` reads `basalEnergyBurned`, the only resting-ish energy
type HealthKit offers.

**Not verifiable here:** real HealthKit sync. The simulator has no Health app
and no authorisation, so a fresh install correctly syncs zero rows. The
plumbing is covered by core tests over `FakeHealthProvider` and by a UI test on
the screen; a device is required to confirm sample ingestion.


## 5. Decision gates before implementation

1. **Import format** (recommend: CSV; alternatives: TSV, pasted report text, PDF — PDF
   is a much bigger lift and should not be the POC).
2. **Where import lives in the UI**: paste sheet vs file picker in the Reports tab
   (affects M2 native surface only; core unchanged either way).
3. **(HealthKit, closed)** the spec map per §4 turned out to be unnecessary —
   the mapping was already encoded in `HealthDomain` and the three bridges.
   Shipped 2026-09-24.

## 6. Verification boundary

M1+M2 are fully verifiable here: `swift test` (targeted suites), native Debug simulator
build, and a manual run in the booted iPhone 17 simulator (fixture conflict appears in
Reports → accept and reject both resolve across relaunch). No HealthKit auth, no device,
no Apple ID needed.