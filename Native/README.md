# Native laboratory manual entry + hydration

This is the iOS app target for the existing Almanac core. It uses the
local package at `../Package.swift`; it adds no server, account system or
separately deployed service. The target supports iPhone and iPad on iOS 17+.

## Authored

- Navigation: a compact root shell with Today, Trends, a central Quick Log
  action and Modules. The app-owned Modules page links to Training, Hydration,
  Nutrition, Fasting, Prayer, Laboratory, Profile, Measurements and Settings,
  so the domain screens are not system-overflow tabs.
- Today includes a native graphical tracking calendar. Selecting a past date
  shows a read-only, chronologically merged history from the module-provided
  `Timeline` providers; the 04:00 Almanac logical-day boundary is shown in the UI.
- The editorial foundation is applied to the shell, Today, Trends, Quick Log and
  Modules index. Training, Hydration, Nutrition, Fasting, Prayer, Laboratory,
  Profile, Measurements and Settings remain native module screens for now; a
  later pass will bring them onto the same tokens and components.
- Visual language: a true-neutral page with hairline rules rather than stacked
  cards, one step of panel surface, and a desaturated ink-blue accent reserved
  for things Almanac recorded. Fraunces is used only for the screen title and
  the readiness number; everything else is the system sans until licensed
  Neue Montreal files are supplied.
- Quick Log provides water presets plus focused food, training and body entry;
  the Settings appearance picker persists System/Light/Dark across launches.
  Fraunces and Almarai ship with their OFL files; Neue Montreal remains a
  licensed-font dependency until approved files are supplied.
- Profile edits the existing local `ProfileStore` fields. Measurements shows
  recent body-composition and custom measurements and can add manual values.
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
  Import automation (CSV, `LabReportCSVImport`) creates these proposals:
  unchanged re-imports are no-ops via fingerprints, and unranked changes are
  held for review instead of applied.
- Import CSV: paste a report CSV in the Laboratory module; rows sharing a
  `source_report_id` form one report, source text is stored verbatim, blank
  dates stay unknown, and re-importing the same file adds nothing.
- Hydration: log water (presets or a custom amount, with an optional note),
  a dashboard of today's total against a settings-configurable daily goal,
  and delete. Backed by `HydrationLoggingService`/`HydrationStore` in the
  core; `LaboratoryModel` and `HydrationModel` share one `Database` connection.
  Nutrition's first-install reference import is the one temporary exception:
  it uses a second connection on a utility task so its long write transaction
  does not block the main actor from opening the dashboard.
- HealthKit: read and write for the `.water` domain only, via the one file
  permitted to `import HealthKit` (`HealthKitProvider.swift`). Inbound sync
  reuses the core's `HealthSyncService` unmodified; outbound uses
  `HydrationWriteback`, which pushes manually-logged entries not yet marked
  synced. The inbound/outbound pair runs when Connect is tapped, after each
  local hydration log/delete, and whenever the scene becomes active.
  Authorization is requested from Settings, not on launch.
- Local notification reminders (fixed times, configurable in Settings) via
  `NotificationScheduler`. No Info.plist key is required for local
  notifications; only runtime authorization is requested, from Settings.

The app's interactive connection is owned on the main actor. The temporary
nutrition-reference connection is the narrow background exception described
above. Saving an existing result calls the core's atomic value/metadata edit
API. The application uses
`Application Support/Almanac/almanac.sqlite`, migrates in sequence, and seeds
idempotently. An open/migration failure displays an error; it never resets data.
The actor is `user` because this is the existing local personal database model,
not an authenticated multi-user service.

## Verification boundary

The Swift sources pass `swiftc -frontend -parse` on Linux. Project file
references and shared-scheme XML have been checked for internal consistency.
These are **syntax/structure checks, not Apple SDK compilation**.

On 2026-09-22, on the Intel iMac for this session (macOS 15.8 Sequoia, Xcode
26.3 / 17C529), a Debug simulator build of the shared `Almanac` scheme for an
iPhone 17 (iOS 26.3 runtime) **succeeds**, the app **launches in the
Simulator without crashing**, and **survives relaunch with its database
intact** (`almanac.sqlite` created with 73 tables, migrations recorded in
`schema_migrations`). The only wrinkle on this Intel host: the build must run
with `ONLY_ACTIVE_ARCH=YES`, otherwise the app target also compiles an arm64
simulator slice while the local package only produced an x86_64 `AlmanacCore`
module, and the arm64 pass fails with “Unable to find module dependency:
'AlmanacCore'”. Consider setting `ONLY_ACTIVE_ARCH = YES` in the project's
Debug configuration so plain Xcode Run works without the flag.

Still not verified: interactive entry and navigation, keyboard layout,
accessibility, device signing or deployment, and the cross-app HealthKit
round trip (logging water in the Health app and watching it appear, and the
reverse) — the Health-app half needs a human drive of the Simulator; its
logic is covered by core tests on Linux.

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

On an Intel Mac, add `ONLY_ACTIVE_ARCH=YES` to the invocation — see the
Verification boundary section.

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
   and iPad navigation. Large Dynamic Type and the shell/calendar reflow are
   verified in the simulator; VoiceOver, keyboard dismissal and iPad remain
   human interaction checks.
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
13. Open Quick Log from the shell, log a water preset, then open Trends and
    confirm the empty state or bounded chart; open Modules and verify every
    destination remains reachable.

The HealthKit paths in items 10 and 11 are code-verified and now run from
three places — Connect in Settings, after each local log/delete, and on scene
activation — so what remains for those two items is driving the Simulator's
Health app itself.

Report conflict behavior is covered in core tests. Debug builds seed one
conflicting report pair automatically (`LabReportFixture`, first launch only);
open it from the Laboratory module and accept or reject with a reason, then
confirm the unresolved badge clears.

Document import, attachments, backup UI, OCR, medical interpretation, and
other tracker screens are outside this pass. Trends is now a first-class root
surface with a bounded readiness chart. The full earlier Laboratory
specification remains incomplete until the remaining features are implemented
and the real UI path above has been verified.
