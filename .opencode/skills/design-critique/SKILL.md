---
name: design-critique
description: Structured design feedback on a screen of the Almanac iOS app. Trigger with "critique this screen", "what do you think of Today", "review the Quick Log sheet", or with a simulator screenshot path. Reads the Swift source and, where possible, a captured screenshot.
argument-hint: "<screen name, e.g. today | trends | modules | quick-log | settings, or a screenshot path>"
---

# /design-critique

Get structured design feedback on one screen of Almanac.

This app has **no Figma file and no design artifact**. Its design system is
`Native/Almanac/DesignSystem.swift`, and the rules that govern a change are in the
`almanac-design-system` skill. Read both before critiquing. A critique that does not know
this app's own doctrine will recommend template design — filled card grids, floating
actions over content, all-caps eyebrows — all of which have already been fixed here once
and will be proposed again.

## Usage

```
/design-critique $ARGUMENTS
```

Critique this screen: @$1

## Getting the material

Three sources, in order of usefulness:

1. **The Swift source.** `Native/Almanac/<Screen>.swift`. This is the ground truth and is
   always available. Read it before forming an opinion.
2. **`snapshot_ui` from XcodeBuildMCP.** Connected and live — see `.opencode/CONNECTORS.md`.
   Returns every element's role, label and identifier as **text**, which is readable
   without image input, so this is the workhorse. `build_run_sim`, then `snapshot_ui`, then
   `tap` by `elementRef` to navigate, then `snapshot_ui` again. **Re-snapshot after every
   state change** — refs are regenerated and go stale, and a sheet that covers a screen does
   not remove the screen from the tree, so a stale ref can tap something the user cannot see.
   Call `wait_for_ui("settled")` before trusting anything.
3. **A screenshot.** `screenshot` from the same server, or `docs/ui/capture.sh` for the
   light/dark/type-size matrix. Note that I cannot read pixels directly — surface the image
   to the user (attach it, or open it in the Review pane) and reason from the source and the
   tree instead of claiming to have seen it.

Which screen maps to which view:

| Name | View | File |
|---|---|---|
| `today` | `ReadinessDashboardView` | `ReadinessDashboardView.swift` |
| `trends` | `TrendsView` | `TrendsView.swift` |
| `modules` | `ModulesView` | `MoreViews.swift` |
| `quick-log` | `QuickLogView` | `QuickLogView.swift` |
| `check-in` | `MoodSorenessCheckInView` | `MoodSorenessCheckInView.swift` |
| `settings` | `SettingsView` | `SettingsView.swift` |
| `rhythm` | `EditorialRhythmCalendarView` | `EditorialRhythmCalendarView.swift` |

If no name is given, ask which screen. With XcodeBuildMCP connected you can navigate to
any of them, so prefer going and looking over describing them from memory.

### Known shapes, so you do not misread them

- `ReadinessDashboardView` reports as a **single** text element
  (`Saturday 26 September, Today, Good morning, Yazeed`) because it combines its subtree
  for VoiceOver. Its children still appear individually in the tree's text list; only the
  target list is flat. A low target count is not "this screen is not interactive".
- A sheet does not remove the screen beneath it. Quick Log open still reports Today's
  `Today` / `Trends` / `Modules` buttons. Judge what is reachable by the screenshot, not by
  whether the element is in the tree.

## What I Need From You

- **The screen**, by name or screenshot path
- **Focus** (optional): "focus on the empty state", "focus on Dynamic Type", "focus on the
  bar"
- **State** (optional): a screen's design depends on whether it is empty, provisional, or
  populated. "the empty state" is a materially different critique.

## Critique framework

### 1. First impression (two seconds)
What draws the eye first, and is that the right thing? Is the purpose clear without
reading? Does it read as an instrument, or as an app?

### 2. Hierarchy and rules
Is there one prominent card, and only one? Are the sections separated by rules rather than
stacked boxes? Is the reading order right? Is whitespace doing work, or is it just gap?

### 3. Doctrine conformance
Walk the `almanac-design-system` rules. Report drift specifically: a raw `Color(`, a
hardcoded number where a token exists, accent used decoratively, a second prominent card,
Fraunces below 22pt, an all-caps or tracked heading.

### 4. Usability
Can the goal be accomplished in the fewest steps? Are interactive elements obvious? Are
there dead ends? Is anything interactive under 50pt, or overlapping something interactive?

### 5. States
Does this screen handle loading, empty, error, and populated? A `@Published` error that no
view renders is a finding — the user gets silence.

### 6. Accessibility
VoiceOver semantics (label, value, trait, not just a `Text`), Dynamic Type including
accessibility sizes, Reduce Motion, Increase Contrast, 44pt targets, and whether a
composed visual has a text equivalent. The palette itself already passes WCAG AA on every
text pair, so do not report contrast findings without computing the ratio.

## How to give feedback

- **Be specific**: "the FAB overlaps the Trends button's hit area" not "the bar feels off"
- **Explain why**: tie it to a doctrine rule or to a concrete user failure
- **Propose the change**, with the token to use
- **Acknowledge what works** — this app has genuinely good decisions; name them
- **Do not invent problems to seem thorough.** A short accurate critique beats a long
  speculative one. If the screen is fine on a dimension, say so.

## Output

```markdown
## Design Critique: [screen]

### Overall impression
[1–2 sentences: what works, and the single biggest opportunity]

### Doctrine conformance
| Rule | Status | Note |
|---|---|---|
| Rules separate, containers don't | ✅ / ⚠️ / ❌ | |
| One prominent card | | |
| Accent only where measured | | |
| Fraunces display-only | | |
| Sentence case headings | | |
| Touch targets ≥ 50pt | | |
| Data monospaced | | |

### Findings
| # | Finding | Severity | Where | Recommendation |
|---|---|---|---|---|
| 1 | | 🔴 / 🟡 / 🟢 | `file:line` | |

### States
| State | Present? | Note |
|---|---|---|
| Loading | | |
| Empty | | |
| Error | | |
| Populated | | |

### Accessibility
- **VoiceOver**: [what is announced, what is silent]
- **Dynamic Type**: [what breaks or is clamped at accessibility sizes]
- **Targets**: [any under 50pt, any overlapping]

### What works well
- 

### Priority
1. **[Highest impact]** — why, and the token to use
2. **[Next]**
3. **[Next]**
```

## Notes

- This app is deliberately **not** a conventional consumer app. "Boring", "quiet", and
  "restrained" are usually correct. A critique that reports those as weaknesses is wrong.
- The strongest accessibility pattern in the codebase is
  `EditorialRhythmCalendarView`'s linear day list, substituted for the ring grid at
  accessibility type sizes. When critiquing any composed visual, compare it against that
  rather than inventing a standard.

