---
name: health-data-visualization
description: Set and enforce standards for Almanac's Swift Charts, trends, health metric units, missing data, aggregation, and time ranges so charts never mislead or invent health insights. Use when adding or reviewing any chart, trend, insight, or health metric surface, or when a graph looks wrong or overconfident.
---

# Health data visualization — Almanac

Almanac is a physiological logbook for one person. A chart is a claim about their body. The
standard is not "it looks good"; it is "a careful reader cannot draw a conclusion the data
does not support."

This skill covers chart and trend semantics. It does not cover general page layout (see
`almanac-design-system`) or end-to-end usability (see `ios-ui-ux-audit`).

## Known chart and health surfaces

| Surface | File | What it plots | Window |
|---|---|---|---|
| Readiness trend | `Native/Almanac/TrendsView.swift` | Readiness score (0–100) with threshold bands | 30 / 90 / 365 days |
| Insights | `Native/Almanac/InsightsView.swift` | Trend summaries, correlations, badges | 14 / 30 / 90 days |
| Body metric history | `Native/Almanac/BodyMetricHistoryView.swift` | One body-composition metric | Last 366 days |
| Body circumference | `Native/Almanac/BodyCircumferenceView.swift` | Measurement series | Per screen |
| Digestion history | `Native/Almanac/DigestionHistoryView.swift` | Daily counts, Bristol/colour tallies | 7 / 30 / 90 days |
| Exercise progress | `Native/Almanac/ExerciseProgressGraphsView.swift` | Load and reps performed, by equipment variant | Full history |

Data helpers: `Sources/AlmanacCore/Insights/TrendEngine.swift`,
`CorrelationEngine.swift` (minimum 14 paired days), `Sources/AlmanacCore/Health/HealthSummaryStore.swift`,
`Sources/AlmanacCore/Localization/UnitDisplay.swift`.

## Non-negotiable data rules

These come from the app's own doctrine and existing behavior. Treat violations as findings,
not style preferences.

1. **Missing is not zero.** No score means the value slot stays empty and the state is said in
   words (`ReadinessDashboardView.readinessValue`). `HealthSummaryStore` omits domains with no
   rows. A summary cell with no number shows `—`, never `0`. `AlmanacMeter(fraction: nil)`
   draws no track. A health app that invents a plausible number is worse than one that says
   it does not know.
2. **A failed read is not an empty state.** "Could not load" and "nothing recorded" are
   different claims. Show the failure with `AlmanacProblemNote` where it happened; leave the
   empty state for genuinely empty windows.
3. **Every chart states its window and its n.** "90 days" is the window; the number of days
   actually recorded is `n`. `InsightsView` already states paired-day counts and says "not
   enough paired days" instead of printing a weak correlation.
4. **Aggregation is named.** Average, minimum, maximum, direction (Rising/Easing/Steady), and
   count are different facts. Do not label an average as a "score", or a direction with two
   points as a trend.
5. **Correlation is not causation, and neither is advice.** Association copy names the paired
   sample size and the window. No causal verb, no diagnosis, no supplement/medication advice.
   Digestion advisories stay withheld pending clinician review (`docs/features/digestion.md` §3).
6. **Units are stored as codes and displayed localized.** Use `UnitDisplay.localized` for
   `ml`, `kg`, `bpm`, `ms`, `min`, `kcal`, `mg`, `/10`. Laboratory units such as `mmol/L` are
   the source's own text and are shown verbatim. Never silently convert or relabel a unit.
7. **Time is the logical day.** Days begin at 04:00 (`TimeModel`), dates display in Gregorian
   `Calendar.almanacDisplay`, and missing date precision stays missing
   (`PartialDateTime`, "Date unknown"). Do not invent a timestamp to place a point.
8. **One measured ink.** `AlmanacPalette.accent` marks recorded data. Status colors
   (`.good`, `.warning`, `.critical`) are reserved for judgement. Multiple series are
   distinguished by symbol and legend, not by inventing extra line colors.
9. **Nothing is conveyed by color alone.** Every series has a legend or label; every bar and
   point has an accessible name and value.
10. **The y-axis must not exaggerate.** Counts and volumes start at zero. A body metric may
    use `.automatic(includesZero: false)` (as `BodyMetricHistoryView` does) only when the axis
    labels make the range legible and the caption does not imply a dramatic change. Readiness
    is fixed at 0…100. No broken axis without disclosure.

## Before building a chart — answer these

Write the answers into the PR or the view's doc comment; a chart that cannot answer them is
not ready.

- [ ] **Question:** what single question does this chart answer?
- [ ] **Metric and unit:** what exactly is plotted, and in which unit?
- [ ] **Window:** 7 / 14 / 30 / 90 / 365 days — and is the user told?
- [ ] **Aggregation:** raw readings, daily total, daily average, or a summary statistic?
- [ ] **n:** how many points or paired days? What is shown when n is too small?
- [ ] **Missing data:** gaps, zeros, or omitted points — and does the caption say which?
- [ ] **Comparison:** is there a baseline, target, or threshold? Is it data or judgement?
- [ ] **Scale:** what are the axis minimum and maximum, and why?
- [ ] **Accessibility:** what does a non-visual reader get instead of the shape?

## Rules while implementing

### Marks and series

- Use `LineMark` for a continuous quantity over time and `PointMark` to show where actual
  readings exist. A line through two points is not a trend; say "one session logged so far —
  a line needs at least two."
- Use `BarMark` for counts and categories. Do not use bars for a continuous physiological
  value over time.
- Reference bands use dashed `RuleMark` and a caption naming the threshold and scale
  (`TrendsView` does this). They are not data series and belong in the legend only if
  labelled.
- Separate variants only when the comparison is legitimate; otherwise show one line and say
  why (`EquipmentVariant.combinedModeFootnote`).
- Do not connect across long gaps as if the readings were adjacent. If interpolation is used,
  disclose it; prefer showing the gap.

### Axes and scale

- Label axes with the metric and unit (`Load (kg)`, `Reps (sets × reps)`).
- Use the app's date formatting for axis labels (`Date.FormatStyle.almanacDateTime`), not a
  hand-built formatter.
- Keep tick counts small enough to read at accessibility sizes.
- If the domain is fixed for a score (0–100), pin it. If it is automatic, verify the first and
  last labels are visible and not misleading.

### Selection and inspection

- `chartXSelection` may reveal a point, but the same information must exist without dragging:
  a selected-record card, a table, or an accessibility descriptor.
- A selected marker must not imply precision the data lacks. Show the date and value, not a
  smoothed estimate.
- Reset or default the selection predictably; do not silently show the last point as if it
  were today's reading.

### Accessibility for charts

- Give the chart an `.accessibilityLabel` and a truthful `.accessibilityHint`.
- Provide `.accessibilityChartDescriptor` (or an equivalent text summary/table) for every
  chart. Today `TrendsView` has a label and hint but no descriptor; treat that as a known gap,
  not a pattern to copy.
- Bars and points may carry per-mark labels/values (see `DigestionHistoryView`, which labels
  each bar and gives it a count).
- At accessibility type sizes, prefer a linear fallback list over a shrunken chart when the
  chart cannot be read.
- Do not rely on color, position alone, or drag for meaning.

### Motion and performance

- Gate animation on `\.accessibilityReduceMotion`; do not animate a reading into place in a
  way that delays the number.
- Bound the number of marks (a year of daily points is acceptable; multiple years of raw
  samples need aggregation or downsampling).
- Charts should not fight the scroll view; avoid nested gestures that steal scrolling.

## Review checklist for an existing chart

- [ ] Window and n are visible in text, not implied.
- [ ] Missing days are gaps or explicitly explained; no zero-substitution.
- [ ] Y-axis domain and ticks make the magnitude honest; units are on the axis.
- [ ] Aggregation is named; a summary is not presented as a raw reading.
- [ ] Trend words match the evidence (two points are not "rising").
- [ ] Correlations show paired-day count and respect the 14-day minimum.
- [ ] No causal, diagnostic, or treatment claim.
- [ ] Series are distinguishable without color alone.
- [ ] Units localized through `UnitDisplay`; dates through the display calendar.
- [ ] Selected-point details are available without a drag.
- [ ] Chart has a text equivalent and (ideally) a chart descriptor.
- [ ] Animation respects Reduce Motion.
- [ ] Light/dark and Arabic/RTL checked; axis direction mirrors correctly.

## Misleading-pattern red flags

| Pattern | Why it misleads | Corrective |
|---|---|---|
| Zero substituted for a missing reading | Invents a measurement | Omit the point; state "no reading" |
| `Emphasize`-style truncated axis with no labels | Exaggerates change | Start at zero, or label the range and explain |
| One point drawn as a trend line | Implies direction from nothing | Point only; say more data is needed |
| Average presented as "today's score" | Changes the question | Name the window and statistic |
| Correlation printed below the minimum n | Statistical noise as insight | "Not enough paired days" |
| Status color on a neutral series | Implies judgement | Use accent + symbol/legend |
| Percent change from a tiny base | Amplifies noise | Show absolute values and n |
| "Improved" language without a baseline | Asserts causality/value | State the comparison and its basis |

## Acceptance criteria

A chart or health-insight change is acceptable only when:

1. It satisfies every pre-build question and the review checklist.
2. It contains no invented value, zero-substituted gap, or undocumented aggregation.
3. Its axis, units, window, and n are stated on screen.
4. Its claims survive the red-flag table: no causal or diagnostic overreach.
5. It has a non-visual equivalent, and any drag interaction has a static alternative.
6. It works in light/dark, at accessibility sizes, and in RTL/Arabic.
7. Its animation respects Reduce Motion.
8. `TrendEngine`/`CorrelationEngine` gates are respected, not reimplemented ad hoc.

## Boundaries

| Question | Use |
|---|---|
| Tokens, type, color, layout doctrine | `almanac-design-system` |
| Is the screen usable? | `ios-ui-ux-audit` |
| Is the chart accessible? | `ios-accessibility-qa` |
| Wording of the insight or caption | `ux-copy` |

This skill owns data semantics: what is plotted, what is omitted, what is claimed, and in what
unit and window.
