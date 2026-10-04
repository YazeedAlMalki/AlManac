# Almanac — Readiness (Slice 2)

**Status:** the pipeline is closed as of 2026-09-29. Baseline pipeline, §9.7
calibration counting and §9.8's three baselines are built and tested, and as of
2026-10-04 a person without a watch can produce a score at all. Four things
remain unbuilt, and each is a missing data model rather than a missing call.

## What is built

| §9 rule | Where | Tested by |
|---|---|---|
| §9.1–9.2 formula, pure, baselines passed in | `ReadinessFormula` | existing |
| §9.3–9.6 bands, text, confidence, precedence | `ReadinessEngine` | existing |
| §9.7 valid day — sleep, **or** both RHR and HRV | `ValidDayFacts` | `ReadinessBaselineServiceTests` |
| §9.7 calibration — "first 21 valid days from first use" | `ReadinessBaselineService.resolve` | `calibrationStopsAtTwentyOne`, `calibrationIsNotAWindow` |
| §9.8 general baseline — last 28 valid days | same | `generalBaselineIsWindowed` |
| §9.8 shift-specific — activates at 14 valid days on that shift | same | `shiftBaselineActivatesAtFourteen`, `thirteenShiftDaysIsNotEnough` |
| §9.8 Ramadan — ≥14 usable prior Ramadan days, else general + notice | same | `ramadanBaselineActivates`, `ramadanCalibrating`, `ramadanBaselineIsNotCircular` |
| §9.8 "shift schedule change never resets the 21-day calibration" | same | `shiftChangeDoesNotResetCalibration` |
| §5.23 `readiness_baseline` rows | `ReadinessBaselineStore` | `ReadinessBaselineStoreTests` |
| §9.4 religious-fast suffix, §9.6 fasted-session precedence | `ReadinessModel` | UI |
| §9.4 shift-transition suffix | `ReadinessModel.isCircadianTransition` | UI |
| §9.8 notices on screen | `ReadinessDashboardView` | UI |
| §6.7 "manual fallback" for RHR and HRV | `VitalsRecordStore.recordManual`/`update`/`delete`, `VitalsView` | `VitalsManualEntryTests`, `ManualVitalsReadinessTests`, `TrainingProgramUITests` |
| §9.1 missing-input redistribution, end to end | `ReadinessModel.refresh` | `ManualVitalsReadinessTests` |

## Manual entry, and what it took to make a score reachable (2026-10-04)

**The gap.** BRD §6.7 promises RHR, HRV, steps and active energy "imported
(HealthKit-authoritative, §5.2) with **manual fallback**". `vitals_record` had
exactly one writer — the HealthKit bridge — so a person without a watch, or one
who declined the HRV permission §5.2's own scenario names, could never produce a
readiness score. `ReadinessEngine` returns `score: nil` when duration, stages,
RHR+baseline and HRV+baseline are all missing, so the two weighed inputs being
unreachable took the whole feature with it.

**Only RHR and HRV, and only because those are the two the formula weighs.**
`ReadinessFormula` has no term for steps or active energy, so a field for them
would be a control with nothing on the other side of it. The screen's footer
says so rather than leaving the absence to be discovered.

**Two defects found while driving it, both in the app:**

1. **`latestValue(for:)` was the wrong read for today's score.** `ReadinessModel`
   took the newest row in `vitals_record`, which was correct while the only
   writer was the bridge — a HealthKit sample is always today's or last night's.
   It stops being correct the moment a person types "this morning, about last
   night": that reading is timestamped yesterday, and "newest row wins" hands
   today's score a number from a different night while looking entirely
   reasonable. `latestValue(for:since:)` bounds the read to the day being scored
   (the last primary episode's start, else the start of the logical day); with no
   resolvable start it reads nil rather than falling back to whole history,
   because the fallback is the bug.
2. **A manual wake marker scored as a zero-minute night.** §9.2's sleep-duration
   bands put `0` minutes in the worst band, so a zero-duration episode was
   scored as the worst possible night rather than as the absence of a
   measurement. `StoredSleepEpisode.measuredDurationMinutes` returns nil for a
   zero-duration row and `ReadinessModel` reads that instead.

**The baseline can be today's own reading, and the score that follows is not
66 — it is usually 74 and it is wrong in the dangerous direction.** Re-measured
2026-10-04, after the "always 66" note below was found to be an artefact of
measuring it without sleep data.

`meanPerDay` averages within a day, and `recent(_:through:)` keeps `$0 <= date`,
so today is inside §9.8's 28-valid-day window. But a window day contributes to a
metric's mean *only if it carries that metric*. **When today is the only day in
the window carrying an RHR — which is the normal state for anyone who types
vitals occasionally — the "28-day baseline" is one day long and consists of the
reading being scored.** Then `delta ≡ 0` by construction, so `rhrScore` returns
its `delta ≤ 0` row (**95**) and `hrvScore` its `pct ≥ -5%` row (**75**),
whatever the numbers were.

Those two rows are the defect, and they are worse than they look. §9.2's tables
assume a baseline assembled over many stable days, where "exactly at baseline"
deserves near-perfect marks. A self-comparison is vacuously at baseline, so a
baseline that does not exist yet pays out **+95 and +75 of unearned credit**
rather than reporting nothing. Measured against the real engine:

| Today | Current score | What it says |
|---|---|---|
| one RHR + one HRV, no sleep | **66** | "Moderate recovery — train at reduced intensity" |
| the same, plus an 8h sleep episode | **74** | "Recovery is good — ready for a strong session" (green) |

The second row is the one that matters, because an 8h night is the ordinary
shape of a scored day. A morning whose resting rate is 13 bpm above baseline and
whose HRV is 70% below it reads **74, green, "ready for a strong session"**.
`confidence` says `medium`, because the two inputs are counted as *present* — the
app reports high confidence in a number derived from a comparison with itself.

**It is not a calibration-phase artefact, and the earlier note saying to revisit
it "when §9.7's calibration completes" was wrong.** Measured with 27 prior
sleep-only valid days: `validDayCount = 28`, `calibrationDay = nil` — calibration
finished 7 valid days earlier — and the score is still the degenerate one. The
trigger is *data shape*, not phase: it recurs for the life of the record, on
every first entry after any gap, for exactly the population the manual fallback
was built for. Ten consecutive single-reading days score
`66, 63, 63, 63, 63, 57, 49, 49, 49, 42` — the first is always degenerate
because today is alone in the window, and only then does a baseline begin to
accumulate.

**Why it shipped.** `ReadinessBaselineServiceTests.logDays` seeds days *before*
the day under test, with the comment "so today's own data is never part of what
today's score is measured against." That is true of the helper and false of the
production window, which includes today. No test in the suite has ever logged a
vital on the day being scored, so the degenerate case was never executed.

**What a fix costs, measured.** Treating a degenerate baseline as *no* baseline —
the metric's input becomes missing and its weight redistributes, which is §9.1's
own rule and invents no threshold — moves the realistic case 74 → 72 and leaves
the recommendation unchanged, but moves `confidence` from `medium` to `veryLow`.
That is the honest gain: it does not rescue the number, it stops the app
over-claiming how much it knows. The sleep-only score behind it (72) is
defensible on its own terms. Open question, and a product decision rather than an
arithmetic one: whether a missing personal baseline should also *withhold* a
recommendation, or merely mark it preliminary.

**The training screen asked the question and then ignored the answer.**
`ProgramDayView`'s "Factor in your readiness score?" dialog had both buttons
calling the same `onStart()`, and `ProgramSessionView` opened with
`readinessAdjusted` false either way. A person who said "Yes — today's score is
22" got a session identical to the one they got by saying no. That is the other
half of why checklist rows 7.10/7.11 were recorded as unreachable "because the
simulator has no score", and the half nobody would have found by adding a score.
`ProgramDayView.onStart` now carries the answer, `ProgramListView` holds it as one
`StartingSession` value rather than a flag that could disagree with the day it
belongs to, and `ProgramSessionView` opens scaled when the answer was yes *and*
there is a score. The toggle stays, because the answer is changeable for as long
as the sheet is up.

## The two design decisions worth arguing about

**Calibration counts from the first valid day, not from a rolling window.**
§9.7 says "first 21 valid days **from first use**". A windowed count would
re-count a user who has been logging for a year, and would report "Day 1 of 21"
to someone with 400 days of history the first time they opened the app after an
update. So the count is over whole history: three `SELECT DISTINCT
logicalDay` queries and a set union. Cheap, exact, and it is the only reading
under which the number means what the spec says.

**The 21st valid day is still calibrating.** The phase is "first 21 valid
days", and "after calibration: full personalised scoring active" — so the
boundary is `<=`, not `<`. Day 21 reads "Day 21 of 21"; day 22 reads as
personalised. Getting this off by one in the other direction would start
pretending a personal baseline one day before it has one.

## The Ramadan substitution — and why `dayType` is not needed

§9.8 writes the Ramadan baseline as "Uses Ramadan days only (dayType =
'religious', scheduleType = 'ramadan')". **Nothing in this repo ever writes
`day_record.dayType`.** Migration014 creates the column; no code sets it. A
previous session's note treated this as a blocker on the whole of Slice 2; it
is not.

What does exist and does carry the fact is `ReligiousFastScheduleStore`: a
`ramadan` schedule is a dated span (`startGregorianDate`…`endGregorianDate`),
so "is this day inside a Ramadan" is answerable directly. It is answerable
*better* than through `dayType`, for two reasons:

1. A manual correction (§11.2's "calendar honesty") can move a fast day, and it
   moves it by editing the schedule or its corrections. A `dayType` column would
   have to be kept in step with that separately, and would be a second thing to
   forget.
2. "Prior years' Ramadan data" needs a *range* of Ramadans, which is what a
   list of schedule rows is. A per-day flag cannot answer "which days belonged
   to a Ramadan that has already finished" without scanning.

So the service asks the schedule. The substitution is recorded here rather than
made silently, and `dayType` remains unwritten — which is now visibly a
no-op column rather than a hidden dependency.

**"Prior" is enforced.** The usable-day count is of Ramadan days strictly
*before* this Ramadan's own start, and the averaged window is likewise. A
baseline built from the days currently being scored would be the score compared
against itself — the same non-circularity
`NotificationTriggerAssembler.averageWakeTime` keeps when it excludes the day it
is predicting. `ramadanBaselineIsNotCircular` pins it with nineteen valid days
at a wildly different RHR inside the current Ramadan.

## Baseline persistence, and why nothing reads it back

`ReadinessBaselineStore` writes the `readiness_baseline` rows Migration014
created and nothing had ever written to. **The scoring path does not read them.**
The service computes from the same stores the row summarises, so reading the row
back would let a day's score be measured against a snapshot a later pass has not
refreshed. §9.8 says "updated daily after readiness calculation" — that is a
record, not a cache. A stale baseline is worse than a recomputed one.

The table has no unique constraint on `(baselineType, shiftType)`, so `save` is
delete-then-insert inside a transaction rather than an `ON CONFLICT` upsert. A
unique index would need a migration to make an upsert tidier, on a table that
has never shipped.

## Not built, and why

| §9 flag | Status | Why |
|---|---|---|
| `manualRecoveryDay` | always `false` | Nothing records a user-declared recovery day. |
| `plannedRestDay` | always `false` | `PrescribedWorkoutStore` holds templates, not a dated plan. There is no "is this day a rest day" to read. |
| `plannedDeloadDay` | always `false` | No deload-week data model exists anywhere in the repo. |
| `avgSleepDurationMin`, `avgSoreness`, `avgMood` baseline columns | written as NULL | The service computes RHR and HRV, which are the two the formula actually scores against (`ReadinessFormula.rhrScore`/`hrvScore` take a baseline; sleep is scored by absolute band, mood/soreness by their own scales). Writing numbers nobody reads would be a second kind of claim. |

The first three are the same gap: a training *plan* with dated sessions and
load, which is a larger piece of work than wiring three booleans. Inventing a
plan model to turn them on would be building a feature nobody asked for in order
to light up three flags.

## Where it runs

`ReadinessModel.refresh()` is still the single assembly point, called from the
app's foreground handler. It is idempotent and pull-based, and the baseline
pass reads stores rather than being handed values, so a missed call site costs
one stale refresh rather than a wrong day.
