# Owner decisions — 2026-10-22: the bottom bar

Settled by the owner on 2026-10-22 and handed to the build as decided, not as
proposals. Where the build had to fill in a detail, it is listed under "Build
choices" with what it would take to change it.

## The decision

**Five equal columns: Today · Trends · [+] · Journal · Settings.** Four
destinations and one action, the action third so it sits at exactly half the
bar's width.

| Item | Decision |
|---|---|
| Roster | Today, Trends, Journal, Settings, plus the quick-log action |
| Modules | Renamed **Journal**. "Module" still names the things inside it |
| Settings | **A tab of its own.** Profile moves inside Settings and leaves the Journal index |
| Capture | **Unchanged.** The `+` opens `QuickLogView` as before: five destinations, one-tap water presets, the sheet stays open after a log |
| Re-tap | Tapping the tab already showing pops it to its root |
| iPad | The bar's row is width-capped and centred |

**Supersedes** the roster in `owner-decisions-2026-09-26.md` §13 ("The tab
roster is Today, Trends, Modules") and the 2026-09-27 entry in
`docs/implementation-status.md` that recorded it. §14 (Journal stays an index,
not a drawer) and §15 (the action has no single default target) stand. The
2026-09-27 rule that "a tab slot is earned by daily-use frequency" is not what
put Settings on the bar: it is there by the owner's decision, and the problem it
answers is item 6 below — the old index mixed the app's own controls (Profile,
Settings) in with the record.

It also moves further from the Technical Spec's D-3 ("5-tab bar: Home · Log ·
Train · Insights · Settings", `docs/almanac-tech-spec-v1_0.md:63`), which was
already superseded on 2026-09-27. D-3 and this bar share only Settings.

## Why (what the old bar did)

1. **No rhythm.** Today and Trends shared one half, Modules took the other, and
   the action had a fixed 68pt column between them. On a 390pt phone the
   targets sat at about 12 / 32 / 50 / 78%. Five equal columns put them at
   10 / 30 / 50 / 70 / 90%.
2. **iPad.** The app ships for iPad (`TARGETED_DEVICE_FAMILY = "1,2"`) and the
   bar had no width cap, so its targets spread across the whole screen.
3. **Re-tap did nothing.** `TabCoordinator.popToRoot()` existed, but nothing
   called it: inside Laboratory, tapping Modules left Laboratory on screen.
4. **A stale hint.** The action's accessibility hint named four quick-log
   destinations; there are five (digestion arrived later).
5. **Two grids.** Today (`circle.grid.2x2`) and Modules (`square.grid.2x2`)
   were the same icon drawn twice.
6. **Content and chrome mixed.** Profile and Settings were rows in the module
   index.
7. **An unexplained Dynamic Type clamp** on the bar's captions.

## Build choices (open in the handoff, decided here)

| Choice | What was built | Overrule by |
|---|---|---|
| Arabic for "Journal" | **المفكرة**. Not تسجيل, which is already "Quick log" (تسجيل سريع) | One string, in two tables: `Sources/AlmanacCore/Localization/Resources/ar.lproj/Localizable.strings` (the tab) and `Native/Almanac/Localizable.xcstrings` (the screen title) |
| The action's VoiceOver label | "Add a record"; Arabic **إضافة سجل** (a proposal, not reviewed) | `AlmanacApp.swift`, `quickLogButton`, and its catalog entry |
| The action's hint | "Choose water, food, training, a body measurement, or digestion" — the console's five cards, in their order | Same place |
| Journal's icon | `book.closed` | `AlmanacIcon.journal` |
| iPad width cap | **760pt**, not the handoff's "~700": 760 is the width Today, Trends, Quick Log and exercise progress already cap their content column at, so the bar lines up with the screen above it. Named once, `AlmanacMetrics.contentWidth`, and those four screens now use it | `AlmanacMetrics.contentWidth` |
| How re-tap pops | The tab's path is cleared (`TabRouting.plan(…reselecting:)`, pure and tested), **and** the tab's root view is given a new identity. The second half is needed because a screen pushed by a plain `NavigationLink { … }` — Settings → All reminders, a trend's detail — is in no path, so clearing the path cannot pop it. Cost: a re-tap rebuilds the root, so its scroll position and any unsaved root state reset | `TabCoordinator.tap(_:)`, `AlmanacApp.selectedDestination` |
| Profile's place in Settings | The first section, "Profile", one row | `SettingsView` |
| The Dynamic Type clamp | Kept at xLarge, with its reason in a comment: five captions in one row; "Settings" is ~62pt in a ~75pt slot at xLarge | `destinationButton` in `AlmanacApp.swift` |

## Not changed

The capture path, Trends' contents, the Journal index's grouping, Today's
content, the custom bar itself (still not a `TabView`, still in the layout
flow, still no floating button).

## Merged onto master (2026-11-20)

This branch was built on the 2026-10-20 master and landed after the 2026-10-23
Profile move (`d57509d`). Where the two met:

| Point | Result |
|---|---|
| Profile's rows (Shifts & rhythm, Body composition, Body circumferences, Log body) | Owned by the **Settings** tab, because Profile is. They push onto Settings' stack on top of Profile, and `AlmanacApp.settingsDestination` draws them |
| The Journal index | Neither Profile, Settings nor the four Profile rows have a row in it |
| The action's hint | "Choose water, food, training, or digestion": Quick Log has four cards since the body logger moved to Profile |
| UI tests | `openProfileRow` now goes Settings → Profile → row |
