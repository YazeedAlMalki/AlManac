# Training/Exercise — Slice 4 design, v1 (backfilled)

**Status:** schema (migration 016) and full CRUD store layer built
2026-09-16, TDD, 33 tests, green. `WorkloadComputer` (session-level load
aggregation) and a quick-add UI (Training tab + a section on the readiness
dashboard) both added 2026-09-17. Still not built: any HealthKit bridge, and
any UI for `PrescribedWorkoutStore`'s templates/containers. No
`docs/features/training.md` existed until this entry — this doc is a
backfill, written after the code, not before it. See §1 for why that
matters more here than it did for Fasting or Body Composition.

## 1. Why this doc is a backfill, and what's unrecoverable

Nutrition, Laboratory, and Fasting each got a design doc *before* their
schema was built. Training didn't — it was built directly from
`prescription-model-v0.1.md`, a design produced in an earlier session's
context and never committed to this repository as a file. That document
does not exist on disk anywhere under this repo. `docs/architecture/spec-reconciliation.md`
§6 calls it out explicitly: *"`prescription-model-v0.1.md` (2026-09-02,
project memory)"* — memory, not a file.

What survives is its **effects**: the two enumerations and the schema shape
in `Migration016_TrainingSchema`'s own doc comments, and the assignment
rules cited (by section number, into a document nobody can open) in the
doc comments of the seed that has since been removed
(`WgerCC0Seed`, deleted 2026-09-24 — see §4). Both are quoted verbatim in
§2/§4 below.
What does **not** survive: the document's actual prose — its full reasoning
for each of the twelve prescription types, the open question at its own
§8 about `quality_reps` (referenced but not explained anywhere in code),
and any container-to-prescription-type coupling rules it may have
specified. If a future session needs that reasoning, it has to be
reconstructed or re-requested; it cannot be read off this filesystem.

The tech spec's own §5.17 ("Training Tables": `exercise`, `program`,
`session`, `set_entry`, `workout_day`, `workout_day_exercise`,
`workout_merge_record`, a plain sets/reps/load shape) was **not** built,
and per spec-reconciliation.md §6, was deliberately superseded by the
prescription model rather than transcribed — the same kind of "two specs
disagreeing before either is code" situation Migration016 documents for
itself. Nothing here is "implementation exceeds spec"; §5.17 simply lost
to a different design before ether existed as code.

## 2. The prescription model, as reconstructed from code

**Core idea** (Migration016's own words): the tech spec's sets/reps/load
shape *"silently corrupts every [training] kind"* that isn't a straight
barbell lift — an AMRAP prescribes a time cap and measures rounds; a
straight set prescribes reps and measures completion; a skill session has
neither. Rather than force every training kind through one shape, or build
twelve separate tables (most of which would sit empty — see §4), the model
uses two orthogonal, closed, enumerable dimensions:

**Twelve prescription types** — *what kind of work a bout is, and which
side of it (prescribed vs. actual) means what*:

| Type | What's prescribed / what's measured (inferred from field usage — see §4) |
|---|---|
| `reps_load` | sets × reps against an external load; actuals may differ from plan |
| `reps_bodyweight` | sets × reps, bodyweight only — no load field is meaningful |
| `time_under_load` | a held duration under load or bodyweight tension |
| `distance` | a distance target/result (a run, a row) |
| `duration` | a time target/result with no distance or rep count |
| `rounds_for_time` | fixed work, minimize elapsed time ("for time") |
| `work_in_time` | fixed time cap, maximize rounds/reps (AMRAP) — confirmed by `WorkoutBoutStoreTests`' own test name |
| `interval` | repeating work/rest blocks |
| `quality_reps` | skill/drill work — **zero source content anywhere in the exercise data lake today; the open question is prescription-model-v0.1.md's own §8, unresolved and unreconstructable from code** |
| `hold_stretch` | a held stretch |
| `release` | soft-tissue/myofascial work |
| `session_only` | a session logged with no bout-level detail (RPE and notes only) |

**Ten container types** — *the shape a `prescribedWorkout` template or a
session's bouts are organized into*: `straight_sets`, `superset`,
`circuit`, `emom`, `amrap`, `for_time`, `interval_block`, `ladder`,
`skill_block`, `flow`. Prescription type and container type are genuinely
orthogonal in the schema (a `workoutBout.containerType` is a separate,
independently-nullable column from `prescriptionType`) — nothing in code
enforces a pairing rule (e.g. that an `amrap` container's bouts must be
`work_in_time`), because the source document that might have specified such
rules is exactly what's unrecoverable per §1.

**Prescribed vs. actual, not sets/reps/load.** `workoutBout` carries both a
full "prescribed" field group and a full "actual" field group (§4 lists
them). Which fields a given `prescriptionType` actually fills is a
by-convention discipline, not something the schema enforces per type — e.g.
`work_in_time` prescribes `prescribedWorkSeconds` and measures
`actualRounds`/`actualReps`; `rounds_for_time` prescribes `prescribedRounds`
and measures `elapsedSeconds`. **Never inferred from the prescribed side**
(Migration016's own words) — a bout that wasn't actually measured leaves its
actual fields `nil`, not a copy of the plan.

**Why one wide table, not twelve.** A generic type/key/value fact table was
the other option considered (per Migration016's comment). A wide, sparse,
nullable row was chosen instead for two reasons: it matches how
`vitals_record` and `mood_log` already do "one flexible fact table" in this
schema, and the twelve types are closed and enumerable — unlike vitals
metrics, which are open-ended. Real data supports this: per
`spec-reconciliation.md` §6.1 (cited by Migration016), 5 of the 12 types
have zero source content today, so twelve dedicated tables would mostly sit
empty. **This means there is no per-type Swift struct or enum anywhere** —
`prescriptionType`/`containerType` are plain `String`s validated only by a
SQL `CHECK` constraint (`Migration016_TrainingSchema.prescriptionTypes`/
`.containerTypes`, the two canonical arrays) and by test assertions. Adding
twelve dedicated types would be undoing a considered decision, not filling
a gap — don't, unless the "5 of 12 types have zero content" premise changes.

## 3. Schema (migration 016)

Four tables — `exerciseCatalog`, `prescribedWorkout`, `workoutSession`,
`workoutBout` — full column list in `Sources/AlmanacCore/Persistence/Migration016.swift`,
not reproduced here since the source file is the more precise reference and
duplicating it risks drifting out of sync. Key facts worth stating
separately from the source:

- `exerciseCatalog`'s key is `(sourceId, exerciseId)` — e.g. `("wger",
  "132")` — not a synthetic identity; `prescriptionType` is Almanac's own
  assignment per §2 above, never something a source dictionary carries.
- `workoutBout.prescriptionType`/`.containerType` are **copied onto the
  bout at logging time**, not joined live from the catalog row — a later
  correction to a catalog exercise's mapping must never reinterpret
  history, the same provenance principle Nutrition's per-value licensing
  already follows.
- Soft delete follows `nutrition_log`'s pattern (`deletedAt` nullable,
  queries filter `WHERE deletedAt IS NULL`), explicitly **not**
  `sleep_episode`'s broken pattern (a `deletedAt` column that table never
  actually got before it was deleted and rebuilt as `SleepEpisodeStore` —
  see `docs/implementation-status.md`, 2026-09-16).
- No `program`/`workout_day` multi-week structure, and no
  `workout_merge_record` (the tech spec §10 HealthKit-merge-confidence
  audit trail) — neither was ever designed for the prescription model;
  building either now would be inventing spec, not implementing it.

## 4. What's built

- **`ExerciseCatalogStore`, `PrescribedWorkoutStore`, `WorkoutSessionStore`,
  `WorkoutBoutStore`** (`Sources/AlmanacCore/Training/`) — full CRUD (insert/
  log, idempotent soft delete, read by id, read by natural query). 20 tests
  across the four stores plus `Migration016Tests`' 6 schema tests.
- **`WgerCC0Seed` — REMOVED 2026-09-24, replaced by `WorkoutGuideSeed`.** The
  seed was 21 wger exercises licensed CC0, fetched from wger's API. It is gone
  because the "every exercise shipped must include a demonstration graphic"
  rule cannot be met from wger: `docs/exercise-sources.md` records the
  measurement — "Pause Bench", "Thruster" and "Glute-Ham Raise" have no
  clean-licensed illustration in any source, and several others only match the
  wrong movement. Migration 035 soft-deletes the rows it wrote, so logged bouts
  still resolve.
- **`WorkoutGuideSeed`** — all 302 `bryllim/workout-guide` exercises (Bryl
  Lim, CC BY-SA 4.0), each shipped with the demonstration graphic drawn for
  it. Exercise list, licence, author and per-frame upstream attribution are
  read from workout-guide's own `manifest.json`, copied into the resource
  bundle rather than retyped, so a re-sync can diff against upstream.
  `prescriptionType` is a mechanical mapping from the source's own
  `exerciseType`/`isStretch` fields (`WorkoutGuideSeed.prescriptionType`,
  pinned by `WorkoutGuidePrescriptionMappingTests`), not 302 hand-assigned
  rows: `weight_reps` → `reps_load`, `bodyweight_reps`/`assisted_bodyweight`
  → `reps_bodyweight`, `distance_duration` → `distance`, `duration` → `time_under_load`
  when the name reads as a static hold (hold/plank/sit/hang) else `duration`,
  `isStretch` → `hold_stretch`. 21 tests.
- **`ExerciseGraphicAudit`** — the rule as a build failure: every shipped
  exercise must name a graphic that is actually in the bundle, or the build
  (and the app's own launch) fails.
- **`WorkloadComputer`** (2026-09-17) — session-level tonnage/distance/
  duration/reps/rounds/average-RPE aggregation from a session's bouts. See
  its own doc comment for exact per-type coverage; deliberately partial
  (`interval`, `quality_reps`, `hold_stretch`, `release`, `session_only`
  aren't modeled — no summary field fits them well enough to be worth a
  placeholder). 13 tests.

**Total: 46 tests across the Training module, all green** (33 from the
2026-09-16 schema/store pass + 13 from `WorkloadComputer`).

## 5. What's deliberately not built, and why

**HealthKit workout bridge.** The obvious next step by analogy with
`BodyCompositionMeasurementHealthBridge` — but that analogy is the wrong
one, for the same reason `SleepEpisodeHealthBridge` was built wrong and
later deleted (`docs/implementation-status.md`, 2026-09-16): a
`workoutSession` groups multiple `workoutBout` rows the way a
`sleep_episode` groups sleep stages, not the way a
`body_composition_measurement` row is one raw sample. A real blocker beyond
that shape mismatch: `HealthSample` (`Sources/AlmanacCore/Health/HealthProvider.swift`)
— the one platform-neutral type any HealthKit sync must go through, since
`AlmanacCore` cannot import HealthKit at all — carries only
`externalID/domain/start/end/value/unit/sourceName`. There is nowhere on it
to carry an `HKWorkoutActivityType` (running vs. strength training vs.
cycling), which any sensible mapping to `prescriptionType` would need.
Extending `HealthSample` (or introducing a workout-specific parallel type)
is a real design decision this pass doesn't make. Also unresolved: `workoutSession`
itself has no `source`/`healthKitUUID` columns at all, so even a resolved
mapping has nowhere to do an idempotent upsert without its own migration
first. Flagged, not attempted — the master build order's own contingency
table anticipated exactly this ("HealthKit wiring on iMac takes longer than
expected → build schema/stores/UI on yamal; iMac wiring catches up later").

**Per-type Swift structs/enums for the 12×10 combinations.** Rejected, not
missing — see §2's "why one wide table" reasoning. Revisit only if the "5 of
12 types have zero source content" premise changes.

**UI — built 2026-09-17.** `TrainingModel`, `TrainingDashboardView`,
`ExercisePickerView`, `LogBoutView` (`Native/Almanac/`), plus a "Training"
section on `ReadinessDashboardView` when today has a summary. Deliberately
scoped down from the fuller picture in §6.2 below: quick-add only, against
one ad-hoc "today's session" — no `PrescribedWorkout` template picker, no
container selection, no bout editing (only delete). `WorkoutGuideSeed.seed` is
now called from `LaboratoryModel.open()` (it never was before — the catalog
would have been empty at every launch until this). The picker's rows show the
exercise's bundled demonstration graphic.

**Calorie burn from training load.** No MET or Compendium-derived
calorie-burn code exists anywhere in this repo (confirmed absent by grep,
not merely undocumented) — blocked on an unresolved licensing question
(Compendium publishes no licence terms; three provenance/licence emails —
SFDA, Compendium authors, yuhonas/wrkout — were still unsent as of
2026-09-16 per `Claude outputs/almanac-project-status-2026-09-16.md`, and
this repo has no way to verify whether that has since changed — it's
out-of-band, personal correspondence). `WorkloadComputer` deliberately
reports tonnage/distance/duration, never an energy estimate.

**`program`/multi-week structure, workout-merge-confidence model.** Neither
was ever designed for the prescription model (§3) — not a gap in this pass,
an absence in the design itself.

## 6. Build plan, next

**2026-09-18 addendum (Ticket 4, yamal-buildable scope):** three gaps this
plan left open turned out to be buildable without any HealthKit dependency
and are now done — `workoutSession.sessionType` (Migration026, the
user-selected sport/activity), `ExerciseProgressStore` (cross-session
per-exercise weight/reps/sets history — see `docs/implementation-status.md`,
2026-09-18), and `WorkoutHealthKitMatcher` (pure time-overlap matching,
step 1(d) below, built against a standalone `HealthKitWorkoutSample` fake
so it's ready to wire once the bridge exists). Step 1(a)-(c) are still
open — the matcher only solves "given a session and some candidate
windows, which one wins," not where the candidates come from.

1. HealthKit bridge — needs, in order: (a) a design decision on how
   `HealthSample` (or a new parallel type) carries workout activity type,
   (b) a migration adding `source`/`healthKitUUID` to `workoutSession` for
   idempotent upsert, (c) a mapping from `HKWorkoutActivityType` to
   `prescriptionType`/`containerType` defaults (a real per-value decision
   table, not a guess), (d) the bridge itself, one `workoutSession` per
   `HKWorkout` (matching the granularity that actually exists on both
   sides), with unmatched/unstructured workouts landing as `session_only` —
   time-overlap matching itself is done (`WorkoutHealthKitMatcher`, above).
2. ~~UI~~ — done 2026-09-17 (§5 above), scoped to quick-add against an
   ad-hoc daily session, using `WorkloadComputer` for the aggregate shown
   both on the Training tab and (when today has one) as a section on
   `ReadinessDashboardView`. Still open: a bout detail/edit view (today's
   screen only deletes), a session review screen for past days (today's
   screen only shows today), and any UI for `PrescribedWorkoutStore`'s
   templates/containers — that store exists in `AlmanacCore` since the
   schema pass and still isn't reachable from anywhere in the app.
3. Calorie burn — blocked on the Compendium/MET licensing question; not
   scheduled.
