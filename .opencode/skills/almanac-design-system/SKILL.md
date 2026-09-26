---
name: almanac-design-system
description: Almanac's own design doctrine, as rules an agent can check code against. Use before changing any view, when a UI change "looks off", when reviewing a diff that touches Native/Almanac, or when deciding whether a proposed visual change fits the app. Triggers on "does this fit", "is this on-brand", "design review", "Almanac style".
argument-hint: "[optional: the view, file, or proposed change to check]"
---

# Almanac design doctrine

Almanac is a private physiological logbook. One person records sleep, water, food,
training, prayer, fasting and lab results against days that begin at 04:00, then reads
one readiness number back. The interface is **instrument-like, not decorative** — neutral
paper, hairline rules, and an ink-blue accent that marks something the app *measured*.

This skill is the doctrine. `Native/Almanac/DesignSystem.swift` is its implementation and
its doc comments are the source of truth; if the two disagree, the code wins and this file
is the thing that needs fixing.

## The tokens

Never hardcode these. All of them live in `DesignSystem.swift`.

| Token | Use |
|---|---|
| `AlmanacPalette.canvas` | The page |
| `AlmanacPalette.surface` | One step off the page — a panel, or the bar |
| `AlmanacPalette.surfaceMuted` | A second step. Chips, icon wells, selected tab background |
| `AlmanacPalette.divider` | Rules. The structural device |
| `AlmanacPalette.textPrimary` / `.textSecondary` | Body / supporting text |
| `AlmanacPalette.accent` | **Only** where Almanac recorded something |
| `AlmanacPalette.onAccent` | Text on an accent fill |
| `AlmanacPalette.good` / `.warning` / `.critical` | Status. The only colours allowed to carry judgement |

`AlmanacMetrics`: `screenInset 20`, `cardPadding 24`, `sectionGap 32`, `cardRadius 14`,
`controlRadius 10`, `minimumControl 50`.

`AlmanacTypography.font(_:)`: `.display`, `.screenTitle`, `.sectionTitle`, `.body`,
`.bodyMedium`, `.label`, `.caption`, `.data`, `.dayNumber`.

## Rules

1. **Rules separate; containers do not.** Most panels are ruled areas of the page, not
   boxes stacked on it. A screen where every block is an identical filled card has no
   hierarchy at all. Reach for a `Rectangle().fill(AlmanacPalette.divider)` before a
   second surface.
2. **One prominent card per screen.** `AlmanacCard(prominent: true)` is for the single
   object the screen is about. Everything else is `prominent: false`.
3. **Accent means measured.** Ink-blue appears where Almanac recorded something. Do not
   tint a label, a border, or a decorative element with it — that spends the one colour
   that carries meaning. Status colours are the *only* other colours allowed to mean
   anything.
4. **Two surface steps, no more.** Reaching for a third surface means the hierarchy is
   wrong, not the colour.
5. **Fraunces is display-only** — `.display` and `.screenTitle` and nothing else. At
   22pt and below its high-contrast strokes are the thinnest part of the cut, so
   headings inside content are the sans at medium weight.
6. **Sentence case, no tracking, no uppercase** on every heading and eyebrow.
   `AlmanacSectionHeader` and `AlmanacEyebrow` already do this. A tracked-out all-caps
   eyebrow above every heading is the oldest template tell there is.
7. **Data is monospaced.** `.monospacedDigit()` on every reading, so digits do not
   jitter as values change.
8. **Touch targets are `AlmanacMetrics.minimumControl`** (50pt), which is above the 44pt
   platform minimum. Nothing interactive may be smaller, and nothing interactive may
   overlap something else interactive.
9. **The canvas is a true neutral**, not a warm tint. A warm cream reads as a template.
10. **Never replace a missing reading with zero.** This is load-bearing, not a style
    rule. When there is no score, the value slot stays empty and the state is stated in
    words — see `ReadinessDashboardView.readinessValue(_:)`, whose comment says exactly
    this. A physiological instrument that invents a plausible number is worse than one
    that says it does not know yet.

## Screen anatomy

- Three destinations (Today, Trends, Modules) and one action (Quick Log) in a custom bar
  in the layout flow — not a `TabView`, and not `safeAreaInset`, because a navigation
  stack swallows the inset and traps the last row.
- Today is the app's most important screen: date, title, greeting, the one prominent
  readiness panel, the day's primary action, then a ruled list of what was recorded.
- Root screens carry no navigation title; Today hides its bar entirely.

## Anti-patterns, already retired from this codebase

Do not reintroduce these. Each has been fixed once and has a commit or a comment saying so.

| Anti-pattern | Why it is wrong here |
|---|---|
| All-caps tracked eyebrows | The oldest template tell; kills the daybook voice |
| A page of identical filled cards | No hierarchy — see rule 1 |
| Warm cream canvas | Reads as a template, forces three near-whites to stay legible |
| A warm accent blue | Should read as a pen in a chart margin, not a product |
| A floating action overlapping content | It steals taps from the row underneath |
| Status colour used decoratively | Judgement is the only thing it is for |
| Inventing a zero for missing data | Rule 10 |

## Checking a change

1. Does it introduce a raw `Color(`, `Color.accentColor`, or a hex literal outside
   `DesignSystem.swift`? That is a finding.
2. Does it hardcode a spacing or size number where a token exists? `AlmanacMetrics` is
   under-used across this app, so new code should not add to the problem.
3. Does it add a prominent card, and is there already one on that screen?
4. Is anything interactive under 50pt, or overlapping something interactive?
5. Does it clamp Dynamic Type with `.dynamicTypeSize(...)`? There are only four such
   sites and each is a considered trade-off; a fifth needs a reason in a comment.
6. Does it animate without checking `\.accessibilityReduceMotion`?

## When the doctrine and a request conflict

Say so rather than quietly complying. If a request is "make it look more like a normal
app", the honest answer is which specific normal-app thing conflicts and what it costs —
usually it is a floating element over content, a filled card grid, or an accent used for
decoration. Offer the version that fits the instrument.
