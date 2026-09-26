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

## OI-4 permission verification

Before this change, `HealthDomain` and `HealthKitProvider.quantities` did **not**
include waist; the adapter requested sharing permission only for dietary water.
This implementation adds `HKQuantityTypeIdentifier.waistCircumference` to both
read and write authorization, in cm. Read/write usage descriptions now mention
waist. The existing HealthKit entitlement covers the bridge; no
circumference-specific entitlement is needed.

**The Technical Spec itself could not be read.** The authoritative path
recorded in `docs/architecture/spec-reconciliation.md`,
`../almanac-tech-spec-v1.0.md`, does not exist on this Mac, and a re-check on
2026-09-25 found no copy: the home-directory search returned only the
Almanac BRD, the design reference and the feature notes; `~/Downloads` holds
the body-measurements, addendum and attribution notes but no spec; and no MCP
document resource was available. `docs/implementation-status.md` records the
same gap independently, so this is a known repository-wide absence rather than
a search miss here.

Consequently this note does **not** claim waist is absent from §6 or Appendix C.
What is verified is narrower and still useful: waist was absent from the
pre-change `HealthDomain` and `HealthKitProvider.quantities`, and the adapter
requested sharing permission only for dietary water. Waist is now in both the
read and write sets, in cm, and both usage descriptions name it. Checking §6
and Appendix C against this is a two-minute read once the file is available.

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
