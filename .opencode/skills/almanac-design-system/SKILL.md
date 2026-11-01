---
name: almanac-design-system
description: "Define and enforce Almanac's SwiftUI design system: semantic colors, typography, spacing, reusable components, light/dark, and RTL, while preserving native iOS conventions. Use before changing any view, when a UI change looks off, when reviewing a diff that touches Native/Almanac, or when auditing hardcoded values against the tokens."
---

# Almanac design system

Almanac is a private physiological logbook. One person records sleep, water, food, training,
prayer, fasting, body measurements, and lab results against days that begin at 04:00, then
reads one readiness number back. The interface is **instrument-like, not decorative**:
neutral paper, hairline rules, and an ink-blue accent that marks something the app *measured*.
Status colors are the only colors allowed to carry judgement.

## Source of truth

`Native/Almanac/DesignSystem.swift` is the implementation and its doc comments are the
authority. This skill is the doctrine and the review procedure. If the two disagree, the code
wins and this file is what needs fixing.

Supporting files:

| Concern | Source |
|---|---|
| Icons | `Sources/AlmanacCore/Design/AlmanacIcon.swift` |
| Localized numbers | `Sources/AlmanacCore/Localization/NumberInput.swift` |
| Display units | `Sources/AlmanacCore/Localization/UnitDisplay.swift` |
| Appearance setting | `AlmanacAppearance` in `DesignSystem.swift` |
| Objective measurement | `docs/ui/measure.sh`, `docs/ui/capture.sh` |

## Tokens

### Color — `AlmanacPalette`

All colors resolve per appearance through `UIColor { traits in … }`. Never hardcode a color,
a hex literal, `Color.accentColor`, or `.red`/`.green`/`.orange` outside this file.

| Token | Light | Dark | Meaning and use |
|---|---|---|---|
| `canvas` | `#FCFCFA` | `#0B0B0C` | The page. A true neutral, not a warm cream. |
| `surface` | `#F1F1ED` | `#15161A` | One step off the page: the bar, a prominent panel. |
| `surfaceMuted` | `#E6E6E1` | `#1E2024` | Second step: icon wells, chips, pressed rows. |
| `divider` | `#DCDCD6` | `#2A2C30` | Rules and card outlines. Never a `Divider()`. |
| `textPrimary` | `#1A1A18` | `#ECECEA` | Body and readings. |
| `textSecondary` | `#63635E` | `#9A9C9F` | Supporting text and captions. |
| `accent` | `#1F4E8C` | `#6FA0D8` | **Only** where Almanac recorded something. |
| `onAccent` | `#FFFFFF` | `#0B0B0C` | Text/icons on an accent fill. |
| `good` | `#1E7A4C` | `#63D394` | Status: measured good. |
| `warning` | `#8A5A00` | `#F2B84B` | Status: caution. |
| `critical` | `#B3261E` | `#FF7A70` | Status: failure or danger. |

`AlmanacStatusTone` (`.neutral`, `.good`, `.warning`, `.critical`) maps tone to color and
symbol. Use the tone, not the color, when the meaning is a judgement.

### Typography — `AlmanacTypography`

`AlmanacTypography.font(_:locale:)` returns a Dynamic Type–relative font. Use roles, never
ad-hoc sizes for text.

| Role | Size | Style | Face |
|---|---|---|---|
| `.display` | 64 | `.largeTitle` | Fraunces |
| `.screenTitle` | 34 | `.title` | Fraunces |
| `.sectionTitle` | 22 | `.title2` | Sans, medium |
| `.body` | 17 | `.body` | Sans, regular |
| `.bodyMedium` | 17 | `.body` | Sans, medium |
| `.label` | 13 | `.caption` | Sans, medium |
| `.caption` | 12 | `.caption` | Sans, regular |
| `.data` | 17 | `.body` | Sans, medium — pair with `.monospacedDigit()` |
| `.dayNumber` | 12 | `.caption` | Sans |

- **Fraunces is display-only.** `.display` and `.screenTitle`, nothing else. At 22pt and
  below its high-contrast strokes are the thinnest part of the cut, so headings inside
  content use the sans at medium weight.
- Arabic locale swaps to **Almarai** (regular/bold). PP Neue Montreal is commercially
  licensed and not redistributed; the system fallback is intentional until licensed files
  exist.
- Every reading gets `.monospacedDigit()` so digits do not jitter as values change.

### Spacing and geometry — `AlmanacMetrics`

| Token | Value | Use |
|---|---|---|
| `screenInset` | 20 | Horizontal page inset |
| `cardPadding` | 24 | Inside an `AlmanacCard` |
| `sectionGap` | 32 | Between page sections |
| `cardRadius` | 14 | Card corner |
| `controlRadius` | 10 | Buttons and controls |
| `minimumControl` | 50 | Minimum hit target (above iOS's 44) |
| `ruleWeight` | 1 | The only rule weight |
| `AlmanacRule.metricTextInset` | 62 | Aligns a rule with a metric row's text |

## Components — use these before inventing

| Component | What it is for | Rules |
|---|---|---|
| `AlmanacRule` | The structural device: horizontal or vertical | Never `Divider()`, never a bare `Rectangle().fill(divider)` |
| `AlmanacCard` | A panel | `prominent: true` for the one object a screen is about; everything else outlined |
| `AlmanacSectionHeader` | Section title with optional factual `detail` | Sentence case; detail carries a range/count/window, never decoration |
| `AlmanacEyebrow` | Small caption above a heading | Sentence case, no tracking; default secondary ink, not accent |
| `AlmanacMetricRow` | Icon, title, value, optional detail and tone | Pass `action` only when the row opens something; a nil action is a reading, not a dead button |
| `AlmanacMeter` | Progress toward a target | `fraction: nil` draws no track at all; never render an empty bar as "0%" |
| `AlmanacStatusMark` | Status word + symbol in a tone | Tone must match the word; do not use for decoration |
| `AlmanacProblemNote` | A read/save failure, in place | Never a substitute for an empty state; one accessible element |
| `AlmanacMetricRowStyle` | Pressed state for metric rows | Tinted surface, 0.12s, no scale |
| `AlmanacPrimaryButtonStyle` | The one primary action | Full width, 50pt minimum, accent fill |
| `AlmanacSecondaryButtonStyle` | Secondary action | Outlined, 50pt minimum |

Modal screens are built from native `Form`/`List` and `NavigationStack`; they still use the
palette and type roles. For screen-level setup use `.almanacScreen()`,
`.almanacModuleSurface()`, and `.almanacNavigationHost(_:)` rather than repeating the
tint/background/scroll treatment.

## Doctrine rules

1. **Rules separate; containers do not.** Most panels are ruled areas of the page, not boxes
   stacked on it. Reach for `AlmanacRule` before a second surface.
2. **One prominent card per screen.** It is for the single object the screen is about
   (on Today, readiness). Everything else is `prominent: false`.
3. **Accent means measured.** Ink-blue appears where Almanac recorded something. Do not tint
   labels, borders, or decoration with it.
4. **Two surface steps, no more.** A third surface means the hierarchy is wrong, not the
   color.
5. **Fraunces is display-only.**
6. **Sentence case, no tracking, no uppercase** on headings and eyebrows. The tracked all-caps
   eyebrow is the oldest template tell there is.
7. **Data is monospaced.** Every reading uses `.monospacedDigit()`.
8. **Touch targets are `AlmanacMetrics.minimumControl` (50pt).** Nothing interactive may be
   smaller or overlap another interactive element.
9. **The canvas is a true neutral**, not a warm tint.
10. **Never replace a missing reading with zero.** When there is no score, the value slot
    stays empty and the state is stated in words (`ReadinessDashboardView.readinessValue`).
    A physiological instrument that invents a plausible number is worse than one that says it
    does not know yet.

## Light and dark

- Both appearances ship. A change is incomplete until it is reviewed in both.
- Colors come from semantic tokens; a raw `Color(.systemGray…)` or `.primary` is a finding
  when a token exists.
- The divider is intentionally low contrast (~1.3:1) because it is decorative structure, not
  a control boundary. Do not "fix" it; do verify text and meaningful non-text contrast.
- Increase Contrast is a system setting; check that the app still reads with it on.
- Do not invert or hand-pick colors per appearance; add a dynamic token instead.

## RTL and Arabic

The app supports `en` and `ar` (`knownRegions` in the Xcode project), with 1,200+ Arabic
strings in `Localizable.xcstrings`.

- Use **leading/trailing**, never left/right, for layout. `HStack`, `List`, `Form`, and
  navigation mirror automatically.
- Use directional SF Symbols that mirror when the meaning is layout direction
  (`chevron.forward`, `chevron.backward`, `arrow.forward`). Do not mirror symbols whose
  meaning is physical direction (an arrow meaning "up/rising").
- Do not flip images or icons manually unless they encode layout, not content.
- Numbers, dates, and units go through the app's formatting (`AlmanacNumber`,
  `NumberDisplay`, `UnitDisplay`, `Calendar.almanacDisplay`), not string interpolation.
- Body-side labels ("Left"/"Right" circumference) are anatomical sides, not layout sides;
  they are correctly not mirrored.
- Test Arabic by launching in an Arabic locale and walking at least Today, Quick Log, Trends,
  and Settings. Watch for truncated labels, mixed-direction text, and controls that assume a
  left-to-right reading order.

## Native iOS conventions

- Prefer system navigation, sheets, alerts, lists, forms, pickers, and text fields. The
  custom bar is a deliberate, documented departure; do not add a second one.
- Root screens carry no navigation title; Today hides the navigation bar. Pushed screens use
  native titles and back behavior.
- Respect safe areas; the bar is in layout flow so content is never trapped underneath it.
- Let text scale. Dynamic Type clamps are rare, considered trade-offs, and need a comment.
- Use the right keyboard, capitalization, and content type on inputs.
- Destructive actions use a role and a confirmation where the result cannot be undone.

## Enforcement checklist

Run on any view change:

- [ ] No raw color, hex, `Color.accentColor`, or judgement color outside the palette.
- [ ] No `Divider()` and no hand-drawn rule; use `AlmanacRule`.
- [ ] Spacing and radii come from `AlmanacMetrics` where a token exists.
- [ ] Type uses `AlmanacTypography` roles; readings use `.monospacedDigit()`.
- [ ] At most one prominent card on the screen.
- [ ] Accent appears only where something was measured.
- [ ] Missing data stays missing; no invented zero or placeholder value.
- [ ] Touch targets are at least 50pt and do not overlap.
- [ ] Light and dark both checked.
- [ ] Leading/trailing used; Arabic checked when the layout can mirror.
- [ ] Dynamic Type at accessibility sizes checked; any new clamp has a written reason.
- [ ] `docs/ui/measure.sh` reports one rule weight and no off-token colors on the capture.
- [ ] Native control behavior preserved (back, sheet dismissal, keyboard, selection).

## Acceptance criteria for a design-system change

A change is acceptable only when all are true:

1. It introduces no new token unless the existing set genuinely cannot express the meaning,
   and the new token has a documented semantic name.
2. It works in light and dark without per-appearance hacks.
3. It survives the largest Dynamic Type size without clipping or overlapping controls.
4. It reads correctly in RTL/Arabic if it uses direction-sensitive layout.
5. It preserves the 04:00 logical-day and measured-data semantics.
6. It uses an existing component where one exists; a new component documents its states
   (default, pressed, disabled, loading, error, empty, accessibility size).
7. `measure.sh` still passes on Today light/dark/largest-type.

## Anti-patterns already retired — do not reintroduce

| Anti-pattern | Why it is wrong here |
|---|---|
| All-caps tracked eyebrows | Template tell; kills the daybook voice |
| A page of identical filled cards | No hierarchy |
| Warm cream canvas | Reads as a template; forces extra near-whites |
| A warm/product accent blue | Should read as a pen in a chart margin |
| Floating action overlapping content | Steals taps from the row underneath |
| Status color used decoratively | Judgement is the only thing it is for |
| Inventing a zero for missing data | Rule 10 |
| `Divider()` or a second rule weight | Three weights appeared on one screen once |
| `Text` + `.onTapGesture` as a button | No role, no value, no hit target |

## When doctrine and a request conflict

Say so rather than quietly complying. If a request is "make it look like a normal app", name
the specific normal-app thing that conflicts and what it costs — usually a floating element
over content, a filled card grid, or an accent used for decoration. Offer the version that
fits the instrument.

## Boundaries

| Question | Use |
|---|---|
| Is this flow usable and coherent? | `ios-ui-ux-audit` |
| Is this screen accessible? | `ios-accessibility-qa` |
| Is this chart honest? | `health-data-visualization` |
| What should this label say? | `ux-copy` |
| Visual taste on one screen | `design-critique` |

This skill owns tokens, components, doctrine, and light/dark/RTL enforcement. It does not
run usability or accessibility audits; it supplies the rules those audits check against.
