# Almanac — manual acceptance checklist

**Created 2026-09-30. Never driven before this.**

## How to read the marks

| Mark | Meaning |
|---|---|
| **PASS** | Driven, and it behaved as this line says. |
| **FAIL** | Driven, and it did not. The finding is written next to it. |
| **UNRUN** | Not driven. No claim either way. |

**A step is only PASS if it was driven.** "The code looks right" is not a
result. Where something could not be driven by an agent at all — it needs a
human on a physical device, or hours of wall-clock waiting — it is UNRUN and
says so, rather than being quietly ticked because it is probably fine. That
distinction is the entire value of this document: a checklist where unrun steps
are marked pass is worse than no checklist, because it manufactures confidence.

## Status of this run

| | |
|---|---|
| Core suite | **PASS** — recounted 2026-10-06 on Swift 6.3.3, x86_64 Linux (a cloud container, `swift test`): branch `claude/handoff-2026-10-06` **987 Swift Testing tests in 107 suites + 379 XCTest (1 skipped, the opt-in real-bundle test), 0 failures**; master `efb1c0b` **938 in 99 suites + 373 XCTest (1 skipped), 0 failures**. The 627/78 that stood here was 2026-09-30's. |
| App + widget build (iPhone 16e simulator) | **PASS** |
| Insights UI tests | **PASS** — 5 of 5 |
| Notification settings UI tests | **PASS** — 5 of 5 |
| Timeline UI tests | **PASS** — 3 of 3, after two defects were fixed (see §6) |
| The three suites above, together | **PASS** — 13 of 13, 8m42s |
| Full UI suite | **UNRUN** — **83 test methods** by grep on the 2026-10-06 branch (78 on master, plus 4 in the new `KitchenUITests` and 1 template test in `TrainingHistoryUITests`); the "68" that stood here was 2026-09-30's. The whole suite **does** run in CI (`test-ios`, a fresh simulator, about 2.5 hours). On master `efb1c0b` (run 37354673943, 2026-10-05): **78 run, 7 failed** — `BodyCircumferenceUITests.testSidedLoggingWarningAndPersistence`, `BodyCompositionWellnessUITests.testDiscontinuingAPlanKeepsItVisible`, `NotificationSettingsUITests` ×3 (`testASwitchFlipsAndReverts`, `testTheScreenSaysWhetherNotificationsAreAllowed`, `testTurningEverythingOffAsksFirst`), `ProblemChannelUITests.testHydrationWithASuccessfulWriteDoesNotClaimItCouldNotRead`, `TrainingProgramUITests.testRemovingFromRotationThenRestoringItsPosition`. **This branch at `3653be0`** (run 37452597841, 2026-10-06): **83 run, 7 failed.** Four are master's: `BodyCircumferenceUITests.testSidedLoggingWarningAndPersistence`, `NotificationSettingsUITests.testASwitchFlipsAndReverts`, `NotificationSettingsUITests.testTheScreenSaysWhetherNotificationsAreAllowed`, `ProblemChannelUITests.testHydrationWithASuccessfulWriteDoesNotClaimItCouldNotRead`. Three are new tests of this branch's that failed on their first run: `KitchenUITests.testAPantryItemCanBeAddedAndRemoved`, `KitchenUITests.testARecipeDeclaringARecordedAllergenIsWithheld` and `TrainingHistoryUITests.testApplyingATemplateFillsTodayAndStaysEditable`. Three of master's failures passed here and are taken as flaky, not fixed: BodyCompositionWellness, NotificationSettings `testTurningEverythingOffAsksFirst`, TrainingProgram `testRemovingFromRotationThenRestoringItsPosition`. `TrainingProgramUITests` passed 13 of 13, including 7.10 and 7.11 with the new way of clearing today's readings. `KitchenUITests` opening Recipes and choosing a recipe passed. The new failures' messages could not be read from the session: the log tool returns only the last 5,000 lines, and the artifact and log-zip hosts are blocked. One cause was certain (the template test looked for text fields with a helper that never searches text fields) and is fixed, a likely one in the allergen test is fixed, and CI now prints every failure message at the end of the log (`Summarise failures`). **Second run, `0e6fd55`** (run 37472541675): **83 run, 5 failed**, with every failure message printed by the new `Summarise failures` step. The template test now **passes**, and so do all three NotificationSettings tests. Failed:
- `BodyCircumferenceUITests.testSidedLoggingWarningAndPersistence` and `ProblemChannelUITests.testHydrationWithASuccessfulWriteDoesNotClaimItCouldNotRead`: master's own. Both are a harness snapshot error at `UIScrollSupport.swift:174`.
- `AllergenFilterUITests.testRecordingPeanutsMakesTheSearchSayWhatItChecked`: "Profile never opened". It passed on master and on this branch's first run, and it runs before any Kitchen test, so it is taken as a navigation flake.
- `KitchenUITests.testAPantryItemCanBeAddedAndRemoved`: "Multiple matching elements" for "Pantry". The mode picker's segment and the toolbar button share the name. Fixed in the test.
- `KitchenUITests.testARecipeDeclaringARecordedAllergenIsWithheld`: "the allergen disclaimer is missing". The note is an `AlmanacProblemNote`, which is one element rather than a static text. Fixed in the test.

Both Kitchen failures were the tests' own lookups, not the app.

**Third run, `12ffa44`** (run 37495143616): **83 run, 6 failed.**

- `KitchenUITests.testAPantryItemCanBeAddedAndRemoved` and the template test **pass**.
- `KitchenUITests.testARecipeDeclaringARecordedAllergenIsWithheld` got further, past the hidden entry and the disclaimer. It then failed with "the hidden recipe is not listed once the entry is opened": the tap landed on the entry's cell and left it collapsed. The test now taps the disclosure's own button and finds the recipe by identifier or name.
- The other five failures are in code this branch does not touch. Each has also failed on master or on an earlier run of this branch:
  - `AllergenFilterUITests.testAToggledAllergenIsStillThereAfterReopening`: the toggle did not flip.
  - `BodyCircumferenceUITests.testSidedLoggingWarningAndPersistence`.
  - `BodyCompositionWellnessUITests.testDiscontinuingAPlanKeepsItVisible`.
  - `NotificationSettingsUITests` ×2: "Settings does not offer the reminders screen".

They flip between runs, which is the shared-state flakiness `docs/implementation-status.md` describes for this suite. That is the baseline a branch is compared against; the 2026-10-06 handoff's "four known failures" (BodyCircumference 1, BodyCompositionWellness 2, Attributions 1) does not match it, and none of the seven is diagnosed. The 2026-10-06 work was written without Xcode; CI's `xcodebuild` compiled it, and CI's `test-ios` is its only UI run. |
| Device-only steps (§4) | **UNRUN** — no agent can drive these. |
| Training Program steps (§7) | **17 of 17 recorded PASS** — the last full-file run was 2026-10-05: `TrainingProgramUITests` 13 of 13 (iPhone 16e, iOS 26.3, on a shared and dirty database; see `docs/implementation-status.md`). The "7 of 17" that stood here was 2026-10-02's. **Re-run needed:** the 2026-10-06 branch changed how 7.10 and 7.11 clear today's readings (the Vitals log now includes today), and that has not been driven. |

**Recounted 2026-10-02 (`c4bd0be`):** the core suite was then **900 tests, 95
suites, 0 failures** (168.7 s). Superseded by the 2026-10-06 count in the table.
The Insights, Notification settings and Timeline UI rows are still the
2026-09-30 run and have not been re-driven; they do not claim current code.

---

## 1. Foundation

| # | Step | Result |
|---|---|---|
| 1.1 | `swift build` clean | **PASS** |
| 1.2 | `swift test` green | **PASS** — 2026-10-06: 987 + 379 (1 skipped) on the branch, 938 + 373 (1 skipped) on master; see the status table |
| 1.3 | App target builds for a simulator | **PASS** |
| 1.4 | Widget extension is built and embedded | **PASS** — `AlmanacWidgets.appex` present in the built app |
| 1.5 | Every migration applies to a virgin database | **PASS** — 2026-10-06: 49 on master; 54 on the branch (001–049 and 051–055, 050 reserved for the fasting work), exercised by every core test |
| 1.6 | A profile from before migration 041 upgrades without being replaced | **PASS** |
| 1.7 | A second `migrate` on an up-to-date database is a no-op | **PASS** |

## 2. Notification scheduling (Slice 11)

The pure half is covered by `NotificationPlannerTests` (28) and
`NotificationRuleStoreTests` (11), all green. What those tests *cannot* cover is
whether the OS honours a request, which is §4.

| # | Step | Result |
|---|---|---|
| 2.1 | All nine §14.2 types are reachable from the assemblers and the planner | **PASS** |
| 2.2 | Appendix B is applied per fire instant, not once per pass | **PASS** — pinned by `suppressionIsPerFireInstant` |
| 2.3 | A night shift tonight suppresses tonight's bedtime and leaves tomorrow's | **PASS** |
| 2.4 | A dry fast suppresses water; a confirmed IF suppresses meal | **PASS** |
| 2.5 | Post-shift sleep suppresses readiness, water, meal, bedtime, supplements | **PASS** |
| 2.6 | §5.25's default table is what ships | **PASS** — `testTheSeededDefaultsAreTheSpec§525Table` |
| 2.7 | The `suppressDuring*` columns are never written | **PASS** — pinned by a test, deliberately |
| 2.8 | Two runs over unchanged state produce an identical plan | **PASS** |
| 2.9 | Every type has an individual switch in the app | **PASS** — `testEveryNotificationTypeHasASwitch` |
| 2.10 | The screen states whether the OS will allow notifications | **PASS** |
| 2.11 | A switch flips and reverts | **PASS** — after `tapSwitchControl`; a row-level tap does not move a SwiftUI `Toggle` |
| 2.12 | Turning everything off asks first, and can be cancelled | **PASS** |
| 2.13 | A notification actually arrives at its scheduled minute | **UNRUN** — device-only, see §4.1 |
| 2.14 | A water reminder is suppressed live when a dry fast starts | **UNRUN** — device-only, and depends on 2.13 |
| 2.15 | Backgrounding the app for a day and returning leaves a correct schedule | **UNRUN** — needs a day of wall-clock time |
| 2.16 | Declining the permission prompt does not surface an error | **UNRUN** — the system alert is not drivable from a test |

## 3. Readiness (Slice 2)

| # | Step | Result |
|---|---|---|
| 3.1 | A valid day is sleep, or both RHR and HRV — not either alone | **PASS** |
| 3.2 | Calibration counts valid days from the first one, not a rolling window | **PASS** |
| 3.3 | The 21st valid day is the last calibrating day | **PASS** |
| 3.4 | The general baseline averages the last 28 valid days, days not readings | **PASS** |
| 3.5 | A shift baseline activates at exactly 14 valid days on that shift | **PASS** |
| 3.6 | 13 is not enough, and the user is told why | **PASS** |
| 3.7 | A shift baseline is built only from days on that shift | **PASS** |
| 3.8 | A shift schedule change never resets the 21-day calibration | **PASS** — §9.8, explicitly |
| 3.9 | Ramadan falls back to the general baseline below 14 prior Ramadan days, with the notice | **PASS** |
| 3.10 | A Ramadan baseline never counts the days it is scoring | **PASS** — pinned with 19 in-window days at a different RHR |
| 3.11 | `readiness_baseline` rows are written and replaced, not accumulated | **PASS** |
| 3.12 | Religious fast days reach the score's text and the precedence rules | **PASS** (code + build) — **not driven on screen** |
| 3.13 | The "Day X of 21" label appears on Today | **UNRUN** — no simulator data set up to reach 1–20 valid days and photograph it |
| 3.14 | A readiness score with 21+ valid days is *not* labelled preliminary | **UNRUN** — same reason |
| 3.15 | Sleep stages reach the score | **PASS** (core tests green) |

## 4. Device-only — **needs a human on a physical device**

None of these can be driven by an agent. They are listed so that "the code
looks right" is visibly not the same as "this was checked".

### 4.1 Notifications
- [ ] Grant notifications; confirm a water reminder arrives at its scheduled minute.
- [ ] Start a religious dry fast; confirm the next water reminder is suppressed.
- [ ] End the fast; confirm reminders resume on the next app open.
- [ ] Log a mood check-in; confirm today's readiness notification stops.
- [ ] Switch to a night shift; confirm tonight's bedtime reminder does not fire and tomorrow's does.
- [ ] Force-quit; reopen; confirm the schedule is rebuilt correctly.

### 4.2 HealthKit
- [ ] First-run permission sheet lists every domain, once.
- [ ] Denying one domain does not break the others.
- [ ] Sleep, RHR, HRV, steps and body composition all sync.
- [ ] The permission sheet is not re-requested on every launch.

### 4.3 Backup and restore
- [ ] Create a backup; share it as a `.zip`; import the `.zip` on a second install.
- [ ] Restore over a populated database; confirm HealthKit re-syncs without duplicating workouts or measurements.
- [ ] Restore from a backup made by a different app version; confirm it is refused with a readable reason.
- [ ] Corrupt a bundle; confirm it is detected before anything is written.

### 4.4 Wearables and real time
- [ ] Post-shift sleep is classified as primary, not a nap, after the first night shift.
- [ ] A workout crossing midnight is attributed to the right logical day.
- [ ] A DST transition day is 23 or 25 hours and does not duplicate or drop an entry.

### 4.5 Accessibility
- [ ] Every screen at every Dynamic Type size, including the accessibility sizes.
- [ ] VoiceOver on Today, Quick Log, Timeline and the reminders screen.
- [ ] Increase Contrast and Reduce Motion.

## 5. Deliberately unticked

| Step | Why it is UNRUN rather than PASS |
|---|---|
| 2.13–2.16 | Notification delivery is the OS's behaviour. A simulator test can assert a pending request; it cannot assert a banner. |
| 3.13–3.14 | Reaching 1–20 valid days needs seeded data and a photographed screen. The arithmetic is tested; the label's appearance is not. |
| 4.\* | Requires a human, a physical device, and in two cases a day of waiting. |
| Full UI suite | Exceeds a 50-minute command timeout. Six of 52 passed before the run was abandoned. The remaining 46 are **not** claimed either way. |
| 7.\* | The Training Program feature has no UI at all. Its core is built and tested (900-test suite green), but nothing in this document's §7 can be driven until someone writes the screens, and a core test passing is not a driven step. |

## 6. Defects found by driving this

Two real defects surfaced while building item 4, both pre-existing and neither
caused by the readiness work.

**The Timeline UI tests had been failing since 2026-09-26** — passing on an
empty database, failing on a populated one. The cause was not the Timeline
screen. The shared `reveal` helper swipes, and a swipe on that particular
`List` left the accessibility hierarchy byte-identical across a dozen attempts,
so a budget-only loop reported "not there", which is indistinguishable from a
control that genuinely was not offered. `reveal` now watches whether the content
moved and falls back to a press-then-drag. Two wrong answers to "where is the
anchor?" are documented in the fix: application-level `staticTexts` puts the
fixed tab bar in the measurement, and `cells` is empty for SwiftUI lists.

**A settings switch appeared not to work.** The reminders screen's switches read
their value out of a `@State` array that was loaded once on appear, so a
successful write was immediately overwritten by the stale copy. Found by
`testASwitchFlipsAndReverts`; the reload now happens after every write.

A third finding is not a defect but a note: `tap()` on a SwiftUI `Toggle` row can
land on the label and do nothing. `tapSwitchControl()` exists for this and the
new tests use it. A test that reads "the switch is broken" when the tap missed
is a test that will send someone looking in the wrong place.

## 7. Training Program — **UI driven by automation**

Added 2026-10-02. The core of this feature is built (`docs/features/training-program.md`).
The native UI screens (`ProgramListView`, `ProgramDayView`, `ProgramSessionView`, `ExerciseProgressGraphsView`) are implemented and wired into `TrainingDashboardView` and `AlmanacApp`. Core test suite passes (900/900).

**Driven 2026-10-02–04.** `TrainingProgramUITests` now drives the whole §7
surface: the picker, authoring, the day→session loop, all three skip-prompt
answers, both readiness answers, the equipment-variant selector, actuals
reaching both graphs, the separate/combined toggle and its comparability note,
pre-migration history, and the abandon/delete versus rotation-step rows. A
full-file run (`-only-testing:AlmanacUITests/TrainingProgramUITests`) passes
**12 of 12** (2026-10-04, after the known-failure passes on 2026-10-02). The
first run at 12 tests was **11 of 12**, and the one failure was worth having
found: the two new readiness tests sort first by name, so the abandon/delete
test now runs against a day carrying their training sessions, and the longer
list re-renders more of itself per delete than its drain loop allowed for. The
runs found automation-side issues (SwiftUI steppers/pickers expose a bare
`value`, so assertions read `label`-or-`value`; below-the-fold sheet rows are
`reveal`ed; a tab switch resets the inner Programs→Day stack, so re-navigation
settles the Modules home first; and the abandon/delete test's drain of today's
log must wait for the row count to hold still before picking a row, because a
query issued mid-animation matches the row being deleted and the swipe then
fails on an element that is already gone) and three genuine **app bugs**, fixed
in the app:

- **"Put back" never restored.** The pool row's restore button — and the same
  swipe action — called `setAvailability(.permanent, …)`, i.e. wrote
  `is_active = false` again: a no-op on an item already removed, so a removed
  exercise could never come back. It now routes through a dedicated
  `ProgramModel.restore` to the store's reversible `setActive(id:to: true)`,
  keeping the item's cycle position, prescription and progression rule.
- The same fix exposed the row's "Put back" button to the accessibility tree
  (`.accessibilityElement(children: .contain)` on the row, `.borderless` on the
  button); before it, the row's tap gesture swallowed the inner control and a
  VoiceOver user had no way to restore an exercise.
- **The readiness question's answer was discarded.** Both buttons on
  "Factor in your readiness score?" called the same `onStart()`, and the session
  opened unscaled either way, so answering **Yes** produced exactly the session
  answering **No** did. This is the reason 7.10/7.11 needed a real fix and not
  just a score: the checklist recorded them as unreachable "because the simulator
  has no score", which was half the reason, and the half that adding a score
  would not have revealed. `ProgramDayView.onStart` now carries the answer,
  `ProgramListView` keeps it in one `StartingSession` value (not a separate
  flag, which could disagree with the day it belongs to), and `ProgramSessionView`
  opens already scaled when the answer was yes *and* a score exists.

Rows are **PASS** only where the automation above actually drove the step and
the row text records the scope.

**How 7.10/7.11 get a score to choose.** Both tests hand-enter a resting rate
and an HRV through Modules → Vitals, which is BRD §6.7's "manual fallback" and
the whole of the new `VitalsView`. Each test first clears the hand-entered
readings left by earlier runs from the Vitals log. Until 2026-10-06 the log left
out today's readings (an exclusive upper bound, a defect), so today was cleared
through the seeding spec instead; the log now ends with today and the one helper
reaches it. **That change has not been driven yet** — the two rows below stand on
the 2026-10-05 run, which used the old clearing route. It then plants three
prior days of ordinary readings and types exactly two readings of its own, for
today.

The prior days are planted by launch argument (`-AlmanacSeedVitals`, parsed by
`VitalsSeedPlan`) rather than typed, because the editor's `DatePicker` cannot be
told which day to write on: tapping it expands a graphical calendar whose day
cells are locale-formatted buttons, and CI resolves the newest iOS runtime
instead of pinning one. The mechanism, the measurement behind it and the reason
the picker route was rejected are recorded at `XCUIApplication.seedVitals` in
`Native/AlmanacUITests/UIScrollSupport.swift`.

**Those three days are not decoration.** Before the degenerate-baseline fix, a
baseline assembled only from the day being scored reported `rhrScore` 95 and
`hrvScore` 75 whatever the numbers were, so the two rows were asserting on scores
produced by comparing a value with itself; both tests seeded three filler
readings per metric purely to drag that within-day average away from the pair
under test. With the fix that arrangement yields no score at all, which is the
right answer for what it was arranging. Measured figures and the test-coverage
hole behind the defect are in `docs/features/readiness.md`.

Two checks keep this honest rather than merely passing. Both rows were run with
the baseline removed and **fail** — at "starting a day with a readiness score
must offer to scale the session by it", and only there. And
`testAReadingCanBePlantedOnADayOtherThanToday` asserts the seeding hook itself
puts a reading on the day it names and not on today's card, so the first sign it
had stopped working is a failure about the hook rather than a score three screens
later.

The steps are the UX flow from `docs/handoff-2026-10-01-training-program.md`.

| # | Step | Result |
|---|---|---|
| 7.1 | Workout → "Start Workout" offers the program picker | **PASS** — `testStartWorkoutOpensTheProgramPicker` taps the Training-dashboard "Start workout" link and asserts the `Programs` nav bar |
| 7.2 | Program picker lists every non-deleted program, several at once | **PASS** — a program created in `testAuthoredProgramsAndDaysAppearOnThePicker` lands on the picker, and a non-empty picker offers adding a day (`testStartWorkoutOpensTheProgramPicker`, non-empty branch, with the shared simulator DB's leftover programs already on it). "Several at once" is not separately counted; deletion is not part of these tests |
| 7.3 | Choosing a program offers its days in authoring order, not alphabetically | **PASS** — adds "Push" then "Pull" and asserts `Push.frame.minY < Pull.frame.minY` (alphabetical would be Pull first) |
| 7.4 | Starting a day generates the session from the rotation, excluding permanently removed items | **PASS** — `testStartingADayBuildsASessionWithTheSkipPrompt` adds an exercise to the pool, starts the day, and asserts session slots appear and finishing advances the rotation ("pass 2"). The "excluding permanently removed items" clause is driven by 7.8's UI test and the core rotation tests |
| 7.5 | The generated list shows prescribed sets × reps × load per exercise | **PASS** (row presence) — slot rows (`session-slot-*`) appear for the generated session. The assertion checks slot presence; the prescription text within a row is not itself asserted |
| 7.6 | "Skip just for today" and "Remove from rotation" are visible **together** in one prompt | **PASS** — the same test asserts both buttons exist on the one prompt it opens (Decision 3) |
| 7.7 | Skip-for-today offers the same exercise again on the next session of that day | **PASS** — `testSkippingForTodayReoffersTheExerciseNextSession` skips the generated slot ("Skip just for today"), asserts the held row is shown and undoable, finishes, sees the day advance to pass 2, then starts again and asserts the same exercise is re-offered |
| 7.8 | Remove-from-rotation never offers it again, and re-adding restores its position | **PASS** — `testRemovingFromRotationThenRestoringItsPosition` removes an exercise ("Remove from rotation"); the day marks it "Removed from rotation" and counts "1 of 2 in rotation"; a fresh session offers only the remaining exercise; "Put back" restores it ("2 in rotation", mark cleared) and a later session offers both again. Driving this exposed an app bug — "Put back" wrote `is_active = false` again instead of restoring — fixed via `ProgramModel.restore` |
| 7.9 | "Factor in your readiness score?" prompt, Yes and No | **PASS** (both legs) — the No leg is `startCurrentDay`, which asserts the "No, train as written" button appearing and being tapped; the Yes leg is `testAnsweringYesScalesThePrescriptionAndNamesWhatMoved`, which asserts the "Yes — today's score is N" button appearing and being tapped |
| 7.10 | Choosing Yes lowers the prescription per the day's readiness band, and the change is shown | **PASS** — `testAnsweringYesScalesThePrescriptionAndNamesWhatMoved` plants three prior days of readings as a real baseline, hand-enters a resting rate and an HRV for today through Modules → Vitals (BRD §6.7's "manual fallback"), starts a day and answers Yes. The sheet opens already scaled: `readiness-toggle` is on, it names the band ("Moderate") and the number ("scaled from N"), and the `prescription-changes-*` panel states what became what. Which fields move depends on the prescription's type, so the assertion is that the panel names a movement, not which one. Fails if the baseline is removed (see "How 7.10/7.11 get a score to choose") |
| 7.11 | A very-low-readiness day presents as a rest day | **PASS** — `testAVeryLowDayPresentsAsARestDayAndCanBeTrainedAnyway` seeds the same three-day baseline and types a pair far outside it, answers Yes, and asserts "Today is a rest day" with no readiness toggle on screen (the rest day *replaces* the session rather than sitting above a scaled one), a disabled Finish, and a working "Train as written anyway" that restores the plan as written. Fails if the baseline is removed (see "How 7.10/7.11 get a score to choose") |
| 7.12 | Equipment variant selector per exercise, four options plus "not specified" | **PASS** — `testEquipmentVariantPickerOffersTheFiveAnswers` opens the selector on a generated slot; the prompt offers "Not recorded" plus Barbell/Dumbbell/Cable/Machine; choosing Barbell records it on the control |
| 7.13 | Entering actuals updates the two graphs | **PASS** — `testEnteringActualsUpdatesBothGraphs` adds a load-bearing exercise with 4 kg prescribed, marks the bout done (registering actuals), finishes, opens the progress screen, and asserts both the Load graph and the Reps-performed graph gained a logged point |
| 7.14 | The separate/combined radio toggle on the graph, applying to both graphs | **PASS** — `testVariantModeToggleAppliesToBothGraphsAndShowsTheNote` flips the radio to Combined and asserts both the weight and volume graphs keep their logged points (the toggle is a read applied to both) |
| 7.15 | Combined mode shows the "may not be directly comparable" note; separate mode does not | **PASS** — the same test asserts the "Equipment variants may not be directly comparable" note is absent in separate mode and present in combined mode |
| 7.16 | An exercise with only pre-migration history still draws a series in separate mode | **PASS** — `testPreMigrationHistoryStillDrawsASeriesInSeparateMode` finishes a bodyweight bout with no variant (the shape pre-Migration049 history has), and asserts the volume graph still draws a series in the default separate mode ("N logged") while the weight graph honestly reports no load |
| 7.17 | Deleting a session does not consume a rotation step | **PASS** — `testDeletingOrAbandoningASessionDoesNotConsumeARotationStep` drives both legs that skip a rotation step: *abandoning* ("Put down" writes nothing, the day stays pass 1) and *deleting* (Today → Rhythm → day editor → deleting that day's "1 min" training rows leaves the day back at pass 1). No assertions touch other days' sessions |
