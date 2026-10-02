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
| Core suite | **PASS** — 627 tests, 78 suites, zero failures (recounted 2026-09-30 against `f3c10e2`; the 606/75 recorded earlier was captured before the last commit's tests landed) |
| App + widget build (iPhone 16e simulator) | **PASS** |
| Insights UI tests | **PASS** — 5 of 5 |
| Notification settings UI tests | **PASS** — 5 of 5 |
| Timeline UI tests | **PASS** — 3 of 3, after two defects were fixed (see §6) |
| The three suites above, together | **PASS** — 13 of 13, 8m42s |
| Full UI suite (68 tests) | **UNRUN** — exceeds a 50-minute command timeout. A background run reached 13 passed / 1 failed (`BodyCircumferenceUITests.testSidedLoggingWarningAndPersistence`, which also failed on two earlier runs of a different subset, so it is pre-existing and state-dependent) before it was stopped. The other 54 are **not** claimed either way. |
| Device-only steps (§4) | **UNRUN** — no agent can drive these. |
| Training Program steps (§7) | **7 of 17 driven (PASS)** — `TrainingProgramUITests` pass 3 of 3 in a full-file run, twice in a row (2026-10-02); 7.1–7.6 and the 7.9 No-leg were driven. The rest are **UNRUN (UI)**: built and core-tested, but no UI test drives them (see §7). One test-infra bug (stale-frame tap after `reveal`) was found and fixed in the harness; the app was not at fault |

**Recounted 2026-10-02 (`c4bd0be`):** the core suite is now **900 tests, 95
suites, 0 failures** (168.7 s), up from the 768/88 it stood at immediately
before that commit. The UI rows above are still the 2026-09-30 run and have not
been re-driven, except **§7 Training Program** (driven 2026-10-02, this run, 3
of 3); the §7 row therefore claims current code, the other UI rows do not.

---

## 1. Foundation

| # | Step | Result |
|---|---|---|
| 1.1 | `swift build` clean | **PASS** |
| 1.2 | `swift test` green | **PASS** — 627/627 |
| 1.3 | App target builds for a simulator | **PASS** |
| 1.4 | Widget extension is built and embedded | **PASS** — `AlmanacWidgets.appex` present in the built app |
| 1.5 | Every migration applies to a virgin database | **PASS** — 45 migrations, exercised by every core test |
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

**Driven 2026-10-02–03.** `TrainingProgramUITests` now drives the whole §7
surface except the two engine-dependent rows (7.10–7.11): the picker,
authoring, the day→session loop, all three skip-prompt answers, the readiness
door, the equipment-variant selector, actuals reaching both graphs, the
separate/combined toggle and its comparability note, pre-migration history, and
the abandon/delete versus rotation-step rows. A full-file run
(`-only-testing:AlmanacUITests/TrainingProgramUITests`) passes **10 of 10**
(2026-10-03, after the known-failure passes on 2026-10-02). The runs found
automation-side issues (SwiftUI steppers/pickers expose a bare `value`, so
assertions read `label`-or-`value`; below-the-fold sheet rows are `reveal`ed; a
tab switch resets the inner Programs→Day stack, so re-navigation settles the
Modules home first) and one genuine **app bug**, fixed in the app:

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

Rows are **PASS** only where the automation above actually drove the step and
the row text records the scope. 7.10–7.11 stay **UNRUN**: `ReadinessEngine`
yields no score without sleep/vitals data, the simulator has neither, so no UI
run can reach the "Yes" band or the very-low rest-day presentation.

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
| 7.9 | "Factor in your readiness score?" prompt, Yes and No | **PASS** (No leg) — starting a day must present the prompt, asserted via the "No, train as written" button appearing and being tapped. The "Yes" leg is 7.10, UNRUN |
| 7.10 | Choosing Yes lowers the prescription per the day's readiness band, and the change is shown | **UNRUN (UI)** — readiness *adjustment* is covered by core tests (`ReadinessAdjustment`); no UI run can reach a Yes answer because `ReadinessEngine.evaluate` yields no score without sleep/vitals data, and the simulator has neither, so the prompt offers no band to choose |
| 7.11 | A very-low-readiness day presents as a rest day | **UNRUN (UI)** — rest-day presentation is core-tested; the very-low band is unreachable in the UI for the same engine reason as 7.10 |
| 7.12 | Equipment variant selector per exercise, four options plus "not specified" | **PASS** — `testEquipmentVariantPickerOffersTheFiveAnswers` opens the selector on a generated slot; the prompt offers "Not recorded" plus Barbell/Dumbbell/Cable/Machine; choosing Barbell records it on the control |
| 7.13 | Entering actuals updates the two graphs | **PASS** — `testEnteringActualsUpdatesBothGraphs` adds a load-bearing exercise with 4 kg prescribed, marks the bout done (registering actuals), finishes, opens the progress screen, and asserts both the Load graph and the Reps-performed graph gained a logged point |
| 7.14 | The separate/combined radio toggle on the graph, applying to both graphs | **PASS** — `testVariantModeToggleAppliesToBothGraphsAndShowsTheNote` flips the radio to Combined and asserts both the weight and volume graphs keep their logged points (the toggle is a read applied to both) |
| 7.15 | Combined mode shows the "may not be directly comparable" note; separate mode does not | **PASS** — the same test asserts the "Equipment variants may not be directly comparable" note is absent in separate mode and present in combined mode |
| 7.16 | An exercise with only pre-migration history still draws a series in separate mode | **PASS** — `testPreMigrationHistoryStillDrawsASeriesInSeparateMode` finishes a bodyweight bout with no variant (the shape pre-Migration049 history has), and asserts the volume graph still draws a series in the default separate mode ("N logged") while the weight graph honestly reports no load |
| 7.17 | Deleting a session does not consume a rotation step | **PASS** — `testDeletingOrAbandoningASessionDoesNotConsumeARotationStep` drives both legs that skip a rotation step: *abandoning* ("Put down" writes nothing, the day stays pass 1) and *deleting* (Today → Rhythm → day editor → deleting that day's "1 min" training rows leaves the day back at pass 1). No assertions touch other days' sessions |
