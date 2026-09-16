# Spec reconciliation — Technical Specification v1.0 vs. this repository

**Status:** in progress. Slice 2 landed against the spec (migration 014);
four table collisions are identified and undecided.
**Date:** 2026-09-15

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
and the definitions are not the same. Migration 014 deliberately creates none
of them.

### 4.1 `sync_anchor`

| | Migration 001 | Spec §5.24 |
|---|---|---|
| Key | `domain` TEXT | `sampleType` TEXT (HK type identifier) |
| Anchor | `anchor_token` BLOB | `anchorData` TEXT (base64 `HKQueryAnchor`) |
| Extra | `last_error` | `lastSyncTimestamp` |

Same purpose, different shape. The spec's is narrower — it assumes one anchor
per HealthKit sample type, where 001 allows any sync domain. Cheapest of the
four to resolve.

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
lose the licence model.** The honest options are to treat §5.9 as superseded,
or to keep both with a view.

### 4.3 `hydration_log` / `drink_entry` / `caffeine_log`

Here the spec is ahead. It defines a `drink_entry` that fans out to hydration,
caffeine and nutrition in one log — BRD §6.2's unified drink logging — plus a
`caffeine_log` carrying `hoursBeforeIntendedSleep` and a caffeine context
relative to *intended sleep*, which is the whole point of §6.2 for a
shift worker. This repository has hydration with drink attachments but **no
caffeine table at all**, so caffeine is currently untracked.

### 4.4 `lab_result`

The spec's §5.18 `lab_result` is ten columns: date, name, value, unit,
reference range, notes. This repository has roughly fourteen laboratory tables
— catalog, analytes, aliases, external codes, panels, reports, observations,
revisions, conflict resolution — with an authored iOS interface on top.

The spec's own §6.6 calls v1 labs "manual entry, local-only, display-only",
so the spec is not wrong; the repository simply went much further. Collapsing
to `lab_result` would delete a finished module.

## 5. What is decided, and what is not

**Decided:** new work follows the spec verbatim (migration 014 onward); the
04:00 boundary is the product rule; the 2026-08-05 spec outranks the
2026-09-15 reconstruction.

**Not decided — needs the owner:**

1. Whether §5.9 (`food_item`) and §5.18 (`lab_result`) are superseded by the
   richer implementations, or whether those implementations are rewritten to
   match the spec.
2. Whether `sync_anchor` moves to the spec's shape.
3. Whether §5.12-§5.14's `drink_entry` / `caffeine_log` replace the current
   hydration tables, or are added alongside them.
4. When to renumber 001-014 into the spec's ordering — free until the first
   durable database exists, and not before.
