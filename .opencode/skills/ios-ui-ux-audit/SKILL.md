---
name: ios-ui-ux-audit
description: Audit Almanac's SwiftUI screens end to end for usability, navigation, information architecture, interaction behavior, and visual consistency. Use when asked to review UX, inspect a flow, find usability defects, or assess a release. Produces prioritized findings backed by Swift source, simulator snapshots, tests, or screenshots.
---

# iOS UI/UX audit — Almanac

Audit the product people actually use, not a screen in isolation. Every finding must point at
evidence: a `file:line`, a simulator state, a UI test, or a screenshot. "I would have done it
differently" is not a finding; "the row says it opens Training but has no action" is.

This skill audits and reports. Do **not** change application code unless the user explicitly
asks for fixes after the report.

## Almanac's actual shape

Read these before judging anything:

| Concern | Source |
|---|---|
| App shell and bar | `Native/Almanac/AlmanacApp.swift` |
| Tab + stack state | `Native/Almanac/TabCoordinator.swift`, `Sources/AlmanacCore/Navigation/TabRouting.swift` |
| Design tokens | `Native/Almanac/DesignSystem.swift` |
| Today | `Native/Almanac/ReadinessDashboardView.swift` |
| Trends | `Native/Almanac/TrendsView.swift`, `InsightsView.swift` |
| Modules menu | `Native/Almanac/MoreViews.swift` (`ModulesView`) |
| Quick Log | `Native/Almanac/QuickLogView.swift` |
| Requirements | `docs/brd-v1_6.md`, `docs/device-checklist.md` |

Grounded facts to reason from:

- Three destinations — **Today, Trends, Modules** — and one action, **Quick Log**, in a
  hand-built `AlmanacNavigationBar` laid out in flow. It is deliberately **not** a `TabView`
  and not a `safeAreaInset`.
- Each tab owns a `NavigationStack`; `TabCoordinator` owns selection and one path per tab.
  Cross-tab jumps go through `TabCoordinator.go(to:)` and the `AppRoute` enum (today root,
  trends root/detail, training, hydration, nutrition, fasting, supplements, context, prayer,
  circadian, body circumference, vitals, laboratory, import history, timeline, body
  composition, digestion, profile, settings).
- 56 Swift source files declare views under `Native/Almanac`. Models are `ObservableObject`s
  owned by `AlmanacApp`; the database is shared through `LaboratoryModel`.
- The app is bilingual: `en` and `ar` (`knownRegions`), with Arabic strings in
  `Localizable.xcstrings` and an Almarai text face.
- Days are logical days beginning at **04:00**, not calendar days.

## Evidence rules

1. **Driven or not driven.** Use the repo's own convention: `PASS` only if actually driven;
   `FAIL` with the observed behavior; `UNRUN` when the state could not be reached. See
   `docs/acceptance-checklist.md` — a checklist that marks unrun steps as pass manufactures
   confidence and is worse than none.
2. **Source evidence** is `path:line`, not a memory of the file.
3. **Runtime evidence** is a `snapshot_ui` element tree, a screenshot path, a log line, or a
   test name with its result.
4. **Separate observation from inference.** If you infer a problem from code without driving
   it, label it `Inferred — not driven`.
5. **Do not count a shadowed element as missing.** A sheet over a screen leaves the screen in
   the accessibility tree; re-snapshot after every state change.

## Audit workflow

### 1. Define scope

Pick one of:

- **Screen audit** — one view and its states.
- **Flow audit** — a task from entry to completion (log water; complete check-in; open Training;
  log a lab result).
- **Release audit** — all three tabs plus Quick Log, the Modules menu, Settings, and one editor
  per data family.

State the scope at the top of the report. An audit that silently covers three screens and
claims "the app" is a false claim.

### 2. Inventory before judging

```sh
# Views in scope
rg -n 'struct .*: View' Native/Almanac --glob '*.swift'

# Navigation and entry points
rg -n 'AppRoute\.|tabs\.go\(|NavigationLink|\.sheet\(' Native/Almanac --glob '*.swift'

# Interactive affordances that may not be controls
rg -n 'onTapGesture|simultaneousGesture|DragGesture' Native/Almanac --glob '*.swift'
```

List every screen, sheet, alert, and empty/error state the scope contains. A flow with an
unlisted error state is an incomplete audit.

### 3. Build and drive

Use XcodeBuildMCP (defaults are configured; see `.opencode/CONNECTORS.md`):

```text
build_run_sim
snapshot_ui                 # text tree: labels, roles, identifiers
tap / swipe / drag / type_text / wait_for_ui
screenshot                  # pixels when layout matters
set_sim_appearance          # light / dark
set_sim_ui                  # content size, increase contrast
```

`docs/ui/capture.sh` remains the reproducible light/dark/largest-type matrix, and
`docs/ui/measure.sh` answers the objective token questions. Prefer the MCP for navigating;
prefer the scripts for the matrix.

Known limits that produce false findings:

- VoiceOver is **not** simulated. `snapshot_ui` reads the same tree but does not exercise
  focus order or verbosity.
- `elementRef`s go stale after any state change; `wait_for_ui("settled")` and re-snapshot.
- A root screen's subtree can collapse to one element; a low target count is not evidence of
  a non-interactive screen.

### 4. Drive each state, not just the happy path

For every screen in scope:

- First launch / empty data.
- Populated data.
- Loading.
- Read failure.
- Save failure and validation error.
- Long content (many rows; longest labels).
- Both appearances.
- Largest Dynamic Type (at least once per flow).
- Arabic / RTL when text direction can change the layout.

### 5. Evaluate against the checklist

#### Information architecture and navigation

- [ ] Can a first-time user name the three destinations and predict what each holds?
- [ ] Does the Modules menu group features by the user's mental model (body, intake,
      training, time/context, records), not by database table?
- [ ] Is every feature reachable in at most two taps from the bar or a row that names it?
- [ ] Do cross-tab jumps land on the named feature, with a back path that returns somewhere
      coherent (not a dead end, not the wrong stack)?
- [ ] Does tapping the current tab while deep in its stack pop to the root (the documented
      behavior)?
- [ ] Is there exactly one obvious way to do each primary task? Duplicate entry points are
      acceptable only when both are named and behave identically.
- [ ] Do pushed screens keep a visible way back, including after a modal?
- [ ] Are sheets used for bounded tasks and pushes for browsing? A sheet that contains a
      multi-level hierarchy is a navigation smell.

#### Interaction behavior

- [ ] Is every tappable thing a `Button` (or a control), not `Text` + `.onTapGesture`?
- [ ] Does every button produce its promised result, including when data is missing?
- [ ] Do rows that open a feature look tappable and rows that are readings not look tappable?
- [ ] Is the primary action of a screen visually singular and reachable without scrolling
      past unrelated content?
- [ ] Do destructive actions confirm, name the object, and offer Cancel?
- [ ] After a save, does the screen show the new value without a manual refresh?
- [ ] Are loading states distinct from "nothing recorded" and from a failed read?
- [ ] Is dismissed keyboard/focus restored where a form continues?
- [ ] Can the flow be completed with one hand on the smallest supported screen?

#### States and feedback

- [ ] Empty state says what is empty and what will fill it. It never implies a failed read.
- [ ] Read problems use `AlmanacProblemNote` (or equivalent) and sit where the failure
      happened; they do not masquerade as empty states.
- [ ] Save/validation errors identify the field and the correction.
- [ ] A missing reading stays missing: no zero, no dash that could be mistaken for a value,
      no invented trend point.
- [ ] Partial data is labeled (`Provisional`, `Low confidence`, `n inputs missing`,
      `not enough paired days`), not silently aggregated into certainty.

#### Content and consistency

- [ ] Terminology matches the app: check-in, readiness, logical day, Modules, Quick Log.
- [ ] Dates use the Gregorian display calendar and the 04:00 logical day; no date is invented.
- [ ] Numbers and units are localized through the app's own formatting (`AlmanacNumber`,
      `UnitDisplay`, `NumberDisplay`), not string concatenation.
- [ ] Status words agree with status color and symbol (Final/Provisional, confidence labels).
- [ ] The same concept is named the same way on Today, Trends, Modules, and in Settings.
- [ ] Copy is sentence case, direct, and free of template language.

#### Visual consistency

- [ ] Tokens only: no raw colors, ad-hoc spacing, or hand-drawn rules. Defer to
      `almanac-design-system` for the full doctrine and to `docs/ui/measure.sh` for the
      objective check.
- [ ] One prominent card per screen, if any.
- [ ] Hierarchy is carried by rules and type, not by a stack of identical filled cards.
- [ ] Light and dark both read as the same product; nothing disappears in either.

#### Platform conventions

- [ ] Native navigation, sheets, alerts, lists, pickers, and text fields are used where they
      are the obvious iOS answer; deliberate departures (the custom bar) are justified.
- [ ] Safe areas and the home indicator are respected; the last row is not trapped behind the
      bar.
- [ ] Text fields have the right keyboard, capitalization, and content type.
- [ ] No control requires a gesture with no visible affordance or accessible alternative.

### 6. Prioritize

| Severity | Definition | Example |
|---|---|---|
| **Critical** | Blocks a primary task, corrupts trust in data, or traps the user | Save silently fails; missing score shown as 0; no way back |
| **High** | Task completes only with a workaround, or a state is misleading | Dead-looking row opens nothing; error shown as empty state |
| **Medium** | Real friction, recoverable, users will notice | Primary action below the fold; duplicate labels; keyboard hides Save |
| **Low** | Polish; inconsistent but not misleading | Two names for one feature; caption size drift |

Tie-break by reach: a Medium on Today outranks a High on a screen one user opens monthly.
State the tie-break in the report.

### 7. Report

```markdown
## UI/UX Audit: [scope]

**Build:** [commit] · **Device:** iPhone 16e, iOS [version] · **States driven:** [list]
**Verdict:** [ship / ship with fixes / not ready] — [one sentence]

### Summary
| Critical | High | Medium | Low |
|---|---|---|---|
| N | N | N | N |

### Findings
| # | Severity | Area | Finding | Evidence | Proposed fix |
|---|---|---|---|---|---|
| 1 | 🔴 Critical | Interaction | … | `ReadinessDashboardView.swift:214`; snapshot … | … |

### Flow results
| Flow | Steps driven | Result | Notes |
|---|---|---|---|
| Log water | bar → Quick Log → Water → Save | PASS | … |

### Coverage and gaps
- Screens audited: …
- States not reachable: … (`UNRUN`, with why)
- Inferred but not driven: …

### What works well
- …
```

## Acceptance criteria for the audit itself

- [ ] Scope and build/device are stated.
- [ ] Every in-scope screen and every state in §4 is either driven or marked `UNRUN` with a
      reason.
- [ ] At least one complete primary flow per tab, plus Quick Log, is driven end to end.
- [ ] Both appearances are checked; largest Dynamic Type is checked at least once per flow.
- [ ] Every finding has file/line or runtime evidence; inferences are labeled.
- [ ] Findings are prioritized and each proposed fix is the smallest change that removes the
      problem.
- [ ] No application code was modified during the audit.

## Boundaries

| Question | Use |
|---|---|
| Does this visual change fit Almanac's doctrine? | `almanac-design-system` |
| Is this screen accessible? | `ios-accessibility-qa` |
| Is this chart or health claim honest? | `health-data-visualization` |
| What should this label/error say? | `ux-copy` |
| Pure visual taste on one screen | `design-critique` |

Do not duplicate those reports here; link to them and keep this one about how the product
behaves.
