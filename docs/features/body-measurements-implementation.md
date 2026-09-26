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

## Owner decisions retained

- **OI-1 is a reversible stub, not a resolved product decision:** toggle-off
  preserves all historical left/right rows and makes subsequent arm/thigh
  entries unsided. No averaging, deletion or conversion. Marked in code and UI.
- **OI-2/OI-3:** reminder cadence and trend/dashboard presentation are undecided.
- **OI-6:** this build request explicitly authorizes waist read + write.
- **OI-7:** the implementation uses the explicitly requested fixed seven points;
  the wider BRD custom-point question remains separate.

## OI-4 permission verification

Before this change, `HealthDomain` and `HealthKitProvider.quantities` did **not**
include waist; the adapter requested sharing permission only for dietary water.
This implementation adds `HKQuantityTypeIdentifier.waistCircumference` to both
read and write authorization, in cm. Read/write usage descriptions now mention
waist. The existing HealthKit entitlement covers the bridge; no
circumference-specific entitlement is needed.

**Technical Spec verification remains incomplete:** the authoritative path
recorded in `docs/architecture/spec-reconciliation.md`,
`../almanac-tech-spec-v1.0.md`, does not exist on this Mac. A search under the
user's home did not locate another copy, and no MCP document resource was
available. Consequently this note does not claim waist is absent from §6 or
Appendix C; only its absence from the pre-change implementation was verified.

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
