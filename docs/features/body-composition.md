# Body Composition & Wellness — Slice 7 design, v1

**Status:** built 2026-09-16 (migration 018, TDD). All five stores/bridges in
§5/§6 exist and are green: `BodyCompositionMeasurementStore` +
`BodyCompositionMeasurementHealthBridge`, `CustomMeasurementStore`,
`SupplementPlanStore` + `SupplementLogStore`, `ContextEventStore` — 23 tests
across 6 suites. Schema is transcribed verbatim from
`../../../almanac-tech-spec-v1.0.md` (the recovered, authoritative Technical
Spec — see `docs/architecture/spec-reconciliation.md`), narrowed to what Slice
2 didn't already build and what the owner didn't defer, plus a `deletedAt`
column beyond the spec's literal text (§3). A first SwiftUI Measurements page
now exists under More; full CRUD, supplement/context screens, notification wiring
and progress photos remain future work.

The native app now has a first Measurements surface under More: it lists recent
body-composition and custom measurements and accepts manual values. The complete
Slice 7 UI (plans, adherence, context tags, editing and historical exploration)
remains future work.

## 1. What Slice 7 actually still needs (most of it is already done)

The original BRD-derived brief for this slice assumed wellness logging was
0% built. It is not — Migration014 (Slice 2, 2026-09-15) already shipped
`mood_log`, `soreness_log`, and `injury_note` with working stores
(`MoodLogStore`, `SorenessLogStore`, `InjuryNoteStore`) and readiness-cycle
linking. Laboratory (`lab_result` in the spec) is separately superseded by
the repo's own ~14-table module, already ~85% built with an iOS UI
(`docs/architecture/spec-reconciliation.md` §4.4) — no schema work needed
there either.

What's genuinely at 0% and in scope for this design:

| Concern | Spec table(s) | Status |
|---|---|---|
| Weight / body-fat % / lean mass / skeletal muscle / visceral rating | `body_composition_measurement` (§5.18) | Not built — **see §3, a real collision** |
| Owner-definable circumference measurements | `custom_measurement_definition`, `custom_measurement_log` (§5.18) | Not built |
| Progress photos | `progress_photo` (§5.18) | **Deferred** — owner decision 2026-09-16, "not now, later update." No schema or store this pass. |
| Supplement plan + adherence | `supplement_plan`, `supplement_log` (§5.20) | Not built |
| Context tags (illness, travel, stress, etc.) | `context_event` (§5.20) | Not built |

Out of scope for this doc (already done or already decided elsewhere):
mood, soreness, injuries, lab results.

## 2. Schema — Migration 018, transcribed verbatim

Exact column shapes from spec §5.18 and §5.20, minus `progress_photo` (deferred)
and `lab_result` (superseded). CamelCase, matching the convention Migration014
onward already established (`spec-reconciliation.md` §5).

```sql
CREATE TABLE body_composition_measurement (
    id              INTEGER PRIMARY KEY,
    timestamp       TEXT NOT NULL,
    timezoneOffset  TEXT NOT NULL,
    logicalDay      TEXT NOT NULL,
    metric          TEXT NOT NULL,  -- weight | body_fat_pct | lean_mass_kg |
                                    -- skeletal_muscle_kg | visceral_rating
                                    -- ('weight' lives here, not in
                                    -- vitals_record — see §3)
    value           REAL NOT NULL,
    unit            TEXT NOT NULL,  -- kg | pct | rating
    source          TEXT NOT NULL,  -- apple_health | inbody | smart_scale | manual
    conditions      TEXT NOT NULL DEFAULT 'unknown',  -- fasted | non_fasted | unknown
    healthKitUUID   TEXT UNIQUE,
    pendingHealthKitWrite INTEGER NOT NULL DEFAULT 0,
    createdAt       TEXT NOT NULL
);
CREATE INDEX idx_body_comp_metric ON body_composition_measurement(metric, timestamp);

CREATE TABLE custom_measurement_definition (
    id      INTEGER PRIMARY KEY,
    name    TEXT NOT NULL UNIQUE,
    unit    TEXT NOT NULL,
    createdAt TEXT NOT NULL
);

CREATE TABLE custom_measurement_log (
    id              INTEGER PRIMARY KEY,
    definitionId    INTEGER NOT NULL REFERENCES custom_measurement_definition(id),
    timestamp       TEXT NOT NULL,
    logicalDay      TEXT NOT NULL,
    value           REAL NOT NULL,
    notes           TEXT,
    createdAt       TEXT NOT NULL
);

CREATE TABLE supplement_plan (
    id          INTEGER PRIMARY KEY,
    name        TEXT NOT NULL,
    doseAmount  REAL NOT NULL,
    doseUnit    TEXT NOT NULL,   -- g | mg | ml | tablet | capsule | scoop
    frequency   TEXT NOT NULL,   -- daily | twice_daily | pre_workout | custom
    timingNotes TEXT,
    isActive    INTEGER NOT NULL DEFAULT 1,
    createdAt   TEXT NOT NULL,
    updatedAt   TEXT NOT NULL
);

CREATE TABLE supplement_log (
    id              INTEGER PRIMARY KEY,
    planId          INTEGER NOT NULL REFERENCES supplement_plan(id),
    timestamp       TEXT NOT NULL,
    logicalDay      TEXT NOT NULL,
    taken           INTEGER NOT NULL DEFAULT 1,
    notes           TEXT,
    createdAt       TEXT NOT NULL
);

CREATE TABLE context_event (
    id          INTEGER PRIMARY KEY,
    date        TEXT NOT NULL,  -- YYYY-MM-DD
    tags        TEXT NOT NULL DEFAULT '[]',
    -- illness | medication_change | travel_jet_lag | unusual_stress |
    -- heat_exposure | sauna | poor_watch_wear | late_night_event |
    -- sleep_interruption | competition_day
    notes       TEXT,
    createdAt   TEXT NOT NULL,
    updatedAt   TEXT NOT NULL
);
```

`progress_photo` stays documented in the spec for when it's picked back up —
filesystem storage keyed by a UUID filename (no PII, no BLOB), `pose` and
`notes` columns already anticipate a future comparison UI. Nothing to build
now.

## 3. A fifth schema collision, found while designing this slice

`docs/architecture/spec-reconciliation.md` resolved four spec/repo collisions
on 2026-09-16 and flagged a fifth (Training) rather than silently building
around it. This is a sixth, in the same spirit — found while checking what
Slice 7 still needs, not decided anywhere before now:

**`VitalsRecordHealthBridge` (built during the Slice 2 HealthKit-bridge work)
already writes HealthKit `bodyMass` samples into `vitals_record` as
`metric = 'weight'`.** Spec §5.19's own `vitals_record` comment lists only
`rhr | hrv_sdnn | steps | active_energy_kcal` — no weight, and no
`restingEnergy` either, which the same bridge also writes. There's no `CHECK`
constraint enforcing the enum (it's a Swift-level convention, not a schema
one), so nothing is broken, but two competing homes for weight is a real
design problem: `vitals_record` has no `conditions` (fasted/non-fasted) or
`source` values wide enough for InBody/smart-scale, so it cannot express what
§5.18 needs body composition to express.

This isn't "implementation ahead of spec" like the four resolved
collisions (nutrition, lab) — there's no richer body-composition model
sitting in `vitals_record`, just a domain slotted into the nearest existing
table during Slice 2's sprint, before Slice 7 had a design. Since no durable
database exists yet (`docs/architecture/health-data-foundation.md` §11), this
is free to correct.

**Decision (this doc, 2026-09-16):** `body_composition_measurement` is the
sole home for `weight`. As part of building migration 018:
- Remove the `.bodyMass: ("weight", "kg")` entry from
  `VitalsRecordHealthBridge.metricMap` (`Sources/AlmanacCore/Vitals/VitalsRecordHealthBridge.swift:21`).
- Add a new `BodyCompositionMeasurementHealthBridge` (see §4) that owns
  `.bodyMass`, `.bodyFatPercentage`, `.leanBodyMass` and writes into
  `body_composition_measurement` with `source = 'apple_health'`,
  `conditions = 'unknown'` (HealthKit doesn't carry fasted state).
- Leave `restingEnergy` in `vitals_record` as-is — it doesn't collide with
  anything §5.18/§5.20 claims, and pulling on that thread is out of scope
  here. Flagged, not silently left broader than the spec's comment without a
  reason on record.
- No data migration needed: nothing has run against a durable database yet.

## 4. HealthKit bridge — bi-directional, following the existing pattern

Per Appendix C, `bodyMass`, `bodyFatPercentage`, and `leanBodyMass` are the
only body-composition metrics with a HealthKit type at all (skeletal muscle
and visceral rating have none — manual/InBody-import only, matching the BRD's
"user picks which to track"). All three are bi-directional (read ✅ write ✅),
same as `dietaryWater` already is.

`Sources/AlmanacCore/Health/HealthProvider.swift:25` needs two new
`HealthDomain` cases: `bodyFatPercentage`, `leanBodyMass` (`bodyMass` already
exists — it's the *bridge* that needs to change, not the domain enum).

`BodyCompositionMeasurementHealthBridge` follows `VitalsRecordHealthBridge`'s
shape (`HealthSampleWriting`, idempotent upsert on `(source, healthKitUUID)`)
for the read side, and `HydrationHealthBridge`'s pattern for the write side
(`.water` is the only other domain Almanac currently originates back out to
HealthKit) — `pendingHealthKitWrite` on `body_composition_measurement` exists
for exactly this: a manual entry queued for push, cleared once
`HealthWriter.write(_:)` confirms it.

## 5. Store plan

New files under `Sources/AlmanacCore/BodyComposition/`, matching
`InjuryNoteStore`'s shape (draft/read structs, `Database`-backed, `Clock`
injected, ISO8601 helpers):

- `BodyCompositionMeasurementStore` — log, read-latest-per-metric, history
  for charting, read-by-source (to distinguish manual overrides from
  imported rows per the "user can override or duplicate" requirement).
- `CustomMeasurementStore` — definition CRUD (owner-defined circumference
  list) + log/history per definition.
- `SupplementPlanStore` — plan CRUD (`isActive` toggle rather than delete,
  matching `injury_note`'s soft-state convention).
- `SupplementLogStore` — adherence logging per plan per day; a "taken"
  read for a date range is what a reminder/adherence-insight screen needs.
- `ContextEventStore` — tag CRUD per date; `tags` is a JSON array like
  `soreness_log.bodyAreas` already is, same encode/decode helper reusable.

Reminders reuse the existing local-notification architecture rather than a
new one — `supplement` is already a row in the spec's notification
suppression matrix (Appendix B), so `NotificationScheduler` (when built) picks
plans up the same way it will pick up meal/water rules.

## 6. Seams — built, in this order

Per `mattpocock-skills:tdd`: no test written at an unconfirmed seam. All five
built as separate red/green cycles, weight first (highest-value,
most-requested path):

1. `BodyCompositionMeasurementStore.log` / `.latest(metric:)` — plain
   CRUD + "most recent value per metric" read. ✅ `BodyCompositionMeasurementStoreTests`, 4 tests.
2. `BodyCompositionMeasurementHealthBridge.apply` — HealthKit import,
   mirroring `VitalsRecordHealthBridgeTests`' existing test shape. ✅
   `BodyCompositionMeasurementHealthBridgeTests`, 5 tests. Surfaced and fixed
   two pre-existing bugs in the process — §7 below.
3. `CustomMeasurementStore` — definition create + logging against it. ✅
   `CustomMeasurementStoreTests`, 5 tests.
4. `SupplementPlanStore` / `SupplementLogStore` — plan CRUD, then adherence
   logging against an existing plan. ✅ `SupplementPlanStoreTests` (5) +
   `SupplementLogStoreTests` (3).
5. `ContextEventStore` — tag logging + read-by-date. ✅
   `ContextEventStoreTests`, 3 tests.

Not built: the full body-composition UI, and supplement reminders (needs Slice
11's notification scheduler — the `supplement` row in the spec's Appendix B
suppression matrix is ready for it, but nothing schedules notifications yet in
this codebase).

## 7. Bugs found and fixed while building §6.2

Building the HealthKit bridge test (`ON CONFLICT`/soft-delete, mirroring
`VitalsRecordHealthBridge`'s existing shape) surfaced two bugs already
present in that existing code, both fixed as part of this pass — full detail
in `docs/implementation-status.md`'s 2026-09-16 entry:

1. `vitals_record`'s `ON CONFLICT(source, healthKitUUID)` had no matching
   index — every HealthKit update threw. Fixed: Migration019.
2. `vitals_record`'s soft-delete set `createdAt = NULL` against a `NOT NULL`
   column — every delete threw. Fixed: Migration020 (new `deletedAt`
   column); the identical bug existed in `sleep_episode` too (Migration021).
   `body_composition_measurement` was designed with `deletedAt` from the
   start for the same reason (§2's schema already reflects this fix, not
   the original spec text).

`SleepEpisodeHealthBridge`'s deeper, separate schema mismatch (documented in
`docs/implementation-status.md`) was flagged, not fixed — out of scope here.
