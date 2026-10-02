# Training Program — the layer above a session

**Status:** core + UI built, 2026-10-02. Migration 049, three stores, three
engines; the screens in `Native/Almanac` (`ProgramListView`, `ProgramDayView`,
`ProgramSessionView`, `ExerciseProgressGraphsView`). The feature's definitions
come from `docs/handoff-2026-10-01-training-program.md`, which is a
product-decisions handoff, not a status handoff; `docs/features/training.md`
remains the doc for everything underneath it.

## 1. What a program is, and why it is three tables

`docs/features/training.md` §3 records that Slice 4 built **no**
`program`/`workout_day` structure, and §5 records that as a deliberate absence
rather than a gap: it was never designed, so building it would have been
inventing spec. It is now designed — by the 2026-10-01 handoff — and built.

| Table | Owns |
|---|---|
| `trainingProgram` | a name ("My PPL", "Mobility") and notes |
| `programDay` | one part of a split, by the user's own label ("Push") |
| `programDayExercisePool` | **the prescription**: an exercise, where it sits in the rotation, where it sits in a session, what to do with it, and how it progresses |

The third table is the feature. `trainingProgram` and `programDay` are
deliberately thin — see `ProgramStore`'s doc comment for why putting anything
about *what to train* on a program would be a second home for a prescription
that the pool owns.

**The handoff's table names are not this repository's.** It specifies
`training_program` / `program_day` / `program_day_exercise_pool` and extends
`workout_session` / `workout_session_set`. This repo has `workoutSession` and
`workoutBout` (Migration016), and camelCase tables throughout the Training
module. Migration049 documents each substitution in its own comment, the same
way Migration044 documents the ones before it. Two of the handoff's four
"new" columns to the session-set table already existed: `prescribed_reps` and
`prescribed_load_kg` are `workoutBout.prescribedReps` / `.prescribedLoadKg` from
Migration016. **Only two columns were actually added to `workoutBout`**
(`equipmentVariant`, `wasSkippedForSession`) and three to `workoutSession`
(`programDayId`, `rotationIndex`, `readinessAdjusted`).

## 2. The key rule

> `programDayExercisePool` is the prescription. `workoutBout` is the log.
> **The prescription never changes because of what was logged.**

This is why the pool is a separate table rather than a view or a flag on the
bout, and it is asserted rather than assumed:
`ProgramDayExercisePoolStoreTests.loggingABoutDoesNotTouchThePrescription` logs a
bout at 105 kg against a 100 kg prescription and reads the pool row back with
its timestamps, so an `updatedAt` bump would fail the test. Three mechanisms
change a prescription, and all three are the user acting:

1. editing it (`ProgramDayExercisePoolStore.updatePrescription`)
2. a per-session skip, which writes **no pool state at all** (§4)
3. permanent removal, which sets `isActive = false` (§4)

## 3. Rotation

`RotationEngine` (`Sources/AlmanacCore/Training/RotationEngine.swift`).

**Rotation advances on completed sessions, not calendar time** (Decision 2). The
whole point of `rotationIndex` is that a week off does not skip three exercises
— the user comes back to the next item, not the item three passes on.

The model:

- The day's **active** pool items, ordered by `rotationPosition`, are the cycle.
- `head = rotationIndex mod cycle.count`.
- The session's **window** is the first `slotCount` items from the head, where
  `slotCount = max(positionWithinSession) + 1` over the day's live items.

So a 4-exercise pool with a 2-slot session offers items 1 and 2 on the first
Push, items 2 and 3 on the second, items 3 and 4 on the third, and wraps. The
pool rotates through everything without any single item having to be in every
session — which is what a rotation is for, and what "give me my next session"
would not do.

**`nextRotationIndex` counts live sessions, not `MAX(rotationIndex) + 1`.** This
was not the first implementation and the difference is not academic: `MAX`
cannot honour an undo. Delete the last session and `MAX + 1` still counts past
it, so the next session skips an exercise the user never actually did. Counting
rows fixes it, and `RotationEngineTests` covers deletion.

**Two queries per plan**, whatever the pool size. Not a per-item read in a loop
— the handoff §8 performance rule, and the reason the split into series/plan is
worth doing at all.

## 4. Availability: two mechanisms, one prompt

Decision 3, and the separation is the load-bearing part:

| | Mechanism | Rotation effect |
|---|---|---|
| **Permanent** removal | `isActive = false` | Never offered again until re-added by hand. Prescription, progression rule and rotation position all survive. |
| **Per-session** skip | **nothing is written to the pool** | **Holds its position.** Re-offered next time this day comes up. |

**Holding its position *is* the absence of a write.** The only record of a
per-session skip is `workoutBout.wasSkippedForSession` — the bout exists with
`wasSkippedForSession = 1` and no actuals. So `ProgramDayExercisePoolStore`
exposes both through one typed entry point,
`skipForSessionOnly(_:item:)`, and `ExerciseAvailability.mutatesPool` states
outright that `perSession` has no database effect. A caller that reaches for it
expecting a row to write finds there is nothing to write, which is the point.

**Why `isActive = false` is not `deletedAt`.** They answer different questions.
`isActive = false` is "the gym doesn't have it" — reversible with one call, and
the item keeps its position so re-adding it puts it back where it was.
`deletedAt` is "this is gone". Both reads exist and they disagree on purpose:
`items(programDayId:)` is the **authoring** read and shows inactive items (greyed
out, so "why isn't this being offered" is answerable);
`activeItems(programDayId:)` is the **rotation** read. A permanently removed
exercise does *not* shorten the day — `sessionSlotCount` reads live items
including inactive ones, so the window refills from the next active item instead
of the session quietly getting smaller.

`substitutesForSlot` on `RotationEntry` records that a slot was filled by a
substitute. Each skip takes the next unused cycle item in slot order; if the pool
is exhausted the slot is simply omitted rather than repeated.

## 5. Readiness adjustment

`ReadinessAdjustment` (`Sources/AlmanacCore/Training/ReadinessAdjustment.swift`).

**The table this implements is reconstructed, and that is a deviation worth
reading before anyone trusts the numbers.** The handoff asks for "readiness
adjustment computation" and points at `prescription-model-v0.1.md` — which was
never committed to this repository (`docs/features/training.md` §1). Two rules
survive it, quoted in `docs/almanac-technical-spec-v1_0.md` §5.17: `release` is
the only type that should ever *increase* on a low-readiness day, and
`quality_reps` holds volume and drops complexity rather than reducing work.
Every multiplier between those anchors was reconstructed from the two rules and
from `ReadinessFormula`'s own six bands and real 40/70 thresholds.

| Band | Volume | Complexity | Rest | Release |
|---|---|---|---|---|
| excellent / good | 1.0 | 1.0 | 1.0 | 1.0 |
| moderate | 0.85 | 0.9 | **1.1** | 1.0 |
| belowBaseline | 0.7 | 0.75 | 1.25 | 1.25 |
| poor | 0.5 | 0.6 | 1.5 | 1.5 |
| veryLow | **rest day** | — | — | — |

`release` rises as readiness falls and never falls below 1.0, which is the
surviving rule made mechanical. `veryLow` yields `nil` volume — a rest day,
which is a different thing from a very light one and is `AdjustedPrescription.isRestDay`.

Rounding is not left to floating point: load to 0.5 kg **down**, duration to 5 s
**down** (floored at one interval), rest to 5 s **up** (more rest on a bad day,
never less), and counts never below 1. `ReadinessAdjustment.table` is one array
of `BandRule`s — the single place to edit to overrule the whole table. Recorded
in `CONTEXT.md` under "Decisions taken without an answer".

## 6. Per-exercise progression

`ExerciseProgression` (`Sources/AlmanacCore/Training/ExerciseProgression.swift`).

Decision 4: the rule is **the user's, per exercise** — not a global "+2.5 kg
applied everywhere". The increment and the condition live on the pool item
beside the prescription they modify, so an exercise nobody has ever logged and a
barbell squat with a plate history can both have their own rule.

`ProgressionCondition` has **exactly one case**, `all_reps_completed`. The
handoff names that one and no other; it also makes the set user-defined, which
makes it product surface nobody has designed. One case is the honest amount to
build, and adding a condition is a migration.

`ProgressionSuggestion` is a **suggestion and never a write** — it does not
touch the pool item, for the same key rule as §2. Two properties that are easy to
get wrong and are tested rather than assumed:

- The base is the **last actual load**, never the pool's prescribed load. Progression
  that compounded off the plan would climb forever on an exercise never attempted.
- An unknown or incomplete rule produces `nil`, which is *not* the same as "hold".
  Nil means "nothing can be said", and treating it as satisfied would silently
  progress every exercise whose rule was never configured.
- A bout skipped for the session is not an attempt, so it does not satisfy the
  condition.

`suggestions(for:)` takes the whole session's items and reads history in **one
batched query**; the single-item form delegates to it.

## 7. Equipment variants and the two graphs

`EquipmentVariantGraph` (`Sources/AlmanacCore/Training/EquipmentVariantGraph.swift`).

Decision 1: variants are tracked **separately** at write time and only the
*graph* chooses to draw them together, via one radio toggle
(`EquipmentVariantDisplay.separate` / `.combined`) that applies to **both**
graphs. `showsComparabilityFootnote` is true only in combined mode, and
`EquipmentVariant.combinedModeFootnote` holds the text — one copy, because two
hand-typed copies of a caveat are how one of them ends up wrong.

Two properties that matter more than they look:

- **The unspecified variant is a series, not a hole.** Every bout logged before
  Migration049 has a null variant. In separate mode, null is its own series
  (labelled "Not recorded"), so the users with the longest history are not the
  ones with an empty graph.
- **Combined keeps each point's variant.** Combined means drawn together, not
  stripped of provenance — "why did my weight jump 20 kg" is answerable only if
  the cable session is still identifiable.

**Volume is reps performed (sets × reps), not the handoff's
`sets × reps × load`** — see `CONTEXT.md`. Weighting volume by load makes the
axis a statement about the barbell rather than about the session.

One query per read in both modes and both graphs. The toggle is the thing that
changes the number of lines, so splitting the query per variant would mean a
query per line.

## 8. What's built, and verified

| | Tests |
|---|---|
| `Migration049_TrainingProgram` | 10 |
| `ProgramStore` + `ProgramDayStore` | 18 |
| `ProgramDayExercisePoolStore` | 26 |
| `RotationEngine` | 25 |
| `ReadinessAdjustment` | 20 |
| `ExerciseProgression` | 18 |
| `EquipmentVariantGraph` | 15 |

132 tests across the seven seams the handoff listed. **Full suite: 900 tests, 95
suites, 0 failures**, up from the 768/88 baseline recorded before this work
began. The handoff named rotation's "skip/hold-position path and
irregular-schedule gaps" as the ones to cover hardest, and they are: skip holds
position, calendar gaps do not advance, deleting a session does not either.

**Two pre-existing tests broke and were fixed, not adjusted around:**
`BodyMeasurementTests.swift:24`'s `[41...48]` column-count assertion → `[41...49]`
(the file's own comment says a human should edit that line when a migration lands),
and a `snapshot` assertion that now excludes the five new columns and checks their
values separately.

## 9. What's deliberately not built

- **No UI automation.** The screens are built and compile, but nothing drives
  them from a test; the acceptance checklist marks the steps "implemented, not
  driven by automation" rather than claiming a driven pass.
- **`quality_reps` deferred**, per the owner's pre-resolution: zero source
  content, high authoring cost. The type exists in Migration016; no authoring
  surface for it was built.
- **Strict-cycle rotation only** — position moves through
  `setPositions(id:rotationPosition:positionWithinSession:)`, and there is no
  drag-reorder API, per the owner's pre-resolution of the handoff's open question.
- **One progression condition**, §6.
- **The rotation prompt's two-options-shown-together requirement** (Decision 3's
  flagged tension: "remove permanently" must be as easy to reach as "skip for
  today") is implemented in `ProgramSessionView` as a single `confirmationDialog`
  offering both "Skip just for today" and "Remove from rotation" together.