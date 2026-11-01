---
name: ios-accessibility-qa
description: Validate Almanac's SwiftUI app for VoiceOver, Dynamic Type, contrast, touch targets, Reduce Motion, keyboard access, and RTL layouts. Use before shipping, after a UI change, or when asked to QA accessibility. Produces PASS/FAIL/UNRUN evidence and a release gate, and does not claim VoiceOver was tested when it was not.
---

# iOS accessibility QA — Almanac

This is a **validation** skill: run the app, drive the states, and record what actually
happened. It is not a line-by-line code audit of one view — use `accessibility-review` for
that. The two complement each other: the review finds risky code; this skill proves or
disproves the user-facing result.

## Ground truth to start from

- 56 Swift files declare views under `Native/Almanac`; the primary flows are Today
  (`ReadinessDashboardView`), Trends (`TrendsView`, `InsightsView`), Modules
  (`ModulesView`), Quick Log (`QuickLogView`), and the editors behind them.
- The app supports `en` and `ar`; Arabic strings live in `Localizable.xcstrings`.
- Dynamic Type is clamped in exactly four places (Today's eyebrow at `.xxLarge`, the custom
  bar captions at `.xLarge`, and two rhythm-calendar labels at `.xxxLarge` and `.xxLarge`).
  A fifth clamp needs a written reason.
- Reduce Motion is explicitly checked once (`ReadinessDashboardView`), around the readiness
  score animation. Every other animation must be checked in the running app.
- The palette is designed to pass AA: secondary text is about 5.88:1 light / 7.15:1 dark,
  and status colors are about 5.2–11:1. The divider is intentionally ~1.34:1 and is exempt
  as decorative structure. Recompute; do not inherit these numbers blindly.
- Charts (`TrendsView`, `BodyMetricHistoryView`, `DigestionHistoryView`,
  `BodyCircumferenceView`, `ExerciseProgressGraphsView`) have labels and per-mark values in
  places, but no `accessibilityChartDescriptor` today. Treat that as a known gap.
- The custom navigation bar is not a `TabView`; it must be validated as a control group, not
  assumed to inherit TabView semantics.

## What "PASS" means

Borrow the repo's convention (`docs/acceptance-checklist.md`):

| Mark | Meaning |
|---|---|
| **PASS** | Driven, observed, and the criterion holds. |
| **FAIL** | Driven and the criterion does not hold, with the observation recorded. |
| **UNRUN** | Not driven. No claim either way. |

Never mark a step PASS because the code "looks right." VoiceOver cursor behavior, focus
order, and verbosity require a human or a real assistive-technology pass; tooling reads the
tree but does not operate VoiceOver.

## Test matrix

Run this for the agreed scope (usually: all primary flows plus Settings/Profile and one editor
per data family).

| Area | Method | Pass criterion |
|---|---|---|
| VoiceOver semantics | `snapshot_ui` tree + manual VoiceOver | Every control has name, value, and correct trait; reading order is sensible; no duplicate or missing elements |
| VoiceOver behavior | Manual Sound/Speech on simulator or device | Actions announced, state changes announced, custom actions reachable via rotor |
| Dynamic Type | Simulator text size, including AX5 | No clipping/overlap; content reflows; controls remain reachable |
| Contrast | Compute + Accessibility Inspector | Text ≥ 4.5:1 (≥ 3:1 large); meaningful non-text ≥ 3:1; divider exempt |
| Touch targets | Tree frames + source | ≥ 44×44pt platform minimum and ≥ 50pt app minimum; no overlaps |
| Reduce Motion | Settings toggle + drive animations | No essential information depends on motion; animations are gated |
| Keyboard | Full Keyboard Access + hardware keyboard | Focus order is logical; activation, escape/dismiss, and text entry work; no trap |
| RTL | Arabic launch + screenshots | Layout mirrors; text/numbers/dates read correctly; icons mirror only when meaningful |
| Forms | Drive each input state | Labels, values, errors, and focus are announced; keyboard does not hide the action |
| Composed visuals | Tree + descriptor check | Rings, calendar, charts have a text equivalent; drag-only info has a static path |

## Tooling

XcodeBuildMCP is connected (see `.opencode/CONNECTORS.md`):

```text
build_run_sim
snapshot_ui                 # accessibility tree as text
tap / swipe / drag / type_text / wait_for_ui
screenshot
set_sim_appearance          # light / dark
set_sim_ui                  # content size, increase contrast
start_sim_log_cap / stop_sim_log_cap
```

Prefer `snapshot_ui` to prove structure, and `screenshot` to prove layout. For VoiceOver,
enable it manually: Simulator → Settings → Accessibility → VoiceOver (or use the
Accessibility Inspector). Automating the VoiceOver cursor is not supported by the current
tooling; say so in the report.

Known traps:

- **A shadowed element remains in the tree.** Re-snapshot after every state change and call
  `wait_for_ui("settled")`.
- **`elementRef`s are regenerated.** Never reuse one after changing state.
- **A collapsed root subtree is not a missing screen.** Today may report as one combined
  element; inspect its children under the capture's text.
- Dynamic Type and appearance changes can rebuild refs; re-snapshot after each.

## Procedures

### 1. VoiceOver

For each screen, walk the tree in reading order:

- **Name:** every control has `.accessibilityLabel` or a genuine visible label (not a sibling
  `Text` next to a slider).
- **Value:** sliders, steppers, toggles, pickers, and multi-select chip groups expose
  `.accessibilityValue` or an equivalent state.
- **Trait:** buttons are `.isButton`; selected tabs/chips carry `.isSelected`; headings use
  `.accessibilityHeading` where structure matters; decorative images are hidden.
- **Order:** date/title/primary reading/actions before secondary detail; the custom bar's
  destinations are announced as destinations, not images.
- **Custom gestures:** every `DragGesture`, `chartXSelection`, or swipe-only action has an
  `.accessibilityAction`, a visible control, or a static text alternative.
- **Announcements:** after save/error, the new state is reachable or announced; errors are not
  silent.
- **Duplicates:** `.combine` can make a container repeat its only child's label; `.ignore` plus
  an explicit label is the fix (see `AlmanacProblemNote`).
- **Charts and rings:** check for a descriptor or a text summary; a label plus hint without a
  descriptor is a gap.

Record the screen, element, name, value, trait, and issue. Distinguish "tree says" from
"VoiceOver said".

### 2. Dynamic Type

- Drive at least the default, `xxxLarge`, and `AX5` (`accessibility5`).
- Check: no clipped glyphs, no truncated controls, no overlapping rows, no content hidden
  behind the bar, actions still on screen.
- Verify the four existing clamps are still the only ones and remain justified; flag fixed
  `.font(.system(size:))` on text.
- Check composed layouts: Today's readiness card switches to a vertical arrangement at
  accessibility sizes; the rhythm calendar substitutes a linear day list. Confirm equivalents
  elsewhere rather than assuming.
- Check tab bar captions, metric rows, buttons, chart axes, and form labels.

### 3. Contrast

- Compute ratios from the actual colors in `DesignSystem.swift` (use relative luminance; show
  the numbers in the report).
- Text: 4.5:1 normal, 3:1 large. Non-text controls/state: 3:1.
- Decorative rules are exempt; do not report the divider.
- Check Increase Contrast on: the system may strengthen system colors while custom tokens stay
  fixed; verify meaningful boundaries and text still hold.
- Status colors are meaningful; their text pairings must pass.

### 4. Touch targets

- Measure interactive frames in the tree and in source.
- App minimum is 50pt (`AlmanacMetrics.minimumControl`); platform minimum is 44pt.
- Watch for invisible padding that looks larger than the actual hit area, rows whose action
  covers a footer, and adjacent controls sharing a seam.
- The Quick Log button is 52pt; metric rows are at least 64pt. Check chips, steppers, and
  chart selection areas.

### 5. Reduce Motion

- Toggle Settings → Accessibility → Motion → Reduce Motion.
- Drive score updates, sheet transitions, chart selection, pressed states, and any
  `withAnimation`.
- Pass only if no essential state change is conveyed solely by motion and animations are
  skipped or reduced. The pressed-state tint at 0.12s is not essential motion; the score
  animation is the one explicitly gated today.

### 6. Keyboard and Full Keyboard Access

- Enable Settings → Accessibility → Keyboards → Full Keyboard Access.
- Traverse with Tab/arrow keys: focus order follows visual/reading order, every control is
  reachable, Space/Return activates, Escape dismisses sheets/alerts, and no control traps
  focus.
- With a hardware keyboard, check text fields: focus, Return/Done, next-field behavior, and
  that the keyboard does not cover the primary action.
- Verify switches, segmented pickers, and the custom bar respond to keyboard selection.

### 7. RTL and Arabic

- Launch in Arabic: set the simulator/app language to Arabic (Settings → General → Language &
  Region), or use the scheme's launch arguments; verify the locale actually applied before
  recording results.
- Check: layout mirrors; leading/trailing spacing is correct; navigation chevrons mirror;
  physical-direction icons (rising arrows) do not mirror; numbers, dates, and units read
  correctly; mixed Arabic/Latin text does not reorder incorrectly.
- Check that body-side labels ("Left"/"Right" circumference) remain anatomical, not layout
  sides.
- Screenshot at least Today, Quick Log, Trends/Insights, and Settings.

### 8. Forms and errors

- Every `TextField`, `Picker`, `Slider`, `Stepper`, and `Toggle` has a programmatic label.
- Validation errors are announced and identify the field and fix.
- Destructive confirmations name the object and offer Cancel.
- Focus returns to a sensible place after an error or sheet dismissal.

### 9. Widgets

- Check the Almanac widget's labels and values, and that its buttons have meaningful
  names/hints. Verify actions are reachable without the app open.

## Severity and evidence

| Severity | Meaning | Examples |
|---|---|---|
| **Critical** | Blocks a task for an assistive-technology user | Unlabeled primary button; focus trap; action only via drag |
| **High** | Task possible but misleading or extremely difficult | Missing value on a slider; clipped text at AX sizes; color-only status |
| **Medium** | Friction or inconsistency | Weak hint; illogical focus order; icon mirrors incorrectly |
| **Low** | Polish | Redundant label; non-ideal announcement punctuation |

Evidence must be a screen/element, a computed ratio, a frame size, a screenshot path, or the
exact setting used. Mark untested states `UNRUN` and say why.

## Report template

```markdown
## Accessibility QA: [scope]

**Build:** [commit] · **Device:** iPhone 16e, iOS [version]
**Settings driven:** VoiceOver [on/off] · Dynamic Type [sizes] · Reduce Motion [on/off] ·
Increase Contrast [on/off] · FKA [on/off] · Language [en/ar]

### Release gate
**Result:** PASS / FAIL / BLOCKED (unrun)
| Area | Result | Notes |
|---|---|---|
| VoiceOver semantics | | |
| Dynamic Type | | |
| Contrast | | |
| Touch targets | | |
| Reduce Motion | | |
| Keyboard | | |
| RTL | | |

### Findings
| # | Severity | Area | Finding | Evidence | Fix |
|---|---|---|---|---|---|

### VoiceOver detail
| Screen | Element | Name | Value | Trait | Issue |
|---|---|---|---|---|---|

### Contrast computations
| Pair | Ratio | Required | Result |
|---|---|---|---|

### Coverage and gaps
- Driven: …
- UNRUN (and why): …
- Tree-only claims (VoiceOver not operated): …
```

## Release gate — acceptance criteria

Ship only when all are true, or an exception is explicitly accepted in writing:

1. **Zero Critical** findings; every High is fixed or has an accepted, dated exception.
2. Every primary flow (Today, Quick Log, Trends, Modules entry, Settings) passes
   name/value/trait and reading-order checks in the tree.
3. No text is clipped or controls overlapped at `AX3` or below, and primary flows remain
   usable at `AX5`.
4. All text and meaningful non-text contrast meets 4.5:1 / 3:1; Increase Contrast verified.
5. No interactive target is below 50pt in the app or overlaps another.
6. Reduce Motion is respected; no essential information is motion-only.
7. Full Keyboard Access can traverse and complete the primary flows without a trap.
8. Primary screens pass in Arabic/RTL, including mirrored navigation and correct numerals and
   dates.
9. Every chart/ring/calendar has a text equivalent; drag-only detail has a static alternative.
10. The report distinguishes driven results from inferred ones and marks `UNRUN` honestly.

## Boundaries

| Question | Use |
|---|---|
| Code-level a11y audit of one view | `accessibility-review` |
| Design tokens, type scale, RTL doctrine | `almanac-design-system` |
| General usability and navigation | `ios-ui-ux-audit` |
| Chart honesty and data semantics | `health-data-visualization` |

This skill owns validation procedure, evidence, severity, and the release gate. It does not
redefine the design system and does not edit application code unless asked.
