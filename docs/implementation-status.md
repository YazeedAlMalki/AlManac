# Almanac implementation status

Updated 2026-09-25. The production nutrition reference bundle now ships as an
AlmanacCore resource and installs into the app database on first launch. The
app-owned More navigation and Today tracking calendar are also live.

The canonical product requirements are now `docs/brd-v1_6.md`. The v1.5
Monthly Achievement Calendar is superseded by the v1.6 Activity Rings Calendar
and is not a current implementation target.

## 2026-09-25 — More navigation and Today tracking calendar

The app now owns its navigation instead of relying on iOS to overflow the sixth
root tab.

- The root `TabView` has exactly five destinations: Today, Training, Hydration,
  Nutrition and More. More is an app-owned `NavigationStack` with Laboratory,
  Profile, Measurements, Prayer, Fasting and Settings links. Existing Laboratory
  and Settings screens were made embeddable so More does not create nested
  navigation stacks.
- `ProfileView` edits the existing `ProfileStore` fields and refreshes the Today
  greeting after save. `MeasurementsView` reuses the body-composition and custom
  measurement stores, shows recent values, and accepts manual body/custom adds.
- `PrayerView` is reachable from More. `PrayerModel` reuses the core
  `PrayerTimeEngine`, ensures a rolling cache on launch/foreground, resumes
  authorized location updates, recalculates after a location/method change, and
  pauses location updates in the background.
- `FastingView` is reachable from More. `FastingModel` runs the existing
  `ReligiousFastingService.ensureDay` orchestration after prayer-cache refresh,
  shows the day's religious session/window state, and can be refreshed manually.
- `TrackingCalendarModel` provides a native graphical date picker on Today. A
  selected calendar date is converted to Almanac's explicit logical-day label
  (04:00 boundary), then `TrackingTimeline` merges the module-provided laboratory,
  nutrition and hydration providers with the specialised training, measurement,
  mood, soreness, sleep and vitals stores into one ordered, value-preserving
  read-only history. Viewing history never writes historical readiness data.
- HealthKit body-composition and vitals bridges now derive logical days through
  the same DST-safe `TimeModel` as sleep/workouts. Migration 037 stores a
  timezone identifier for new samples; identified rows are re-bucketed on app
  configuration; legacy offset-only rows are repaired only when their stored
  offset still matches the sample's current zone, otherwise they wait for a
  safe re-sync. Migration 038 carries the same zone context for custom
  measurement timestamps. A 03:30 sample on a fallback transition remains in
  the previous Almanac day.

## 2026-09-25 — BRD v1.6 Activity Rings Calendar

The Today tracking surface now implements the v1.6 §6.16 product surface rather
than the superseded free-date picker:

- `ActivityRingCalendar` is a derived, local-first month reader. It uses the
  existing hydration settings/logs, live workout sessions, and nutrition logs;
  it does not persist a second ring-state cache.
- Hydration and training are binary rings. The month query uses `TimeModel` and
  the 04:00 logical-day boundary, including month-end and DST-safe bounds.
  Civil calendar dates are rendered as calendar dates, while records are
  assigned to their logical day.
- A logged nutrition day reports `dietProfileRequired`; the ring does not invent
  hit/off/mess thresholds before the separate Diet Profile spec exists. A day
  with no nutrition log renders no nutrition ring. Golden completion requires a
  Nutrition `hit`, so the current dependency cannot produce a false golden day.
- Digestion has a persisted Settings toggle. Its visual indicator is distinct and
  explicitly unavailable because the daily fill rule is intentionally undefined.
- The current explicit hydration goal is used for the displayed month until the
  separate §6.10 historical target-snapshot work exists; no retroactive target
  history is invented here.
- Today now has previous/next month controls, a selectable month grid, a
  separate today halo, non-color ring states plus VoiceOver labels, day detail,
  and a correction surface for hydration, nutrition, and training logs. The
  correction surface recalculates the rings through the owning stores.
- Migration 039 adds the singleton Activity Rings display preference. Core
  tests cover the public month seam; UI tests cover the grid, navigation,
  day-detail/editor path, and the Settings toggle.
- Final verification: 332 XCTest tests (1 skipped), 420 Swift Testing tests,
  simulator build, and all 10 UI tests pass.

## 2026-09-25 — Fasting edit reconciliation

- `FastingAwareNutritionLog.update` now revises the stored meal and reruns the
  fasting decision against the edited food, amount and occurrence time.
- Removing a meal's calories restores an affected normally-ended, shortened or
  invalidated fast; moving a shortened or invalidated meal later/into the fast
  re-applies the correct end or invalidation. The existing active/recent-session
  scope is explicit.
- Edit-path regression tests cover timestamp, amount, restoration, invalidation,
  extension, unknown-time and metadata-only cases.

## 2026-09-25 — Atomic bundle document restore

- Bundle documents are staged before touching the live document root, then
  committed with rollback protection. A failed write now leaves both the
  document tree and live database unchanged.

## 2026-09-25 — Circular wake-time averaging

- `NotificationTriggerAssembler` now uses a circular mean for the seven-day
  fallback wake time, so observations straddling midnight average to the
  correct time-of-day. Exactly opposed observations return no prediction rather
  than an arbitrary midpoint.
- Added ordinary, across-midnight and undefined-midpoint regression tests.

## 2026-09-25 — Production nutrition reference bundle ships

The generator, cross-language importer and Nutrition UI already existed, but the
only generated database lived outside the repository and no app launch path
called the importer. A fresh install therefore had an empty food catalogue.

- Rebuilt from the exact official USDA 2026-04-30, CIQUAL 2025, CoFID 2021 and
  AFCD Release 3 inputs. The resulting 8.5 MB SQLite resource contains **8,354
  foods and 49,036 values**; pipeline QA reports zero fidelity, token, licence
  or portion-fidelity problems.
- The real `.sqlite` file is committed at
  `Sources/AlmanacCore/Nutrition/Resources/almanac.sqlite` through one targeted
  `.gitignore` exception. `Package.swift` copies it into AlmanacCore's resource
  bundle, so the app and tests resolve the same artefact.
- `AttributionCatalog` now guards all four shipped nutrition datasets as well as
  the exercise sources. USDA, CIQUAL, CoFID and AFCD each carry publisher,
  source-provided notice, source and licence links; the three transformed
  datasets state what the normalization changed.
- `NutritionReferenceBundle.installIfNeeded(into:)` imports on first launch and
  after a bundle SHA change, while returning without mutation for an unchanged
  bundle. `NutritionModel.configure()` starts the first install on a utility
  task using a second SQLite connection. WAL lets the rest of the app remain
  usable while the long reference write transaction runs. An existing catalogue
  remains searchable while its SHA is checked; a first install shows preparation
  progress, and a failure offers retry without discarding a valid old catalogue.
- The public seam test installs the real resource into a migrated in-memory
  database, searches the resulting catalogue and proves a second install is a
  no-op. The existing fixture and real-bundle tests continue to cover importer
  transactions, licence guards, portions and user-dish preservation.
- Fresh-install simulator verification: the Today dashboard was already visible
  4.26 seconds after launch while the background import continued, then finished
  at 34.32 seconds with 8,354 foods, 49,036 values, 123 household measures,
  2,941 food factors and one import audit row. A second launch left the audit
  count at one.
- Final checks: pipeline QA passed; Python 3.14 real-lake integration passed 102
  tests (1 opt-in skip); the full Swift run passed 325 XCTest tests (1 skip) and
  419 Swift Testing tests; the Debug simulator build and all nine UI tests pass,
  including the new More destinations, Today tracking calendar, Prayer, and Fasting screen coverage.

Still not done: owner-supplied Saudi/Gulf dish data, and the derived
`edibleGrams`/specific-gravity calculation recorded as to-do #17.

## 2026-09-24 — Exercise graphics + Attributions page

Implements the two requirements in `docs/exercise-sources.md` and
`docs/attribution-requirement.md` (both added to this repo in this pass).

- **`WorkoutGuideSeed`** — the catalogue is now all 302 `bryllim/workout-guide`
  exercises (Bryl Lim, CC BY-SA 4.0), each bundled with the 512×512 PNG drawn
  for it (~9.7 MB, one per exercise, not all 906 frames). The exercise list,
  licence, author and per-frame upstream attribution come from workout-guide's
  own `manifest.json`, copied into the resource bundle rather than retyped.
  `prescriptionType` is a mechanical mapping from the source's own
  `exerciseType`/`isStretch` fields, not 302 hand-assigned rows.
- **The rule is enforced, not asserted.** `ExerciseGraphicAudit` fails the
  build (and the app's own launch) if any shipped exercise lacks a graphic that
  is really in the bundle. `AttributionAudit` does the same for a bundled
  source with no Attributions entry. Both also run in `LaboratoryModel.open()`.
- **`Attributions` page** — `Native/Almanac/AttributionsView.swift`, under
  Settings → About. Compiled-in entries plus a per-author list read from the
  local catalogue, so it works offline. Every CC BY-SA entry carries title,
  author, source link and licence link; the Everkinetic entry is marked
  modified with the derivation described, as CC BY-SA requires.
- **Migrations 034/035** — `exerciseCatalog.licenseAuthor` and
  `.graphicPath`. **035 also soft-deletes the old wger rows**: those 21
  exercises have no compliant graphic, so leaving them live would break the
  rule the app enforces on itself and an upgraded app would refuse to open.
  Soft delete, not erase — bouts logged against them still resolve.

**Why the wger seed was removed rather than given borrowed graphics:** measured
against all four sources, "Pause Bench", "Thruster" and "Glute-Ham Raise" have
no clean-licensed illustration anywhere (only free-exercise-db, whose photo
provenance is unverified), and others only match the wrong movement ("Wall
Squat" → "Squat"). A wrong demonstration is worse than none. Table in
`docs/exercise-sources.md`.

**Also fixed (found while verifying):** `AppGroupDatabase.legacyFileURL()` —
introduced with the widget/App-Group work in `2108af0` — returned a path inside
an `Application Support/Almanac` directory it never created, so a **fresh
install with no App Group container could not open its database at all**
("SQLite error 14"). Caught by reinstalling from scratch rather than trusting a
relaunch. One `createDirectory` call restores the behaviour the pre-widget code
had.

**Verified (iMac, this session):** `swift test` — XCTest 292 (1 opt-in skip),
Swift Testing 394, 0 failures. Debug simulator build of the shared `Almanac`
scheme succeeds. Fresh simulator install: app launches, database created,
migrations 34+35 recorded, 302 live catalogue rows, **0 without a graphic**,
all 302 graphics present and non-empty in the installed bundle.

**Not verified:** nothing outstanding for this feature — see the UI test
target below, which closes the gap this entry previously carried.

### 2026-09-24 addendum — `AlmanacUITests` target

The gap above ("not driven interactively") is now closed by a UI test target.

- **`Native/AlmanacUITests/AttributionsUITests.swift`** — 3 XCTest UI tests on
  a real simulator: the Attributions page credits every bundled source with
  title, author, source link and licence link; a derived image is marked
  modified *and* says what changed; the per-exercise author list is present;
  and every visible row of the exercise picker draws a demonstration graphic.
- Wired into `project.pbxproj` (target `AB00000000000000000008`,
  `TEST_TARGET_NAME = Almanac`) and the shared `Almanac` scheme's `TestAction`.
  Run with:

  ```sh
  xcodebuild test -project Native/Almanac.xcodeproj -scheme Almanac \
    -configuration Debug -sdk iphonesimulator \
    -destination 'platform=iOS Simulator,id=<simulator-udid>' ONLY_ACTIVE_ARCH=YES
  ```

- Historical note: when this target had six roots, iOS collapsed the sixth tab
  into **More** and presented the overflow as a table. The app now owns a
  five-tab shell and an app-owned More page; the UI helper covers both shapes.


## 2026-09-24 — HealthKit non-water domains: sleep, vitals, body composition

`docs/next-slice-brief.md` §4 recorded this slice as **blocked** on the spec's
§6/Appendix C HealthKit permission map, which is not on this machine. The block
turned out to be unnecessary: the map was already encoded in the codebase —
`HealthDomain` names all eleven domains, the three bridges each declare the
metric and unit their samples land under, and `SleepStage` is defined in terms
of `HKCategoryValueSleepAnalysis`. Only the `HealthDomain` → HealthKit
identifier mapping in the iOS adapter was missing, and that is a 1:1 reading of
names the core already fixed.

**What was actually broken:** `HealthKitProvider` returned an empty change set
for every domain except `.water`, and nothing in `Native/` ever called
`VitalsRecordHealthBridge`, `BodyCompositionMeasurementHealthBridge` or
`SleepClassifier`. Three bridges, fully built and tested, feeding nothing.

### New

- **`Sources/AlmanacCore/Sleep/SleepEpisodeHealthBridge.swift`** — the one
  domain with no writer. Sleep was the only `HealthDomain` whose samples could
  not reach a table: `SleepClassifier` and `SleepEpisodeStore` existed with
  nothing feeding them. Composes `HealthSampleStore` (a previous bridge
  re-implemented that persistence and was deleted — Migration021) and
  re-classifies each touched day through §8.1–§8.3.

  Two non-obvious things it had to get right, both found by tests:
  - An episode is keyed by the day it **wakes**, and with a 04:00 boundary a
    sample's own logical day is only a hint about where its episode ends. Each
    touched day is therefore widened by the day after it: withdrawing the
    23:00–03:00 stage of a night leaves the remaining stages ending at 07:00, on
    a day the withdrawn sample never mentioned.
  - An episode's identity is its first sample's UUID, so withdrawing that one
    sample re-identifies an unchanged night. The upsert cannot see that (the new
    identity is a different key), and the dashboard sums every episode on the
    day, so superseded rows are retired explicitly. `sleep_episode` has no
    `deletedAt` column, so this is a hard delete, scoped to rows that have a
    `healthKitUUID` and only on a day that was just reclassified — manual
    wake-time entries are never touched.

- **`Sources/AlmanacCore/Health/HealthSummaryStore.swift`** — the display
  surface `next-slice-brief` §4 flagged as the genuinely new design work.
  Reads the three tables the bridges write as one list. The three do not agree
  on soft deletion (`body_composition_measurement.deletedAt`,
  `vitals_record` has no such column, `sleep_episode` is keyed by source), so
  each spec carries its own scope predicate.

- **`Native/Almanac/HealthModel.swift` / `HealthView.swift`** — the sync driver
  and Settings → Health data. It was placed in Settings rather than as a
  seventh tab; the current app-owned More page now carries that navigation.

### Two mappings that are not the obvious identifier

- `.heartRate` reads **`restingHeartRate`**, not raw heart rate.
  `VitalsRecordHealthBridge` files it under the `rhr` metric and
  `ReadinessModel` reads it as resting heart rate averaged over 28 days as the
  readiness baseline. Feeding it all-day instantaneous readings would report
  "120 bpm" after a run and make every readiness score wrong — worse than
  reporting none. The cost: a user with no Apple Watch sees no resting heart
  rate, which is the honest answer rather than a fabricated one.
- `.restingEnergy` reads **`basalEnergyBurned`**. HealthKit has no
  `restingEnergyBurned`; basal energy and resting metabolic rate are close but
  not the same measurement.

`HKCategoryValueSleepAnalysis.asleepUnspecified` maps to `.asleepCore` — sleep
of unknown depth, and core is the stage always present in a night, so it cannot
distort the deep/REM weighting. A stage value outside the known set is dropped,
not guessed.

### Not done, deliberately

- **HealthKit workouts.** Matching a workout to a logged bout needs a
  duplicate/merge policy — a real decision. `WorkoutHealthKitMatcher` stays
  built and unwired. `HealthDomain.workouts` is excluded from
  `HealthKitProvider.readableDomains`.
- **Water is still `HydrationModel`'s.** It is the only write-back domain;
  syncing it from two places would race on the same anchor.

### Verification

- `swift test`: XCTest 302 (1 opt-in skip) + Swift Testing 394, 0 failures.
  10 new core tests across `SleepEpisodeHealthBridgeTests` and
  `HealthSummaryStoreTests`. The summary tests drive the **real** bridges
  through `HealthSyncService` and read the summary back, so a screen wired to
  the wrong table or metric fails rather than showing nothing.
- Simulator build succeeds; 4/4 UI tests pass, including a new one asserting
  the Health screen is reachable and never renders a blank list.
- Fresh install: 35 migrations, 302 exercises, 0 health rows — correct, since
  the simulator has no Health app and no authorisation.

**Not verified:** real sample ingestion. The simulator cannot authorise
HealthKit, so no actual sleep or vitals sample has been synced end to end. The
plumbing is covered by tests over `FakeHealthProvider`; a device is required to
confirm HealthKit returns what the mapping expects — in particular whether
`restingHeartRate` is populated for the user, which decides whether the Today
dashboard has a resting heart rate at all.


## 2026-09-25 — HealthKit workouts: the last unwired domain

Closes the whole of `docs/features/training.md` §6 step 1 — the item deferred
from the 2026-09-24 slice. Every `HealthDomain` now has a mapping in
`HealthKitProvider` and a writer in core.

**Decided with the user:** an unmatched workout becomes its own session (so watch
workouts count with no manual logging), and two records are "the same workout"
at 60% overlap.

### One correction worth reading

I described that second rule to the user as *"60% of the shorter window"*, and
that description was **wrong**. A 45-minute run inside an 8-hour session shares
100% of the shorter window, so that rule does the exact thing it was meant to
prevent — it absorbs the run into the day's session. The metric that actually
separates the cases is overlap over the **union** of both windows: the same pair
scores ~9% there, while two near-identical windows still score ~98%. Shipped as
60%-of-union, and the correction was flagged before implementing rather than
after.

`WorkoutHealthKitMatcher` also had a latent bug the new tests exposed: its
tiebreak was `max(by: overlap)` with no further key, so two equally-overlapping
sessions resolved by **input order** — a workout could move between sessions on
alternate syncs. It now breaks ties on a total order (confidence, then
duration, then id).

### New

- **`Sources/AlmanacCore/Training/WorkoutSessionHealthBridge.swift`** — one
  `HKWorkout` maps to exactly one session. No confident match → a new session
  with no bouts; a match → the user's session is *claimed* and enriched, never
  duplicated. A withdrawn workout soft-deletes a session the bridge created but
  only *releases the claim* on one the user logged, because that record is
  theirs and a source withdrawing its own sample is not permission to erase
  something Almanac never owned.
- **`Migration036_WorkoutSessionSource`** — `source` + `healthKitUUID` on
  `workoutSession`, with a partial unique index. The two columns deliberately
  mean different things: `source` records who *created* the row, `healthKitUUID`
  only that a workout is linked to it. Conflating them is what made the first
  draft of the withdrawal path delete users' own logs.
- **`WorkoutActivity`** — turns an activity identifier into a label, with a
  camel-case fallback. Deliberately **not** the ~80-row decision table §6 step
  1(c) anticipated: `workoutSession.sessionType` is free text with no semantic
  consumer, so the table would mostly re-spell what the fallback produces. The
  doc records when to promote it to a closed enum.

### Two pre-existing bugs that auto-logging would have made visible

- **`TrainingModel.logBout`** attached a manually logged bout to
  `sessions(date:).first`. Once a watch workout created a session, that would
  have become the target and the user's own sets/reps would report as the
  watch workout's detail. It now prefers a session with no `healthKitUUID`.
- **`WorkloadComputer`** summed only bouts, so a session-only workout
  contributed *no* training load — which would have made Q1's "training load
  counts watch workouts" true of the database and invisible on the Training tab.
  `summary(for:bouts:)` now adds the duration of sessions that have no bouts,
  skipping any that do, or the same workout would count twice.

### `HealthSample.activity`

The one platform-neutral type every sync passes through gained a single optional
`activity` field, carrying an opaque identifier. Not an enum: an enum there could
only mirror Apple's ~80 values and would rot each iOS release. The identifier
crosses the boundary and the decision about it stays in testable core.

`HealthKitProvider` derives the identifier from `String(describing:)` rather than
`rawValue`, which is an `NSUInteger` index in this SDK. Safe because the
identifier only ever becomes a *display label* — a workout is identified by its
UUID — so a change in reflection could at worst alter a label, never a link.

### Verification

- `swift test`: XCTest 313 (1 opt-in skip) + Swift Testing 402, 0 failures.
  19 new tests: 8 bridge, 4 matcher, 4 workload, 2 summary, 1 migration fixture.
- Simulator build clean; 4/4 UI tests pass.
- Fresh install: 36 migrations, both new columns present, 302 exercises, 0
  sessions and 0 anchors — correct, since the simulator cannot authorise
  HealthKit.

**Not verified:** real sample ingestion, for the same reason as the 2026-09-24
entry. A device is required, and the specific things to watch there are whether
HealthKit returns resting heart rate for the user, and what activity identifiers
its SDK actually reflects.


## 2026-09-23 — Slice 12 remainder: ZIP wrapper, HealthKit reconcile, migration fixtures, widgets (iMac)

## 2026-09-23 — Slice 12 remainder: ZIP wrapper, HealthKit reconcile, migration fixtures, widgets (iMac)

Finishes the Slice 12 work the earlier entry scoped as deferred: the actual
ZIP container, restore-time de-duplication, migration fixtures, and the
iOS-only widgets/App Intents.

- **`Sources/AlmanacCore/Backup/BackupZipper.swift`** — the ZIP wrapper the
  2026-09-19 entry explicitly out-scoped. Hand-rolled pure-Swift ZIP codec
  (STORE entries, CRC-32, local offset 0), because `FileManager.zipItem`/
  `unzipItem` and the `Archive` framework do not exist in this SDK and iOS
  cannot shell out to `/usr/bin/zip`. Envelope semantics: exactly one
  `.almanac-backup` entry; foreign DEFLATE entries are refused
  (`notABackupFile`), not decoded; path traversal is guarded; CRC validated
  on read. `BackupView` export shares a `.zip` twin; import accepts both
  `.zip` and raw `.almanac-backup`. Verified against `/usr/bin/unzip`
  interop and CRC-corruption rejection (4 tests).
- **`HydrationStore.reconcileAfterRestore()`** — restore-time HealthKit
  de-dup, wired into `BackupBundle.restoreBundle` right after the restored
  database is swapped in. Collapses only provable overlap: a
  `healthkit`-sourced hydration row whose `external_id` equals a **live**
  manual row's `healthkit_external_id`; the manual row wins and the HealthKit
  row is soft-deleted (matching the table's sticky-delete semantics so a
  re-sync of the same anchor range cannot resurrect it). Timestamp-window
  matching across *different* sources stays deliberately unresolved — the
  "keep both, or confirm?" question remains a product decision, recorded as
  such in the method's doc comment. 4 tests.
- **Migration fixtures** (`MigrationFixtureTests.swift`) — build a real
  database through the first N migrations
  (`AlmanacMigrations.all.filter { $0.version <= n }`), seed, upgrade to head
  (now 34), verify data + foreign keys. Covers v010 → head, v015 → head (the
  export/re-import path), and the v012 refusal. `migrate` exposing only
  newly-applied versions is the assertion seam.
- **Widgets + App Intents** (`Native/AlmanacWidgets/`) — `WaterWidget`
  (today's total + goal from the shared `HydrationStore`, one-tap +250 ml via
  `LogWaterIntent`) and `FastingWidget` (active session + start/end via
  `StartFastIntent`/`EndFastIntent`). The database moved to App Group
  `group.com.almanac.personal` so the widget extension and the app open the
  *same* SQLite file (`AppGroupDatabase`, compiled into both targets; falls
  back to Application Support when the group container is unavailable, e.g.
  unsigned builds). New `AlmanacWidgets.appex` target embedded into the app,
  with its own entitlements file and the widget Info.plist's
  `NSExtensionPointIdentifier`.
- **Verified on this iMac:** full `swift test` — Swift Testing 386/386 in 61
  suites, plus 37 XCTest suites including `BackupZipperTests`,
  `MigrationFixtureTests`, `RestoreHealthReconcileTests`. Debug simulator
  build of the shared `Almanac` scheme succeeds; the app launches with the
  `.appex` embedded; with entitlements signed in, `almanac.sqlite` is created
  inside the `group.com.almanac.personal` container (verified via
  `simctl get_app_container groups`) and no Application Support copy exists.
  The HealthKit entitlement under ad-hoc `-` signing is refused by SpringBoard
  on install (expected; a provisioning profile resolves it).

Also landed in this working tree from a parallel session (committed together,
tests green): Migration034, `Attribution.swift`/`ExerciseAuthorCredits` and
the Attribution views/UI wiring.

**Out of scope, unchanged:** HealthKit timestamp-window conflict policy (keep
both vs confirm — product question), Slices 8/9/10 (SFDA email, clinician
review, insights UI).

## 2026-09-23 — Slice 12: whole-app backup bundle + restore UI (iMac)

The 2026-09-19 pass built `BackupService.restore(from:)` (happy-path snapshot
restore). This pass builds the `.almanac-backup` container on top of it — the
restore/export half of Slice 12 that the handoff scoped as AI-delegatable once
`BackupService` existed:

- **`Sources/AlmanacCore/Backup/BackupBundle.swift`** — one self-contained
  `*.almanac-backup` file carrying the live database *and* every document
  file. The container is itself a SQLite database (`bundle_meta`,
  `bundle_db`, `bundle_files`), so the same open/query machinery works on
  bundle and app alike — no archive library.
  - `writeBundle(to:documentsRoot:note:)` — online-backup snapshot of the
    live DB (never a file copy, WAL-consistent), `wal_checkpoint(TRUNCATE)`
    so the payload is the whole database, every regular file under the
    document root keyed by its relative path (symlink-resolved on both
    sides before the prefix is stripped), then the container assembled in
    one transaction and finished in DELETE journal mode so no `-wal`/`-shm`
    sidecar survives next to a file about to be shared. Records to
    `backup_manifest` exactly like `snapshot(to:)`.
  - `readBundleInfo(at:)` — validates structure + the db digest without
    touching the live database; a schema mismatch is *reported* (an old
    backup can be listed) not thrown.
  - `restoreBundle(at:documentsRoot:)` — refuses a mismatched
    `schema_version` and a failed checksum before mutating anything; writes
    documents *before* the database (orphan files after a failed restore are
    harmless, metadata pointing at never-written documents is the bug this
    order prevents); database is swapped wholesale via the online backup
    API, replacing rather than merging. Files on disk that are not in the
    bundle are left alone, unreferenced rather than deleted. Document paths
    are escape-checked against the document root.
  - `listBundles(in:)` — keyed on the files themselves, not
    `backup_manifest` (that table lives inside the database a restore
    replaces); broken `.almanac-backup` files are skipped, newest first.
- **`BackupService`** — new error cases (`notABackupFile`,
  `incompatibleSchemaVersion`, `corruptBundle`, `missingPayload`,
  `cannotWriteDocument`, `cannotReadDirectory`) with user-facing
  descriptions; `db`/`clock`/`currentSchemaVersion` made internal for the
  extension.
- **`Native/Almanac/BackupView.swift`** — Settings → Data → Backup &
  restore: create a backup with one tap, ShareLink the latest, list backups
  on device (old-schema ones marked "restore not available"), confirm-and-
  restore (app restarts via `exit(0)` after restore because the in-memory
  connection no longer matches the replaced file). Wired in SettingsView
  behind `if let db = labModel.db`.
- **`Tests/AlmanacCoreTests/BackupBundleTests.swift`** — 7 tests: database+
  documents round trip, wholesale-replace + stray-files-left-alone, schema
  gate rejects before mutating, tampered payload rejected before mutating,
  corrupt/missing files rejected, manifest recording, list newest-first +
  skips broken.

**Verified on the iMac (this session):** full `swift test` — XCTest 281 (1
env-gated skip, 0 failures), Swift Testing 370/370 — plus a Debug simulator
build of the shared `Almanac` scheme (`generic/platform=iOS Simulator`,
`ONLY_ACTIVE_ARCH=YES`) **succeeds** with the new Settings section and
BackupView present.

**Deliberately out of scope, unchanged from the handoff / 2026-09-19 entry:**
BRD §6.18's ZIP container (the actual format is the SQLite snapshot; wrapping
it in ZIP is a separate later slice), transactional rollback *mid-apply*
(the schema/checksum gates make the meaningful failure modes happen before
any mutation, but a document-write failure code paths past some document
writes — flagged in the file header, not silently claimed), HealthKit
re-sync + sourceIdentifier/timestamp de-duplication (needs the §6.18
"reconcile separately" decision and HealthKit, both outside the Linux core),
migration fixtures (v010 → current; export-v015-restore-v016), widgets and
App Intents (iOS/Xcode + product scope questions, separate slices). The
BackupView UI compiled in the simulator but was not interactively driven
(share sheet, confirm dialog, post-restore restart).

## 2026-09-22 — first Apple-platform verification (this iMac)

On the machine itself (Intel iMac18,3, macOS 15.8 Sequoia; Xcode 26.3 /
17C529 is the ceiling — no macOS Tahoe is reachable from this hardware):

- **Native target compiles.** A Debug simulator build of the shared `Almanac`
  scheme (iPhone 17, iOS 26.3 simulator runtime) succeeds with
  `ONLY_ACTIVE_ARCH=YES`. Without it, the app target also builds an arm64
  simulator slice while the local package only produced an x86_64
  `AlmanacCore` module — “Unable to find module dependency: 'AlmanacCore'”.
- **App launches in the Simulator without crashing** during DB open and
  migration. `almanac.sqlite` is created under
  `Application Support/Almanac/` with 73 tables and the migrations recorded
  in `schema_migrations`, and **survives terminate/relaunch**.
- **HealthKit water path audited end-to-end by reading the code**, not just
  tests: `HealthSyncService` (rows + anchor commit atomically),
  `HydrationWriteback`'s pending queue (`healthkit_synced_at IS NULL`,
  row-by-row retry), sticky user soft-deletes in `HydrationStore.apply`,
  own-write echo filtering and anchor archiving in `HealthKitProvider` —
  all present and correctly wired to Settings.
- **One wiring gap found and fixed** (Native-only, uncommitted): the
  inbound/outbound sync ran only when Connect was tapped. `.log`/`.delete`
  on `HydrationModel` now run the same sync after every local change
  (`syncAfterChange`), and scene activation triggers `syncOnForeground`,
  so water logged in Health appears without re-tapping Connect. No
  `Sources/AlmanacCore` file was touched; Linux core tests were not
  re-run because nothing in the core changed.
- **Still outstanding:** interactive entry/navigation, keyboard, VoiceOver,
  device signing/deployment, and the cross-app Health-app round trip
  (items 10–11 in `Native/README.md`), which needs a human drive of the
  Simulator's Health app.

## 2026-09-22 — Lab import automation (M1 + M2)

The conflict-review machinery existed end-to-end (`upsertReport`
fingerprinting, `recordReportConflict`, `resolveReportConflict`,
`ReportConflictView`) but nothing produced proposals in a real run, so the
review screen was permanently empty. Two milestones (`docs/next-slice-brief.md`)
close that gap:

- **M1 — dev fixture.** `Native/Almanac/LabReportFixture.swift` (DEBUG-only,
  added to the Xcode project's Sources phase): when the app has no reports
  yet, upserts one report and an unordered reissue with a corrected header —
  `.conflict`, held for review. Verified in the iPhone 17 simulator via
  sqlite: exactly one `lab_report` row and one `conflict` revision after
  launch, and still exactly one after terminate/relaunch (idempotent at the
  store level — re-sends resolve to `replayIgnored`).
- **M2 — CSV import automation.**
  `Sources/AlmanacCore/Laboratory/LabReportCSVImport.swift`: RFC-4180-lite
  parser, rows grouped by `source_report_id` into one report, written through
  the same `upsertReport`/`record` seams as manual entry. Conservative per
  `docs/features/laboratory.md`: verbatim source text; blank dates stay
  unknown; comparator-led numerics (`<0.01`, `~5`) parse to quantitative with
  the comparator while non-numeric values stay `.text`; empty values become
  absent observations (`notReportedBySource`); unmatched analytes stay
  unmatched and visible; re-importing the same file is a fingerprint no-op;
  unranked changes are held as conflicts (`holdAsConflict`). Native surface:
  paste sheet (`CSVImportView`, Laboratory tab).
- **Verification:** 8 new core tests (`LabCSVImportTests`) — full suite green
  under the Xcode 26.3 toolchain; native Debug simulator build succeeds;
  fixture verified live in the simulator (report + one conflict on first
  launch, unchanged after relaunch).

## Verified core

Swift 6.3.3 on x86_64 Linux (`yamal`, `source env.sh`): **115 XCTest tests —
114 pass, 1 opt-in test skipped, zero failures.** Plain `swift build && swift
test`; the default parallel build works on this machine. The skipped test
imports the real bundle, and passes when enabled:

```sh
ALMANAC_NUTRITION_BUNDLE=~/ALManac-food-data/build/almanac.sqlite \
    swift test --filter NutritionRealBundleTests
```

Python 3.14, `tools/nutrition`: **101 unittest tests, zero failures**, including
the real-lake integration tests:

```sh
cd tools/nutrition && ALMANAC_NUTRITION_INTEGRATION=1 python3 -m unittest discover -s tests -t .
```

Earlier records: 85 tests on Swift 6.0.3 in the 2026-09-08 session container
(`-j 1 -Xswiftc -disable-batch-mode`); 79 on Swift 6.3.3 per the user log. No
change has been run on an Apple platform.

## Nutrition module (2026-09-13)

The 2026-09-13 handoff's build order, steps 1–6:

1. Nutrient dictionary and qualifier vocabulary as data: `tools/nutrition/dictionary/`.
2. USDA Foundation Foods extracted, and 3. canonicalised (395 foods).
4. Bundle step with the failing licence assertion (`A`, `B`, `N` or the build
   fails), built while USDA was the only source.
5. CIQUAL 2025, CoFID 2021 and AFCD R3 extracted and canonicalised; union; the
   bundle holds 8,354 foods and 49,036 values. `qa` re-reads every mapped raw
   cell with independent readers: passed, 0 tokens coerced.
6. AlmanacCore: `LicenceGroup.native` (`N`, ships; the `almanac` namespace moved
   from `A` to `N`); `NutrientValue.basis`; migration 008 (`nutrition_*`
   reference tables with licence and qualifier CHECKs);
   `NutritionReferenceImporter` (re-runs the licence assertion against Swift's
   own registry before copying anything, in one transaction); `NutritionCatalog`
   (food, values, bases, calories, folded search); `GeneralAtwater` and
   `EnergyEstimate` (4/4/9/7 on total carbohydrate, publisher's figure as a
   labelled fallback).

Details: `docs/features/nutrition.md`. Pipeline contract:
`tools/nutrition/README.md`. Findings in the data:
`~/ALManac-food-data/PROCESSING-LOG-2026-09-13.md`.

Not done: Almanac-native dish data (blocked on Yazeed); wiring the bundle
import into the app target (needs the Apple toolchain); food logging and portions.

## Nutrition portions, pipeline side (2026-09-15)

`tools/nutrition/` step 1 of the 2026-09-14 handoff's build order: a fourth
canonical file (`portions.csv`) and bundle table (`nutrition_portion`)
carrying USDA `food_portion` (household measures) and CoFID "1.2 Factors"
(specific gravity, edible proportion). Details: `docs/features/nutrition.md`
§8; contract: `tools/nutrition/README.md` "Canonical format".

Python 3.14, `tools/nutrition`: **102 unittest tests, zero failures**,
including the real-lake integration tests and a new fidelity check
(`qa.portion_fidelity`) that re-reads every raw portion cell independently —
0 problems against the full 8,354-food lake (3,064 raw cells re-read: 123
household measures, 2,887 edible proportions, 54 specific gravities).

**Not reconciled with AlmanacCore.** A concurrent branch (uncommitted at the
time of writing) independently built its own `nutrition_portion` table
(migration 010) scoped to household measures only, with `edible_proportion`
living on a separate `nutrition_dish` table for the user's own `almanac:`
dishes — it has no slot for CoFID's per-reference-food edible proportion or
specific gravity. `NutritionReferenceImporter` was deliberately left
untouched here rather than risk clobbering that in-progress, uncommitted
work; the Swift test counts above predate it and were not re-verified this
session. See `docs/features/nutrition.md` §8 before starting that
reconciliation.

## Nutrition: transactions, portions, native dishes, the food log (2026-09-15)

The AlmanacCore side of the 2026-09-14 `claude/ponytail-anxf91` handoff,
reconciled onto `codex/manual-entry`'s bundle-imported schema (migration 008
wins over that branch's competing `nutrition_food`/`nutrition_value` — richer,
namespaced, per-basis, already populated with 8,354 real foods). Its own
migration 008 comment called this "a mechanical merge, but a real one"; in
practice the two schemas differed enough (namespace, basis, multi-language
names vs. a flat single-language table) that every ported file needed
rewriting against `NutritionCatalog`'s actual shape, not just repointing.

- **`Database.transaction` nests** (`Database.swift`): a call made while one is
  already open now uses a `SAVEPOINT` instead of failing, guarded by a
  per-connection `NSRecursiveLock` so a second thread mid-transaction gets a
  genuine outer transaction rather than silently attaching to the first
  thread's work. `DatabaseTests.swift`, 9 tests, ported unchanged — it never
  depended on the nutrition schema.
- **Migrations 009-011**: `nutrition_log`/`nutrition_log_revision` (009, the
  food log — untyped `food_ref`, no foreign key, so removing a reference
  source can never erase a meal); `nutrition_dish` + `nutrition_portion` +
  `nutrition_dish_component` (010); the portion-identity unique index (011).
  `nutrition_dish` holds `yield_grams`/`edible_proportion` for `almanac:`
  foods in its own table rather than widening migration 008's `nutrition_food`
  — that table intentionally mirrors the bundle schema, and a dish-only column
  would break the mirror. (§8 above names the still-open question these three
  tables don't answer: CoFID ships edible-proportion/specific-gravity for
  *every* reference food, not just dishes, and that doesn't fit here either.)
- **`NutritionDishEditor`** (`NutritionDish.swift`): create/edit/delete for
  `almanac:` foods; `setRecipe`/`recompute` with cycle detection and
  missing-ingredient/unmeasured-nutrient/unit-conflict reporting
  (`RecipeReduction`). Reduction always writes basis `.per100g` (a dish is
  solid) and `ref.namespace.licenceGroup` for the value rows — the source
  branch hardcoded licence group A there, which would have mislabelled every
  computed dish value.
- **`NutritionCatalog`** gained portion read/write (`addPortion`, `portion(of:
  unit:modifier:)`, `grams(of:...)`, English-plural matching, ambiguity
  returned rather than guessed) — ported as-is, schema-independent.
  `edibleGrams`/`removeSource` were not ported: the first needs the
  reference-food edible-proportion CoFID data §8 is about, the second is
  already subsumed by the importer fix below.
- **`NutritionLogStore`/`NutritionSummary`** (food log, revisions, timeline
  integration, day totals): ported with call sites adjusted to
  `values(for:basis:)`/`EnergyEstimate.preferred(from:basis:)` instead of the
  source branch's single-basis catalog. `EnergyEstimate.scaled(toGrams:)` and
  `NutrientValue.scaled(toGrams:)` (`NutritionScaling.swift`) needed adding —
  this codebase's `EnergyEstimate` had no scaling method yet.
- **Defect found and fixed: `NutritionReferenceImporter` blanket-deleted and
  reimported every table on every `importBundle` call.** The bundle already
  carries an `almanac` source row and, per the fixture, can carry `almanac:`
  food rows of its own — a curated native food is ordinary reference data,
  replaced on reimport like any other. A user-authored dish is not, and the
  blanket delete would have erased every dish on the next bundle update, with
  nothing to distinguish the two: both are `namespace = 'almanac'`. Fixed by
  scoping the delete to `food_ref NOT IN (SELECT food_ref FROM
  nutrition_dish)` — only `NutritionDishEditor.create` ever inserts a
  `nutrition_dish` row, so its presence is exactly "a person authored this
  here," regardless of namespace. `nutrition_source`/`nutrition_nutrient` are
  upserted row-by-row rather than replaced, because a preserved dish's values
  still reference both and SQLite enforces foreign keys per-statement, not at
  transaction end — deleting either out from under a surviving row fails
  immediately, even mid-transaction. (SQLite also refuses `ON CONFLICT` after
  an `INSERT ... SELECT`; only a `VALUES`-sourced insert accepts it, hence the
  per-row loop instead of a set-based upsert.)
  `NutritionBundleImportTests.testReimportingReplacesAndDropsARemovedSource`
  and a new `NutritionDishTests` case
  (`testReimportingTheBundlePreservesADeviceAuthoredDishAndReplacesABundleShippedOne`)
  cover both directions.
- **Arabic search-folding regression coverage** added to
  `NutritionReferenceTests.swift` (hamza/harakat/tatweel folding, internal and
  surrounding whitespace, Arabic-Indic digits) against `NutritionCatalog.search`
  — `TextFold` itself is unchanged and shared with Laboratory; these three
  tests just pin that `NutritionCatalog` exercises it the same way.

**Verified:** `swift build && swift test` on Swift 6.3.3 (`yamal`, `source
env.sh`) — 174 tests, 0 failures, 1 opt-in test skipped (unchanged from
before). Satisfies the ponytail handoff's outstanding item 3 ("test on
6.3.3"); its item 2 (populate the catalog) was already done independently on
this branch (8,354 foods); its item 1 (the schema duplication) is this
section.

**Still open, not attempted here** — flagged rather than guessed at, per the
existing rule that publicly accessible is not the same as reconciled:
1. Unifying `nutrition_portion` (this section) with the pipeline's
   three-kind portion table (§8) — needs that work to land first; both are
   uncommitted and it would be reconciling against a moving target.
2. `edibleGrams` and any specific-gravity lookup — blocked on the same thing.
3. The Saudi/Gulf native dish *data* — unchanged, still blocked on supply, not
   a build task; `NutritionDishEditor` can author dishes today, there just
   aren't any yet.
4. Portions/dish-components on a *non-native* reference food do not survive
   that food's own reimport (`ON DELETE CASCADE` from `nutrition_food`, which
   a bundle-namespace food is still fully replaced on) — pre-existing
   behaviour of the "replace on reimport" design, not introduced here, and
   out of scope for this pass.
5. A second, apparently unrelated concurrent session added hydration tracking
   (`Sources/AlmanacCore/Hydration/`, migration 012) to this same working tree
   while this work was in progress. No collision occurred — its migration
   number was claimed after this session's 009-011 — but it is a reminder this
   checkout had two sessions writing to it at once.

## Targeted corrections

- Unranked report imports default to `holdAsConflict`. Incoming report content
  is retained. `resolveReportConflict` accepts/rejects atomically, requiring an
  actor and reason and recording resolution time. Resolved proposals no longer
  count as unresolved, including replays of rejected equal-version content.
  Resolution fields are available through `reportRevisions`.
- Explicit observation corrections compare only with the current revision.
  A → B → deliberate A creates three attributable revision events. Import
  replay detection still searches historical fingerprints and creates no copy.
- Unchanged report content advances a newer source ordering marker. A/v1 →
  A/v3 → B/v2 retains A/v3. Conflicting equal versions are held for review.
  Overlapping partial issue dates do not establish ordering.
- Date-only strings have no textual offset. Time, calendar and offset syntax
  are validated. Unknown-offset local times remain unknown; timeline filtering
  conservatively widens the possible span and labels it potential.
- `saveManualEdit` commits value and metadata together. A failed metadata
  change rolls back the content revision too.

`RequestedFixTests` covers these regressions. Existing laboratory, import,
manual-entry, timeline, migration, catalog and synchronization tests also pass.
The earlier file-backed create/reopen/edit/history test remains in the suite.

## Schema and integrity

Migration 007 is appended; migrations 001–006 are unchanged. It removes the
unique observation fingerprint constraint (needed for deliberate reverts),
keeps the lookup index, and adds report-conflict resolution attribution.
Observation identity, revision numbering and the one-current-revision rule
remain intact. Catalog IDs and existing data are preserved.

The repository contains a reusable catalog, aliases, panels, reports,
observations with revisions, metadata correction history, module-provided
timeline queries, and the existing body-mass sample store. No additional
tracker or import automation was added.

The catalog coverage document remains the inventory of seeded and unseeded
tests. The catalog is not complete. Reference intervals remain result-specific;
no global intervals, medical interpretation or automatic conversion were added.

## Interface status

Native manual-entry code is authored in `Native/Almanac`, with an iOS 17+
Xcode app target and shared scheme in `Native/Almanac.xcodeproj`. It uses the
existing local `AlmanacCore` package.

Implemented screens: report list/create/edit/detail; result entry/editing with
canonical and alias search; longitudinal test history and source-report links;
separate content/metadata revision history; and report-conflict accept/reject.
Original units, source text, comparators, laboratory ranges, specimens and
unknown/partial dates remain visible and editable. Saving a correction requires
a reason and uses the atomic core edit API.

Linux Swift parsing passes for all four UI source files. Project references,
local package path and shared-scheme XML pass consistency checks. This does not
establish SwiftUI type correctness or a usable running Apple application.
See `Native/README.md` for the Apple build command and outstanding interactive
acceptance steps. No screenshots or runtime verification are claimed.

## Remaining boundaries

- Apple SDK compilation, Simulator launch and interactive UI verification have
  not been performed in this Linux environment.
- Document import and document-file backup/restore remain deferred. The SQLite
  snapshot does not include document files.
- The current storage model is a local personal database. There is no multi-user
  account boundary or server authorization layer; do not claim cross-user RLS.
- Timeline filtering still runs in Swift over current records.
- No automatic unit conversion, OCR, AI interpretation or new tracker.
- The Technical Spec is not in this checkout, but it is not lost: the full
  2026-08-05 original is one directory above the repository root at
  `../almanac-tech-spec-v1.0.md`. See
  `docs/architecture/spec-reconciliation.md`.

To verify the modified core on yamal after importing this branch:

```sh
cd ~/projects/almanac
source env.sh
swift build
swift test
```

---

## 2026-09-15 — Technical Spec recovered; Slice 2 (Core Daily) built

**The spec was never lost.** `../almanac-tech-spec-v1.0.md`, 96 KB, dated
2026-08-05: the 48-table schema, readiness formula v1.0, sleep classification,
circadian and fasting engines, notification suppression matrix, HealthKit
permission map. Everything this codebase has been declining to infer.
`docs/architecture/spec-reconciliation.md` records what that changes.

### Added

- **Migration 014 — `core_daily_schema`.** Fourteen §5 tables transcribed
  verbatim: `profile`, `day_record`, `circadian_context`, `shift_schedule`,
  `shift_occurrence`, `shift_recurrence_pattern`, `sleep_episode`,
  `readiness_cycle`, `vitals_record`, `mood_log`, `soreness_log`,
  `injury_note`, `readiness_record`, `readiness_baseline`. Column names are
  the spec's camelCase, which does not match migrations 001-013 — deliberate,
  see the reconciliation doc.
- **`Sources/AlmanacCore/Sleep/`** — §8 episode detection (30-minute merge
  rule), primary-sleep determination (user correction → shift-aware →
  post-shift elevation → general 26-hour window → none), episode typing,
  multi-source priority with no duration summing.
- **`Sources/AlmanacCore/Readiness/`** — §9 and Appendix A: five input
  scorers, provisional (capped at 90) and final weights, proportional
  redistribution of missing inputs, confidence tiers, colour grades, text
  bands with context suffixes, recommendation precedence, calibration and
  baseline rules.
- **`Sources/AlmanacCore/Circadian/`** — §13 context determination.

### Corrected

- **`TimeModel`'s default boundary is 04:00** (§7.1). It was `.midnight`, a
  documented placeholder chosen while the spec was believed lost, and
  `Native/Almanac/HydrationModel.swift` had silently taken it — hydration was
  being grouped by calendar date, not by Almanac's logical day.
- `Tests/…/TimeModelTests.swift`: the four calendar-arithmetic tests now ask
  for `.midnight` explicitly instead of relying on the default, and a new test
  pins the default at 04:00.
- `Tests/…/HydrationFeatureTests.swift:46`: added `?? 0` to an optional passed
  to `XCTAssertEqual(_:_:accuracy:)`. It compiles under the 6.3.3 toolchain on
  `yamal` but not under 6.1.2; the fix is valid on both.

### Verified

Swift 6.1.2 on x86_64 Linux: **258 XCTest tests — 257 pass, 1 opt-in test
skipped, zero failures.** 54 of those are new (16 sleep, 22 readiness, 9
circadian, 6 schema, 1 time model).

Note the toolchain: this run used 6.1.2, not the 6.3.3 in `env.sh`, because it
was executed from a Linux VM that has no access to `~/.local/swift` on the
host. Re-running `source env.sh && swift test` on `yamal` itself is the
confirmation that matters.

### Not built yet in Slice 2

- Stores for `profile`, `mood_log`, `soreness_log`, `injury_note`,
  `vitals_record`, and §8.4 readiness-cycle linking of mood and soreness.
- HealthKit sleep and vitals import (the `.water`-only provider is the pattern).
- Check-in UI and dashboard.

---

## 2026-09-16 — Slice 7 (Body Composition) design + first TDD pass; two pre-existing bugs fixed, two more flagged

Design docs first: `docs/features/body-composition.md` (Slice 7) and
`docs/features/fasting.md` (Slice 6) — most of both slices turned out to
already be specified verbatim in the recovered tech spec, so the design pass
was mostly citation plus a handful of real owner decisions (Ramadan
auto-detect with manual correction; vendor an Adhan port for prayer times;
progress photos deferred to a later update). Owner chose to build Body
Composition first.

### Added (migration 018, TDD red/green)

- **`body_composition_measurement`, `custom_measurement_definition`,
  `custom_measurement_log`, `supplement_plan`, `supplement_log`,
  `context_event`** — transcribed from spec §5.18/§5.20, minus
  `progress_photo` (deferred) and `lab_result` (superseded by the existing
  laboratory module). `body_composition_measurement` adds `deletedAt` and a
  `(source, healthKitUUID)` partial unique index beyond the spec's literal
  text — needed for a working upsert/soft-delete, see below.
- **`BodyCompositionMeasurementStore`** — log/read by id, latest-per-metric,
  ranged history for charting. 4 tests.
- **`BodyCompositionMeasurementHealthBridge`** — inbound HealthKit sync for
  `bodyMass`/`bodyFatPercentage`/`leanBodyMass` (Appendix C's only
  bi-directional body-composition types), following
  `VitalsRecordHealthBridge`'s upsert-by-`(source, healthKitUUID)` shape.
  5 tests.
- Two new `HealthDomain` cases: `bodyFatPercentage`, `leanBodyMass`.

### Fixed — a real schema collision, found designing this slice

`VitalsRecordHealthBridge` (Slice 2) was writing HealthKit `bodyMass` into
`vitals_record` as `metric = 'weight'`, colliding with §5.18's dedicated
table (no `conditions`/InBody-source support in `vitals_record`). Recorded as
a sixth spec/repo divergence in `docs/architecture/spec-reconciliation.md`
§7. Fixed: `.bodyMass` removed from `VitalsRecordHealthBridge.metricMap`;
weight now exclusively goes through the new bridge/table. No data migration
needed — no durable database exists yet.

### Fixed — two pre-existing bugs, found and repaired while building this slice

Both confirmed pre-existing (git-clean files, untouched by this session)
before being fixed:

1. **`vitals_record`'s upsert always threw.**
   `VitalsRecordHealthBridge.apply`'s `ON CONFLICT(source, healthKitUUID)
   WHERE healthKitUUID IS NOT NULL` had no matching index — Migration014 only
   gave the table a single-column `healthKitUUID UNIQUE`. Every update threw
   `SQLite error 1: ON CONFLICT clause does not match any PRIMARY KEY or
   UNIQUE constraint`. Fixed in Migration019 (adds the matching partial
   unique index).
2. **`vitals_record`'s soft-delete always threw.** The same bridge's delete
   path set `createdAt = NULL` to mark a retracted sample, but `createdAt` is
   `NOT NULL` — `SQLite error 19: NOT NULL constraint failed`. Fixed in
   Migration020 (adds a proper `deletedAt` column); `VitalsRecordStore`'s
   read methods now exclude soft-deleted rows.
3. **`sleep_episode` was also missing `deletedAt`** — same shape as #2,
   found by running the full suite afterward. Migration021 adds the column.
   **This alone does not fix `SleepEpisodeHealthBridgeTests`** — see below.

Confirmed by running `VitalsRecordHealthBridgeTests` before Migration019/020
existed: 4 of 5 cases failed with exactly these two errors. `297 tests, all
green` (2026-09-16 project status doc, commit `c83e88c`) evidently did not
include this suite passing against a real upsert/delete path.

### Flagged, not fixed — two larger pre-existing defects found running the full suite

Both confirmed pre-existing and unrelated to Slice 7 (git-clean files before
this session touched anything nearby):

1. **`SleepEpisodeHealthBridge` is not just missing a column — it's built
   against the wrong table shape entirely.** Its INSERT references
   `startTime`, `endTime`, `recordedAt`, `recordedTzOffset`; the real
   `sleep_episode` (Migration014, §5.6) has `startTimestamp`, `endTimestamp`,
   `timezoneOffset`, `createdAt`, plus required `durationMinutes`,
   `episodeType`, `logicalDay`, `updatedAt` the bridge never sets. 4 tests
   fail on `no such column`. This needs a real rewrite against the actual
   schema, not a migration — flagged in `Migration021`'s doc comment rather
   than attempted here.
2. **`SyncAnchorStore` still queries `sync_anchor` by the old `domain`-keyed
   shape.** `spec-reconciliation.md` §4.1 records that Migration015 already
   moved this table to the spec's `sampleType`-keyed shape (2026-09-16,
   commit `c83e88c`) — but `SyncAnchorStore.swift` was never updated to
   match. Every call fails with `no such column: domain`. This cascades into
   18 XCTest failures across `HealthSyncTests`, `HydrationSyncTests`,
   `SyncAnchorStoreTests`, `BackupServiceTests`, and `TimelineTests` — the
   collision doc's own "resolved" status is only half true: the schema
   moved, the consuming code didn't. Needs `SyncAnchorStore` rewritten
   against `sampleType`, which is a real task, not a line fix — not
   attempted here.

### Verified

`swift build && swift test` on Swift 6.3.3 (`yamal`, `source env.sh`): new
Slice 7 work (9 tests, `BodyCompositionMeasurementStoreTests` +
`BodyCompositionMeasurementHealthBridgeTests`) and the two fixed
`vitals_record` bugs all green. The two flagged defects above are the only
failures left in the suite; both predate this session.

### Added — remaining Slice 7 seams (same session, continued)

The other three seams from `docs/features/body-composition.md` §6, same
migration 018, same TDD pattern:

- **`CustomMeasurementStore`** — owner-defined circumference measurements
  (definition CRUD, unique names, log/history per definition). 5 tests.
- **`SupplementPlanStore`** (create/deactivate/active-list, soft-state like
  `InjuryNoteStore`) + **`SupplementLogStore`** (adherence logging, per-day
  and per-plan-range reads). 5 + 3 tests.
- **`ContextEventStore`** — tag logging/read-by-date, reusing
  `SorenessLogStore`'s JSON-array-tags pattern. 3 tests.

**Slice 7 status after this session:** all six §5.18/§5.20 stores this
design doc scoped are built and green (23 tests across 6 suites, migration
018 unchanged). Not built: any UI, progress photos (deferred), supplement
reminders (blocked on Slice 11's notification scheduler, not yet built).

### Fixed — the `SyncAnchorStore` defect flagged above (same session, continued)

Rewrote `SyncAnchorStore` (`Sources/AlmanacCore/Sync/SyncAnchorStore.swift`)
to query `sync_anchor` by its actual Migration015 shape
(`sampleType`/`anchorData`/`lastSyncTimestamp`) instead of the pre-Migration015
one (`domain`/`anchor_token`/`last_synced`). Public API unchanged — every
caller (`HealthSyncService`, `BackupServiceTests`) already says `domain` as
its own vocabulary; only the SQL underneath was wrong. Spec §5.24 has no
error column at all, but `testFailureKeepsLastGoodAnchor` requires one (real
behavior — a failed sync must stay visible without losing the last good
anchor), so `lastError` is added beyond the spec's literal text, same
treatment as `deletedAt` earlier in this session. Migration022.

No new tests written — the existing ones (`SyncAnchorStoreTests`,
`HealthSyncTests`, `HydrationSyncTests`, `BackupServiceTests`) already pinned
the required behavior; they were the red this fix turns green.

### Deleted, not fixed — `SleepEpisodeHealthBridge` (same session, continued)

Fixing it would have meant matching its INSERT to `sleep_episode`'s real
columns, but that table holds *merged, classified* episodes (spec §8's
30-minute merge rule) — one row per night, not one row per raw HealthKit
sample. The bridge wrote exactly the latter: idempotent upsert of one
`HealthSample` into one row, no merge logic at all. Correcting the column
names would have shipped something that still produces a spurious "episode"
per stage transition (`inBed`/`asleepCore`/`asleepDeep`/`asleepREM`/`awake`
each arrive as separate HealthKit samples).

That raw-sample-upsert behavior — insert/update/soft-delete/never-resurrect,
keyed by `(source, externalID)` — already exists, generically, and already
works: `HealthSampleStore` (`Sources/AlmanacCore/Health/HealthSampleStore.swift`),
proven via `.bodyMass` in `HealthSyncTests`/`HydrationSyncTests`, with zero
domain-specific branching (`healthDomain` is a stored filter value, not a
switch). `SleepEpisodeHealthBridge` was a wrong-shaped duplicate of it, not
a variant with real reasons to differ.

**Deleted:** `SleepEpisodeHealthBridge.swift`, `SleepEpisodeHealthBridgeTests.swift`,
and the `sleep_episode.deletedAt` migration that existed only to serve the
deleted bridge (nothing else writes to `sleep_episode`, confirmed by
grep — `SleepClassifier` is a pure in-memory classifier with no persistence
of its own; wiring classified `SleepEpisode`s into `sleep_episode` is a
real, separate task, still "not started" per Slice 2's own list above).
The migration that had been `Migration022` (`SyncAnchorLastErrorColumn`)
was renumbered down to `021` to close the gap — free, since nothing has
shipped yet.

No new test written: reusing `.sleep` through `HealthSampleStore` exercises
the same code path already covered by `.bodyMass`'s tests, with no new
branching to pin.

### Added — `SleepEpisodeStore`, wiring `SleepClassifier`'s output (same session, continued)

`SleepClassifier` (§8) is pure and stateless by design — its own doc comment
says persistence is the caller's job, and until now nothing was that caller.
**`SleepEpisodeStore`** (`Sources/AlmanacCore/Sleep/SleepEpisodeStore.swift`)
is it: `upsert(_:timezoneOffset:logicalDay:)` writes a classified
`SleepEpisode` into `sleep_episode`, plus `episode(id:)` and
`episodes(for:)` reads. 5 tests, all green on the first pass.

Identity for idempotent re-classification is `healthKitUUID` alone — no new
migration needed. Every episode the classifier produces has
`source = .healthkit` (`groupIntoEpisodes` hardcodes it), and the column
already carries a genuine single-column `UNIQUE` (Migration014) — the
composite-index problem `vitals_record`/`body_composition_measurement` had
doesn't apply here. `healthKitUUIDs.first` stands in for the whole merged
group: reprocessing the same raw samples regroups them identically
(`groupIntoEpisodes` sorts by start first), so the first UUID is stable
across runs.

Deliberately not built: converting raw `health_sample` rows (via
`HealthSampleStore(healthDomain: .sleep)`, wired last session) into
`SleepStageSample`s for the classifier to consume — HealthKit's sleep
category value (an Int) needs mapping to `SleepStage`, which is a distinct,
separately-scoped task. Also not built: triggering readiness-cycle creation
from a newly-stored primary episode (Slice 2's own long-standing gap, "not
built" above — unrelated to this fix, not widened here) and a
`correctType` mutation for a user override (`userCorrectedAt` has no source
in `SleepEpisode` yet; `upsert` writes `userCorrectedType` when already set
but nothing sets it today).

### Verified

`swift build && swift test`: **XCTest suite 262 tests, 0 failures. Swift
Testing suite 105 tests in 23 suites, 0 failures.** Every defect found this
session — the sixth spec/repo collision, two `vitals_record` bugs, the
`sleep_episode` non-fix (deleted instead), `SyncAnchorStore`'s stale column
names — is fixed, deliberately resolved by deletion, or wired up properly
instead of patched. Nothing outstanding from this session remains red.

---

## 2026-09-17 — Slice 6 (Fasting): intermittent fasting core

Migration022, TDD. `docs/features/fasting.md` has the full picture; summary:

- **`fasting_session`** (spec §5.21, `protocol`/`isDryFast`/`correctionHistory`
  transcribed verbatim) — the only Slice 6 table built this pass.
  `religious_fast_schedule`/`prayer_settings`/`prayer_times_cache`/
  `nutrition_window` are still design-only: all four depend on the
  prayer-time engine (vendoring an Adhan port), a separate, self-contained
  task deliberately not mixed into this pass.
- **`FastingSessionStore`** (`Sources/AlmanacCore/Fasting/`) — `start`,
  and `recordNutritionEntry(calories:at:)` implementing §11.1's
  break/invalidate/shorten decision tree exactly: zero calories never
  breaks a fast; a calorie entry ends the active session; a backdated entry
  before a session's start invalidates it (and clears `isActive`, so a new
  session isn't blocked); a backdated entry inside an already-ended
  session's span shortens it and recomputes duration; both corrections are
  appended to `correctionHistory`. 7 tests.
- **`IFSuggestion.shouldSuggest`** — the 14-hour (configurable) trigger, a
  pure function mirroring `SleepClassifier`'s "pure and synchronous, caller
  handles persistence" shape. 3 tests.
- **`idx_fasting_session_one_active`** — a partial unique index enforcing
  "only one active session at a time" at the schema level, beyond the
  spec's literal text — added because the break/backdate logic assumes
  exactly one active session exists.

Scope line drawn deliberately: backdating reconciles only against the
active session or the single most-recently-started ended session, not
arbitrary session history — every example in spec §11.1 only needs that
much.

Not built: wiring the suggestion trigger to `NutritionLogStore` (needs
"hours since last calorie entry," a small integration nothing calls yet),
and all of religious fasting / the prayer-time engine (`docs/features/fasting.md`
§6).

**Verified:** `swift build && swift test` — XCTest 262/262, Swift Testing
115/115 (was 105; 10 new tests, zero regressions).

### Added — `IFSuggestionService`, wiring the trigger to `NutritionLogStore` (same session, continued)

`IFSuggestionService` (`Sources/AlmanacCore/Fasting/IFSuggestionService.swift`):
`shouldSuggestFast(at:thresholdHours:)` end to end, `hoursSinceLastCalorieEntry(before:lookbackHours:)`
exposed separately for a UI that wants to show the actual gap. 6 tests.

`ponytail:` "a calorie entry" is approximated as *a food log entry with a
stated amount* rather than a real computed kcal figure — a precise number
needs `NutritionCatalog`/`EnergyEstimate` (what `NutritionSummary` does, at
real fixture cost: no existing test seeds a full nutrient-value fixture for
this, `NutritionSummary` itself has zero test coverage today). Since this is
only a prompt (a false positive costs one wrong suggestion, not a state
change), the coarse signal was judged good enough; the actual
session-breaking path (`FastingSessionStore.recordNutritionEntry`) still
takes a real `calories` number, because that one changes stored state.

**Verified:** XCTest 262/262, Swift Testing 121/121 (was 115; 6 new tests,
zero regressions).

### Added — `FastingAwareNutritionLog`, wiring break detection to `NutritionLogStore.record` (same session, continued)

`FastingAwareNutritionLog` (`Sources/AlmanacCore/Fasting/FastingAwareNutritionLog.swift`):
`record(_:)` calls `NutritionLogStore.record`, computes the entry's *real*
energy via `NutritionCatalog`/`EnergyEstimate` (unlike `IFSuggestionService`'s
coarser approximation — this one changes stored state, ending/shortening/
invalidating a session, so it earns the real kcal figure), and calls
`FastingSessionStore.recordNutritionEntry` with it. The timestamp is the
draft's own `eatenAt`, not "now" — a backdated meal is exactly what the
break logic reconciles. 4 tests, including the first real Atwater/
publisher-energy fixture in the test suite (seeded `nutrition_source`/
`nutrition_nutrient`/`nutrition_food`/`nutrition_value` rows directly, the
same pattern `NutritionLogTests` already uses for a bare food-exists
fixture, extended with an actual energy value).

Architecture note: this lives in the Fasting module, not folded into
`NutritionLogStore` — Nutrition "holds nothing, stores nothing" beyond the
food log and must not know a higher-level feature exists on top of it, same
dependency direction as `IFSuggestionService`.

Not built: the same wiring for `NutritionLogStore.update` — editing an
existing meal's timestamp or amount is arguably the *more* central
backdating case than a fresh `record` call, not attempted this pass.

**Verified:** XCTest 262/262, Swift Testing 125/125 (was 121; 4 new tests,
zero regressions).

---

## 2026-09-17 — Slice 2 UI: readiness dashboard, mood/soreness check-in, feedback

The Slice 2 UI build order assumed `ReadinessCycleStore` and a persisted
`ReadinessRecord` already existed ("stores are already built, just wire
them"). Neither did — `readiness_cycle`/`readiness_record` were schema-only
(Migration014), and `ReadinessEngine.evaluate` was a pure function nothing
had ever called against real inputs. Built as prerequisites, TDD:

- **`ReadinessCycleStore`** (Migration023 adds a unique index enabling the
  companion store's upsert) — read/create `readiness_cycle` rows.
  Deliberately does not derive a cycle from `SleepEpisodeStore`'s primary
  episode; determining the primary episode and closing the previous cycle
  (§8.4) is a separate, not-yet-built task. `ensureCycle` makes a bare cycle
  from whatever timestamp the caller has. 6 tests.
- **`ReadinessRecordStore`** — persists a `ReadinessOutcome` into
  `readiness_record`, upserting by `readinessCycleId` (one row per cycle,
  not a history of re-evaluations through the day). Separately handles
  §9.10 feedback (`feedbackValue`, a string — `"thumbs_up"`/`"thumbs_down"`,
  not a `Bool`) and `latestUnratedRecord(before:)`, which finds a past,
  already-scored, unrated cycle for a feedback prompt shown at the start of
  the *next* cycle. 7 tests.

### Added — the UI itself (`Native/Almanac/`, new "Today" tab, first in the app)

- **`ReadinessModel`**: the one place assembling `ReadinessInputs`/
  `ReadinessContext` from Profile/Vitals/Mood/Soreness/SleepEpisode/Injury
  and calling `ReadinessEngine.evaluate`. Computes a naive 28-day RHR/HRV
  baseline on the fly (no `readiness_baseline`-backed store exists, §9.8);
  wires only `InjuryNoteStore.injuriesAffectingTraining()` into
  `ReadinessContext` (§9.6 precedence rule 1) since it's the one real store
  behind that struct's fields — manual recovery/rest/deload/religious-fast/
  shift-transition context and §9.7 calibration-day counting stay at their
  defaults, documented inline, pending Training/Fasting's religious half/
  Circadian.
- **`ReadinessDashboardView`**: score, colour, band text + recommendation,
  confidence tier, and which inputs were actually used (missing ones say so
  rather than being silently omitted).
- **`MoodSorenessCheckInView`**: one combined sheet, not two separate
  screens — spec §17's own screen map (`MoodSorenessScreen: 1-10 sliders +
  body area tagging`) treats mood and soreness as a single check-in against
  the same cycle. `MoodCheckInView`/`SorenessCheckInView` are its two
  composable halves. Soreness is overall score + which body areas, not a
  score per area — `soreness_log` (Migration014) has no column for that, and
  neither does the spec's own screen map.
- **`FeedbackPromptView`**: asks about a *previous* cycle's outcome, never
  today's — §9.10 explicitly forbids the 👍/👎 prompt appearing right under
  the score that produced it.

### Not verified here

`Native/Almanac` is an Xcode target (SwiftUI, iOS 17+) with no SwiftPM
presence — nothing under it compiles or runs on this Linux machine.
`swift build`/`swift test` cover only `AlmanacCore` (138/138 green,
unchanged by the UI commit). `project.pbxproj`'s six new file entries were
added by hand, matching the existing entries' shape; unverified until opened
in Xcode. No UI tests — matching every other `Native/Almanac` screen in this
repo (Hydration, Nutrition have none either), and there is no simulator or
Xcode on this machine to write or run any against.

**Verified (AlmanacCore only):** XCTest 262/262, Swift Testing 138/138 (was
125; 13 new tests — `ReadinessCycleStoreTests`, `ReadinessRecordStoreTests`
— zero regressions).

---

## 2026-09-17 — Slice 3 polish: vendored Adhan, `AdhanCalculator`

`batoulapps/adhan-swift` (commit `0bc1000`, MIT) vendored verbatim as a new
`Adhan` SwiftPM target — `docs/architecture` decision already recorded this
choice in `docs/features/fasting.md` §3; this session executed it.
`Sources/AlmanacCore/Prayer/AdhanCalculator.swift` wraps it:
`prayerTimes(latitude:longitude:date:timeZone:method:)`, with
`PrayerCalculationMethod` mapping `prayer_settings.calculationMethod`'s
vocabulary onto Adhan's own enum. Verified against a real external
reference (`api.aladhan.com`, method 4) for Riyadh, 2026-09-17: matched to
the minute on five of six prayers, one minute off on Asr. 5 tests.

**Verified:** Swift Testing 143/143 (was 138; 5 new, zero regressions).

---

## 2026-09-17 — Slice 6 (Fasting + Prayer): religious fasting and prayer infrastructure

Migration024: `religious_fast_schedule`, `prayer_settings`,
`prayer_times_cache`, `nutrition_window` (§5.11, §5.21–5.22), the four
tables the intermittent-fasting-only Migration022 deliberately left out.
Deliberately not touched: no `nutritionWindowId` column added to
`nutrition_log`/`hydration_log` — that's a separate cross-module task
(§6 of `docs/features/fasting.md`).

- **`PrayerSettingsStore`**: the `prayer_settings` singleton, self-healing
  like `ProfileStore`. 5 tests.
- **`PrayerTimeCacheStore`**: plain CRUD over `prayer_times_cache`, upsert
  by date. `deleteFuture(after:)` never removes an `isManualOverride` row.
  6 tests.
- **`PrayerTimeEngine`** (§12.3/§12.4): `recalculateCache` (30 days,
  applying per-prayer offsets, skipping manual overrides),
  `ensureCache` (the "fewer than 7 days cached" trigger), and
  `applyLocationUpdate` — a real haversine distance check, not a stub: ~6km
  within Riyadh is ignored, ~845km to Jeddah triggers the full
  update-settings/invalidate-future/recalculate flow, and past cached dates
  are never touched. 8 tests.
- **`ReligiousFastScheduleStore`** (§11.2): Ramadan matches a stored
  Gregorian range (from the new `ramadanRange(hijriYear:)` helper); Mon/Thu
  and White Days are matched live via
  `Calendar(identifier: .islamicUmmAlQura)` — confirmed working correctly
  on Linux/Swift 6.3.3 (a real risk with an ICU-backed exotic calendar,
  checked rather than assumed). A manual correction always overrides the
  calculated result, either direction. 9 tests.
- **`NutritionWindowStore`** (§7.2): `window(containing:)` matches by
  timestamp range, not calendar-date string — confirmed against the spec's
  own defining example, a 03:50 suhoor entry on calendar day D+1 correctly
  resolving to D's night window. 5 tests.
- **`FastingSessionStore.endScheduled(id:at:)`**: a scheduled, non-break end
  for §11.2's "at Maghrib(D)" auto-end — doesn't touch `correctionHistory`
  the way `recordNutritionEntry`'s outcomes do. 2 tests.
- **`ReligiousFastingService.ensureDay`**: composes all of the above —
  creates a religious `FastingSession` (dry, starting at Fajr) plus its
  night window if none exists for a fast day, or ends the existing one past
  Maghrib. Idempotent, pull-based (no scheduler exists), same pattern as
  `ReadinessCycleStore.ensureCycle`. 7 tests.

42 new tests this session (143 → 185). Not built: the 200+-city manual-fallback
JSON (§12.2), `nutritionWindowId` wiring into Nutrition/Hydration, and
Appendix B notification suppression (blocked on Slice 11) — all recorded in
`docs/features/fasting.md` §6. Nothing in the app calls any of this yet;
every surface here is pull-based, waiting on UI/dashboard integration.

**Verified:** full clean rebuild (`rm -rf .build && swift build`) plus
Swift Testing 185/185 (was 143; 42 new tests, zero regressions).

---

## 2026-09-16 (backfilled 2026-09-17) — Slice 4 (Training/Exercise): schema and stores

Never logged here despite existing in code with earlier filesystem
timestamps than every "Slice 6"/"Slice 7" entry above — discovered and
backfilled while starting the Slice 4 continuation session. Full account
now lives in `docs/features/training.md` (also backfilled this session,
since Training never got a design doc at all — the source design,
`prescription-model-v0.1.md`, was never committed to this repo; only its
effects survive in code comments). Summary:

Migration016: `exerciseCatalog`, `prescribedWorkout`, `workoutSession`,
`workoutBout` — a 12-prescription-type/10-container-type model, deliberately
built instead of the tech spec's own §5.17 sets/reps/load tables (recorded
as a fifth spec/repo divergence in `docs/architecture/spec-reconciliation.md`
§6). `ExerciseCatalogStore`, `PrescribedWorkoutStore`, `WorkoutSessionStore`,
`WorkoutBoutStore` — full CRUD, idempotent soft delete. `WgerCC0Seed` — 21
real CC0-licensed wger exercises (fetched live from wger's API, correcting
an earlier illustrative "squat/deadlift/bench" list that turned out to be
CC-BY-SA 4 in wger's actual catalog, not CC0). 33 tests.

**Not built then, still not built:** any HealthKit bridge, any UI, any
calorie-burn computation (blocked on unresolved Compendium/MET licensing).
See `docs/features/training.md` §5 for the full account of why the obvious
HealthKit-bridge approach (modeled on `BodyCompositionMeasurementHealthBridge`)
is the wrong shape here, for the same reason `SleepEpisodeHealthBridge` was
deleted.

---

## 2026-09-17 — Slice 4 continuation: WorkloadComputer

`WorkloadComputer` (`Sources/AlmanacCore/Training/`): turns a session's
bouts into one `WorkoutLoadSummary` (tonnage, distance, duration, reps,
rounds, average RPE). Deliberately partial — `interval`/`quality_reps`/
`hold_stretch`/`release`/`session_only` aren't modeled, matching the "start
simple" instruction this was reconstructed from (the source spec for exact
per-type formulas doesn't exist on disk — see `docs/features/training.md`
§1). 13 tests.

Caught in passing: `nutrition_window` (added by Migration024, Slice 6, in
the previous session) matches `NutritionReferenceTests`' `nutrition_%` LIKE
assertion and broke it — a real regression from that session, missed
because only the Swift Testing summary line was checked, not the separate
XCTest summary below it. Fixed by excluding `nutrition_window` from that
query with a comment explaining the naming collision (spec §5.11 names it
that way even though Fasting, not Nutrition, owns it).

**Verified:** XCTest 262 tests, 1 skipped, 0 failures (was 1 failure — the
`nutrition_window` regression above — before the fix). Swift Testing
198/198 (was 185; 13 new tests).

---

## 2026-09-17 — Slice 4 continuation: quick-add Training UI

`Native/Almanac/`: `TrainingModel` (owns today's ad-hoc session + bouts,
same `configure(db:)`/`refresh()` pattern as `HydrationModel`/
`ReadinessModel`), `TrainingDashboardView` (new "Training" tab: today's
`WorkloadComputer` summary + bout list + delete), `ExercisePickerView`
(searchable catalog list), `LogBoutView` (the quick-add sheet — fields shown
depend entirely on the picked exercise's `prescriptionType`, per
`docs/features/training.md` §2). `ReadinessDashboardView` gained a
"Training" section (today's summary, shown only when non-empty) and now
takes a second `trainingModel` parameter.

Also fixed: `WgerCC0Seed.seed` was never actually called anywhere — the 21
CC0 wger exercises built 2026-09-16 would have sat unseeded at every real
app launch. Now called from `LaboratoryModel.open()`, same place/pattern as
`LabCatalogSeed.seed`.

Scoped down deliberately: quick-add against one ad-hoc daily session only —
no `PrescribedWorkoutStore` template/container UI (that store has existed
in `AlmanacCore` since the schema pass and still isn't reachable from the
app), no bout editing (delete only), no past-day session review.

Not verified by a build here, same caveat as every other `Native/Almanac`
UI change: no SwiftPM presence, Xcode-only, nothing to compile on this
Linux machine. `AlmanacCore` itself is unaffected (this session touched no
`Sources/AlmanacCore` files) — Swift Testing 198/198, XCTest 262 (1
skipped), unchanged from the prior entry.

---

## 2026-09-18 — Ticket 3: caffeine context validation found and fixed a real threshold bug

Commit `6eeeb06` (2026-09-16) had already added shift-aware tests for
`CaffeineLogStore.computeContext`, but its own message admitted they were
checked against "the thresholds actually shipped" rather than an
independent source — i.e. the expected values were derived the same way
the code derives them, so the suite could never disagree with the code. No
file in this repo (`almanac-tech-spec-v1.0.md` §5.14,
`docs/architecture/spec-reconciliation.md` §4.3) states numeric hour
boundaries for `early`/`normal`/`late`/`very_late`; BRD §6.2, the actual
source, isn't in the repo.

Confirmed the real boundaries with the product owner: **early ≥12h,
normal 8–12h, late 3–8h, very_late <3h** (lower bound inclusive). The
shipped code had **early ≥6h, normal 3–6h, late 1–3h, very_late <1h** —
every band off by roughly a factor of two.

Rewrote `ShiftAwareCaffeineContextTests` (13 scenarios: day/night/evening
workers, no-schedule, occurrence-without-sleep-window, multiple-contexts-
same-day, the three real boundaries at 12h/8h/3h, a split shift, a rest
day inside a 4-on-4-off rotation using its own sleep window rather than
the neighboring night shift's, caffeine logged at the exact instant a
shift ends, and a recurring rotating pattern) against the confirmed
thresholds first, confirmed 7 of 13 failed against the old code (46%
accuracy — temporarily reverted just `CaffeineLogStore.swift` via `git
stash` to prove this rather than assert it), then fixed
`computeContext`'s four comparisons and its doc comment. 13/13 pass now.

**Verified:** Swift Testing 202/202 (was 198; 4 new scenarios — split
shift, rest day, shift-end boundary, plus one boundary test split into
three — zero regressions), XCTest 262 (1 skipped), unchanged.

---

## 2026-09-18 — Ticket 1: readiness-cycle boundary logic (yamal-buildable scope)

Built from `almanac-handoff-2026-09-18.md` (project root, one level up from
this repo) — the three referenced decision docs
(`decision-ticket-1-readiness-cycle-2026-09-18.md` etc.) don't exist
anywhere in either repo, so this was built from the handoff's own summary
of the decided model, confirmed with the product owner before starting
rather than guessed at silently.

`ReadinessCycleStore`'s own doc comment already flagged that boundary
computation — picking a wake time and deriving a cycle window from it — was
"not yet built anywhere in this repo." This slice builds that piece, plus
three supporting components, all on real `sleep_episode`/`readiness_cycle`
tables rather than a parallel schema:

- **`CycleBoundaryCalculator`** (`Sources/AlmanacCore/Readiness/`) — pure,
  stateless. `.detected`/`.manual` wake sources compute identically (decision
  1.2: manual is a substitute, not a different rule); `.trackingOff` falls
  back to a fixed calendar day rolling over at 23:59:00 local (decision 1.3)
  — deliberately not `TimeModel`'s existing `DayBoundary.wakeOffset`, which
  only takes whole hours and is about which day a *logged entry* belongs to,
  a different question from when a readiness cycle itself resets. 5 tests.
- **`SleepEpisodeStore.upsertManualWake`** (decision 1.2) — a user-entered
  wake time substituting for a missing sleep entry. Reuses `sleep_episode`
  (`source = .manual`, already a first-class case) rather than a new table;
  idempotent per `logicalDay` by querying for an existing manual primary
  row first, unlike the classifier's `upsert` which can only key off
  `healthKitUUID`. 4 tests.
- **`SleepTrackingSettingsStore`** (Migration025, `sleep_tracking_settings`)
  — the "Track sleep" toggle, a singleton row following `PrayerSettingsStore`'s
  self-healing pattern. Defaults to `true` with no row yet, matching decision
  1.1 (wake detection is the default). 3 tests.
- **`SleepTrackingToggleService.disableTracking`** (decision 1.4) — mid-cycle
  toggle-off. Deliberately does not touch `readiness_cycle` at all: the open
  cycle's boundary is preserved simply by not writing to it, and the *next*
  cycle switches to the calendar-day rule for free, the next time something
  calls `CycleBoundaryCalculator` with tracking off. The toggle-off instant
  is recorded as the cycle's sleep-ended time by reusing `upsertManualWake`
  — the schema has no "in-progress, end not yet known" shape for
  `sleep_episode` (every row requires both a start and an end), so the
  manual-wake slot doubles as the pending-confirmation entry. No separate
  "prompt state" table: the service's return value
  (`sleepEpisodeIdPendingConfirmation`) is the signal a caller's UI would
  check — the handoff explicitly scoped the confirm/edit prompt itself as a
  stub, no copy specified. 3 tests.

**Not built:** anything HealthKit-side (real wake-time detection from
sleep sessions) — explicitly deferred to iMac per the handoff. No UI beyond
what the four components above expose as return values; the confirm/edit
prompt is unbuilt by design.

**Verified:** Swift Testing 216/216 (was 202; 14 new tests, zero
regressions), XCTest 262 (1 skipped), unchanged.

---

## 2026-09-18 — Ticket 4: training/workout schema gaps (yamal-buildable scope)

Same handoff as Ticket 1 above. Training's schema/stores/UI (Migration016,
2026-09-16/17) already covered most of Ticket 4's ask — see
`docs/features/training.md`. Checked against that doc and the actual
schema before building anything, specifically to avoid a repeat of the
2026-09-16 schema-collision incident: three genuine gaps remained, all
built here, nothing duplicated.

- **`workoutSession.sessionType`** (Migration026) — the user-selected
  sport/activity ("CrossFit", "football", "running", ...), which
  `workoutSession` had no column for at all. Deliberately a plain nullable
  `TEXT`, no `CHECK` constraint — unlike the twelve prescription types
  (closed and enumerable by design, §2), the set of sports a session can be
  is open-ended; the ticket's own examples end in "etc." 2 tests.
- **`ExerciseProgressStore`** (`Sources/AlmanacCore/Training/`) — the actual
  point of collecting per-exercise data that `WorkloadComputer` doesn't
  cover: `WorkloadComputer` aggregates one session's bouts into a summary,
  this follows one exercise's `actual*` fields (never prescribed — same
  provenance rule as everywhere else in Training) across every session it
  appears in, oldest first. A plain join over `workoutBout`/`workoutSession`,
  filtered to live rows on both sides. 4 tests.
- **`WorkoutHealthKitMatcher`** — pure time-overlap matching, ready to wire
  to a real HealthKit bridge later, built and tested against a standalone
  `HealthKitWorkoutSample` fake rather than `HealthSample` (extending
  `HealthSample` for workout activity type is its own undecided design
  question, training.md §5). Enforces "one HK workout per Almanac session,
  never split" by picking the single greatest-overlap candidate when more
  than one candidate's window overlaps the session's. 5 tests.

**Not built:** any real HealthKit ingestion (blocked on iMac and on an
unscoped workout-domain HealthKit decision per the handoff — flagged as a
follow-up ticket, not guessed at here). No UI for `sessionType` or
`ExerciseProgressStore` — both are storage/logic only, same "not verified
by a build here" caveat as every other `Native/Almanac` UI gap in this repo.

**Verified:** full clean rebuild (`rm -rf .build && swift build`) plus
Swift Testing 227/227 (was 216; 11 new tests, zero regressions), XCTest 262
(1 skipped), unchanged.


## 2026-09-18 — Ticket 5: nutrition portion-schema reconciliation (`nutrition_food_factor`, Migration027)

`docs/features/nutrition.md` §8 flagged the pipeline's `nutrition_portion`
(`household_measure`/`specific_gravity`/`edible_proportion`, Processing
Design v0.1 §4) as unreconciled with AlmanacCore's own `nutrition_portion`
(Migration010, household measures only). `specific_gravity` and
`edible_proportion` are per **reference food** — thousands of CoFID rows —
so they cannot reuse `nutrition_dish.edible_proportion` (one row per
device-authored `almanac:` dish; that stays exactly as it was). New table
`nutrition_food_factor` (Migration027) holds both, keyed `(food_ref, kind,
source_record)`, CHECK constraints mirroring the bundle's own qualifier/value
rule verbatim. `NutritionReferenceImporter` now imports `household_measure`
rows into the existing `nutrition_portion` table (row-by-row — `unit_fold`
needs `TextFold`, so not a bulk `INSERT...SELECT`) and the other two kinds
into the new table (a plain bulk copy). Both ride the existing cascade-
delete-then-reinsert transaction, so a device-authored dish's own portions
still survive a reimport and nothing duplicates on a repeat import.
`NutritionCatalog.foodFactor(of:kind:)` is the read side. 4 new tests in
`NutritionBundleImportTests.swift` against the real fixture
(`tools/nutrition/fixtures/bundle_v1.sql`); one existing test updated
(module-prefixed-table assertion) and one pre-existing test
(`testReimportingReplacesAndDropsARemovedSource`) fixed — its hand-built
"source removed" bundle deleted `nutrition_food`/`nutrition_source` rows for
the dropped namespace but not the matching `nutrition_portion` rows, which
the real pipeline's own `PRAGMA foreign_key_check` gate would never allow to
ship inconsistently; this only surfaced once something finally read
`nutrition_portion`.

Verified on yamal: `swift test` green, Swift Testing 237/237, XCTest 266
(1 skipped), zero regressions.

## 2026-09-18 — Slice 11 start: notification suppression matrix

The wayfinder's "Ticket 9: suppression matrix" turned out to already be
fully specified — tech spec §14 and Appendix B, both complete — just not
built. `NotificationSuppressionMatrix.shouldSuppress(_:in:)` transcribes
Appendix B's nine notification types × five suppression axes verbatim, pure
and stateless (`Sources/AlmanacCore/Notifications/`) — no storage, no
`UNUserNotificationCenter` (Darwin-only, not on Linux, same reason
`WorkoutHealthKitMatcher` stops at pure matching logic). One cell is
genuinely confusing in the spec itself: `suhoor`'s "during dry fast" column
reads "🚫 (send = end of fast approaching)", which doesn't quite make sense
since suhoor fires *before* the fast starts (§14.2) — transcribed literally
(🚫 = suppress) rather than silently reinterpreted, flagged in the doc
comment rather than resolved. 10 tests in
`NotificationSuppressionMatrixTests.swift`, every documented cell asserted
both directions (suppress and send).

**Not built:** everything else Slice 11 needs before this is useful —
per-type trigger-time computation (§14.2: water's interval math, suhoor/
iftar off `PrayerTimeEngine`, the 14-day "usual meal time" derivation for
contextual hydration, etc.), a context assembler that reads
`FastingSessionStore`/shift data/`ReadinessCycleStore`/post-shift-sleep
detection into a `NotificationSuppressionContext`, and the actual
`Native/Almanac/NotificationScheduler.swift` wiring (iOS-app-target,
currently hydration-only) that would call `UNUserNotificationCenter` per
§14.1's four-step scheduling run. This pass is the suppression-decision
piece alone, the one part of Slice 11 that was both fully spec'd and
Linux-buildable.

Verified on yamal: `swift test` green (same run as Ticket 5 above, committed
separately).

## 2026-09-18 — Slice 11 continued: trigger-time computation and store-reading assemblers

Builds on the suppression matrix above with the two pieces §14.1's actual
scheduling run needs to produce real fire times, mirroring that same
pure-logic/store-reading split:

`NotificationTriggerTimeComputer` (pure, `Sources/AlmanacCore/Notifications/`)
computes each type's trigger instant from already-resolved primitives per
§14.2: suhoor (-20min before Fajr, fast days only), iftar (at Maghrib, fast
days only), water reminders (every `intervalMinutes` — default 90 — from
wake to 2h before the sleep window, spec silent on whether the first
reminder is at wake itself or one interval later; read here as one interval
later, flagged not guessed), bedtime (-30min default before the sleep
window), and readiness (primary sleep episode end, else an estimate the
caller supplies). Three named types are deliberately absent, each flagged in
the doc comment rather than half-built: Meal/Supplement reminders are plain
user-set clock times with nothing to compute (app-layer settings, not core
logic); Contextual pre-workout snack needs a "planned workout" concept this
repo doesn't have (`PrescribedWorkoutStore` is a template with no time
attached, `WorkoutSessionStore` only records what already happened);
Contextual pre-meal hydration needs a 14-day usual-meal-time derivation off
`NutritionLogStore.eatenAt`, a `PartialDateTime` that can be coarser than
minute-precision or fully unknown — left for its own pass.

`NotificationTriggerAssembler` reads `ShiftScheduleStore`,
`PrayerTimeCacheStore`, `ReligiousFastScheduleStore`, and
`SleepEpisodeStore` per `LogicalDay` and feeds the pure computer, including
a 7-day trailing arithmetic-mean-of-wake-time fallback for readiness when
neither a primary episode nor a shift-derived wake time is available
(plain mean of seconds-since-midnight, not a circular mean — correct for
the ordinary case, not attempted for someone whose wake time straddles
midnight, flagged in the doc comment).

`NotificationSuppressionContextAssembler` closes the gap the suppression
matrix commit above left open: reads `FastingSessionStore`,
`ShiftScheduleStore`, `SleepEpisodeStore`, `ReadinessCycleStore`, and
`ReadinessRecordStore` into a `NotificationSuppressionContext` for the
matrix to consume. Documented honestly: 3 of its 5 axes
(`isDryFastActive`, `isConfirmedIFActive`, `isReadinessAlreadyFinal`) can
only reflect "right now" in the database, not an arbitrary past instant,
because `FastingSessionStore.activeSession()` and
`ReadinessCycleStore.openCycle()` have no point-in-time query — justified
against §14.1's own architecture, which reruns the whole scheduling pass
(and so this whole assembly) on every log entry, shift change, and app
launch rather than computing once and trusting a stale answer.

Small addition to `TimeModel`: `day(before:)`, mirroring the existing
`day(after:)`, needed to walk backward through logical days for the 7-day
average.

36 new tests across `NotificationTriggerTimeComputerTests.swift`,
`NotificationTriggerAssemblerTests.swift`, and
`NotificationSuppressionContextAssemblerTests.swift`.

**Still not built:** the actual `Native/Almanac/NotificationScheduler.swift`
`UNUserNotificationCenter` wiring (iOS-app-target, Darwin-only, needs
Xcode) that would call all of this per §14.1's four-step run, plus the
three flagged-absent trigger types above.

Verified on yamal: `swift test` green, 274 tests (1 skipped —
`ALMANAC_NUTRITION_BUNDLE` not set), zero regressions.

## 2026-09-18 — Slice 11 continued: contextual pre-meal hydration trigger

Builds one of the three types the trigger-time-computation commit above
left flagged rather than built. §14.2: "Contextual: Pre-meal Hydration
Suggestion — Default: OFF. Trigger: ~60 min before usual meal time
(derived from last 14 days of logged meal timestamps). Suppression:
suppressDuringDryFast = 1." The other two flagged types are still not
built, and still can't be without a real product decision: Meal/Supplement
reminders need an undefined settings question (how many preferred times,
stored where), and Contextual pre-workout snack needs a "planned workout"
concept that doesn't exist anywhere in this repo yet.

`NotificationTriggerTimeComputer.contextualHydrationTrigger(usualMealTime:
leadMinutes:)` (pure) applies the fixed 60-minute lead (default,
overridable) to an already-resolved usual meal time, mirroring every
other function in that type.

`NotificationTriggerAssembler.contextualHydrationTrigger(for:before:
leadMinutes:)` does the actual store-reading: queries
`NutritionLogStore.logged(from:to:)` over the 14 days strictly before the
given `LogicalDay` (non-circular — the same `[day-14, day)` pattern the
7-day wake-time average already established, so a day's own not-yet-eaten
meals never contribute to predicting that day), filters to entries whose
`mealType` matches, `basis == .occurrence` (an `eatenAt` that actually
carries a time of day — excludes both coarser-than-minute precision and
the `.recorded`-fallback case where the app only knows when the entry was
logged, not when the meal happened), and averages their seconds-since-
midnight the same way the wake-time average does. Returns `nil` when
nothing qualifies, rather than guessing.

7 new tests across `NotificationTriggerTimeComputerTests.swift` (1) and
`NotificationTriggerAssemblerTests.swift` (6): the pure lead-time
arithmetic; averaging across several qualifying entries; excluding
coarse-precision entries; excluding `.recorded`-fallback entries (using
`FixedClock` to pin the fallback timestamp inside the query window, so
the test is actually exercising the `.occurrence`-only filter rather than
passing by accident via a date-range miss); excluding other meal types;
excluding the day itself; and `nil` when nothing is logged at all.

Verified on yamal: `swift test` green, 281 tests (1 skipped —
`ALMANAC_NUTRITION_BUNDLE` not set), zero regressions — up from 274,
matching the 7 new tests exactly.

**Still not built:** Meal/Supplement reminders and Contextual pre-workout
snack (both need real product/schema decisions, not just wiring), and the
`UNUserNotificationCenter` wiring itself (iOS-only, needs Xcode).

## 2026-09-18: Readiness-cycle primary-episode linking (§7.3/§8.4)

`ReadinessCycleStore`'s own doc comment flagged this as the one piece of
Slice 2's readiness-cycle work left unbuilt: `createCycle`/`ensureCycle`
make bare rows, but nothing tied a *known-primary* sleep episode
(`SleepClassifier`'s job, already fully built — priority: user correction
→ shift-aware → general-longest → none, `effectiveType == .primary`
before an episode is ever persisted) to its `readiness_cycle` row. Picking
*which* episode is primary was never in scope here; this is purely "now
that we know, what does that mean for `readiness_cycle` and everything
downstream of it."

Two new `ReadinessCycleStore` methods split the write in two, matching
§7.3's own split: `linkPrimaryEpisode(id:primarySleepEpisodeId:
primaryWakeTimestamp:cycleStartTimestamp:)` backfills a cycle's primary
episode without touching `cycleEndTimestamp`; `closeCycle(id:
cycleEndTimestamp:)` sets it, called separately because the two are
decided by different events (this cycle's own wake vs. the *next*
cycle's wake).

`ReadinessCyclePrimaryLinkingService` (new) does the actual assembly, via
`linkPrimaryEpisode(for: logicalDay)` or `linkPrimaryEpisode(episodeId:)`:
resolves `anchorDate` from the wake instant itself
(`TimeModel.logicalDay(_:)`, per §8.4 — not the episode's own stored
night-label, which is the caller's chosen grouping, not necessarily the
same rule), creates-or-backfills that day's cycle, closes whichever cycle
was open before it, and relinks mood/soreness logs (via the pre-existing
`ReadinessCycleLinkingService`) into both the newly-closed cycle's final
window and the new cycle's still-open one.

Self-caught correctness bug before ever requesting a compile: the first
draft looked up "the previous cycle to close" via `openCycle()` *after*
creating the new cycle row. Since `openCycle()` orders by id descending
and a brand-new row is both open and highest-id, it would mask the real
previous cycle and silently skip closing it on every run past the first.
Fixed by capturing both `cycle(anchorDate:)` and `openCycle()` (self-
excluded by id) *before* any write in the operation — the same
non-circularity discipline as the 7-day wake-time average never using a
day's own not-yet-happened data.

12 new tests (4 on `ReadinessCycleStore`'s two new methods, 8 on the
service — including one full close→unlink→relink cascade proving a log
wrongly linked to a cycle while it was still open gets correctly moved to
the next cycle once it closes). One test-data bug (not implementation)
caught on the first `swift test` run: `primarySleepEpisodeId` is a real
FK into `sleep_episode`, and two tests used a fabricated id — fixed by
creating genuine `SleepEpisodeStore` rows first.

Verified on yamal: `swift test` green, 293 tests (1 skipped, env-gated),
zero regressions — up from 281, matching the 12 new tests exactly.

**Still not built:** `circadianContextId` wiring on `readiness_cycle`
remains its own separate, unstarted task. Out-of-order backfill (a
correction arriving for a night earlier than the most recently processed
one) and a correction that reaches back past an already-closed cycle
boundary are not handled — `link()` always treats the immediately-prior
open cycle as the one to close, which is correct for the normal forward-
in-time case this was built for, but not verified against replay/backfill
scenarios.

## 2026-09-18: circadianContextId wiring, out-of-order/reach-back linking, Slice 11 Meal/Supplement reminders + pre-workout snack trigger

User instruction: the three "still open" items this same session's own
previous note flagged were quoted back verbatim, followed by "do them" —
explicit authorization under Auto Mode to also make the two product/schema
decisions those items had been blocked on (meal/supplement reminder
settings storage shape; a minimal "planned workout" concept), documented
inline the same way `decision-ticket-*` docs capture earlier calls, rather
than asking with nobody there to answer. Landed as two commits.

### Commit `03de2f2` — circadianContextId + out-of-order/reach-back linking

`readiness_cycle.circadianContextId` has been a real column since
Migration014 but nothing ever wrote it — `CircadianContextEngine` (§13)
was pure and completely unwired. New `CircadianContextStore` persists its
output, one row per date, upserted via a new unique index on
`circadian_context.date` (Migration028 — nothing enforced one-per-date
before, though nothing had ever written a second row either).
`ReadinessCyclePrimaryLinkingService.link()` now computes and attaches a
context id on every link (`linkCircadianContext`), walking a small
backward shift history through `ShiftScheduleStore.occurrence(for:)`.

`link()` also no longer assumes "whichever cycle is open" is the
predecessor being closed — the gap flagged in the previous note. It now
derives true chronological neighbors fresh from
`ReadinessCycleStore.allCycles()` (new method) on every call: the nearest
cycle with a `cycleStartTimestamp` below the new wake time (predecessor,
closed against this wake), and the nearest one above it (successor, this
cycle's own end). This fixes out-of-order backfill (an earlier night
processed after a later one already exists) and reach-back corrections
(a wake time moved earlier, including past an already-closed neighbor's
boundary) — both previously corrupted a cycle's boundaries, since the old
code only ever looked at "the" open cycle. `ReadinessCycleStore.closeCycle`
now takes `cycleEndTimestamp: Date?` (was non-optional) so a correction
that removes what used to be a cycle's successor can reopen it again.

Explicitly out of scope, flagged in the service's own doc comment rather
than built: multi-hop reordering — a correction that jumps a cycle past
more than one existing neighbor in a single move. `link()` only ever
touches the cycle being linked and its two immediate neighbors, which
covers every scenario this repo actually produces; a true multi-hop
reorder would need to walk every affected cycle's own neighbors in turn.

6 new tests: 3 on `ReadinessCycleStore` (`closeCycle` nil-reopens,
`createCycle` attaches a `circadianContextId`, `allCycles` returns every
row), 3 on the service (circadian context computed and attached,
out-of-order backfill fixes both neighbors, a reach-back correction
re-closes the true predecessor). The correction test needed both the
original and corrected episode to share a `healthKitUUID` — caught
before compiling by re-reading `SleepEpisodeStore.upsert`'s own doc
comment: its upsert conflict target is a **partial** unique index on
`healthKitUUID` (`WHERE healthKitUUID IS NOT NULL`), so two episodes with
no UUID never conflict and silently insert as two rows instead of
correcting one — exactly the failure mode a "same night, corrected"
test needs to avoid.

Verified on yamal (installed a Swift 6.0.3 toolchain into the cloud
sandbox to compile and run tests directly, since the device bridge has
none): `swift build` clean, full suite 299/299 Swift Testing tests
(6 new), zero regressions. Committed after clearing a stale
`.git/index.lock` left in the connected folder (needed a delete-
permission grant for this session, since `device_bash` cannot unlink
inside a connected folder until that's approved).

### Commit `6496104` — Slice 11: Meal/Supplement reminder storage, pre-workout snack trigger

**Meal Logging Reminder** (§14.2: "Default: OFF. User sets preferred
times.") — new self-healing `meal_reminder_setting` table, one row per
`NutritionMealType` (Migration029), same self-healing-singleton pattern
as `sleep_tracking_settings` but keyed on `mealType` instead of a single
`id = 1` row. `MealReminderSettingsStore.setReminder`/`setting`/
`allSettings`; a meal type with no row yet reads back as "off, no time
set" rather than a separate not-configured case.

**Supplement Reminders** (§14.2: "Default: OFF per supplement. User sets
time per supplement plan.") — `reminderEnabled`/`reminderMinuteOfDay`
columns added directly to `supplement_plan` (Migration030), since the
spec ties the reminder to one specific plan, not a shareable schedule.
`SupplementPlanStore.setReminder`/`activePlansWithReminders` (active,
enabled, time-set — exactly what "one notification per active supplement
at its configured time" needs).

Both store the reminder time as minutes-since-local-midnight (0–1439),
not a `Date` — a repeating daily reminder has no instant to store.
Resolving a stored minute-of-day onto a real day is
`NotificationTriggerAssembler.mealReminderTrigger(for:on:)` /
`supplementReminderTriggers(on:)`; `NotificationTriggerTimeComputer`
itself gained no new function for either, since there's no rule to keep
pure and separate — just arithmetic simple enough to live directly in the
assembler.

**Contextual: Pre-workout Snack Suggestion** (§14.2: trigger when the gap
between last logged meal and planned workout start exceeds a threshold,
default 3 hours) needed "planned workout start," which nothing in this
repo represented — `PrescribedWorkoutStore` is a reusable template with
no time attached, `WorkoutSessionStore` only records sessions already
completed. New `planned_workout` table (Migration031): deliberately thin
— a scheduled instant plus an optional link to a template, no status or
recurrence, since the trigger only ever needs "the next planned workout
after now." Named snake_case/camelCase like the rest of the
Readiness/Sleep/Notifications domain rather than Training's camelCase
tables, since it's new scheduling support, not one of §5's original
tables.

`NotificationTriggerTimeComputer.shouldSuggestPreWorkoutSnack` deliberately
returns `Bool`, not `Date` like every other function in that enum — the
spec gives this suggestion no lead time and calls it "computed at log
time and at app launch," a live condition re-checked at specific moments,
not something scheduled ahead of a future instant.
`NotificationTriggerAssembler.shouldSuggestPreWorkoutSnack(now:)` reads
`PlannedWorkoutStore.nextUpcoming(after:)` and the most recent logged
meal before `now` (new private `lastLoggedMealTime`, windowed 3 days
back — needed its own `[from, to)` handling distinct from
`usualMealTime`'s: today's own meal must count here, where
`usualMealTime` deliberately excludes it).

31 new tests across `MealReminderSettingsStoreTests` (new, 6),
`PlannedWorkoutStoreTests` (new, 6), `SupplementStoreTests` (+4 reminder
tests), `NotificationTriggerTimeComputerTests` (+5 pure-function tests),
`NotificationTriggerAssemblerTests` (+10: meal reminder resolution,
supplement reminder filtering, pre-workout snack in all four shapes).

Verified on yamal: `swift build` clean, full suite 330/330 Swift Testing
tests pass, zero regressions from either commit. The only test failures
anywhere in the full run (`NutritionBundleImportTests`,
`NutritionDictionaryContractTests` — 15 XCTest cases, "file doesn't
exist") are a pre-existing, unrelated fixture-path gap in the sandboxed
build environment, not caused by this work — confirmed present and
identical before and after both commits, and untouched by anything this
increment changed.

**Still explicitly out of scope**, same as before: `UNUserNotificationCenter`
wiring itself remains iOS/Xcode-only. Multi-hop cycle reordering (flagged
above — closed the next day, see below). No UI for any of this session's
storage — settings screens for meal/supplement reminder times, or a way to
actually create a `planned_workout` row from the app, are separate work;
this increment only built the storage and trigger logic the notification
engine needs.

## 2026-09-18: Multi-hop cycle reordering — anchor-date reconciliation

### Commit `3414294` — `ReadinessCyclePrimaryLinkingService` anchor-date reconciliation

Closes the gap `03de2f2` flagged: a correction that reorders a cycle past
more than its immediate neighbor.

Traced the actual shape of that gap before building anything: `anchorDate`
is a monotonic function of wake time under `DayBoundary.almanac` (§7.1's
fixed 04:00 cutoff), so a correction that *keeps* a cycle's own anchor date
can never cross a fully-established adjacent day's cycle — there's no
calendar day between two consecutive ones to land on. The only way a
correction actually reorders past more than the immediate neighbor is by
moving the wake far enough to land on a *different* anchor date
(`upsertManualWake`) — and when that happens, `link()` was computing a
fresh `anchorDate` and creating/updating a *different* row for it, while
the old row for the previous anchor date was simply abandoned: still
listing the same `primarySleepEpisodeId`, now duplicated across two rows,
and its own neighbor's `cycleEndTimestamp` left stale forever since
nothing ever revisited it. The "walk every affected cycle's neighbors in
turn" framing in `03de2f2`'s own doc comment didn't correspond to a
reachable case — boundary-chain math self-heals in every configuration
that's actually reachable, since rows are never deleted; the orphaned row
was the real, reachable bug.

Fix (confirmed with the user before building, given it reframes what
"multi-hop" actually means here — see `docs/adr/0001-orphaned-readiness-cycle-row-clears-to-bare.md`):
`ReadinessCycleStore.clearToBare(id:)` reverts a row to the same shape
`ensureCycle` produces before classification ever runs.
`ReadinessCycleLinkingService.unlinkLogsFromCycle(cycleId:)` detaches its
logs without relinking them anywhere. `link()` now, before treating
`allCycles()` as ground truth: finds any other row still claiming this
episode as primary under a different anchor date, detaches its logs and
clears it to bare, then repairs whichever cycle used to close against it
(finds that former predecessor fresh, since the orphan's `nil`
`cycleStartTimestamp` now correctly excludes it from `allCycles()`'s
neighbor-finding, and re-closes/relinks it against its new true
successor). The existing predecessor/successor logic for the *current*
cycle's own position is unchanged — it already re-derives neighbors fresh
from `allCycles()` every call, so it "just works" once the orphan is gone.

2 new tests in `ReadinessCyclePrimaryLinkingServiceTests`: the orphaned
row gets cleared and its old neighbor's boundary is preserved
(`correctionAcrossAnchorDateClearsOrphanedRow`); a log inside the
orphan's old window gets picked back up by the neighbor whose window now
extends to cover it (`orphanClearingRescopesLogsToTheExtendedNeighbor`).

Verified via `swift:6.0` in local Docker (Docker Desktop won't mount
`/mnt/kingston` directly — synced the package into a `$HOME`-rooted copy
and ran there; no SPM dependencies, so a plain copy is self-contained).
Full suite 332/332 Swift Testing tests pass (330 prior + 2 new), zero
regressions.

**Still explicitly out of scope**: `UNUserNotificationCenter` wiring and
settings-screen UI remain iOS/Xcode-only, unchanged from before.

## 2026-09-19: Slice 11 status re-verification (correcting a stale build prompt)

A "Slice 11 Build Prompt" handed to a session described the meal/supplement
reminder and contextual pre-workout snack trigger types (§14.2) as still
blocked on a product-decision interview, and Slice 11 as "15% complete."
Both claims were already false by the time that prompt was used: commit
`6496104` (2026-09-18, see above) had already built both trigger types —
`meal_reminder_setting` (Migration029), `supplement_plan.reminderEnabled`/
`reminderMinuteOfDay` (Migration030), and `planned_workout` (Migration031) —
with 31 passing tests. The same prompt also named
`Native/Almanac/HealthKit/HealthSyncService.swift` as an existing
integration point; no such file or `HealthKit/` subdirectory exists. The
real HealthKit code lives at `Native/Almanac/HealthKitProvider.swift`, and
there is no separate sync-service class yet for a scheduler to hook into.

Re-verified on yamal via the native toolchain (`source env.sh && swift
test`, no Docker needed — see the toolchain notes elsewhere in this repo):
full suite **347/347 Swift Testing tests pass, 50 suites, zero failures**
(up from 332; the previously-noted `NutritionBundleImportTests`/
`NutritionDictionaryContractTests` fixture-path failures are gone too).

**Actual remaining scope for Slice 11, unchanged from the 2026-09-18
entries above:** `UNUserNotificationCenter` wiring in
`Native/Almanac/NotificationScheduler.swift` (currently a hydration-only
stub) to consume `NotificationTriggerAssembler`/
`NotificationSuppressionContextAssembler`'s output, its integration into
whatever calls `HealthKitProvider` and into the readiness-cycle callback,
and settings-screen UI for the reminder times/`planned_workout` rows. All
of this is iOS/Xcode-only and cannot be built or verified on yamal.

## 2026-09-19: Slice 12 — `BackupService.restore()`, cycle 1 (happy path only)

`handoff-slices-8-10-12-execution.md` (outer workspace root) proposed
Slices 8/9/10/12; the user picked Slice 12 to drive test-first this
session, scoped to a single confirmed seam: `BackupService.restore(from:)`
restoring a valid, same-schema snapshot into a target database.

Before writing the test, three of that handoff doc's own claims turned
out stale against the actual tree, worth recording since another session
may still be working from it:

- **Migration count.** The doc says "Current migrations: 001–016." Actual:
  `Migrations.swift` registers **001–031** — Migration016 is Slice 4, but
  15 more (Nutrition meal type, BodyComposition/Wellness, Vitals fixes,
  Fasting, religious fasting/Prayer, sleep tracking settings, and more)
  have landed since.
- **Backup format.** The doc describes export as "ZIP format." The actual
  `snapshot(to:)` writes a raw SQLite file via the online backup API
  (`sqlite3_backup_init`/`_step`/`_finish`) plus a `backup_manifest` table
  row in the source DB — there is no ZIP container and no separate
  manifest file. This session's restore implementation targets that real
  format; wrapping it in a ZIP (per BRD §6.18) is a separate, later slice.
- **Migration testing.** The doc says "no migration testing." Actual:
  `MigrationRunnerTests.swift` already covers apply-in-order, idempotency,
  full-rollback-on-failure, duplicate-version rejection, and
  edited/tampered-migration detection — against synthetic migrations, not
  yet an end-to-end real-schema export/restore round trip (which couldn't
  exist until restore did something).

**What changed:** `BackupService.restore(from:)` (previously
`throws -> Never`, unconditionally throwing `.restoreNotImplemented`) now
opens the snapshot file as a `Database` and backs it up into `self.db`
using the existing `Database.backup(into:)` extension in the reverse
direction — the same online-backup mechanism `snapshot()` already uses,
just source and destination swapped. The `.restoreNotImplemented` error
case is removed along with the stub.

Test-first: `testRestoreReplacesTargetContentsWithSnapshot` in
`SyncAndBackupTests.swift` (replacing the now-obsolete
`testRestoreIsExplicitlyUnimplemented`) snapshots a source DB containing
one `sync_anchor` row, restores it over a target DB that already has a
*different* row, and asserts the target ends up with exactly the
snapshot's row — proving restore replaces wholesale rather than merging.
Confirmed red against the `Never`-returning stub, green after the change.
Full suite: 266 XCTest + 347 Swift Testing, zero failures.

**Explicitly out of scope for this slice** (separate future TDD cycles,
per the seam scope confirmed with the user before writing any test):
schema-version mismatch rejection, corrupt/non-SQLite file rejection,
transactional rollback if restore fails partway, HealthKit
de-duplication by `sourceIdentifier` + timestamp, manifest/checksum
validation before applying, and the ZIP container format itself.

Slice 8 was not touched this session — it remains gated on personal-action
items (SFDA email, regional-dish reference material) rather than on
available engineering time. Slices 9 and 10 were picked up later the same
day; see the entry below.

## 2026-09-19: Slices 9 & 10 — schema, stores, and the Insights engine

Continuation of the same session, test-first throughout (red confirmed
against each missing type/table before writing the implementation).
Scoped deliberately to what the handoff doc marks safe to build without
further product sign-off, and to what's buildable on yamal (no UI, no
Xcode/Apple SDK here).

**Slice 9 (Digestion & Urination) — schema only, per the handoff's own
"Schema only for v1" scoping:**

- **Migration032_DigestionSchema** (`Migration032.swift`) creates
  `bowel_movement` and `urination_record`, both indexed on
  `logicalDay`. Both carry a nullable `clinicianEscalationLevel` column
  that nothing writes to yet — BRD §6.3's escalation *wording* needs
  clinician review before ship, and that's a process gate on copy, not on
  the column existing. No escalation-classification logic was written;
  inventing a blood/symptom → escalation-tier mapping without clinical
  sign-off is exactly the "guessing medical wording" the handoff calls
  out as unsafe. Bristol type (1–7) and urination color grade (1–8) are
  plain validated enums (`BristolType`, `UrinationColorGrade`).
- `DigestionStore` and `UrinationStore` (`Sources/AlmanacCore/Digestion/`):
  log + read-by-id + read-by-logical-day, mirroring `SorenessLogStore`'s
  shape. 5 new tests across `DigestionStoreTests.swift` and
  `UrinationStoreTests.swift`.
- UI (quick-entry screens, color/Bristol pickers) is explicitly deferred —
  it's SwiftUI, needs Xcode, and the handoff lists it under
  "pre-App-Store hardening" alongside final medical wording anyway.

**Slice 10 (Insights) — engine + schema, UI deferred:**

- Three pure-logic engines in `Sources/AlmanacCore/Insights/`:
  - `CorrelationEngine.pearson(_:minimumSampleSize:)` — Pearson r with a
    14-sample floor (BRD's own "14+ days of paired data" example) below
    which it returns `.insufficientData` rather than a number — the
    "Limited/insufficient state" guardrail from BRD §6.15. Zero-variance
    inputs return `r = 0`, not NaN. 4 tests: perfect positive/negative
    correlation against hand-computable series, the zero-variance edge
    case, and the insufficient-sample gate.
  - `TrendEngine.snapshot(of:)` — average/min/max plus an up/down/flat
    direction from comparing the older half of the series to the newer
    half (steadier than first-vs-last against one noisy point). 4 tests.
  - `AchievementEngine.badges(for:)` — the five legacy badges from the
    superseded BRD ≤ v1.5 §6.16 (steps, high load, fasted day, nutrition
    targets, perfect log) as a pure function over a
    `DailyAchievementInputs` struct. This remains as legacy core data, not
    a v1.6 product surface; the current calendar is Activity Rings §6.16.
    `isPerfectLog` is taken as a given boolean, not computed here — the
    handoff explicitly leaves "all Wellness data filled in, or all
    recommended entries logged?" as an open, undecided question, and this
    session isn't picking an answer on the doc's behalf. 4 tests.
- Schema: **Migration033_InsightsSchema** creates `correlation_pair`,
  `trend_snapshot`, `achievement_record` (all three named and shaped per
  the handoff's own schema sketch). `correlation_pair.pValue` is nullable
  and unpopulated — `CorrelationEngine` computes `r` and a sample size,
  not a p-value, so the column exists without a fabricated statistic
  behind it.
- `TrendSnapshotStore`, `CorrelationPairStore`, `AchievementRecordStore`
  persist each engine's output, upsert semantics (recomputing a
  metric/pair/day replaces its prior row rather than accumulating history
  — matches BRD §6.17's "recalculates on edit" for achievements). 6 tests
  in `InsightsStoresTests.swift`.
- Trend/correlation *query building* (pulling the actual paired series out
  of `ReadinessRecordStore`, sleep, steps, etc.) was not built — the
  handoff's sequencing question ("build engine now, defer complex UI
  until Slice 2/4 UI lands") only asked for the engine and schema at this
  stage, and wiring real queries is naturally scoped with whatever screen
  first consumes them.

Full suite after both slices: 266 XCTest + **370 Swift Testing** (up from
347; +23 across Slices 9 and 10), zero failures.

**Still gated on personal-action items, unchanged:** Slice 8 (SFDA email,
dish reference material); final Slice 9 medical wording and clinician
review; Slice 10's correlation-approach sign-off (this session proceeded
on the handoff's own stated recommendation, Option A/Pearson, since it
was already a concrete default, not an open question); Slice 10 Insights
UI and real metric-query wiring, deferred alongside Slice 2/4 UI per the
handoff's sequencing note. The former Slice 10 achievement-calendar
surface is superseded by Activity Rings Calendar and is no longer part of
that UI scope.
