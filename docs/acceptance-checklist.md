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
| Core suite | **PASS** — 606 tests, 75 suites, zero failures |
| App + widget build (iPhone 16e simulator) | **PASS** |
| Notification settings UI tests | **PASS** — 5 of 5, run explicitly |
| Timeline UI tests | **PASS** — 3 of 3, after two defects were fixed (see §6) |
| Full UI suite | **UNRUN** — exceeds a 50-minute command timeout. 6 of 52 passed before the run was abandoned; the rest is not claimed. |
| Device-only steps (§4) | **UNRUN** — no agent can drive these. |

---

## 1. Foundation

| # | Step | Result |
|---|---|---|
| 1.1 | `swift build` clean | **PASS** |
| 1.2 | `swift test` green | **PASS** — 606/606 |
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
