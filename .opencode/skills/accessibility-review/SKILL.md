---
name: accessibility-review
description: Accessibility audit of Almanac's SwiftUI views. Trigger with "audit accessibility", "check a11y", "is this screen accessible?", or before shipping a view. Covers VoiceOver semantics, Dynamic Type, touch targets, Reduce Motion, and colour contrast. Reads Swift source; uses simulator settings and a screenshot where available.
argument-hint: "<view or screen name, e.g. today | quick-log | check-in, or a screenshot path>"
---

# /accessibility-review

Audit Almanac's views for accessibility. This is a **native iOS** app, so the platform
model applies, not the web one: there is no ARIA, no keyboard focus ring, no hover state,
and no DOM. The WCAG success criteria still describe the intent, but map onto SwiftUI as
below.

## Usage

```
/accessibility-review $ARGUMENTS
```

Audit for accessibility: @$1

## What I Need From You

- **The view**, by name or file (`Native/Almanac/<Name>.swift`)
- **Focus** (optional): "just VoiceOver" or "just Dynamic Type"

## Criteria, mapped to iOS

| Criterion | On iOS | Where to look |
|---|---|---|
| 1.3.1 Info and structure | Semantic structure, headings, grouping | `accessibilityElement(children:)`, `accessibilityHeading` |
| 1.4.3 Contrast ≥ 4.5:1 (≥ 3:1 large) | `AlmanacPalette` pairs | compute the ratio; do not eyeball |
| 1.4.11 Non-text contrast ≥ 3:1 | Control boundaries and state | **decorative section rules are exempt** |
| 2.1.1 / 2.4.3 / 2.4.7 Keyboard | *Not applicable* — but Full Keyboard Access and Switch Control are | `.accessibilityAction`, custom gestures need an action |
| 2.5.5 Target ≥ 44×44pt | `AlmanacMetrics.minimumControl` (50) | any interactive frame, or an overlap between two |
| 3.3.1 / 3.3.2 Errors and labels | `editorError(_:)`, input labels | `TextField`/`Slider`/`Picker` with no label |
| 4.1.2 Name, role, value | **The big one.** Label + value + trait | see below |

## The four checks that matter most here

**1. Is it a control at all?** A `Text` with `.onTapGesture` is not a control. VoiceOver
announces it as static text, exposes no selected state, and hit-tests only the glyph
bounds. This app had exactly that in the soreness chips. Look for
`onTapGesture` / bare `Text` + tap where a `Button` belongs.

**2. Name, value, trait.** For every `Button`, `Toggle`, `Slider`, `Picker`, `Stepper`:
- **Name** — `.accessibilityLabel`, or a visible label that is genuinely a label and not a
  sibling. `Text("\(score)/10")` next to a `Slider` is a *sibling*, not a label; the slider
  still has no name.
- **Value** — `.accessibilityValue` for anything with a state a user cannot see, including
  every `Slider` and every multi-select chip group.
- **Trait** — `.accessibilityAddTraits(.isSelected)` on selectable things. Traits are
  declared in exactly one place in this app; that is the finding.

**3. Dynamic Type.** Count `.dynamicTypeSize(...)` clamps — there are four and each is a
considered trade-off, so a fifth needs a comment justifying it. Count fixed
`.font(.system(size: N))` calls, which bypass the type scale entirely. Check for
`.minimumScaleFactor` / `.lineLimit` / `.truncationMode` (there are none). Then ask what
breaks at `.accessibility3`.

**4. Composed visuals need a text equivalent.** The activity rings, the rhythm calendar and
the trends chart are built from primitives, so VoiceOver sees nothing useful unless the
view supplies one. The pattern to hold them to is
`EditorialRhythmCalendarView`'s `accessibleDayList` — a linear list substituted for the
grid at accessibility sizes, with a composed label per day. The trends chart has a label
and a hint promising drag-to-inspect, and no `accessibilityChartDescriptor`; the promise
is not kept.

## States

A published error that no view renders is an accessibility finding, not just a bug: the
user gets silence. Check that `@Published` error channels are actually drawn. Three models
in this app publish one that is not.

## Contrast: compute, do not estimate

The palette passes AA on every text pair in both appearances (secondary text 5.88:1 light,
7.15:1 dark; status colours 5.2–11:1), so contrast is rarely the finding. The one
sub-3:1 pair is the hairline `divider` at ~1.34:1, which is **correct**: WCAG 1.4.11 covers
component boundaries that convey state, and a decorative section rule is exempt — Apple's
own separators run about 1.3:1. Do not report it. If you claim a contrast failure, show the
computation.

## Testing approach

**XcodeBuildMCP is connected** — see `.opencode/CONNECTORS.md`. Use it rather than guessing:

```sh
build_run_sim                    # honours .xcodebuildmcp/config.yaml defaults
snapshot_ui                      # the accessibility tree, as text
tap / swipe / drag / type_text   # by elementRef, to reach a given state
set_sim_appearance               # light / dark
```

`set_sim_ui` also covers content size and increase contrast, so the Dynamic Type and
Increase Contrast questions are answerable by looking rather than by reasoning about
SwiftUI layout.

Two limits, both of which will produce false findings if ignored:

- **VoiceOver is not simulated.** The tree is the same data VoiceOver reads, but the
  cursor, focus order and verbosity are not exercised. Say so rather than implying a
  VoiceOver pass happened.
- **A shadowed element is still in the tree.** A sheet covering a screen does not remove
  the screen. Re-snapshot after every state change, and `wait_for_ui("settled")` before
  trusting an `elementRef`.

## Output

```markdown
## Accessibility Audit: [view]

### Summary
**Controls:** [N] | **With semantics:** [N] | **Critical:** [N] | **Major:** [N]

### Findings
| # | Finding | Criterion | Severity | Where | Fix |
|---|---|---|---|---|---|
| 1 | | 4.1.2 | 🔴 | `file:line` | |

### VoiceOver
| Element | Name | Value | Trait | Issue |
|---|---|---|---|---|

### Dynamic Type
- **Clamps:** [sites, and whether justified]
- **Fixed sizes:** [sites]
- **Breaks at accessibility sizes:** [what]

### Targets
| Element | Size | Issue |
|---|---|---|

### Composed visuals
| Visual | Text equivalent? |
|---|---|

### What works well
- 
```

## Notes

- Do not report the absence of ARIA, keyboard focus rings, hover states, or alt attributes.
  They do not exist on this platform and their absence is not a defect.
- `DesignSystem.swift`'s doc comments state the intent for most of the system. Where the
  code and its comment disagree, that is a finding.
- Where possible, verify on a simulator: `set_sim_appearance` and `set_sim_ui` for dark
  mode, Dynamic Type and Increase Contrast; `snapshot_ui` for the semantic tree. Automating
  the VoiceOver cursor itself is not possible with the current tooling and needs a human.

