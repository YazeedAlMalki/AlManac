# Spec reconciliation — Technical Specification v1.0 vs. this repository

**Status:** collisions resolved 2026-09-16 (commit `c83e88c`, migration 015).
The naming split (§3) remains open by design — deferred, not blocking.
**Date:** 2026-09-15 (updated 2026-09-16)

## 1. The spec was not lost

Every status document in this project through 2026-09-15 records Technical
Specification v1.0 as lost since 2026-08-05, and the code was written
accordingly: `Migrations.swift` says "that text is not available to this
package, so none of those 48 tables are invented here", and `TimeModel`
shipped a `.midnight` boundary described in its own doc comment as "a neutral
placeholder, not a decision".

The full spec is at `../almanac-tech-spec-v1.0.md` — 96 KB, 2,300 lines, dated
2026-08-05, one directory above the repository root. It contains what the BRD
defers to it:

| Section | Content |
|---|---|
| §5 | Complete 48-table schema |
| §6, App. C | HealthKit permission map and integration contract |
| §7 | Time and logical-day rules, including the 04:00 boundary |
| §8 | Sleep classification and readiness-cycle linking |
| §9, App. A | Readiness formula v1.0 — weights, scoring bands, confidence, calibration, baselines, precedence |
| §10 | Workout merge confidence model |
| §11-§13 | Fasting, prayer-time and circadian engines |
| §14, App. B | Notification scheduling and suppression matrix |
| §15-§17 | Goals engine, backup/restore contract, screen map |

The 31 KB `../almanac-technical-spec-v1.0.md` written on 2026-09-15 is a
reconstruction produced while the original was believed lost. Where the two
disagree, the 2026-08-05 original is authoritative — it is the document the
BRD's "per Technical Spec" deferrals point at.

## 2. What changed as a result

- **Migration 014** transcribes the fourteen §5 tables Slice 2 needs, verbatim.
- **`TimeModel`'s default boundary is now 04:00** (§7.1), not midnight.
  `Native/Almanac/HydrationModel.swift` was constructing `TimeModel` without a
  boundary and therefore grouping hydration by calendar date — the placeholder
  had become a silent decision. It now gets the spec's rule.
- `SleepClassifier` (§8), `ReadinessFormula` / `ReadinessEngine` (§9,
  Appendix A) and `CircadianContextEngine` (§13) implement the spec's stated
  rules rather than inferred ones.

## 3. The naming split, and why it is temporary

Migrations 001-013 use snake_case. The spec uses camelCase, and migration 014
follows the spec. One database now holds both.

The owner's decision on 2026-09-15 was **spec verbatim, renumber**: the code
should match the spec 1:1, which makes the existing migrations the ones that
move. That reconciliation has not been done. Nothing is applied to a durable
database — tests build in-memory or temporary files — so renumbering and
renaming remain free, and `docs/architecture/health-data-foundation.md` §11
still describes the freeze point correctly: the first durable database.

## 4. The four collisions

These are the tables where the spec and this repository both define something
and the definitions are not the same. Migration 014 deliberately created none
of them; migration 015 (commit `c83e88c`, 2026-09-16) settles all four per
`schema-collision-decision-2026-09-16.md` (project memory). Principle: the
spec governs anything not yet built or anything where it is ahead of the
code; where the implementation already exceeds the spec, the spec section is
amended to match reality rather than the reality being cut down to the spec.

### 4.1 `sync_anchor`

| | Migration 001 | Spec §5.24 |
|---|---|---|
| Key | `domain` TEXT | `sampleType` TEXT (HK type identifier) |
| Anchor | `anchor_token` BLOB | `anchorData` TEXT (base64 `HKQueryAnchor`) |
| Extra | `last_error` | `lastSyncTimestamp` |

Same purpose, different shape. The spec's is narrower — it assumes one anchor
per HealthKit sample type, where 001 allows any sync domain. Cheapest of the
four to resolve.

**Decided 2026-09-16:** adopt the spec's shape. Migration 015 drops the old
`sync_anchor` and recreates it keyed on `sampleType` (UNIQUE), with
`anchorData` (base64 `HKQueryAnchor`) and `lastSyncTimestamp`, per spec §5.24.
`SyncAnchorStore` and `HealthSyncService` moved with it. Prior anchors are not
migrated — next sync re-reads from the start per HealthKit type, an accepted
one-time cost. Shipped in commit `c83e88c`.

### 4.2 `nutrition_log` / `food_item`

The spec models food as one flat `food_item` table: nutrients per 100 g,
`sourceDatabase` as a string, no licence model.

This repository has `nutrition_food`, `nutrition_food_name`,
`nutrition_nutrient`, `nutrition_value`, `nutrition_portion`,
`nutrition_source` and `nutrition_dish` — 8,354 canonicalised foods from
USDA/CIQUAL/CoFID/AFCD with per-value provenance, licence groups and QA. It is
strictly richer than `food_item` and carries the licensing discipline BRD
R-FOOD requires, which `food_item` cannot express.

**Porting this onto the spec's shape would destroy working, tested work and
lose the licence model.**

**Decided 2026-09-16:** superseded by the repository's implementation. The
seven-table nutrition model with per-value provenance and licence groups
stays as-is; §5.9 is recorded as amended, for the reason above. Nothing is
rewritten down to `food_item`.

### 4.3 `hydration_log` / `drink_entry` / `caffeine_log`

Here the spec is ahead. It defines a `drink_entry` that fans out to hydration,
caffeine and nutrition in one log — BRD §6.2's unified drink logging — plus a
`caffeine_log` carrying `hoursBeforeIntendedSleep` and a caffeine context
relative to *intended sleep*, which is the whole point of §6.2 for a
shift worker. This repository has hydration with drink attachments but **no
caffeine table at all**, so caffeine is currently untracked.

**Decided 2026-09-16:** add both, per spec §5.12 and §5.14, alongside the
existing hydration tables rather than replacing them. `drink_entry` carries
the drink taxonomy, per-drink caffeine/calorie fields and custom-drink
support the repo was missing. `caffeine_log` closes the shift-worker gap
entirely — `intendedSleepTimestamp`, `hoursBeforeIntendedSleep`,
`caffeineContext` (`early`/`normal`/`late`/`very_late`). `DrinkEntryStore` and
`CaffeineLogStore` ship with it. Shipped in commit `c83e88c`.

### 4.4 `lab_result`

The spec's §5.18 `lab_result` is ten columns: date, name, value, unit,
reference range, notes. This repository has roughly fourteen laboratory tables
— catalog, analytes, aliases, external codes, panels, reports, observations,
revisions, conflict resolution — with an authored iOS interface on top.

The spec's own §6.6 calls v1 labs "manual entry, local-only, display-only",
so the spec is not wrong; the repository simply went much further.

**Decided 2026-09-16:** superseded by the repository's implementation, for
the same reason as §5.9 above. The ~14-table laboratory module and its
authored iOS interface stay; §5.18 is recorded as amended rather than the
module being collapsed to it.

## 5. What is decided

**Decided 2026-08-05 → 2026-09-15:** new work follows the spec verbatim
(migration 014 onward); the 04:00 boundary is the product rule; the
2026-08-05 spec outranks the 2026-09-15 reconstruction.

**Decided 2026-09-16 (commit `c83e88c`, migration 015) — all four collisions
resolved:**

1. §5.9 (`food_item`) and §5.18 (`lab_result`) are **superseded** by this
   repository's richer implementations (§4.2, §4.4 above). Neither is
   rewritten to match the spec's narrower shape.
2. `sync_anchor` **moved to the spec's shape** (§4.1 above).
3. §5.12-§5.14's `drink_entry` / `caffeine_log` were **added alongside** the
   current hydration tables, not as a replacement (§4.3 above).

Full rationale for all four: `schema-collision-decision-2026-09-16.md`
(project memory).

**Still open, deferred by design — not blocking:**

4. When to renumber 001-013 (snake_case) into the spec's camelCase ordering
   established by 014-015. Still free until the first durable database
   exists (`docs/architecture/health-data-foundation.md` §11), and nothing
   forces it before then. No pressure to act on this now; new work
   (Slice 4 onward) simply follows the spec's camelCase convention verbatim,
   as 014-015 already do.

## 6. Slice 4 (Training) — a fifth divergence, flagged rather than silently built around

Not one of the four collisions above — those only cover tables migration 014
touched. Checked separately while updating this doc (2026-09-16), against
`../almanac-tech-spec-v1.0.md` §5.17 "Training Tables":

The original spec models training as `exercise`, `program`, `session`,
`set_entry`, `workout_day`, `workout_day_exercise`, `workout_merge_record` —
a sets/reps/load shape. `prescription-model-v0.1.md` (2026-09-02, project
memory) argues at length that this shape "silently corrupts every [training]
kind" that isn't a straight barbell lift (AMRAPs, intervals, holds, skill
work, session-only work) and designs a 12-`prescription_type` /
10-`container_type` model instead, with tables named `exerciseCatalog`,
`prescribedWorkout`, `workoutSession`, `workoutBout`.

Nothing in §5.17 has been built (Training is 0% per the 2026-09-16 status
doc), so this isn't "implementation exceeds spec" like §4.2/§4.4 — it's two
specs disagreeing before either is code. The Slice 4 execution instructions
(2026-09-16) direct building the prescription model's tables, camelCase, not
§5.17's. Recorded here so a future reader of migration 016 isn't left
wondering why it doesn't match §5.17 — same transparency principle as the
four collisions above, not a new decision made by this doc.
