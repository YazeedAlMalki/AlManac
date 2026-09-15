# Native laboratory manual entry + hydration

This is the iOS app target for the existing Almanac core. It uses the
local package at `../Package.swift`; it adds no server, account system or
separately deployed service. The target supports iPhone and iPad on iOS 17+.

## Authored

- Reports: list, paginate, create, reopen, edit laboratory name and report date.
- Results: canonical/alias search, unmatched source names, create and edit.
- Numeric, qualitative, text, ratio, titer and absent values. Comparators,
  original units, original transcription, laboratory range text/bounds/units,
  reported flags, specimen, method, LOD/LOQ and derivation remain separate.
- Explicit date precision, including Unknown. No device date or timezone is
  filled into a historical result. Existing separately stored zone context
  survives a date edit; textual offsets take precedence in core date queries.
- Report detail, longitudinal test history with source-report navigation, and
  a separate revision history including metadata corrections and attribution.
- Incoming report-conflict review with explicit accept/reject and reason.
  There is no import automation creating these proposals in this app.
- Hydration: log water (presets or a custom amount, with an optional note),
  a dashboard of today's total against a settings-configurable daily goal,
  and delete. Backed by `HydrationLoggingService`/`HydrationStore` in the
  core; `LaboratoryModel` and `HydrationModel` share one `Database` connection.
- HealthKit: read and write for the `.water` domain only, via the one file
  permitted to `import HealthKit` (`HealthKitProvider.swift`). Inbound sync
  reuses the core's `HealthSyncService` unmodified; outbound uses
  `HydrationWriteback`, which pushes manually-logged entries not yet marked
  synced. Authorization is requested from Settings, not on launch.
- Local notification reminders (fixed times, configurable in Settings) via
  `NotificationScheduler`. No Info.plist key is required for local
  notifications; only runtime authorization is requested, from Settings.

The connection is owned on the main actor. Saving an existing result calls the
core's atomic value/metadata edit API. The application uses
`Application Support/Almanac/almanac.sqlite`, migrates in sequence, and seeds
idempotently. An open/migration failure displays an error; it never resets data.
The actor is `user` because this is the existing local personal database model,
not an authenticated multi-user service.

## Verification boundary

The Swift sources pass `swiftc -frontend -parse` on Linux. Project file
references and shared-scheme XML have been checked for internal consistency.
These are **syntax/structure checks, not Apple SDK compilation**.

Not yet verified: SwiftUI type checking against an Apple SDK, Xcode package
resolution and linking, Simulator launch, interactive entry and navigation,
keyboard layout, accessibility, relaunch persistence through the app, device
signing or deployment. Linux core tests do not establish any of these.

## Build and run on a Mac

Open `Native/Almanac.xcodeproj`, select the shared `Almanac` scheme and an
installed iPhone Simulator, then Run. For a command-line Simulator build from
the repository root:

```sh
xcodebuild -project Native/Almanac.xcodeproj -scheme Almanac \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

The target has a provisional bundle identifier `com.almanac.personal`. Configure
a suitable identifier/team when preparing a physical-device build. The target
now carries the HealthKit capability and `Almanac.entitlements`
(`com.apple.developer.healthkit`), added by hand-editing `project.pbxproj` —
**on first open in Xcode, verify via Signing & Capabilities that HealthKit
shows as added, and let Xcode rewrite the `TargetAttributes`/
`SystemCapabilities` block if anything looks off** rather than fighting the
manual edit further. It still uses no document picker.

## Interactive acceptance checks — outstanding

1. Create a report with an unknown date; close and reopen the app and report.
2. Add Hemoglobin, HbA1c, Ferritin, Vitamin D, Creatinine and TSH through alias
   search. Copy original values, units and ranges from test fixtures or a
   report; do not infer a range. Add ANA with qualitative value `Negative`.
3. Add a bounded numeric result using `<`; verify both comparator and original
   transcription appear. Confirm a blank range remains “Not stated”.
4. Enter a month date, date-only, local time with no offset, Z timestamp and
   +03:00 timestamp. Save/reopen each without precision or timezone invention.
   Invalid calendar dates and offsets should display an error and leave data
   unchanged.
5. Edit one value A → B → A, supplying a reason each time. Revision history
   must show three events with only the latest current. Change only specimen
   or collection date and inspect the separate metadata correction record.
6. Add a second report with the same canonical test. Test history must show two
   measurements; their revision histories remain separate. Follow each source
   report link. Different units/specimens remain visible; no combined trend
   curve or unit conversion is inferred.
7. Clear an optional unit/range/date, save and reopen. Confirm the prior value
   is still accessible in history. Cancel an edit and confirm no save occurs.
8. Exercise compact/large Dynamic Type, VoiceOver, iPhone keyboard dismissal
   and iPad navigation. These interaction checks require the actual app.
9. Log water via a preset and via a custom amount; confirm the dashboard total
   and progress bar update and the entry appears in today's list. Delete an
   entry and confirm the total drops accordingly.
10. From Settings, connect HealthKit; confirm the system authorization sheet
    appears listing only water read/write. Log an entry in Health directly
    (outside Almanac) and confirm it appears in the dashboard after sync.
    Delete a HealthKit-sourced entry in Almanac and confirm it does not
    reappear after a further sync.
11. Log an entry in Almanac with HealthKit connected; confirm it appears in
    the Health app's Water record shortly after (outbound writeback runs
    after connecting and after each manual log's own inbound sync call).
12. Enable reminders in Settings; confirm the notification-permission prompt
    appears, then confirm a reminder fires at a configured time
    (fast-forward the simulator clock or pick a near-future time to verify
    without waiting).

Report conflict behavior is covered in core tests. To exercise its UI, use a
development fixture that supplies conflicting reports via `upsertReport`; then
accept or reject with a reason and confirm the unresolved badge clears.

Trends, document import, attachments, backup UI, OCR, medical interpretation,
and other tracker screens are outside this pass. The full earlier Laboratory
specification remains incomplete until the remaining features are implemented
and the real UI path above has been verified.
