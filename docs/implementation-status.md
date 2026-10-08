# Almanac implementation status

Updated 2026-10-07: the newest entry is the cloud session's 2026-10-06 handoff
work (workout templates, the readiness withhold, the Vitals log), merging
through PR #6; the fasting entry is second. Updated 2026-10-06. **Fasting and prayer times work end to end in the running
app** — religious fasting had never run on a phone (no fast day was ever
detected), and logging food or water never reached a fasting rule; its entry is
second. Updated 2026-10-05: the degenerate-baseline defect recorded below is **fixed**
and the two checklist rows that were asserting on it are repaired; the entry is
at the top. The 2026-10-04 second-pass correction still stands: the "a single-
reading day always scores 66" note lower down was measured without sleep data,
and with an 8-hour episode the same state scored 74 and read "ready for a strong
session". Manual vitals entry —
BRD §6.7's "manual fallback" — is built in `AlmanacCore` and in `Native/Almanac`,
and it makes the two engine-dependent readiness rows in the acceptance checklist
drivable; the entry for that is below. The Training Program layer above a single
session is built in `AlmanacCore` — migration 049, three stores, three engines —
and its screens are built in `Native/Almanac`; see
`docs/features/training-program.md`. The Technical Spec is now
committed under `docs/`, so the references to it resolve from a fresh clone. The production nutrition reference
bundle ships as an AlmanacCore resource and installs into the app database on
first launch. The editorial shell, Today tracking calendar, Trends surface and
Quick Log are also live.

The canonical product requirements are now `docs/brd-v1_6.md`. The v1.5
Monthly Achievement Calendar is superseded by the v1.6 Activity Rings Calendar
and is not a current implementation target.

## 2026-10-06 — handoff work from a cloud session: Kitchen merge-ready and built out, readiness withhold, Vitals log

**Update 2026-10-07.** Both pieces this branch was waiting on are now on
master. Kitchen landed first, through the Kitchen-only branch. Fasting landed
through PR #5 and kept migration 050, as planned. This branch merged master in
both times, and the reservation set in `MigrationReservation.swift` is now
empty. What this branch still adds (templates with migration 055, the readiness
withhold, the Vitals log) merges through PR #6. The paragraphs below are as
written on 2026-10-06.

**Where this is.** Branch `claude/handoff-2026-10-06`, pushed, **not merged to
master**. `claude/kitchen-merge-ready` points at `ebdb51d`, Kitchen as built
plus what it needed to merge. Done in a Linux cloud container: Swift 6.3.3 ran
the core suite; there was **no Xcode**, so no Swift in `Native/` was compiled
and no UI test was run.

**Not done: the fasting and prayer work (handoff task 1).** It exists only as an
uncommitted working tree on the owner's iMac, and is not on GitHub under any
branch, so it could not be backed up, verified, committed or merged from here.
The two notification bugs it fixes are confirmed present on master by reading
the code: `NotificationScheduler.swift:62,111,122` test
`Self.ownedPrefix.hasPrefix($0)`, which is backwards, and
`NotificationPlanner.plan` never filters candidates to `(now, now + horizon]`.
They were left for that work to fix, to avoid a conflicting second fix.

**Merge order.** The fasting work lands first, as the handoff recommended, and
keeps its migration 050. This branch numbers its migrations 051–055 and reserves
050 in the tests (`Tests/AlmanacCoreTests/MigrationReservation.swift`). The
contiguity checks subtract the reservation rather than being loosened, and
`testNoReservedVersionHasLanded` fails the moment 050 merges, which is the
prompt to empty the set. Merging this branch first would force the larger work
to renumber, and would break any database that already applied its 050, since
`MigrationRunner` refuses a renamed migration.

### What changed

- **Kitchen, merge-ready (task 4).** Rebased onto `efb1c0b`; it already sat on
  it, so the original commits are kept. Migration 050 → **051**. Found and fixed
  a real defect: the shipped `almanac.sqlite` has no `almanac` row in
  `nutrition_source`, so `NutritionDishEditor.create` failed its foreign key on
  every device. Nothing in the app had created a dish, so it never showed.
  `create` now writes the row, and a test on the shipped bundle fails without
  that change. Added `KitchenSeedPlan` (`-AlmanacSeedKitchen`, DEBUG- and
  argument-gated, like `VitalsSeedPlan`) and `KitchenUITests` (4).
- **Readiness (task 2).** With vitals present and no personal baseline for any
  of them, the band sentence is withheld from `textDescription` and
  `recommendation`. Score, colour and confidence stay. See
  `docs/features/readiness.md`.
- **Vitals (task 3).** `VitalsRecordStore.log` includes today, and `VitalsView`
  uses it. `clearHandEnteredReadings` now reaches today's readings, and the
  readiness UI tests no longer clear today through the seeding spec.
- **Kitchen build-out (task 5), one commit per step.** 0: TheMealDB's terms
  could not be read from this network (403 on every route), so the gate is shut
  and nothing is imported (`docs/features/themealdb-terms.md`). 1:
  `DishAllergenCheck` is one check for Kitchen and Saved meals: hidden by
  default, collapsed and reachable, a warning page, and confirm before logging.
  2: migration **052** `serving_count`; one serving is the default amount. 3:
  migration **053**; pantry suggestions the owner adds or dismisses. 4:
  migration **054**, the ingredient table. Pantry, log and allergen check all go
  through it, and the allergen check reads more names, never fewer. 5:
  skipped.
- **Workout templates (task 6).** A template stored only a name, a container
  shape and notes, so the first pass stopped at a proposal. The owner then
  unblocked it ("exercises, but editable"), and it is built:
  - Migration **055**, `prescribedWorkoutItem`;
  - `PrescribedWorkoutStore.setItems` and `TemplateApplier`, which copies the
    exercises onto today's own session as planned bouts with nothing marked
    done;
  - screens: an exercise list in the template editor, **Start from a template**
    on Training, and today's rows open the shared `BoutActualsEditor`;
  - tests: `TemplateApplierTests` (8), and one UI test.
  See `docs/features/training.md`.
- **Housekeeping (task 7).** The checklist summary now carries real counts.
  Slice 8 and Slice 4's MET and exercise-library data are marked "owner building
  his own data first", with the licence emails kept as the fallback.

### Verification

`swift test` (Swift 6.3.3, x86_64 Linux):

| Tree | Swift Testing | XCTest |
|---|---|---|
| master `efb1c0b` | 938 tests, 99 suites, 0 failures | 373, 1 skipped, 0 failures |
| branch head | **987 tests, 107 suites, 0 failures** | **379, 1 skipped, 0 failures** |

The skipped test is the opt-in `NutritionRealBundleTests`. The handoff's 374
XCTest for master is one more than this run counted.

Revert-and-run checks, each fails without its fix and passes with it:

| Fix | Test | Without the fix |
|---|---|---|
| Dish foreign key | `testADishCanBeCreatedOnTheShippedReference` | "FOREIGN KEY constraint failed" |
| Readiness withhold | withhold, context and end-to-end tests | 6 XCTest + 3 Swift Testing assertions |
| Vitals log | `logIncludesToday`, with the old exclusive bound | 4 issues |

CI (`.github/workflows/ci.yml`), run on every push to this branch:

- the Linux job (Swift **6.0.3**) caught one test line that 6.3.3 accepts and
  6.0.3 does not, fixed in `62248d6`, and was green from then on;
- `xcodebuild` of the app and widget was **green**, so the `Native/` changes
  compile;
- the full UI suite (`test-ios`, about 2.5 hours on a fresh simulator) ran on
  `3653be0`: **83 run, 7 failed**.
  - Four of the failures are master's own.
  - Three are this branch's new tests failing on their first run: two Kitchen
    tests and the template test.
  - Three of master's failures passed here.
  - `TrainingProgramUITests` passed 13 of 13, including 7.10 and 7.11 on the
    new way of clearing today's readings.
  - The new failures' messages were not readable from the session (only the
    log tail is reachable). The definite cause in the template test and a
    likely one in the Kitchen allergen test are fixed, and a CI step now prints
    every failure message at the end of the log, so the next run says exactly
    what failed.

  The second run, `0e6fd55`, with every failure message printed: **83 run,
  5 failed**.
  - The template test and all of NotificationSettings passed.
  - Two failures are master's own.
  - One is a navigation flake in a test that runs before Kitchen.
  - Two are the Kitchen tests' own lookups: a "Pantry" name shared by two
    buttons, and the disclaimer searched for as plain text. Both are fixed.

  The third run, `12ffa44`: **83 run, 6 failed**.
  - The Kitchen pantry test and the template test pass.
  - The Kitchen allergen test reached its last stage and failed on a tap that
    left the hidden entry collapsed. The tap is fixed.
  - The other five are tests this branch does not touch, failing on some runs
    and passing on others.

  The fourth run, `83578ea`: **83 run, 6 failed**.
  - The Kitchen allergen test passed every check of the app, through the
    warning and the confirmation. It failed on its very last step, closing the
    confirmation: on iOS 26 that dialog has no Cancel button and is closed by
    tapping outside it. The test now does that. Not yet re-run.
  - The other five are the same tests as before, which this branch does not
    touch.

  The fifth run, `8e7b555`: **83 run, 3 failed**.
  - Two are master's own (BodyCircumference, ProblemChannel).
  - The Kitchen allergen test failed on its last check: the iOS 26
    confirmation popover did not close on a tap outside it, and it has no
    Cancel button. The page now asks with an alert, which always shows Cancel.
    This is the one app change the UI runs led to. Not yet re-run.

  The sixth run, `cccf311`: **83 run, 4 failed, none of them this branch's**.
  - Every new test passes: the four Kitchen tests and the template test.
  - The four failures (BodyCircumference, BodyCompositionWellness,
    ProblemChannel, one NotificationSettings) are all on master's own failing
    list and are not diagnosed.
  - `xcodebuild` and the Linux core suite are green.

  Details are in `docs/acceptance-checklist.md`.

**Not run:**

- any UI test locally;
- notification delivery and HealthKit, which need a device.

The four known UI failures (`BodyCircumferenceUITests` 1,
`BodyCompositionWellnessUITests` 2, `AttributionsUITests` 1) were not diagnosed.

## 2026-10-06 — Fasting and prayer times, completed

**What the owner saw:** a Fasting screen that said "No religious fast is
scheduled for today" every day of the year, prayer times only for someone who
granted GPS, and no suhoor or iftar reminder ever. Every rule behind those
screens had been built and unit-tested since 2026-09-17; the defects were in what
reached them. Details, and what each decision rests on, are in
`docs/features/fasting.md` §0, `docs/features/notifications.md` and `CONTEXT.md`
("Fasting and prayer").

**Fasting**

- **No fast day was ever detected** — nothing created a `religious_fast_schedule`
  row. Ramadan (this Hijri year and next) is now created on every refresh,
  inheriting the user's on/off choice; Mon/Thu and White Days are toggles; any
  date can be marked or unmarked; Eid and Tashreeq are never voluntary fast days.
- **A religious session is derived** from schedule + Fajr/Maghrib + first intake
  + time (`ReligiousFastingService`, `FastingIntakeLog`, `FastingCoordinator`),
  for yesterday and today, on launch, foreground, Health sync, prayer-time change
  and screen load. This removed: suhoor invalidating the day's fast (and suhoor
  water ending it with a negative duration), a first open after Maghrib leaving
  the fast open, the logical day being used where Fajr precedes 04:00, and a
  constraint error whenever an intermittent fast was running at Fajr.
- **Logging reaches the rules.** `FastingAwareNutritionLog`/`FastingAwareHydrationLog`
  had no caller; every app write path, both editors, every delete and the
  widget now go through them. Deleting the entry that ended a fast restores it.
  A caloric drink ends an intermittent fast.
- **Intermittent:** an IF started before 04:00 no longer vanishes from the
  screen; §11.1's suggestion is offered; a live timer with the protocol target.
- **Read side:** night-window contents, coming fast days, recent fasts, a widget
  that shows suhoor/iftar and cannot end a religious fast.

**Prayer times**

- City picker over the bundled 230-city list (it had no UI); a chosen city is no
  longer overwritten by the next GPS fix; a fix is named after the nearest city;
  one-shot location instead of a stream while foregrounded.
- Seven more methods and custom angles; Hanafi Asr (Migration050 `asrMethod`);
  per-prayer offsets on screen; Qibla bearing; Hijri date; next-prayer
  countdown.
- **Umm al-Qura's Ramadan Isha** is Maghrib + 120 min. It was 90 — half an hour
  early every night of Ramadan in the default method.
- `ensureCache` rebuilds a cache computed for another place or method.

**Notifications**

- **Past reminders fired again on every foreground** (the planner never applied
  the past/horizon filter its doc promised, and the scheduler maps a past instant
  to one second): opening the app after Maghrib re-announced iftar. Fixed; two
  planner tests that asserted the bug were corrected.
- **The scheduler's ownership check was reversed**: stale reminders were never
  removed, "Turn all off" cancelled nothing, "Queued now" read 0.
- **Dry-fast suppression is per fire instant**: a fast running now no longer
  mutes tomorrow's suhoor or tonight's water.
- **`prayer` alerts**, off by default (Migration050), per-prayer choice; Maghrib
  defers to iftar on a fast day.

Also: the Arabic-locale day-key fix (`fix/arabic-digit-day-keys`, b90742b — on an
Arabic phone the prayer cache keys were written in Arabic-Indic digits and
matched nothing) is included on this branch; restore now rebuilds night-window
assignments (spec line 1942 step 6d).

### Verification

`swift test`, full suite: **982 tests in 102 suites, 0 failures** (199.6 s), and the XCTest half 374 (1 skipped), 0 failures. New suites
`Religious fasting, derived` (28) and `Prayer times, completed` (15); four
existing tests updated (the two that asserted past reminders, the migration list,
the rule-seeding test).

UI (iPhone 16e, iOS 26.3): `NotificationSettingsUITests` 5 of 5 (now including
the `prayer` switch), `AttributionsUITests` Fasting and Prayer 2 of 2,
`OwnerRequestedFeaturesUITests.testFastingTogglesBetweenReligiousAndIntermittent`
1 of 1. `testFastingScreenOpensFromMore` first failed because its button is now
below the fold of a lazy list; it scrolls to it with `reveal` like the rest of
the suite. The full UI suite was not run.

**Merged with master's Kitchen (2026-10-07).** Kitchen landed first (owner's
call) with 051–054 and a reservation holding 050 for this work. Per
`docs/features/kitchen.md`: `Migration050_PrayerPreferences` sits ahead of
`Migration051_KitchenPantry`, `reservedUnmergedMigrationVersions` is empty, and
`BodyMeasurementTests.migrationUpgrade` lists 41–54. Merged result: `swift test`
**1023 tests in 109 suites, 0 failures**, XCTest 376 (1 skipped), 0 failures;
app and widget build. Kitchen logs food through `NutritionModel`, so it reaches
the fasting rules too. UI tests were not re-run on the merged result.

Driven on the iPhone 16e simulator (iOS 26.3), Riyadh chosen from the city list:
prayer times, countdown, Hijri date, Qibla, an offset moving Maghrib by a minute
in the cache; Ramadan 1448 and 1449 rows created on launch (1448: 2027-02-08 →
2027-03-08); a day marked as a fast showing the live Fajr→Maghrib progress;
**250 ml logged from Quick Log ending the fast at that minute**; deleting it from
Hydration **reopening the fast**; an intermittent fast started the previous
evening still shown after 04:00, and ended with its duration.

Not driven: anything that needs a notification to arrive (device-only, §4.1 of
the acceptance checklist), the widget on a home screen, and a real GPS fix.

## 2026-10-05 — the degenerate baseline is fixed, and the tests that asserted on it are repaired

**One product behaviour changed: a baseline assembled only from the day being
scored is now reported as no baseline.**

`ReadinessBaselineService.meanPerDay` returns nil for a metric when every day
contributing to its mean is the day being scored. The delta is then identically
zero by construction, so §9.2's `delta ≤ 0 → 95` and `pct ≥ -5% → 75` rows paid
out +95 and +75 of unearned credit for a comparison with itself. §9.1's own
redistribution rule then treats both vitals inputs as missing, which is the whole
of the fix — it invents no threshold, because a baseline made only of the day it
scores is vacuous by identity rather than by being short.
`ReadinessBaseline.validDayCount` is deliberately unchanged: §9.8 counts valid
days and §9.7's calibration legitimately counts a day that carried its first
reading, so only the baseline itself is unavailable.

Measured cost: the realistic case moves 74 → 72 with the recommendation
unchanged, and `confidence` moves `medium` → `veryLow`. It is a
stop-overclaiming fix, not a number fix.

**Two checklist rows failed on it, and both were asserting on nothing.**
`TrainingProgramUITests` planted every reading on today — three filler readings
per metric plus the pair under test — and that produced a score only because a
day could serve as its own baseline. "Scaled from N" and "Today is a rest day"
were both reading a number obtained by comparing a value with itself.

Repairing that needed a harness capability that did not exist: placing a reading
on a day other than today. The editor's "Measured at" control is a compact
`DatePicker`, so tapping it expands a **graphical calendar** whose day cells are
locale-formatted buttons (`Sunday 4 October` under en_GB, `Sunday, October 4`
under en_US), and `test-ios` resolves the newest installed runtime rather than
pinning one — a value string that works on a desk is not guaranteed on a runner,
so a green local run would be evidence of nothing. `VitalsSeedPlan` plants
readings from a `-AlmanacSeedVitals` launch argument instead: locale- and
version-independent, `swift test`-covered, DEBUG-gated *and* argument-gated, with
`VitalsSeedPlanTests` pinning that an ordinary launch asks for nothing. Note what
that gating is and is not: checked against a Release binary, `VitalsSeedPlan` and
the `-AlmanacSeedVitals` string are both *present* there, because AlmanacCore is
compiled whole into the app. What `#if DEBUG` removes is the single call site, so
a Release build has no path to `apply`. Reachability, not absence.
The mechanism and the measurement behind choosing it are recorded at
`XCUIApplication.seedVitals` in `Native/AlmanacUITests/UIScrollSupport.swift`.

**A second defect surfaced, and it had been hiding.** `VitalsView.reload` reads its
log with `records(metric:from:to:)`, whose `to:` is exclusive, so a reading taken
today is never in the list; the today card has no delete. So
`TrainingProgramUITests.clearHandEnteredReadings` could never remove one while
reporting success, and **16 readings on today** had accumulated across runs,
invisible the whole time. Both readiness rows still passed — `meanPerDay` averages
within a day before averaging across days, so sixteen same-day readings moved the
baseline only slightly and the bands held. That was luck, and it is exactly the
"the score depends on how many rows the test left behind" arrangement the rewrite
was meant to remove. Today is now cleared through the seeding spec (`rhr@0,hrv@0`),
and the helper's own doc says plainly what it cannot reach.

### Verification

`swift test`, full suite: **938 tests, 99 suites, 0 failures** (189.2 s) — 12 new,
all in `VitalsSeedPlanTests`: the guard, the spec grammar including the clear
form, day resolution against §7.1's 04:00 boundary, authoritative-not-additive,
and that a seeded reading is a real reading carrying `recordManual`'s own source,
unit, zone and plausibility check.

UI: both rows pass against a three-day seeded baseline, and **were also run with
the baseline removed, where both fail** — at "starting a day with a readiness
score must offer to scale the session by it", and only there. That is the check
that they are not silently back to asserting on a vacuous score.
`testAReadingCanBePlantedOnADayOtherThanToday` is the seeding hook's own test, so
its first failure would be about the hook rather than about a band three screens
later. Full `TrainingProgramUITests` file: **13 of 13, 0 failures** (1839 s,
iPhone 16e, iOS 26.3) — on a *shared and dirty* database, which is the harder
state. Not run against a virgin simulator, which is what CI sees.

App target, Release: `xcodebuild -configuration Release -destination
'generic/platform=iOS Simulator'` — **BUILD SUCCEEDED**, and the resulting binary
was inspected for the seeding symbols. See the gating note above for what that
found.

## 2026-10-04 (second pass) — the degenerate baseline, re-measured

**No product behaviour changed. The record was wrong and is now corrected.**

The note in the entry below, and the same claim in `CONTEXT.md` and
`docs/acceptance-checklist.md`, described a single-reading day as always scoring
**66**, framed as §9.7's "preliminary" state arriving as arithmetic, to be
revisited "when §9.7's calibration completes". Driven against the real engine
with real stores, both halves of that are wrong.

**Wrong: the 66.** It is what you get with no sleep data. The ordinary shape of a
scored day also carries a sleep episode, and then the same degenerate baseline
scores **74 — green — "Recovery is good — ready for a strong session."** An
8-hour night legitimately scores 100 on duration, so it dominates; the point is
that the two vacuous vitals inputs are added on top of it.

**Wrong: that it is a calibration-phase artefact.** With 27 prior sleep-only
valid days and today's single pair, `validDayCount = 28`, `calibrationDay = nil`
— calibration completed 7 valid days earlier — and the degenerate score is still
produced. The trigger is data shape, not phase. It recurs on every first entry
after any gap, for the life of the record, for exactly the sporadic
manual-entry user §6.7's fallback exists to serve. Ten consecutive
single-reading days score `66, 63, 63, 63, 63, 57, 49, 49, 49, 42`.

**The mechanism, which is worse than "the baseline includes today."** A window
day contributes to a metric's mean only if it carries that metric, so a
first-entry day has a *one-day* baseline consisting of the reading being scored.
`delta ≡ 0` by construction, and §9.2's `delta ≤ 0 → 95` and `pct ≥ -5% → 75`
rows — written for a baseline assembled over many stable days — pay out **+95 and
+75 of unearned credit** rather than reporting that no baseline exists.
`confidence` compounds it: both inputs are counted as *present*, so the score is
labelled `medium` confidence while being derived from a comparison with itself.

**Why it shipped.** `ReadinessBaselineServiceTests.logDays` seeds days *before*
the day under test, commented "so today's own data is never part of what today's
score is measured against". That is true of the helper and false of production,
where `recent(_:through:)` keeps `$0 <= date`. No test in the suite has ever
logged a vital on the day being scored.

**What a fix costs, measured — and it has since been paid.** Treating a
degenerate baseline as *no* baseline —
§9.1's own redistribution rule, inventing no threshold — moves the realistic case
74 → 72 and `confidence` `medium` → `veryLow`. The recommendation is unchanged.
So the fix is not a number fix; it is a stop-overclaiming fix. Whether a missing
personal baseline should also *withhold* a recommendation is a product question
and is left open. Also left open, from the handoff: per-test isolation for the UI
suite, which is a harness investment and not a gap.

> **Acted on in the 2026-10-05 entry above.** The treatment described here is
> what shipped. The cost it had not been priced against is that the fix removes
> the score the 7.10/7.11 UI tests were built on, so both had to be given a real
> baseline.

Full analysis and the measured table: `docs/features/readiness.md`.

### Gates

`swift test`, full suite: **921 tests, 98 suites, 0 failures** (190.9 s) —
unchanged, as expected for a documentation-only commit; the probes used to take
the measurements above were scratch and are not committed.

## 2026-10-04 — Manual vitals, and the readiness question that ignored its own answer

**The gap.** BRD §6.7 promises resting HR, HRV, steps and active energy
"imported (HealthKit-authoritative, §5.2) with **manual fallback**". There was
no fallback: `vitals_record` had exactly one writer, the HealthKit bridge. A
person without a watch — or one who declined the HRV permission §5.2's own
scenario names — could never produce a readiness score, because
`ReadinessEngine.evaluate` returns `score: nil` when duration, stages,
RHR+baseline and HRV+baseline are all missing. That is what left checklist rows
7.10 and 7.11 undrivable.

**Only RHR and HRV, because those are the two the formula weighs.**
`ReadinessFormula` has no term for steps or active energy, so a field for them
would be a control with nothing on the other side of it; the screen's footer
says so rather than leaving the absence to be discovered. No `VitalsModel`
either — `BodyCircumferenceView` and `SupplementView` both drive their store
straight from the view, and the one thing this screen needed beyond that was
`readinessModel.refresh()`.

### New

- **`VitalsMetric`, `VitalsEntryError`** (`Sources/AlmanacCore/Vitals/VitalsVocabulary.swift`)
  — the two hand-enterable metrics, their units and their plausible ranges
  (a typo guard, not a clinical range), and four typed reasons a reading was
  refused. The raw values are the contract with the HealthKit bridge and
  `ReadinessBaselineService`, so a rename here would silently stop every stored
  row from being found; `VitalsManualEntryTests` pins the vocabulary against the
  bridge through its public API.
- **`VitalsRecordStore.recordManual` / `update` / `delete` / `manualRecords` /
  `latestValue(for:since:)`** — the fallback itself. `recordManual` derives
  `logicalDay` from `TimeModel` rather than trusting the caller, stamps the
  metric's unit, and refuses a synced row's correction.
- **`VitalsView`** (`Native/Almanac/VitalsView.swift`) — today's two readings in
  the one prominent card, one "Log a reading" door, a fortnight of history with
  edit/delete on hand-entered rows only. Wired as `AppRoute.vitals` in the
  Modules **Records** section; Today's RHR/HRV "Inputs used" rows are doors into
  it.
- **`StoredSleepEpisode.measuredDurationMinutes`** — nil for a zero-duration row.

### Fixed

- **Today's score could be handed a reading from another night.** `ReadinessModel`
  read the newest row in `vitals_record`, which is the right answer while the only
  writer is the bridge and wrong the moment a person types a reading *about last
  night* this morning — it is timestamped yesterday, and "newest row wins" looks
  entirely reasonable while doing it. The read is now bounded to the day being
  scored, and with no resolvable day it reads nil rather than falling back to
  whole history, because the fallback is the bug.
- **A manual wake marker scored as the worst possible night.** §9.2's duration
  bands put 0 minutes at the bottom, so a zero-duration episode was a 10/100 sleep
  score rather than an absent measurement.
- **The readiness question discarded its answer.** `ProgramDayView`'s "Factor in
  your readiness score?" had both buttons calling the same `onStart()` and the
  session opened unscaled either way, so answering **Yes** produced exactly the
  session answering **No** did. This is the half of "7.10/7.11 are unreachable"
  that adding a score would never have revealed. The answer is now carried
  through `ProgramListView` as one `StartingSession` value — not a second
  `@State` flag, which could disagree with the day it belongs to — and
  `ProgramSessionView` opens already scaled when the answer was yes and a score
  exists. The toggle stays: the answer is changeable for as long as the sheet is.

### Found, and left as it is

> **Superseded by the second-pass entry above.** The "always scores 66" figure
> below was measured without sleep data; with an 8-hour episode the same state
> scores 74 and reads "ready for a strong session", and it is not confined to
> calibration. Read the newer entry instead.

**A day with a single reading of each metric always scores 66.** §9.8's baseline
is the last 28 valid days *including today*, and `meanPerDay` averages within a
day, so on a day with one RHR and one HRV the baseline *is* that reading:
`rhrScore` reads it as 95 and `hrvScore` as 75 whatever the numbers were, and
the score lands on 66 — moderate — every time. That is §9.7's "preliminary"
state arriving as arithmetic rather than as a label, and it is not changed here:
excluding today from the baseline would be a different reading of §9.8 than the
one the spec states. It is recorded in `docs/features/readiness.md`, and it is why
the 7.10/7.11 UI tests leave three ordinary readings behind before typing the
pair they want scored.

> **Superseded by the 2026-10-05 entry above, including the last sentence.** That
> arrangement was the defect's only consumer, and it is gone: a baseline made
> only of the scored day is now no baseline, so those rows run against a seeded
> three-day history and type exactly two readings.

### Verification

`swift test`, full suite: **921 tests, 98 suites, 0 failures**. Up from the
900/95 captured at the previous entry; 21 new tests across three suites — 14
manual-entry, 3 manual-wake-marker, 4 manual-readings-reach-readiness.

App target: `xcodebuild` against `Native/Almanac.xcodeproj`, scheme `Almanac`,
iPhone 16e simulator — **BUILD SUCCEEDED**.

UI: `AlmanacUITests/TrainingProgramUITests` — full-file run
(`-only-testing:AlmanacUITests/TrainingProgramUITests`) — **12 of 12**
(2026-10-04). The first run at 12 tests was 11 of 12, and the failure was the
useful kind: the two new readiness tests sort first by name, so the
abandon/delete test ran against a day now carrying their training sessions and
its drain loop miscounted how long the list takes to settle after a delete.
Checklist §7 is now fully driven, 7.10 and 7.11 included; those two
hand-enter their vitals through Modules → Vitals first. Harness fixes found while
driving: `AlmanacMetricRow` published its identifier on each of its three texts,
so a query for today's resting rate matched three elements and raised instead of
answering (the row is now one accessibility element, which is also what VoiceOver
should have been reading); `reveal` only scrolls one way, so re-entering the
Modules tab from a pushed screen needed the search direction chosen rather than
assumed — tapping the destination you are already on pops that stack to root and
rewinds the list past the row being looked for; and the abandon/delete test's
drain of today's log asked for a row, then swiped it, and a query issued while
the previous delete was still animating the list matched the row on its way out,
so the swipe failed with "no matches found" instead of swiping anything. The
drain now waits for the row count to hold still before choosing a row, which is
the same stale-frame problem the `reveal`→tap race had, one layer down.

## 2026-10-02 — Training Program: the layer above a session (core + UI)

The AI-delegatable half of `docs/handoff-2026-10-01-training-program.md`. Full
write-up in `docs/features/training-program.md`; what follows is what a reader
of this file needs to know.

**Core and UI implemented.** Native screens added (`ProgramListView`,
`ProgramDayView`, `ProgramSessionView`, `ExerciseProgressGraphsView`) and wired
into `AlmanacApp`, `MoreViews` and `TrainingDashboardView`. Core test suite passes
(900/900). Program flows are now also driven from the UI: three
`TrainingProgramUITests` cover Start Workout → picker, program/day authoring
(persistence + authoring order), and the day→session loop with the skip prompt
and readiness door; a full-file run passes 3 of 3 (see the checklist §7 and the
Verification block below). One tap-stability bug was found while driving and
fixed in the test harness, not the app (stale-frame tap after `reveal` on a
lazy `List`).

### New

- **`Migration049_TrainingProgram`** — `trainingProgram`, `programDay`,
  `programDayExercisePool`, three indexes; `workoutSession` gains
  `programDayId` / `rotationIndex` / `readinessAdjusted` plus an index,
  `workoutBout` gains `equipmentVariant` / `wasSkippedForSession`.
- **`ProgramStore`, `ProgramDayStore`, `ProgramDayExercisePoolStore`** — full
  CRUD, typed errors for the three closed sets, soft delete, `setPositions`,
  `setActive`, `setProgression`.
- **`RotationEngine`** — `nextRotationIndex(programDayId:)` and
  `plan(programDayId:rotationIndex:skipping:)`. Two queries per plan.
- **`ReadinessAdjustment`** — band → policy → adjusted prescription.
- **`ExerciseProgression`** — per-exercise suggestion, never a write.
- **`EquipmentVariantGraph`** — separate/combined mode over both graphs.
- **`ProgramVocabulary`** — `EquipmentVariant`, `EquipmentVariantDisplay`,
  `ProgressionCondition`, `ExerciseAvailability`.
- **`ExerciseProgressStore.history(exerciseCatalogIds:)`** — one batched read,
  because a per-item read inside the progression loop was a query per exercise.

### Three things decided while building, not found

**The readiness→prescription table is reconstructed.** `prescription-model-v0.1.md`
was never committed to this repo (`docs/features/training.md` §1), so the handoff's
"readiness adjustment computation" had no source. Two rules survive it — `release`
is the only type that may *increase* on a low-readiness day, and `quality_reps`
holds volume and drops complexity — and the rest was rebuilt from those plus
`ReadinessFormula`'s own six bands and its real 40/70 thresholds. No threshold or
band was invented. `ReadinessAdjustment.table` is the single place to overrule it.
Recorded in `CONTEXT.md`.

**`isActive = false` and `deletedAt` are different, on purpose.** Permanent
removal is reversible and keeps the item's prescription, progression rule and
rotation position; deletion is gone. The store has two reads because the two
questions have two answers — `items(programDayId:)` is the authoring view and
shows inactive items, `activeItems(programDayId:)` is the rotation view.

**A per-session skip writes nothing.** Holding its rotation position *is* the
absence of a write; the only record is `workoutBout.wasSkippedForSession`.
`ExerciseAvailability.mutatesPool` says so, so a call site can't assume both
mechanisms touch the database.

### Fixed pre-existing

`BodyMeasurementTests.swift:24`'s hardcoded `[41...48]` column-count assertion →
`[41...49]`. The file's own comment says a human should edit that line when a
migration lands; it did, with five new columns in scope across two tables.

### Verification

`swift test`, full suite: **900 tests, 95 suites, 0 failures** (168.7 s). Up from
the 768/88 baseline captured before any of this work started; 132 new tests
across seven suites — 10 migration, 18 program+day, 26 pool, 25 rotation,
20 readiness, 18 progression, 15 graphs.

App target: `xcodebuild` against `Native/Almanac.xcodeproj`, scheme `Almanac`,
iPhone 16e simulator — **SUCCEEDED**, no errors, with the four new program
screens in the target; the warnings it printed are pre-existing and in unrelated
files (`SettingsView.swift`, `ActivityRingViews.swift`, widget code signing).

UI: `AlmanacUITests/TrainingProgramUITests` — full-file run
(`-only-testing:AlmanacUITests/TrainingProgramUITests`) — **3 of 3**, twice in a
row (2026-10-02).
Drives 7.1–7.6 and the 7.9 No-leg of the acceptance checklist; the rest of §7
stays UNRUN (UI). One harness bug found and fixed while driving: the tap after
`reveal` could synthesize against a stale frame from a lazy `List` and land on
the row below "Start workout"; the tap now waits for the revealed frame to
settle (`waitUntilSettled`). The app code was not at fault.

## 2026-09-30 — Circadian context stops being a table nobody reads; catalog follow-ups; the README stops lying

Three items, plus the housekeeping.

**Circadian context (Slice 5).** `circadian_context` was written on every
readiness cycle and read by nothing. BRD §6.15 names "comparable-day filtering
(Day Type + Circadian Context)" and §13.2 says insights use `contextType` as a
filter; neither happened. A week spent moving from nights to days was pooled with
a settled one, so the resulting `r` reported a schedule change as a relationship
between sleep and readiness. Correlations now drop transition days, say how many
they dropped, and drop the filter itself when it would cost more than half the
window. A date with no row is *not* a transition — the table is silent about days
the linking service has not reached, and treating absence as one would delete
every unlinked day from every correlation. Today now states the day's context in
words; `.unknown` renders nothing rather than a line, because with no shift
schedule there is no claim to make.

`InsightsQuery` takes a `Clock` like everything else in the package. It was
reaching for `Date()`, which meant the only way to test a *window* was to write
fixtures relative to whenever the test happened to run — and a first draft of the
new tests silently lost half its sample that way, which is documented in the
test file because the symptom was a sample size, not a date error.

**Laboratory catalog (Slice 7).** The five differential percentages and the rest
of the electrolytes are seeded. The percentages were *unseedable* until `TextFold`
was fixed: it erased `%` along with case and punctuation, so "Neutrophils %"
folded to the absolute count's own alias and all five pairs resolved to the
absolute. The catalog's ambiguity handling exists to stop the importer choosing
at random; the fold was manufacturing the ambiguity. The percentages are
catalogued and matchable but deliberately **not** in the CBC panel — a
laboratory printing percentages alongside absolute counts is printing a derived
view of the same numbers.

Import-job records are assessed and **parked**: they need a migration, a store, a
status vocabulary and a screen, and whether a failed import leaves a row saying
so is a product decision. Written up rather than guessed at.

**The README was wrong in three places** and said so with confidence. It claimed
the 48-table domain schema was "NOT BUILT — spec text unavailable" (recovered
2026-09-15, ~76 tables across 45 migrations), that `ReadinessCycle` was not
built, and that restore was "unimplemented by design" (`restoreBundle`
implements §16.2 behind a working screen). Its "what was deliberately NOT built"
and "when the spec arrives" sections were written for a spec that has since
arrived. Each row now names the type that implements it.

**`docs/acceptance-checklist.md` exists.** None did. It records what was driven
and marks the rest UNRUN — notification delivery, HealthKit on a device, backup
restore, two calibration labels needing seeded data. A step is PASS only if it
was driven; "the code looks right" is not a result.

**Two defects found while driving it**, neither caused by the readiness work:
the Timeline UI tests had been failing since 2026-09-26 because the shared
`reveal` helper's swipe did not scroll that particular `List` and a budget-only
loop reported "not there"; and the new reminders screen's switches reloaded
their state once on appear, overwriting a write that had just succeeded.

+65 tests. Full core suite: 622 tests, 77 suites, zero failures.

## 2026-09-29 — Notifications: §14 wired to something that actually fires

Slice 11. A previous note claimed items 3 and 4 were blocked on
`day_record.dayType`. That is wrong, and so is the follow-on claim that the
suppression path needs it. `dayType` is a column nothing reads or writes
(Migration014 creates it, and that is all), and `NotificationSuppressionMatrix`
gets its five axes from fasting sessions, shift occurrences, sleep episodes and
the open readiness cycle. None of them is `dayType`.

**What was actually true:** `Sources/AlmanacCore/Notifications/` held ~480 lines
of trigger arithmetic, suppression logic and settings storage with **no
production caller at all**, while `NotificationScheduler` took raw
`[DateComponents]` and repeated them forever. Every §14 rule was implemented and
unreachable.

- **`NotificationPlanner`** is the missing piece: §14.1's "on each scheduling
  run" as one pull-based call. It reads the two existing assemblers, the existing
  pure matrix, and the new per-type switch table, and returns a
  `[PlannedNotification]` snapshot. All nine types wired end to end.
- **Suppression is evaluated per notification, at that notification's own fire
  instant** — not once for the pass. This is the one design decision worth
  stating. `isNightShift` and `isPostShiftSleep` carry their own timestamps and
  are then correct for a notification 30 hours out: a night shift tonight
  suppresses tonight's bedtime and leaves tomorrow's alone. The other three axes
  cannot be evaluated at an arbitrary instant (their stores have no
  point-in-time variant) and carry this pass's value forward, which is §14.1's
  own rerun-on-every-event architecture rather than a shortcut around it.
- **`Migration045` adds `notification_rule`** (§5.25, the spec's default table
  verbatim). Its four `suppressDuring*` columns are created and **never
  written**: `NotificationSuppressionMatrix` is the authority, and a second
  writable copy of the same matrix is a rule that can disagree with itself.
- **`NotificationScheduler` is now a diff, not a nuke-and-refill.** It adds what
  is missing, removes only what the plan no longer wants, and never touches a
  request it did not mint. It also reports what the OS *refused*, which the old
  `try?` swallowed. And the old repeating `UNCalendarNotificationTrigger`s are
  gone — one-shot triggers are why a rule change can now unschedule anything.
- **Wired pull-based, deliberately.** §14.1 names four event kinds that should
  re-run the pass, spread across most of the app; wiring a call into each is the
  multi-site failure mode `docs/features/fasting.md` records ("the seventh path
  added later will be the one that forgets"). Instead the pass is idempotent and
  safe to call from anywhere, and it is called from the two places all four
  events pass through anyway: the app's foreground handler (already the home of
  `ensureCache`/`ensureToday`, and suhoor/iftar triggers depend on both) and the
  settings screen after a switch. A missed call site costs one pass of
  staleness, not a wrong schedule.
- **Water has two switches and needs both** — the §5.25 default and the
  pre-existing hydration toggle. A user who turned water reminders off must not
  keep getting them because a schema default disagrees.
- **`NotificationSettingsView`** gives every type an individual switch (BRD
  §6.14's "all types individually toggleable") and states the real queued count
  from the OS rather than recomputing a possibly-stale plan.

**Product decisions not taken, on purpose:** no permission prompt on launch (a
prompt must follow a deliberate tap); the pre-workout snack suggestion is
delivered immediately, not scheduled, because §14.2 gives it no lead time; and
per-type user-set *times* exist in storage but only water's interval is exposed
in the UI, which is a follow-up rather than a claim.

**Not verified:** whether a notification actually arrives at a chosen minute. That
is device-only and is listed unrun in `docs/acceptance-checklist.md` rather than
ticked on the strength of the code looking right.

+39 Swift Testing tests (11 rule store, 28 planner) and 5 UI tests, all green.

## 2026-09-29 — The sleep stages finally reach the readiness score

First of readiness integration's five gaps (§9). Closes the one the handoff
called the highest-value item in the remaining set.

**A fifth of every readiness score has been the number 50, reached by
accident.** §9.1 gives sleep quality a 20% weight; §9.2 says "if no stage data →
50, flagged as missing". The 50 was the score on every run — not because stage
data was missing, but because `ReadinessModel.refresh()` built `ReadinessInputs`
without the `stages` field at all. The flag was honest about it
(`.sleepQuality` was reported missing, and confidence was depressed to match),
but the number was still shown to the user with the same weight as the
four-fifths that had actually been measured.

The samples were never missing. `health_sample` has held them since the sleep
bridge landed, and `SleepClassifier` has been reading them since. The only
reader of the stage rows was `private` to `SleepEpisodeHealthBridge` — the data
was in the database, being used by a different feature, one function away.

- **`SleepStageSampleStore`** is that read promoted out of the bridge, with a
  windowed form beside the load-everything form re-classification needs. The
  "a row whose `unit` is not a `SleepStage` is not a sleep sample" rule is a
  contract with `HealthKitProvider`; two readers of it would be two places to
  disagree about it. Same reasoning as the bridge not re-implementing
  `HealthSampleStore`'s persistence — a wrong-shaped duplicate that was once
  built here and deleted.
- **`SleepStageBreakdownReader`** turns one episode's window into the §9.2
  split, read from the *same* primary episode the duration comes from. A
  duration from one night and a quality from another would be a score about no
  night at all.
- **No asleep stage in the window is nil, not three zeros.** A breakdown of
  zeros would score 0 and tell the user they slept terribly on a night the app
  never observed — R-RDY's forbidden substitution, reached by the opposite
  route. Manual entries and devices that report no stages keep taking §9.2's
  documented 50-with-flag path, which is the correct answer rather than a
  workaround.

**This changes scores users have already seen.** Any night with HealthKit stage
data now moves the sleep-quality term off 50, usually *upward* — a real night
outscores neutral, so most scores rise. Historical `readiness_record` rows keep
their stored score (§9.9 forbids silent rewrites), so only newly-computed
scores move, but a user comparing this week to last will see a step that is a
correction rather than a change in their recovery. Recorded here because it is
not a bug fix that can hide.

**Still open, in the other four gaps:** `readiness_baseline` is still orphaned
(Migration014's table has no store, writer or reader, and
`ReadinessModel.recentBaseline` is still a naive raw-row average that always
yields `.general`); 2 of 9 `ReadinessContext` fields are wired, so §9.7's "Day X
of 21" is still unreachable; `CycleBoundaryCalculator.window(...)` is still
test-only; `ContextEvent` tags are still written by `ContextTagsView` and read
by nothing. `day_record.dayType` is still never set to `religious`, which still
holds back §9.8's Ramadan baseline and Appendix B's suppression matrix.

XCTest 374 (1 skipped), up from 364 — the ten new tests. Swift Testing 580 in
73 suites, unchanged by this work. One pre-existing failure in that Swift
Testing run (`BodyMeasurementTests`, which hardcodes the applied-migration list
and is red against the uncommitted Migration045) is not from this change.

## 2026-09-29 — Religious fasting orchestration: the dry-fast break rule and a lost night window

Closes the Tier-0 Slice 6 bug. Two independent defects, one of which the code
had explicitly refused to guess at and one of which was quietly locked in by a
test that asserted the broken behaviour was correct.

**Any intake ends a religious dry fast, water included** (the owner's call).
§11.1's "water never breaks a fast" is written for intermittent fasting and
says nothing about a *dry* fast; the service said so in a doc comment and left
it open. A dry fast that was drunk from is not a fast that was kept, so the
session now **ends** and records the real duration — hours genuinely fasted
before the intake are not erased. It is `end`, not `invalidate`, for that reason.

- `FastingSessionStore.recordIntake(at:)` owns it, deliberately **not** a flag on
  `recordNutritionEntry`, which keeps §11.1 byte-for-byte intact and still
  returns `.noOp` for `calories == 0`. A test pins the boundary: water does not
  break an IF session. Getting this wrong would have broken intermittent
  fasting for every user.
- `FastingAwareHydrationLog` wraps it, same shape and dependency direction as
  `FastingAwareNutritionLog` — Hydration does not learn that Fasting exists. It
  writes the drink first and unconditionally; a broken fast is still a real
  thing the user drank.

**The night window was lost for the whole day.** Window creation sat inside the
session-creation branch behind a `nextDayFajr != nil` guard, while every later
call returned earlier at the already-exists branch. The first `ensureDay` of a
day routinely runs before tomorrow's Fajr is cached, so the session was created
with no window and the window was then unreachable for the rest of that day —
leaving every suhoor and iftar entry in it unassigned. `ensureDay` now ensures
the window on every call, idempotently by lookup, because
`nutrition_window` has no uniqueness constraint on (date, windowType). A test
had asserted the old behaviour; it now asserts recovery and no-duplication.

**Still open, and it is a product decision rather than a bug:**
`day_record.dayType` is never set to `religious`. Nothing types the day, only
the session. The Appendix B suppression matrix and the §9.8 Ramadan readiness
baseline both read `dayType`, so Slice 11's notification scheduler and the
readiness integration are each only half-buildable until this is answered. It
does not block the work above, which is a property of the session.

**Not wired:** the four hydration write paths (`HydrationModel.log`,
`HydrationModel.logDrink`, the widget's `LogWaterIntent`, the Activity Rings
day-detail hydration editor) still write through `HydrationStore` directly, so
the break rule is not yet reached from the running app. The rule is correct and
tested; the call sites are the follow-up. Recorded in `docs/features/fasting.md`
rather than left to be rediscovered.

Full suite: 541 Swift Testing tests in 71 suites, zero failures (up from 517).

## 2026-09-29 — Insights gets real queries

`CorrelationEngine`, `CorrelationPairStore`, `TrendSnapshotStore`,
`AchievementEngine` and `AchievementRecordStore` had been complete and tested
since Slice 10 with **zero app consumers** — so `correlation_pair`,
`trend_snapshot` and `achievement_record` were permanently empty tables. The
engines were never the gap. The line between the tables and the numbers was,
and nothing drew it.

- **`InsightSeriesBuilder`** reads nine metrics out of the real stores.
  `InsightMetric` states per metric how several entries on one day become one
  value, because that is the part a reader has to trust: four drinks sum to a
  day's hydration, two mood check-ins average to a mood, and getting it wrong
  produces a chart that looks fine and means something else.
- **`InsightsQuery`** runs all three engines and persists what they say. There
  is no nightly batch — the horizon is a caller concern the engine header
  already states, and a stored number nobody refreshes is worse than none.
- **`InsightsView`**, linked from Trends. Trends stays as the one metric worth
  plotting; Insights is the read-across surface.

**The honesty rules are in the copy, because that is where a guardrail about
what a screen may say has to be satisfied.** Every trend states how many days of
the window were actually recorded. A short pair says "Not enough paired days —
3 of 14", not a dash and not a number. The direction word is "Higher together",
never "causes". The Associations footer states the caveat in full.

**Three defects fixed:**

- **`CorrelationPairStore` claimed "unordered" and was ordered.** `("sleep",
  "readiness")` and `("readiness", "sleep")` were two rows holding the same
  number. Both metrics are now sorted into a canonical order in and out, and
  `allPairs()` reads only canonical rows so a pre-fix database reports each pair
  once.
- **`TrendDirection` round-tripped by accident.** `TrendSnapshotStore` wrote
  `String(describing:)`, which happened to produce `"up"` and matched the reader
  by luck; a case rename would have silently written a value nothing could read
  back. It has a `String` raw value now.
- **`CorrelationResult` and `TrendSnapshot` were `Equatable` but not `Hashable`**,
  so neither could ride in a `Hashable` result type.

**Five of the nine achievement inputs are constants, each for a stated reason.**
No step target, no high-load threshold, no Diet Profile, and — the one the
engine's own header flags — no decided definition of a perfect log. So
`.perfectLog` is never awarded and a test fails if it ever is. The other four
badges do appear. Recorded in `docs/features/insights.md` §5.

**Not built:** Spearman and p-values (Pearson is the concrete default the
handoff proceeded on, and both need a decision about what the app claims
statistically); context tags as a correlation input (sparse by nature, would sit
at "insufficient" permanently); charts for anything but readiness.

Full suite: 364 XCTest (1 skipped) + **541 Swift Testing** (up from 517), zero
failures. UI suite: **46 tests, all passing** (5 new). Simulator build clean.

## 2026-09-28 — Training history, bout editing, and templates

Closes all three gaps `docs/features/training.md` §2 listed, and the
`PrescribedWorkoutStore` surface that had been in `AlmanacCore` since the
schema pass with no way to reach it.

- **`TrainingSessionReviewView`** — past sessions over 7/30/90 days, each with
  its bouts. The Training screen showed today only.
- **Bouts are editable.** Until now a bout could be logged or deleted but never
  corrected. `updateActuals` writes **only the actual columns**: a prescription
  is what was planned, and an editor offering it would make "I had meant to do
  four reps" indistinguishable from "I did four reps".
- **A HealthKit-derived session is read-only and says so.** Editing figures that
  came from a watch writes a number the next sync overwrites.
- **`TrainingTemplateView`** — list, create, edit, discontinue. A template is a
  name plus a container shape, and the screen says so rather than implying an
  exercise-level editor that would rewrite history.
- **`TrainingContainer` (ten) and `PrescriptionKind` (twelve) are now enums.**
  That is what lets a bout editor offer only the fields a type calls for — a
  timed hold has no load in it. Both transcribe lists that also exist as arrays
  on `Migration016_TrainingSchema` and as SQL CHECK constraints, so tests assert
  the enums equal the arrays; a silent drift would otherwise surface as a
  runtime constraint violation at the insert.
- **`containerType` is validated against the enum**, so a bad value is a typed
  error naming it rather than a raw SQLite CHECK failure at the insert.
- **`WorkoutSessionStore.sessions(from:to:)`** — a review screen otherwise asks
  per day and stitches, which is how one ends up showing fewer days than it
  claims when a single query throws.

**A bug I introduced and fixed before it shipped:** the bout editor's
`int`/`double` helpers returned nil for an unparseable field, so mistyping a
load would have silently blanked it — the figure would become "not recorded"
with no trace. Every field is now validated before anything is written, and a
bad one names itself.

**A pre-existing test bug, fixed:** `BodyCircumferenceUITests` read a live
switch through an element captured *before* `app.terminate()`, so its "must be
0 after toggling off" assertion was reading a snapshot of a dead hierarchy and
could pass or fail on whatever the previous run had left. It now re-queries
after the relaunch.

**Still not built: "apply template to a session".** There is nothing in the
store to apply — a template is a container shape and bouts come from logging —
so it needs a product decision about whether a template prescribes exercises or
only the shape of a session. Recorded, not guessed.

Full suite: 364 XCTest (1 skipped) + **517 Swift Testing** (up from 503), zero
failures. UI suite: **42 tests, all passing** (6 new). Simulator build clean.

## 2026-09-28 — One timeline, and a screen that reads it

Closes the Timeline item. `Timeline` — the generic merge type, the one that
promises a total order over anything a module provides — had **no consumer at
all** outside tests. `TrackingTimeline` was reachable only from the Activity
Rings day editor, which is a *correction* surface: a place to fix a value, not a
place to read a day back. Every other screen assembled its own record list by
hand, which is why Today's record names four domains and knows nothing about the
other eight.

- **`DayTimelineView`** (Modules → Records → Timeline) reads a logical day, or
  seven or thirty of them, in occurrence order. Ruled rows and no prominent card:
  the day is the object and it is the heading, so a filled panel would be
  spending the emphasis on decoration.
- **Nothing is grouped by domain.** The merge type's whole argument is one total
  order over occurrence time; grouping by module would throw that away in favour
  of a list that reads like the hand-rolled ones it replaces.

**Two real defects fixed rather than worked around:**

- **`items(from:to:)` and `items(for:)` were two code paths answering the same
  question, and disagreed.** The range query composed only the three
  table-backed providers (lab, nutrition, hydration); the day query appended the
  health-domain one. So a range silently omitted sleep, workouts, mood,
  soreness, vitals, body composition and custom measurements — and the
  deficiency was invisible, because nothing called the range form. There is now
  one implementation, `items(fromDay:toDay:timeModel:)`, and `items(for:)` is a
  one-day call to it. `TimelineTests` pins that a one-day range and the one-day
  call return identical ids, and that a half-open day range counts no day twice.
- **`items(from:to:)` is now documented as the lesser timeline** rather than
  left looking equivalent. The health-domain provider places entries by *logical
  day*, and a pair of UTC instants does not determine a set of logical days
  without a timezone — picking one would file a 03:00 entry under whichever day
  the wrong zone decided, which is the exact confusion §7.2's night window
  exists to prevent.

**`TrackingTimelineItem` now carries `occurredAt` and `basis`.** A reading
surface needs the time of day on every row, and the item handed back rendered
strings with no timestamp in them. The first attempt recovered the time by
matching on a hand-built id string (`"domain-table-id"`) — which any change to
a provider's naming would have silently broken. Carrying the field is one line
at the mapping site and both new fields default, so the existing calendar
compiles unchanged.

**Also corrected:** `docs/architecture/health-data-foundation.md` §7.1's
`TimelineProviding` sketch had a `static` domain, `Date` bounds and a
`db:` parameter, none of which match what was built. The doc now shows the real
signature with a table saying which was right and why.

Full suite: 364 XCTest (1 skipped) + 503 Swift Testing, zero failures. UI suite:
**37 tests, all passing** (3 new). Simulator build clean.

## 2026-09-28 — Digestion quick entry

Closes the second of the two item-9 gaps. `DigestionStore` and `UrinationStore`
had been complete and green since 2026-09-16 with **zero** `Native/` call sites —
a user could not record a bowel movement or a urination at all.

- **Quick Log now offers Digestion**, and the sheet covers both kinds: a
  segmented control, time, Bristol type, stool colour, the symptom flags, notes,
  and today's entries with swipe-to-delete. Saving returns to Quick Log rather
  than closing it, matching that sheet's existing convention.
- **The scale and the chart are pushed screens, not inline lists.** Seven
  described rows plus eight grade rows in the log form would push the colour
  field, the symptoms, the notes and today's list most of a screen down — and
  this is a *log* form, so everything below the fold is something the user came
  to do. A seven-option wheel would have hidden six of seven behind a spin,
  which defeats the point of a reference scale.
- **No advisory is shown, and the BRD says why.** §6.3's wording "requires
  clinician review before App Store release", so `clinicianEscalationLevel` stays
  NULL and the screen interprets nothing: no colour is called concerning, no
  grade is called dark, blood is the fact the user recorded. The escalation rule
  the BRD *does* give ("amount/type of blood, black stool, …") is keyed on values
  this screen stores precisely so a future rule can read them.
- **Only two of the eight urine grades are named** — 1 pale, 8 dark brown, the two
  the type's own doc comment states. A plausible ladder of eight colour
  descriptions would be eight clinical claims invented here, a clause earlier
  than the clinician review §6.3 is held back for. A test fails if anyone names
  one.
- **`urgency` is not offered.** A bare `Int?` that neither the BRD nor the spec
  gives a scale for; a picker would be inventing the scale.
- **The digestion ring's fill rule was not invented.** BRD §350 says it is
  "explicitly undecided … there is no universal daily bowel-movement target", so
  `.fillRuleUnavailable` is the spec working, and the Settings toggle turning on
  a ring that then says so is correct rather than a bug.
- **Store gaps closed:** `logs(from:to:)` and `delete(id:)` on both stores;
  `StoolColor` as a closed enum; `BristolType.displayName`/`summary`/
  `accessibilityLabel`; `UrinationColorGrade.displayName`/
  `accessibilityLabel`. Colour is offered as **text, never a swatch** — BRD
  §6.3's "never rely on colour alone" means a colour chip relies on colour
  alone.

**Open item:** the Attributions screen does not credit the Bristol scale, and
`BristolType`'s seven names are reproduced published wording (Heaton & Lewis
1997). Recorded in `docs/features/digestion.md` §5.

Full suite: 361 XCTest (1 skipped) + **503 Swift Testing** (up from 492), zero
failures. UI suite: **34 tests, all passing** (7 new). Simulator build clean.

## 2026-09-27 — Supplements and context tags get screens

Closes the two rows `docs/features/body-composition.md` §1 still listed as
"Not built". `SupplementPlanStore`, `SupplementLogStore` and `ContextEventStore`
had been complete and green since 2026-09-16 with **zero** `Native/` call
sites — a user could not create a plan, log a dose, or record a confounder.

- **`SupplementView`** puts today's adherence in the one prominent card and the
  plan list and 14 days of history in ruled sections beneath. Tapping a plan
  logs it, tapping again removes it.
- **`ContextTagsView`** is day navigation, the ten known tags, notes and 30 days
  of history — and deliberately has **no prominent card**, because nothing on it
  is a measurement. The accent means Almanac recorded something, so it is not
  available on a screen of tags.
- **A discontinued plan stays listed.** It is deactivated rather than deleted so
  `supplement_log` keeps a real plan to point at, so showing only active plans
  would make a discontinued supplement look deleted.
- **The adherence headline refuses to average a fact into a guess.** A
  `custom` frequency's schedule is in the plan's own notes, so a list
  containing one reports no count rather than dividing by a denominator it
  invented.
- **Saving a context day edits rather than appends.** `context_event.date` has
  no unique index, and `event(for:)` returns only the first row, so inserting
  unconditionally would silently hide half of what the user just said. Update
  when the day has a row, insert when it does not. **The store's tolerance of
  two rows for one day stays an open question** — fixing it needs a migration
  and a decision about existing duplicates.
- **The context save control is keyed to "differs from stored", not to "has
  something to write".** Those are different conditions, and conflating them
  makes it impossible to *clear* a day: a day carrying a tag has something to
  write the moment that tag is removed, and an emptiness guard would disable
  the only control that could record it. **This was a real bug, caught by the
  UI test** — the first version of the screen could only edit a day that already
  had a row, so it could never create the first one and was unusable.

**Store gaps closed**, all of them behind §5's own "plan CRUD" description:
`SupplementPlanStore.allPlans` and `.update`; `SupplementLogStore.setTaken`,
`.delete` and an all-plans `entries(from:to:)`; `ContextEventStore.events(from:to:)`
and `.updateNotes`. `update` deliberately does not touch `isActive` or the
reminder — both have their own single-purpose methods, so an edit form cannot
clear a reminder by omitting it.

**The UI tests need a wiped data container.** The suite shares one installed
app, so a row written by one test is still there for the next and three tests
were rewritten after failing on their second run. `xcrun simctl uninstall <udid>
com.almanac.personal` before a run is a prerequisite, not a nicety.

Full suite: 361 XCTest (1 skipped) + **492 Swift Testing** (up from 481), zero
failures. UI suite: **27 tests, all passing** (6 new). Simulator build clean.

## 2026-09-27 — The night nutrition window resolves entries

Closes item 5 of the still-open list in `docs/features/fasting.md`.
`nutrition_window` rows had been created and looked up correctly since
2026-09-17, but §7.2's assignment rule had no column to land in and no
code to run it, so a 03:50 suhoor entry was resolvable in principle and
recorded in nothing.

- **`Migration044`** adds `nutrition_window_id` to `nutrition_log` **and**
  `hydration_log`. §5.11 gives the column on the first and §5.13 does not
  on the second, while §7.2's own prose says "any NutritionLog *or
  HydrationLog*". Both get it — a dry fast is opened by water. The
  contradiction and the decision are in
  `docs/architecture/spec-reconciliation.md` §8. The name is
  snake_case to match the two tables it sits in, not §5.11's camelCase:
  half-applying the §3 naming split in one new column would be worse than
  either convention.
- **`NightNutritionWindowAssigner`** is the rule. Matching is by
  timestamp containment, never by logical day — between 04:00 and Fajr the
  two disagree (at 04:10 Riyadh on D+1 the logical day is already D+1
  while the fast is still running) and the window wins. The spec's own
  03:50 example is a case where they *agree*, which makes it the weaker
  test; the one that pins the rule down uses 04:10.
- **Coarse timestamps are left unassigned.** A `"2026-09"` value spans
  the window on paper but has no instant for `Maghrib(D) ≤ timestamp <
  Fajr(D+1)` to be true of. Unassigned is the honest value; assigned
  would be a guess reading as a fact.
- **Every assignment writes, including to NULL.** Editing an entry out
  of the window clears it. A conditional `WHERE nutrition_window_id IS
  NULL` would be the cheaper statement and would make the column a record
  of the first resolution rather than the current one.
- **`nutrition_window.windowType` is now `NutritionWindowType`**, not a
  raw `String`. Its `standardLogicalDay` case is reachable and never
  written: the spec names it and then gives no rule for creating one, and
  inventing one would be a product decision nobody has made.
- **`NutritionWindowStore.rowToWindow` now throws** instead of returning
  nil for an unreadable row. A silent skip would drop a window from the
  list the rebuild walks, and its entries would then be written as NULL —
  a wrong answer that looks right.

**Rebuild.** `assignUnassigned()` is spec line 1942 step 6d ("Rebuild
nutrition_window assignments for religious fast days"). It **clears each
window's assignments before refilling it**, and that order is the whole
correctness point: an entry that a recalculated boundary pushed out of a
window is not findable by querying the window's *new* span, because by
definition it is not in it. Only asking which rows name the window finds
them. `assignUnassigned(inWindow:)` is the scoped form, called from
`ReligiousFastingService.ensureDay` so that marking a day as a fast
retroactively claims an iftar the user logged before marking it.

**The cost worth naming.** The assigner is called at six write paths
(`NutritionModel.log`, `HydrationModel.log`, `HydrationModel.logDrink`,
both Activity Rings day-detail editors, the widget's `LogWaterIntent`),
because every one of them sets the timestamp the rule is defined against.
That is discipline, not design — the seventh path added later will be the
one that forgets and nothing enforces it. A whole-history rebuild is the
backstop, and **it is not yet called from the restore procedure**, which
is not built at all.

**The read side does not exist.** No screen anywhere displays a night
window's contents. The column is written and correct; showing "what you
ate during the fast" is the user-visible half of §7.2 and is not this
item.

Full suite: 361 XCTest (1 skipped) + **481 Swift Testing** (up from 465;
+16 new), zero failures. Simulator build (iPhone 16e, Debug) clean.

## 2026-09-27 — Body composition writes back to HealthKit

Closes the "outbound half" §4 of `docs/features/body-composition.md` describes
and leaves open. `pendingHealthKitWrite` (Migration018) had been written by no
code and read by no code, `HealthKitProvider.write` refused every body domain,
and the three metrics the feature doc calls "bi-directional (read ✅ write ✅)"
were read-only in fact.

- **`BodyCompositionWriteback`** is the outbound drain, beside the inbound
  bridge in `BodyCompositionMeasurementHealthBridge.swift` and sharing its
  metric table. `BodyCompositionMeasurementStore.log` sets
  `pendingHealthKitWrite = 1` — the only writer of the column — and
  `HealthModel.syncNow()` drains it next to the waist writeback.
- **The queue is the flag, not `healthKitUUID IS NULL`** (which is what the
  waist writeback uses). Only a metric HealthKit can hold is ever flagged:
  `skeletal_muscle_kg` and `visceral_rating` have no type at all (Appendix C),
  so inferring the queue from a null UUID would leave those rows retrying a
  write that can never succeed.
- **The two directions do not agree on the unit string, which would have been a
  silent failure.** The store spells body fat `pct` (the BRD's own word);
  HealthKit's label is `%`, and `HealthKitProvider.write` compares the unit
  against its own table and throws `unavailable` on anything else. So `outbound`
  carries metric, domain, store unit *and* health unit, and a test asserts its
  key set equals the inbound bridge's.
- **A row in a unit its metric is not stored in is left queued, not relabelled.**
  A `weight` in pounds sent under HealthKit's `kg` is a wrong number wearing a
  right label. Stays flagged, so the mismatch shows in the row rather than
  being silently dropped or pushed wrong.
- **The echo needed a guard, and it was a latent crash rather than a duplicate.**
  `healthKitUUID` is a column-level `UNIQUE`, but the upsert's conflict target
  is the *partial* index on `(source, healthKitUUID)` — so an inbound sample
  carrying a UUID a manual row already holds is not caught by the upsert and
  fails outright with `SQLITE_CONSTRAINT`. The bridge now skips it, mirroring
  `BodyMeasurementHealthBridge`'s guard. `HealthKitProvider` already drops its
  own exports by bundle identifier, so this is the belt to that braces.

Two defects found and fixed in the code this touches:

- **`BodyMeasurementWriteback.drainOnce` threw out of its loop on the first
  failure,** so one unwritable waist row stopped every row after it from ever
  being tried, and it reported the wrong thing — a single row's failure looked
  like the whole drain's. Now every row is attempted and the first failure is
  rethrown once the loop finishes: the row stays unmatched by the query (which
  is the retry) *and* `HealthModel` still surfaces the error to the user. Its
  existing test asserted the throw and the pending row; both still hold, which
  is why the fix is invisible to it.
- **`HydrationWriteback` had a per-row `catch` and so was silent** about a
  completely failed drain, while the two other writebacks threw. Not changed
  here — it is a third behaviour, and picking one is a product call about
  whether a silent retry or a visible error is wanted. Flagged rather than
  guessed at.

Also generalised, and worth naming because it changes another module's
behaviour: **every originated write now carries `HKMetadataKeySyncIdentifier`**
rather than the waist alone. A retried write is now the same sample instead of
a second one for water and all three body metrics too — hydration had the same
duplicate-on-retry exposure the waist comment warned about, and the fix is the
same line of code, so leaving body composition as the only metadata-free domain
would have been incoherent. `storedWaistIdentifier` is now
`storedIdentifier`, and the returned identifier is the *stored* sample's for
every writable domain (an equal-version retry is ignored by HealthKit, and
returning the fresh object's UUID would record a UUID that does not exist).
`HealthKitProvider.writableDomains` is the single list that now drives both the
write guard and the share-permission request, so adding a writable domain is
one line rather than two that must agree. `NSHealthUpdateUsageDescription` now
says "body measurements" instead of naming only water and waist.

**Verified:** `swift test` — 361 XCTest (1 skip) and 465 Swift Testing, 0
failures, including 12 new cases in `BodyCompositionWritebackTests`. The Debug
simulator build succeeds with no new warnings.

## 2026-09-27 — Nutrition derived values (`edibleGrams`) and `NutritionSummary` coverage

Closes to-do #17 and the "Still open" item 2 of the 2026-09-15 nutrition port.
Two independent gaps, both of which had been left open because the work depended
on reference data that now ships.

- **`EdibleYieldCalculator`** (`Sources/AlmanacCore/Nutrition/NutritionEdibleYield.swift`)
  is the port of the source branch's `edibleGrams`, which the 2026-09-15 pass
  skipped because it needed CoFID's per-reference-food edible proportions (the
  2,887 rows imported 2026-09-25).
- **The result is a four-way split, not a `Double?`** — `.known` / `.notAnalysed`
  / `.unstated` / `.unusable` — because the data forces it. CoFID states a
  proportion for 2,887 of 8,354 foods, so the common case is *nobody stated
  one*; an optional would put that next to a real "not analysed" and invite both
  wrong defaults. `factor?.value ?? 1.0` invents "nothing is discarded" for ~65%
  of the catalogue; `?? gross` reports a gross mass as an edible one. Both return
  a plausible number for a food the data says nothing about, which is the same
  rule `NutritionTotals.incompleteNutrients` already follows one step later.
- **Out-of-range is refused, not clamped.** A proportion outside `(0, 1]` is
  `.unusable`, kept separate from `.unstated` because the data *claimed*
  something and the fault is the bundle's. A bad input mass (NaN, infinite,
  non-positive) throws `NutritionError` instead, because that is the caller's
  mistake, not a gap in the data. Verified empirically along the way: SQLite
  stores `Inf` as REAL but converts `NaN` to NULL, so a NaN proportion is
  indistinguishable from "not analysed" at the storage layer — the test list
  uses `[1.5, 0.0, -0.2, .infinity]`.
- **A dish's own `nutrition_dish.edible_proportion` wins** over the bundle's
  `nutrition_food_factor` row for the same food: it is the figure a person
  decided, and `NutritionDishEditor` is the only writer of `nutrition_dish`.
  `EdibleYieldCalculator` is a `struct` taking `Database` and builds its own
  `NutritionCatalog`/`NutritionDishEditor`, because both collaborators' `db` is
  `private`.
- **`grams(fromVolumeMillilitres:for:)` applies `specific_gravity`,** and is
  documented as the *only* volume case that reaches it: a household measure is
  already converted to grams by `nutrition_portion.gram_weight` via
  `NutritionCatalog.grams(of:amount:unit:modifier:)`, so mL typed by a person is
  the sole remaining case.
- **No production caller, stated rather than glossed.** Nothing in the device
  schema has a slot for an as-purchased mass — `nutrition_log.grams` is the mass
  the food was eaten at, and no screen asks anyone to say "this is raw". The
  missing piece is the column, not the calculation; flagged in
  `docs/features/nutrition.md` §10 rather than left for someone to discover.
- **`NutritionSummary` had no coverage at all** — `DayEnergyTests` builds
  `NutritionTotals` by hand, so the arithmetic that produces them was untested.
  `NutritionSummaryTests` (14 tests) runs the real read against a real catalogue
  and pins the four ways a total declines to be complete, each a field the UI
  must be able to show: an unstated amount is named not zeroed, an unknown food
  is named by ref, a `not_analysed` nutrient marks the day incomplete, and a
  nutrient only some meals report is absent rather than smaller. Also pinned: a
  nutrient reported on two bases is dropped rather than added, an energy figure
  names the routes it came from (`energyBases`), and a soft delete removes a meal
  rather than zeroing it.
- **The logical-day test caught its own premise, not the code's.** It first
  asserted that `2026-09-16T21:30Z` belongs to the 17th in Riyadh. It does not:
  Riyadh is UTC+3 and a day opens at 04:00 local, so the 17th runs
  `01:00Z → 01:00Z` and that instant is 00:30 local — before the boundary, so day
  16. Rewritten to be genuinely two-sided: `2026-09-17T00:30Z` → day 16 and
  `2026-09-18T00:30Z` → day 17, each of which a naive `yyyy-MM-dd` range files
  under the *opposite* day, asserted on both totals and on which food landed
  where.
- **Verified:** `swift test` — 361 XCTest (1 skip) and 453 Swift Testing, 0
  failures. No UI surface changed, so no simulator build was needed for this
  item.

## 2026-09-27 — One rule weight, and the primitive that owns it

Closes the finding `1435669` recorded against `AlmanacPalette.divider` as a known
inconsistency rather than fixing. `docs/ui/measure.sh` reported rules at **0.33pt, 0.67pt
and 1.00pt on the same screen**, in both appearances.

- **The three weights had three unrelated causes**, which is why it survived review —
  each was individually defensible and only the screen they shared was wrong:
  `Divider().overlay(divider)` drew the *system's* idea of a hairline (0.33pt, 14 sites);
  `AlmanacCard`'s 1pt stroke was *centred on the shape's edge*, so half the rule fell
  outside and antialiased across two device-pixel rows (0.67pt, every card in the app);
  and `Rectangle().fill(divider).frame(height: 1)` is 1pt by construction (3 sites).
- **`AlmanacRule`** is now the only thing that draws a rule, at
  `AlmanacMetrics.ruleWeight`. All 19 hand-drawn sites are gone. `Divider()`'s weight is
  a system implementation detail that has changed across OS releases, so a structural
  device whose weight is not in the token file is not one the design system controls.
- **1pt, not a true device-pixel hairline.** 1/3pt is one device pixel at 3x but half of
  one at 2x, so the app's structural device would change weight with the display it
  shipped on. 1pt is also the weight all three existing intentions already asked for.
- **The card border is inset by half its width** so the whole 1pt lands inside the shape
  rather than straddling it. Visually a half-pixel; it is the difference between a border
  that measures 1pt and one that measures 0.67pt. `AlmanacSecondaryButtonStyle` had the
  same stroke and is fixed the same way.
- **`ExerciseProgressView`'s empty state was a hand-rolled `AlmanacCard`** — same padding,
  background, clip and border, written out a second time with the un-inset stroke. It is
  an `AlmanacCard` now.
- **Vertical rules included.** `TrendsView`'s two summary-cell dividers had the same
  defect, so `AlmanacRule` takes an `axis`. **Left alone: `TrendsView`'s `AxisGridLine`** —
  a chart gridline belongs to Swift Charts, scales with the plot, and is not a structural
  rule.
- The `62` indent on metric-list rules is now `AlmanacRule.metricTextInset`, named and
  documented, rather than a literal a caller had to know the cost of.
- **Verified:** the Debug simulator build succeeds; **21/21 UI tests pass**; and
  `measure.sh --capture` reports **one weight, 1.00pt, and "no findings"** on all three
  captures (light, dark, largest Dynamic Type) — the check that was failing is the
  evidence the fix landed. `swift test` could not be run to completion: an unrelated
  parallel session was writing `NutritionEdibleYield.swift` and `EdibleYieldTests.swift`
  into this tree during the build (`input file … was modified during the build`). This
  change touches no file under `Sources/` or `Tests/`.

## 2026-09-27 — Navigation decisions closed; no code changed

The tab-bar roster and the quick-log button's default target had been carried as
an open decision out of the UI Design Reference v1.0 (§5, §11). Both are now
closed. **No source changed in this pass** — the shell was already built in
`1c9a003` and refined in `837e21f` / `4ca270c`; what was missing was the record.

- **Roster: Today, Trends, Modules** (`AlmanacApp.swift:4-8`), the Design
  Reference's own two placeholder tabs plus the module anchor. The rule that
  picks it: **a tab slot is earned by daily-use frequency, not build state and
  not domain depth.** Laboratory — the deepest, most differentiated module — is
  off the bar because it is used per blood draw. Hydration is off it because the
  quick-log action already owns that verb.
- **Modules stays a tab, not a side drawer.** The Design Reference specified a
  drawer; the shell shipped a tab. `ModulesView` is already an app-owned
  `NavigationStack` index, so the drawer's content is in place and only the
  gesture is missing. A drawer would add a full-screen gesture to arbitrate
  against every scroll view in a shell already reworked once for exactly that
  class of bug (`AlmanacApp.swift:80-83`).
- **The quick-log button has no single default target.** It opens the
  `QuickLogView` console: water is the one-tap path (250 / 500 / 750 mL inline),
  Food, Training and Body open focused sheets. Declining to name water as *the*
  target costs water nothing, and a single-target button would push food — a
  three-times-a-day action — to two taps.
- **Supersedes spec §2 D-3** ("5-tab bar: Home · Log · Train · Insights ·
  Settings"), a pre-spec owner decision. D-4 ("Log tab scope: all input modules")
  is partially honoured — the console offers four of them; the rest are in
  Modules. Both recorded, not silently dropped.
- **The build-state table in the decision reference was stale** and is corrected
  in the record: Nutrition, Trends, Training and weight were all listed as
  unbuilt, and all four are built. The sequencing question that table supported
  dissolved with it.

Full reasoning, including what was deliberately not built and why, is in
`docs/features/owner-decisions-2026-09-26.md` §13-15.

## 2026-09-26 — Technical Spec committed to the repository; OI-4 closed

The spec was not lost, but it was not **in** the repository either: it was kept
outside it, at a path recorded as `../almanac-tech-spec-v1.0.md`. That
reference had two faults — a separator typo (`v1.0` for `v1_0`) and a location
that did not exist — so every check for it failed and the file was reported
absent. Both documents are now committed under `docs/`:

- `docs/almanac-tech-spec-v1_0.md` — the 96 KB, 2,300-line original of
  2026-08-05, authoritative per `docs/architecture/spec-reconciliation.md` §1.
- `docs/almanac-technical-spec-v1_0.md` — the 31 KB reconstruction of
  2026-09-15, kept for the record; it does not supersede the original.

Both were copied byte-for-byte from the owner's files and verified by SHA-256.
`Migration014`'s header and `spec-reconciliation.md` now point at the in-repo
paths.

**This closes OI-4** on the body-measurements module. §6.1 and Appendix C list
seventeen HealthKit types and none is `waistCircumference`; the body types
present are `bodyMass`, `bodyFatPercentage` and `leanBodyMass`, all
bi-directional. Waist is unmodelled, not deferred, so the spec needs a
`waistCircumference` row and the circumference build already exceeds it. Three
further divergences were found and recorded in
`docs/features/body-measurements-implementation.md`: no `body_measurement`
table exists in either spec, §6.1's contextual-permission rule is not how this
app asks, and the spec's generic `custom_measurement_log` is not the shape
circumference needs. §7.1 was checked and matches — 04:00 logical day, stored
on insert, never re-timestamped.

## 2026-09-25 — Editorial design foundation and shell

The first vertical slice of the approved UI Design Reference v1.0 is live in
Debug:

- `Native/Almanac/DesignSystem.swift` centralizes the canvas/surface/text/accent
  tokens, Dynamic Type roles, status tones, card/button primitives and the
  appearance override. Fraunces and Almarai ship under the SIL Open Font
  License with their licence files; Neue Montreal is intentionally not
  redistributed and falls back to the system face until licensed files are
  supplied.
- The root shell is now Today, Trends, an always-available Quick Log action and
  Modules. Modules owns the full module index; the three former domain tabs are
  reachable there and use embedded navigation stacks rather than nesting a
  second stack inside Modules. The bar is laid out in flow rather than attached
  with `safeAreaInset`: a navigation stack swallowed that inset, so every scroll
  view kept the full screen height and the last row of a long list — Settings —
  stayed pinned behind the bar with no way to scroll it clear. The quick-log
  action is the bar's one memorable element and sits on the exact centreline: a
  fixed-width spacer holds the middle while Today and Trends share the left half
  and Modules takes the right, instead of four equal columns that pushed the
  action a quarter of the way off-centre.
- A design-token pass replaced the warm-cream canvas and electric-blue accent
  with values chosen for the product rather than for a template: a true-neutral
  page, one step of panel surface, hairline rules as the structural device, and
  a desaturated ink-blue accent that marks something Almanac measured. Fraunces
  is now used only for the screen title and the readiness number — at 22pt and
  below its high-contrast strokes are the weakest part of the cut, so headings
  inside content are set in the sans. Panels are ruled areas of the page rather
  than uniformly filled cards, and only the object a screen is about (the
  readiness card on Today) gets the filled surface. Tracked-out all-caps
  eyebrows, middle-dot meta strings and the "Could not complete the action"
  error title are gone; the alert title is now the specific failure the store
  raised.
- Today is a scrolling editorial ledger: readiness headline, explicit waiting
  state, recommendation, check-in, daily signals, input provenance and the
  Activity Rings rhythm calendar. The calendar keeps the existing model and
  editor seam, adds non-color states/VoiceOver labels, and switches to a list
  layout at accessibility text sizes.
- Trends reads bounded, chronological readiness records through a new core
  store seam and renders a Swift Charts line with scrub selection, summary
  statistics and an honest empty state. Correlations are not implied.
- Quick Log provides one-tap water presets plus focused food, training and body
  entry sheets; the existing domain forms accept an optional completion hook so
  the sheet remains usable for a second entry. The body metric catalogue is
  shared with the Measurements editor so the two write paths cannot diverge.
- The foundation is intentionally applied to the shell, Today, Trends, Quick Log
  and Modules index first. Training, Hydration, Nutrition, Fasting, Prayer,
  Laboratory, Profile, Measurements and Settings remain native module screens
  until a later styling pass; this is a recorded scope boundary, not an
  assumption that they already share the new visual language.
- The named motion budget for this slice is: readiness-score reveal, quick-log
  save confirmation, hydration/nutrition goal crossing, and golden-day/streak
  milestones. The first two are implemented; goal crossing and milestone
  animation remain deliberately reserved rather than adding generic motion.
- Verification: `swift test` passes 421 Swift Testing tests, the Debug
  simulator build succeeds, and all 12 `AttributionsUITests` pass on the
  iPhone 16e simulator, including one that scrolls Modules to its end and
  asserts the last row clears the bar. Large Dynamic Type was checked
  separately; the calendar and readiness card reflow instead of using a
  fixed-width score layout.

Outstanding product/design decisions remain: licensed Neue Montreal files,
custom icon artwork, and final on-device status colors. The quick-log default
action and the Modules-as-drawer question are **closed** — see
`docs/features/owner-decisions-2026-09-26.md` §13-15, recorded 2026-09-27.
Arabic strings and RTL layout are not yet localized; the
Almarai registration is in place for that later pass. The first-slice privacy
and empty-state copy is provisional pending the tone decision recorded in the
reference.

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
  "Logged" is read from the same rows as the day's own energy total, food *and*
  drinks that carry calories: a drinks-only day is a nutrition day. It is
  deliberately not the same as "any drink logged" — water is 0 kcal, is already
  reported by the hydration ring, and would otherwise put "nutrition logged" on
  a day that has none.
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

- *Written when the only build environment was Linux. The Apple build claims
  here were true then and are false now:* `Native/` builds, launches and is
  tested on a simulator daily, and CI builds the app, the widget and the UI test
  suite on every push. For the current state read the evidence at the top of
  this file, not this section. The standing boundaries are the four below.
- Document import and document-file backup/restore remain deferred. The SQLite
  snapshot does not include document files.
- The current storage model is a local personal database. There is no multi-user
  account boundary or server authorization layer; do not claim cross-user RLS.
- Timeline filtering still runs in Swift over current records.
- No automatic unit conversion, OCR, AI interpretation or new tracker.
- The Technical Spec **is** in this checkout, at
  `docs/almanac-tech-spec-v1_0.md`, committed in `84f07e8`. An earlier version of
  this line pointed one directory above the repository root, which no longer
  resolves. See `docs/architecture/spec-reconciliation.md`.

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
