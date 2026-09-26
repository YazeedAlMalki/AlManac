# Almanac — Body Measurements (Circumference Tracking)

**Product:** Almanac (body-monitor app)
**Relates to:** BRD v1.5 §6.6 (Body Composition — currently unscoped, 0% built)
**Version:** 0.1 (draft) | **Date:** 2026-09-25 | **Owner:** Yazeed | **Status:** Draft, awaiting owner approval
**Scope source:** Quick-scope conversation with Yazeed, 2026-09-25
**Revised:** 2026-09-25 — added M6–M11, body outline (§3.2), acceptance criteria, suggested skills (§7); shoulders added as 8th point (Recommendation addendum R11)
**Related:** Diet/Goal Recommendation addendum (in scoping) — body-type recognition lives there, not here

---

## 1. Purpose

Almanac has no way to track body-part circumference (waist, chest, etc.) in centimeters. This note scopes a minimal, standalone module for that. It is **not** the full BRD §6.6 Body Composition module — no body fat %, no skinfold/caliper data, no photos, no lean-mass tracking. Those remain open scope if/when §6.6 gets a full pass.

## 2. Decisions

| # | Decision | Answer |
|---|---|---|
| M1 | Measurement points | Fixed set of **eight**: shoulders, neck, chest, arms (biceps), waist, hips, thighs, calves. Shoulders added 2026-09-25 for shape labels (Recommendation addendum R11). |
| M2 | Unit | Centimeters only. |
| M3 | Left/right sides | **Per-user toggle.** Off (default): one value per limb-type (arms, thighs). On: separate left/right values for arms and thighs. Waist, chest, hips, neck have no side. |
| M4 | Data source | Manual entry, plus HealthKit where Apple Health provides a matching type (waist circumference is the only HealthKit body-measurement type as of iOS 18; the rest have no HealthKit equivalent and are manual-only). |
| M5 | Custom points | Not in this scope (fixed eight only). Open item if Yazeed wants arbitrary named points later. |
| M6 | Unit storage | **`value_cm` stores centimeters, no separate unit column.** Almanac has no imperial units anywhere else in the schema. If inches are ever needed, that is a migration, not a display toggle — flagged so it's a deliberate choice, not an oversight. |
| M7 | Manual-entry correction | **Edit-in-place**, not append-only. Unlike Laboratory/Nutrition, a body measurement has no external source document to preserve and no revision-chain requirement — it's the user's own number, typed by the user. A mis-typed value can be corrected or deleted directly. HealthKit-sourced rows are not user-editable in Almanac (edit in Health instead); deleting a HealthKit-sourced row in Almanac does not delete it from Health. |
| M11 | Body outline | **A front-facing body silhouette that reshapes from the latest measurements.** Baseline proportions come from the existing `ProfileStore` fields `sex` and `height` (already built, commit `2123990`). Display only: it reads `body_measurement` rows and adds no table. See §3.2. |

## 3. Data model

Following the shared pattern from `health-data-foundation-v0.2.md` (event/measurement, per-module table, source provenance preserved):

**Table: `body_measurement`**

| Column | Type | Notes |
|---|---|---|
| `id` | surrogate PK | Almanac-owned identifier, per foundation R9.1 |
| `measured_at` | timestamp | Instant the measurement was taken |
| `logical_day` | derived | Via the existing 04:00-boundary `TimeModel`, not calendar date |
| `measurement_type` | enum | `shoulders`, `neck`, `chest`, `arm`, `waist`, `hips`, `thigh`, `calf` |
| `side` | enum, nullable | `left` / `right` / `null`. Null for shoulders/neck/chest/waist/hips always. Null for arm/thigh when the per-user side toggle (M3) is off; populated when on. |
| `value_cm` | numeric | The measurement itself |
| `source` | enum | `manual`, `healthkit` |
| `source_identifier` | string, nullable | HealthKit sample UUID when `source = healthkit`, for dedup/deletion sync per the existing `HealthSample` pattern |
| `note` | text, nullable | Optional free-text (e.g. "after fast", "post-workout pump") |
| `is_edited` | boolean, default false | Set on any manual correction, per M7. Never applies to `healthkit` rows. |

**Validation (M8, new):** each `measurement_type` gets a plausible-range check at the store layer (not a DB constraint, to allow future range changes without a migration). Working defaults, all in cm, pending Yazeed confirmation (OI-5):

| Type | Plausible range |
|---|---|
| shoulders | 60–170 |
| waist | 40–200 |
| chest | 50–200 |
| hips | 50–200 |
| neck | 20–60 |
| arm | 15–70 |
| thigh | 25–100 |
| calf | 20–60 |

An out-of-range value is a soft warning ("that looks unusually low/high — save anyway?"), not a hard block — Almanac has no medical-grade calibration to justify a hard reject.

**Same-day multiplicity (M9, new):** every entry is kept; there is no one-per-day de-dup. A day with three waist readings shows three rows. Any "latest value for the day" reduction is a display/derived-summary concern (§6), not a write-time constraint — consistent with the foundation's append rule that raw entries are never collapsed at write time.

**Settings addition:** one boolean, `bodyMeasurementTrackSides` (M3 toggle), in the user profile/settings table.

Notes on why this shape:

- **No separate "plan" concept.** Unlike Nutrition or Exercise, a body measurement has no prescribed/achieved split — it's a single logged value. Foundation's Event/Measurement/Plan/Derived-summary framework still applies, but only the Measurement leg is used here.
- **`side` is nullable rather than a second table** to keep one table for all eight points; toggling M3 doesn't require a schema change, only a change in what the logging UI collects.
- **HealthKit sync only touches `waist`.** The other seven types have no HealthKit counterpart, so `source` will only ever be `healthkit` for waist rows. This asymmetry is worth flagging in the UI (e.g. only waist gets an "synced from Health" badge) rather than surprising later.

### 3.1 HealthKit sync direction (M10, new)

Read and write both apply, but only one is unconditional:

- **Read (HealthKit → Almanac):** unconditional. Any waist-circumference sample in Apple Health is imported as a `healthkit`-sourced row, deduped by `source_identifier` per the existing `HealthSample` pattern.
- **Write (Almanac → HealthKit):** **only for manually-logged waist entries**, and only if OI-6 is decided "yes." A manually-entered waist value would need to write back to Health with its own new sample UUID, which then becomes that row's `source_identifier` even though `source` stays `manual` — worth a one-line comment in the migration so a future reader doesn't assume `source_identifier` implies `source = healthkit`.
- The other seven types never touch HealthKit in either direction.

### 3.2 Body outline (M11)

- **Baseline:** a reference silhouette chosen by `ProfileStore.sex`, scaled by `ProfileStore.height`. Nothing new is stored.
- **Anchor zones:** one per measurement point (shoulders, neck, chest, arm, waist, hips, thigh, calf). Each zone's width scales from the latest value for that point; curves are interpolated between zones.
- **Missing values:** a zone with no measurement stays at baseline and is drawn visibly differently (e.g. dashed), so a guessed shape is never shown as a measured one. Same principle as foundation's "missing is never silently zero."
- **Sides:** with the M3 toggle on, left and right limbs draw from their own values; off, both sides mirror the single value.
- **Performance:** the outline redraws **only when a measurement is saved or the screen opens** — never per keystroke while typing. Eight zones is trivial vector work at that frequency.
- **Accessibility (BRD §6.20):** the outline is decorative next to the numbers, never the only place a value appears. VoiceOver reads the values, not the shape.
- **Not in scope:** any label or judgement about the shape (pear, muscular, etc.). That belongs to the Recommendation addendum.

## 4. Open items

| # | Item | Owner |
|---|---|---|
| OI-1 | Should switching the M3 side toggle off, after left/right data already exists, average the two sides into one, keep both and just stop asking for new splits, or something else? | Yazeed (decide) |
| OI-2 | Reminder/cadence: should Almanac prompt for a periodic re-measurement (e.g. weekly), or is this purely opportunistic logging like the current manual flows? | Yazeed (decide) |
| OI-3 | Trend display: single-value history per point, or does this want to feed a dashboard alongside body weight (§6.10 goal weight)? | Yazeed (decide) |
| OI-4 | Confirm HealthKit waist-circumference read/write permission needs adding to the existing HealthKit permission map (Technical Spec §6, App. C). | Claude (verify in repo) |
| OI-5 | Confirm or amend the plausible-range table (M8). These are placeholder defaults, not clinically sourced. | Yazeed (confirm) |
| OI-6 | Should a manually-logged waist measurement write back to Apple Health (M10), or does Almanac only ever read waist from Health and never write to it? | Yazeed (decide) |
| OI-7 | **Conflict with BRD §6.6**, which says circumference measurements are "user-definable" (owner-priority). M1/M5 fix the set at eight. Options: amend the BRD to the fixed eight; keep eight as defaults and allow custom points; or ship eight now and add custom later (would change `measurement_type` from enum to a catalog table). | Yazeed (decide) |
| OI-8 | Outline when `sex` or `height` is missing from the profile: hide the outline, show a neutral baseline, or prompt for the field first? | Yazeed (decide) |

## 5. Acceptance criteria

- [ ] Logging shoulders, neck, chest, waist, or hips never shows a side selector, and always writes `side = null`.
- [ ] With the side toggle off, logging arm or thigh writes one row with `side = null`.
- [ ] With the side toggle on, logging arm or thigh requires both a left and a right value (or two separate entries) and each row carries its `side`.
- [ ] A waist sample created in Apple Health appears in Almanac as a `healthkit`-sourced row with no duplicate on repeated sync.
- [ ] Editing or deleting a `manual` row succeeds and sets `is_edited` on edit (M7). Editing or deleting a `healthkit`-sourced row is not offered in the UI.
- [ ] A value outside the M8 range for its type shows the soft warning and can still be saved on confirmation.
- [ ] Logging the same measurement type twice in one logical day keeps both rows; neither overwrites the other.
- [ ] A measurement logged at 03:30 is assigned to the previous logical day per the 04:00-boundary `TimeModel`, not the calendar date.
- [ ] Saving a new waist value reshapes the outline's waist zone; typing without saving does not redraw.
- [ ] A point with no measurement is drawn in the "not measured" style, never as if measured.
- [ ] Changing `sex` or `height` in the profile changes the outline baseline.

## 6. Next steps

**Yazeed (personal):**

- Approve or amend this note.
- Decide OI-1, OI-2, OI-3, OI-6, OI-7 and OI-8; confirm OI-5.
- **OI-7 first** — it decides whether `measurement_type` is an enum or a table, which the migration depends on.

**AI-delegatable:**

- Confirm HealthKit waist-circumference entitlement/permission (OI-4).
- Write the migration for `body_measurement` + the `bodyMeasurementTrackSides` setting.
- Build the store (`BodyMeasurementStore`) following the existing store pattern (e.g. `DrinkEntryStore`).
- Logging UI: eight-point entry form, side toggle in settings, HealthKit waist sync wiring.
- Body outline view (§3.2) — after the store is green.

## 7. Suggested skills

Skills available in Claude sessions that fit this build. In Claude Code on `yamal`/iMac they only apply if installed there.

| Step | Skill | Why |
|---|---|---|
| Break the build into commits | `mattpocock-skills:to-tickets` | Migration → store → HealthKit bridge → logging UI → outline, each with its blocking edges. |
| Build migration + store | `mattpocock-skills:tdd` | §5's acceptance criteria convert directly to failing tests first. |
| Execute from this doc | `mattpocock-skills:implement` | Works from a spec plus tickets. |
| Explore the outline before building it | `mattpocock-skills:prototype` | A throwaway outline to judge the look and the anchor-zone scaling before committing SwiftUI code. |
| Before merge | `mattpocock-skills:code-review` | Reviews the diff against this doc (the "Spec" axis) and repo standards. |
