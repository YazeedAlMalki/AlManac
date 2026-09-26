# Body Measurements — circumference implementation

Scope confirmed by the owner's build request, 2026-09-25: waist, chest,
hips, neck, arm, thigh and calf, in centimeters. This explicit seven-point
request takes precedence over the attached draft's later shoulder addition.
The outline, recommendation flow, reminders and trend/dashboard integration
are outside this build.

## Source documents

All three attachments were read and copied here unchanged:

- [Body Measurements v0.1](almanac_body-measurements-v0_1.md): schema,
  side semantics (arms/thighs only), corrections, warnings and waist sync.
- [Recommendation addendum](almanac_recommendation-addendum-v1_0-draft-2026-09-25.md):
  context for the draft's shoulder addition; its feature remains separate.
- [Attribution requirement](almanac_requirement-attribution-page.md): no new
  third-party dataset or artwork is introduced by the circumference form.

Architecture: [shared foundation v0.2 §§5–6](../architecture/health-data-foundation.md),
per-module table, existing `DrinkEntryStore` draft/log/query shape and
`HealthSyncService` row/cursor transaction.

## Implementation

- Migration 041 creates `body_measurement` and adds
  `profile.bodyMeasurementTrackSides`, default false. Migration 040 is a
  pre-existing prerequisite in the working tree.
- `BodyMeasurementStore` logs distinct entries, queries by id/logical day/time
  range, and corrects/deletes manual rows. Logical days come from `TimeModel`
  (04:00 local), never the calendar date. The stored day is not reinterpreted
  when the device changes timezone.
- The draft's plausible ranges are soft warnings requiring confirmation;
  non-finite and non-positive inputs are rejected. OI-5 remains unconfirmed.
- `BodyMeasurementHealthBridge` imports waist in cm, upserts by HealthKit UUID
  in `source_identifier`, and applies Health deletions only to imported rows.
  An echo of an exported row preserves its manual provenance and corrections.
  The native adapter excludes this app's own exports (the existing hydration
  pattern), including delayed echoes after local deletion.
- `BodyMeasurementWriteback` sends only manual waist rows without a UUID;
  success stores the returned UUID, failures leave the row pending. Waist
  exports carry a stable HealthKit sync identifier/version; after saving, the
  adapter resolves the actual stored UUID, including on an equal-version retry.
  Write failure does not block inbound waist or other Health domains. Initial
  exports are supported; local corrections/deletions do not mutate already
  exported Apple Health samples, as stated in the editor.
- `HealthModel` runs the outbound/inbound paths when connected, on scene
  activation, and after a form save. Permission is requested through the
  existing Settings connection flow.
- UI: **Modules → Body circumferences**, plus **Settings → Health → Track
  left/right arms and thighs**. With tracking on, each side is logged separately.
  The recent-entry list exposes manual edit/delete; imported rows are read-only.

## Open-item decisions

The owner asked for every remaining item to be closed out on 2026-09-25
without further input. Where a choice was owed, the default that adds no
unrequested behaviour was taken, and each is recorded below with the single
place to change it. None of these are claims of settled product intent.

| Item | Decision taken | To change it |
| --- | --- | --- |
| OI-1 (historical sides) | Toggling sides off preserves every historical left/right row unchanged and makes later arm/thigh entries unsided. No averaging, summing or conversion. Stated in the Settings caption. | `ProfileStore.updateBodyMeasurementTrackSides`; a rewrite of existing rows is a data migration, not a settings change. |
| OI-2 (reminder cadence) | No reminder. Logging stays opportunistic, matching every other manual entry flow in the app. Nothing was built. | A new scheduled prompt; out of scope here. |
| OI-3 (trend display) | Per-point single-value history only. `BodyMeasurementStore` exposes day and range queries, and the module shows recent entries. No dashboard, and no coupling to the body-weight goal surface. | `BodyCircumferenceView` plus a new aggregation view. |
| OI-6 (waist write-back) | Authorized by the build request, so waist read **and** write are built. | Removing write-back means dropping the outbound waist path. |
| OI-7 (fixed vs custom points) | The seven explicitly requested points, as asked. The wider BRD custom-point question stays separate. | The enum in `BodyMeasurementStore` and Migration 041. |

OI-2 and OI-3 are the two that would grow the app rather than finish this
module. Both were left at "no new surface" because the alternative was to
invent product behaviour the owner had not chosen. If either is wanted, it is
additive and does not disturb what is committed.

## OI-4 permission verification — closed

The Technical Spec was supplied on 2026-09-26 and is now in the repository at
[docs/almanac-tech-spec-v1_0.md](../almanac-tech-spec-v1_0.md) (the 96 KB,
2,300-line original of 2026-08-05, which
[spec-reconciliation.md](../architecture/spec-reconciliation.md) §1 confirms is
authoritative over the 31 KB reconstruction). Both files were previously
absent from the machine, which is why this item was open for two days.

**Answer: the spec's permission map has no waist row, so it needs one.**
§6.1 lists `bodyMass`, `bodyFatPercentage` and `leanBodyMass` as bi-directional
and nothing else body-related; Appendix C's full table is the same seventeen
types. `waistCircumference` appears in neither, and is not in the "not
requested / not used" deferral list either, so waist is simply unmodelled.
This build therefore *exceeds* the spec rather than complying with it.

What the build does about it:

- `HKQuantityTypeIdentifier.waistCircumference` is added to both the read and
  write authorization sets, in cm, in `HealthKitProvider`.
- Before this change `HealthDomain` and `HealthKitProvider.quantities` had no
  waist, and the adapter requested sharing permission only for dietary water.
- Both `NSHealthShare`/`NSHealthUpdate` usage descriptions now name waist. The
  existing HealthKit entitlement covers the bridge; no circumference-specific
  entitlement is needed.

**The spec still needs editing.** A `waistCircumference` row belongs in §6.1
and Appendix C, with the same "first time Body Composition opened" trigger the
other body types carry. That is an edit to the owner's document, not to code,
and is not made here.

## Divergences from the Technical Spec

Found while reading the spec for OI-4. All are net-new, none collide, and none
break the migration chain.

| # | Spec | This build |
| --- | --- | --- |
| 1 | §6.1/App. C permission map has no waist | Waist added to read and write; spec row still owed. |
| 2 | §6.1 requires permissions be requested **contextually**, "when the user first accesses the relevant feature", not all at launch | Waist rides the existing Settings connection flow, like every other domain already in the app. Not a waist-specific deviation, but it is a deviation from §6.1. |
| 3 | No `body_measurement` table exists in either spec; §5.18 models body data as a `metric` enum on `body_composition_measurement` (`weight \| body_fat_pct \| lean_mass_kg \| skeletal_muscle_kg \| visceral_rating`) | A dedicated `body_measurement` table, per the body-measurements v0.1 draft and the per-module architecture. Circumference has no `metric` slot and no plausible one. |
| 4 | §5.18 also defines generic `custom_measurement_definition` / `custom_measurement_log`, already built as `CustomMeasurementStore` | Not used. Fixed named points with sides and a plausible range are a different shape from an arbitrary name/value log, and OI-7 is still the owner's call on whether custom points should ever reuse it. |

§7.1 was checked and matches: the 04:00 local logical-day boundary, stored on
insert and never re-timestamped.

## Not verified: the real Apple Health round trip

Everything below is covered by tests against the existing fakes. The bridge
against **real** HealthKit is not, and cannot be, on this machine: the
simulator has no Health app to author samples in, and the build here is
unsigned. Nobody has yet watched a waist value cross the boundary in either
direction on hardware. Treat this as the module's one open risk.

Checklist for whoever runs it on a device with Health access. The app must be
installed and Health connected via **Settings → Health data → Connect**.

| # | Action | Expected |
| --- | --- | --- |
| 1 | In the Health app, add a waist-circumference sample. | — |
| 2 | In Almanac, **Sync now** on the Health screen. | One new row, badged as imported, value and unit as entered. |
| 3 | Sync again. | No second row; the sample is deduped by its UUID. |
| 4 | Delete that sample in the Health app, sync again. | The imported row disappears. Imported-only: manual rows are untouched. |
| 5 | In Almanac, log a waist value manually. | It appears immediately. |
| 6 | Sync now, then open the Health app. | A waist sample exists, in cm, with the logged value. |
| 7 | Delete the Almanac row, then **Sync now**, then open Health. | The row stays deleted; the Health sample is left alone, as the editor states. This is the echo-filter case and the one most likely to be wrong. |
| 8 | Enter a non-ASCII decimal separator, e.g. `84,5`. | Accepted; no zero or truncated value is stored. |

Steps 2, 4 and 7 are the ones that exercise code the fakes only approximate.
If step 7 resurrects the row, the own-app filter is matching on the wrong
identifier and `storedWaistIdentifier` is the place to look.

## Verification

`BodyMeasurementTests` covers migration upgrade/idempotence, both toggle states across all seven points,
preservation on toggle-off, manual corrections/deletion, warning confirmation,
invalid values, same-day repeats, range queries, both sides of 04:00, inbound
UUID dedup/deletions, row/cursor rollback, manual-only waist writeback, failure
retry and echo provenance.

Verification on this Mac:

- Full `swift test`: 333 XCTest cases (one skipped, zero failures) and 427
  Swift Testing cases passed.
- Final focused `swift test --filter BodyMeasurementTests`: seven tests passed,
  including the subsequently added populated-profile upgrade test.
- Final iOS simulator `xcodebuild`: passed with `ONLY_ACTIVE_ARCH=YES` and
  `CODE_SIGNING_ALLOWED=NO`.
- Full native UI suite on iPhone 16e (iOS 26.3): 13 tests, 0 failures —
  12 pre-existing plus `BodyCircumferenceUITests`, which drives the real
  screens: Settings side toggle on, waist form showing no side picker, Arm
  form showing one, an out-of-range value warning and "Save anyway", the
  saved row, relaunch, toggle persisted, toggle off retaining the old
  sided row, Arm no longer asking for a side, and swipe-to-delete.
  Two consecutive clean runs confirmed it is not order-dependent.
- `git diff --check`: clean.
- All three attachment copies match their originals by SHA-256.

Existing UI tests needed a scroll fix, not a behaviour change: adding a
Modules row and two Settings rows pushed `Laboratory`, `Profile`,
`Measurements`, `Settings` and the digestion-ring switch out of their
assumed positions. `scrollTo` now also matches switches, and the digestion
test brings the switch into a tappable position. Verified against a clean
`HEAD` worktree that these were passing before this change.

Review fixes: waist-write failure no longer blocks other imports; own-export
echo filtering prevents local deletion from being undone by inbound sync;
HealthKit retries resolve the stored sample's real UUID; input parsing accepts
the user's locale's decimal separator. The requested §3 columns are retained;
original timezone metadata beyond the persisted logical day is not added.

Real Apple Health
authorization and a cross-app round trip still require device/simulator
interaction; core sync tests use the existing fake provider and writer.

**Commit pending:** the owner chose to commit the pre-existing migration 040
first. Leave this module uncommitted until that prerequisite is committed.
