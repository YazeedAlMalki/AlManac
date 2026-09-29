# Almanac — Readiness (Slice 2)

**Status:** the pipeline is closed as of 2026-09-29. Baseline pipeline, §9.7
calibration counting and §9.8's three baselines are built and tested. Four
things remain unbuilt, and each is a missing data model rather than a missing
call.

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
