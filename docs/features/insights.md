# Insights — trends, associations, badges

**Status:** the three engines (`TrendEngine`, `CorrelationEngine`,
`AchievementEngine`) and their three stores were complete and tested since
Slice 10, with **zero app consumers**. `correlation_pair`, `trend_snapshot` and
`achievement_record` were permanently empty tables, because nothing in the app
could hand an engine a number. The engines were never the gap; the line between
the tables and the numbers was.

Both halves are now built (2026-09-29): `InsightSeriesBuilder` +
`InsightsQuery` in `AlmanacCore`, and `InsightsView` in the app.

## 1. What reads what

`TrendSummary` and `CorrelationSummary` are computed on open and persisted, so
the three tables are no longer empty. There is no nightly batch: the engine
header already states the horizon is a caller concern, and a stored number
nobody refreshes is worse than none.

| Surface | Where |
|---|---|
| Trends (one metric plotted) | `TrendsView` — unchanged, still readiness |
| Insights (all of it) | `InsightsView`, linked from Trends |
| Series extraction | `Sources/AlmanacCore/Insights/InsightSeriesBuilder.swift` |
| Engine orchestration | `Sources/AlmanacCore/Insights/InsightsQuery.swift` |

Nine metrics: readiness, sleep minutes, hydration, steps, resting heart rate,
weight, training-load tonnage, mood, soreness. Five default pairs, chosen
because both sides are recorded daily — a pair the app rarely has data for
would sit at "insufficient" permanently and read as a broken feature.

## 2. The decisions that are not obvious

**A day with no reading is absent, not zero.** This is the whole reason
`CorrelationEngine` has a sample-size gate. Filling a gap would let a pair
reach the 14-day gate on days where one side was never measured, and the `r`
would be a statement about the interpolation as much as about sleep.

**Only days where *both* metrics have a reading are paired.** Same reason.

**How several entries on one day become one value is stated per metric.** Four
drinks sum to a day's hydration; two mood check-ins average to a mood. Getting
this wrong produces a chart that looks fine and means something else, so it is a
field on the enum rather than a decision taken at each call site.

**An unscored readiness record contributes nothing.** A provisional record is
not a zero readiness, and averaging one in would quietly pull every series down
on days the app had nothing to say.

**Sleep is time in bed, not a measured asleep time.** `sleep_episode` stores the
episode's duration and nothing finer. The label says "Sleep" because that is the
user's word for it; the value is not claimed to be more precise than it is.

**A nil tonnage is an absence.** A rest day and a session whose work is not
tonnage are both "no tonnage recorded", and neither is zero kilograms lifted.

## 3. Wording is load-bearing

The BRD's guardrails here are rules about what a screen may *say*, so they are
satisfied in the copy rather than in arithmetic:

- Every trend states **how many days of the window were actually recorded**.
  "Sleep fell 40 minutes" and "sleep fell 40 minutes across six recorded days of
  a fortnight" are different claims.
- A correlation below the gate says **"Not enough paired days — 3 of 14"**. Not
  a dash, not a zero, and not a number.
- The direction word is **"Higher together" / "Lower together"**, never "causes"
  or "affects". `r` cannot make a causal claim and the screen does not let it.
- The Associations section's footer states the caveat outright: *a number below
  says two measurements move together across the days both were recorded. It
  does not say one causes the other.*

## 4. Three defects fixed

- **`CorrelationPairStore` claimed "unordered" and was ordered.** `save` inserted
  the two metrics in the order given and `pair` looked up that exact order, so
  `("sleep","readiness")` and `("readiness","sleep")` were two rows holding the
  same number. A caller offering the pair the other way next time would see the
  old row's sample size beside a fresh `r`, or two rows in a list of "your
  correlations". Both metrics are now sorted into a canonical order on the way
  in and on the way out. `allPairs()` reads only canonical rows, so a database
  written before the fix reports each pair once.
- **`TrendDirection` round-tripped by accident.** `TrendSnapshotStore` wrote
  `String(describing: direction)`, which happened to produce `"up"` and matched
  the reader by luck; a case rename would have silently written a value nothing
  could read back. It now has a `String` raw value, so the storage
  representation is a decision.
- **`CorrelationResult` and `TrendSnapshot` were `Equatable` but not `Hashable`**,
  so neither could be carried in a `Hashable` result type. Now both are.

## 5. What is deliberately not computed

`AchievementEngine` needs nine inputs. Four are derived here; **five are
constants, each for a stated reason**, because a badge that claims a fact nobody
specified is worse than a badge that never appears.

| Input | Value | Why |
|---|---|---|
| `stepsTarget` | 0 | No step target is defined anywhere in this codebase. 0 means "any steps recorded", which is the only comparison the data supports. |
| `highLoadThreshold` | 0 | No high-load threshold is specified. |
| `calorieTargetMet` | false | Needs a Diet Profile resolver, not built. |
| `macroTargetMet` | false | Same. |
| `isPerfectLog` | false | The engine's own header says the handoff leaves "all Wellness data filled in, or all recommended entries logged?" undecided. |

So **`.perfectLog` is never awarded**, and a test fails if it ever is. The other
four badges do appear: a dry fast day is detected from `fasting_session`, and
hydration from the user's own `dailyGoalMilliliters`.

## 6. Still not built

- **Spearman and p-values.** `CorrelationEngine` is Pearson only. The Slice 10
  handoff recommended "Pearson/Spearman + thresholds"; Pearson is the concrete
  default that was proceeded on, and the p-value column exists but is written
  NULL. Both need a decision about what the app claims statistically.
- **Context tags as a correlation input.** The tags exist (`ContextTagsView`) and
  would be a natural confounder, but they are sparse by nature and would sit at
  "insufficient" permanently.
- **Charts.** Trends are numbers and ranges, not plots. `TrendsView` plots
  readiness because one line is worth plotting; nine small multiples is a
  different piece of work.
