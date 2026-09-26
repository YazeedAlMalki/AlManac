---
name: design-system
description: Audit, document, or extend Almanac's design system — the tokens and components in Native/Almanac/DesignSystem.swift. Use when checking for hardcoded values that bypass a token, documenting a component's states, or designing a new pattern that fits the existing system.
argument-hint: "[audit | document | extend] [component or file]"
---

# /design-system

Almanac's design system is Swift code, not a Figma library. It lives in
`Native/Almanac/DesignSystem.swift` and its governing rules live in the
`almanac-design-system` skill. **Read that skill first** — it says what the system is for,
and this skill is about whether the code obeys it.

## Usage

```
/design-system audit                    # Whole app
/design-system audit <View>.swift       # One view
/design-system document AlmanacCard     # Document a component
/design-system extend <pattern>         # Design a new component
```

## The system

| Layer | Where | Notes |
|---|---|---|
| Palette | `AlmanacPalette` | 12 tokens, light + dark, via a dynamic `UIColor` provider |
| Typography | `AlmanacTypography` | 9 roles; `.custom(_:size:relativeTo:)` so the scale is Dynamic Type–aware |
| Metrics | `AlmanacMetrics` | 6 spacing, radius and target values |
| Icons | `AlmanacIcon` | Centralised SF Symbols, pending the approved custom sheet |
| Status | `AlmanacStatusTone` | The only colours allowed to carry judgement |
| Components | `AlmanacCard`, `AlmanacSectionHeader`, `AlmanacEyebrow`, `AlmanacMetricRow`, `AlmanacStatusMark`, `AlmanacPrimaryButtonStyle`, `AlmanacSecondaryButtonStyle` | |
| Modifiers | `almanacScreen()`, `almanacModuleSurface()`, `almanacNavigationHost(_:)`, `editorError(_:)` | |

## Audit

The audit is mechanical. Run these and report counts, not impressions:

```sh
# Colours outside the palette — should be zero outside DesignSystem.swift
grep -rn 'Color(\|Color\.accentColor\|Color\.white\|Color\.black\|Color\.gray' Native/Almanac/ | grep -v DesignSystem.swift

# Token adoption: AlmanacMetrics is the least-used layer in the app
grep -rc 'AlmanacMetrics\.' Native/Almanac/*.swift | grep -v ':0'
grep -rn 'AlmanacMetrics\.' Native/Almanac/ | grep -v DesignSystem.swift

# Fixed-point fonts that bypass the type scale
grep -rn '\.font(\.system(size:' Native/Almanac/

# Dynamic Type clamps (four exist, each a considered trade-off)
grep -rn '\.dynamicTypeSize(' Native/Almanac/

# Interactive elements with no name/value/trait
grep -rn 'onTapGesture' Native/Almanac/
grep -rc 'accessibilityLabel\|accessibilityValue\|accessibilityAddTraits' Native/Almanac/*.swift | grep ':0'

# Dead UI: compiled but never instantiated
for sym in $(grep -oE '^(private )?struct [A-Za-z]+' Native/Almanac/*.swift | awk '{print $NF}' | sort -u); do
  n=$(grep -rho "\b$sym\b" Native/Almanac/ | wc -l)
  [ "$n" -le 1 ] && echo "possibly dead: $sym"
done
```

Two cautions when interpreting the output:

- **A hardcoded number is not automatically a defect.** `AlmanacMetrics` is genuinely
  under-used across this app, so a raw `8` for a one-off gap is a smaller problem than the
  fact that the system has six values nobody uses. Report adoption as its own finding.
- **Check for dead code first.** A duplicated component still in the build phase will
  report every violation it contains, and those can only be fixed by deleting it. This
  app carried 267 lines of a superseded calendar that way; they are gone now.

## Output — audit

```markdown
## Design System Audit: [scope]

### Token adoption
| Token group | Declared | Call sites outside DesignSystem.swift | Files using it |
|---|---|---|---|
| `AlmanacPalette` | 12 | [N] | [N of 31] |
| `AlmanacTypography` | 9 roles | [N] | [N of 31] |
| `AlmanacMetrics` | 6 | [N] | [N of 31] |

### Violations
| Kind | Count | Where | Fix |
|---|---|---|---|
| Off-palette colour | | | |
| Fixed-point font | | | |
| Hardcoded spacing | | | |
| Dynamic Type clamp | | | |
| Interactive without semantics | | | |

### Dead code
| Symbol | Lines | Referenced by |
|---|---|---|

### Priority
1. **[Highest]** — token with the widest adoption gap
2. **[Next]**
```

## Output — document

```markdown
## Component: [Name]  (`file:line`)

### Purpose
[What it is for, in the app's own terms]

### Properties
| Property | Type | Default | Notes |
|---|---|---|---|

### Variants
| Variant | Use when | Visual |
|---|---|---|

### States
| State | Visual | Behaviour |
|---|---|---|

### Tokens used
- Colours: […]
- Typography: […]
- Metrics: […]

### Accessibility
- **Name**: [what VoiceOver announces]
- **Value / traits**: [if stateful]
- **Target size**: [pt]
- **Dynamic Type**: [clamped or adaptive]

### Do / Don't
| ✅ | ❌ |
|---|---|
```

## Output — extend

Propose a component only when the pattern appears at least twice, or when a doctrine rule
requires it. Include: the problem, existing patterns it relates to, the Swift API, the
tokens it uses (never new literals), its states, its accessibility contract, and any open
question. If it would need a **new** token, say so explicitly and justify the value — that
is a design decision, not an implementation detail.

## Notes

- Components are doc-commented at their definitions and those comments are load-bearing:
  they explain *why*, and the existing ones are good. New components need the same.
- `editorError(_:)` is the one error surface in the app; a new screen that invents its own
  alert wording is drifting.
- `snapshot_ui` from XcodeBuildMCP (connected — see `.opencode/CONNECTORS.md`) will show
  whether a component's semantics are actually exposed, which static reading cannot.
