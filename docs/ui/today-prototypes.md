# Today screen — three prototypes

**Build:** prototyped on `8b3cfb0` + working tree · **Device:** iPhone 16e, iOS 26 simulator
**Captured:** 9 screenshots — 3 prototypes × {light, dark, largest Dynamic Type}
**Artifacts:** `docs/ui/today-prototypes/` (images, `capture.sh`, `analyse.py`)
**Verdict:** recommend **Instrument**, with one caveat named at the end.

---

## Scope, and one limitation stated up front

This reviews three candidate designs for the Today screen. It does **not** review the rest of
the app, and it is not a release audit.

**I could not see the screenshots.** The agent that produced this report cannot accept image
input. Every visual claim below is derived from **pixel measurement** of the PNGs — background
colour, ink distribution per band, distinct ink colours, chromatic-pixel counts, blank-run
detection, and Dynamic Type growth. That is real evidence and it caught three genuine bugs
(§4). It is **not** aesthetic judgement. Where a claim is "feels calm" or "reads as cold", I
have not made it. The nine images are open in the Review pane for a human to judge.

Aesthetic taste on a single screen belongs to `design-critique`; this report is about what the
designs *do*.

---

## 1. What each prototype is

| | Thesis | Type system | Colour |
|---|---|---|---|
| **Instrument** | Almanac is a measuring device. No greeting, no cards: a label gutter, tabular figures, one hairline between every pair of things. | 84pt light numeral; 118pt label gutter; monospaced units. 20 sizes, all fixed (now scaled). | Accent only where Almanac itself recorded a value. |
| **Day Page** | An almanac has a page per day. The page is *set*: serif display title, wide measure, entries as printed lines with hanging labels. | Fraunces serif throughout; score as a folio numeral in the margin. | None. No surface fill anywhere. |
| **Native Console** | The fastest-reading iOS health surface: large title, hero value, compact two-column grid — done with Almanac's restraint. | Token roles via `AlmanacTypography`; hero panel at display scale. | One filled hero panel; tone colour on channels carrying a judgement. |

All three read the **live** models (`PrototypeTodayFactory`), so each shows the real score,
the real totals, and the real empty states — not a mock-up of a good day.

---

## 2. Measured comparison

| Metric (light) | Instrument | Day Page | Native Console |
|---|---|---|---|
| Primary text contrast | 20.4:1 | 20.4:1 | 20.4:1 |
| Secondary text contrast | 5.9:1 | 5.9:1 | 5.9:1 |
| Distinct type levels (≥200px) | 7 | 7 | 6 |
| Content blocks (Quiet-row separations) | 39 | 36 | 28 |
| Ink coverage | 4.3% | 4.2% | 4.4% |
| Chromatic pixels | 8068 | 8068 | 8068 |
| Thin full-width rules | 10 | 6 | 7 |
| Texture fill (3rd grey) | yes (~2356px) | no | no |
| Dark-mode parity | pass | pass | pass |

**Reading this table.** Secondary contrast 5.9:1 clears WCAG AA (4.5:1) and the 3:1 large-text
bar with room to spare; primary at 20:1 clears AAA. The chromatic count is **identical in all
three** because it is entirely the shared bottom bar's selected-tab tint — the prototypes add
**no** decorative colour of their own. Verified by locating those pixels: every one sits in
rows 2211–2378, the same rows in all three images.

Instrument carries the most structure (10 rules, 39 blocks, plus a third grey), Day Page the
fewest surfaces (6 rules, zero fill), Native Console the fewest blocks (28) because its grid
compresses content into tiles.

---

## 3. Evaluation against the brief

| Axis | Instrument | Day Page | Native Console |
|---|---|---|---|
| **Originality** | High — a device panel, unlike Health/Oura | Highest — an editorial page; visually unlike anything in the category | Lowest — closest to a recognisable modern health app |
| **Information hierarchy** | Strong, carried by rules and tabular alignment | Strong in reading order; weakest for *scanning* | Strong, carried by the one filled hero |
| **Speed of health-data entry** | Fast: every channel visible, recovery toggle above the fold | Slowest: entries are prose lines, more scrolling | Fast, but Inputs strip is below the grid |
| **Information density** | Highest | Medium | Medium-high |
| **Consistency with Almanac doctrine** | New rules, same palette/type | Deviates: serif body, italics, no tokens for sizes | Best token conformance (`AlmanacTypography` in 18 places) |
| **Maintainability** | Medium — many bespoke sizes | Lowest — most bespoke type | Highest — token roles |
| **Accessibility** | Now scales (+37.6% at AX5); was frozen | Scales (+55.2%) | Scales (+55.1%), and already collapsed its grid to one column at accessibility sizes |
| **Generic patterns** | Avoids all listed clichés | Avoids all; risks "wall of text" | Nearest to a template grid — the listed risk |

Every prototype avoids the banned patterns: no gradients, no glassmorphism, no glow, no random
accents, no oversized decorative icons, no emoji, no meaningless charts. Measured, not assumed —
one accent colour, and it is the system's.

---

## 4. Bugs found by measuring, and fixed

These are the substantive findings. Each was invisible without reading the pixels.

| # | Finding | Evidence | Status |
|---|---|---|---|
| 1 | Non-prototype build being photographed: `xcodebuild -showBuildSettings` resolved a stale DerivedData product, so all three designs rendered the production screen | three designs produced **identical** md5s; only 3 distinct images for 6 files | Fixed — capture script refuses a binary lacking the gate symbol |
| 2 | **Instrument ignored Dynamic Type entirely** | AX5 vs medium ink **+1.1%**, content rows *identical* (870) — text did not move | Fixed → **+37.6%** |
| 3 | **354px dead hole** at AX5 in Instrument's score row | blank-run detection: rows 507–861 with zero ink | Fixed → 188px, in line with the others |
| 4 | Day Page +9% at AX5 (partial) | half its sizes were token-based, half fixed | Fixed → +55.2% |

Root cause of 2–4: fixed `.system(size:)` fonts, which are frozen and cannot scale. The fix
keeps each prototype's chosen size while making it scale (`Font.almanacScaled`), which is what
`AlmanacTypography.font` already does for shipped screens via `relativeTo:`.

**This is the single most important result in the report.** Instrument as first written was
not merely imperfect — at the largest accessibility size it was *unchanged*, which means a
user who needs large text would have got the same 84pt numeral and the same 11pt labels as
everyone else. That is a hard accessibility failure, and it was found by measuring ink
coverage rather than by looking at a screenshot.

---

## 5. What each does well, and what it costs

**Instrument** — *Best for a user who opens Today to read numbers.* The label gutter and
tabular figures make the channels scannable in one vertical sweep; rules carry hierarchy with
no card stack; density is highest of the three. It also carries the most structure, and at
accessibility sizes that structure becomes loose (188px of quiet in the header) — the 84pt
numeral is the tension. Its cost is warmth: it reads as an instrument, deliberately.

**Day Page** — *Best for a user who reads Today once, carefully.* It is the most distinctive
and the only one with zero surface fill; typography alone carries everything. The costs are
real: it is the slowest to scan, it deviates furthest from the design tokens (bespoke serif
sizes, italics as a semantic device), and an editorial page is harder to maintain than a token
system. It is also the least like the rest of the app.

**Native Console** — *Best for a new user.* Highest token conformance, most maintainable, and
the only one that already anticipated accessibility sizes by collapsing the grid to one
column. Its weakness is the one the brief names: it is the closest to a familiar health-app
grid, so it risks looking like the category rather than like Almanac.

---

## 6. Recommendation

**Choose Instrument.** Reasons, in order:

1. **It fits the product's own claim.** Almanac's promise on Today is that it will not invent
   a reading — "no zero, no dash mistaken for a value", provisional states labelled, missing
   inputs counted. An instrument that shows a label gutter, a tabular reading, and a rule per
   channel is that promise expressed structurally rather than asserted in copy. The other two
   present the same data; Instrument presents it as a *record*.
2. **Highest information density with the strongest hierarchy.** 39 content blocks and 10
   rules, and it never needed a card stack — which is exactly the doctrine's "hierarchy
   carried by rules and type, not a stack of identical filled cards".
3. **Native Console is the safer choice and that is its problem.** It is more maintainable and
   probably more immediately legible to a new user, but it is also the closest to the
   category's clichés — the specific failure the brief asked to avoid.
4. **Day Page is the most interesting and the wrong first move.** It is the most original, but
   it deviates most from the token system on the app's most-used screen, and its scanning cost
   lands on the task users repeat daily.

**Caveat, and it is a condition rather than a footnote.** Instrument's 84pt numeral is the
source of its AX5 looseness. If Instrument is chosen, the numeral needs a deliberate decision
at accessibility sizes — either a capped size or a different arrangement — before it ships. It
now scales, but "scales" is not the same as "reads well at that size". I have measured the
gap; I have not seen it.

---

## 7. Coverage and gaps

- **Prototypes built and captured:** 3, on a real simulator, real data.
- **States driven:** populated data, both appearances, largest Dynamic Type. All driven.
- **Empty / read-failure / save-failure states:** present in the code (each prototype renders
  `AlmanacProblemNote` and per-channel `—`), **`UNRUN`** — not driven, because the shared
  simulator database is populated and the capture path cannot inject a read failure.
- **RTL / Arabic:** **`UNRUN`.** All three use leading/trailing alignment, so they should
  mirror, but I did not capture it. Do not treat that as verified.
- **VoiceOver:** **`UNRUN`.** Not simulated; `snapshot_ui` reads the same tree but does not
  exercise focus order. No prototype sets explicit accessibility labels beyond the inherited
  text — that is unverified, not confirmed-good.
- **Not driven, inferred:** the accessibility-size tension in Instrument's numeral is inferred
  from a 188px blank run, not from looking at it.

## 8. Isolation

Prototypes are reachable **only** through a launch argument
(`-AlmanacTodayPrototype instrument|day-page|native-console`), read in
`AlmanacApp.selectedDestination`. On an ordinary launch the branch is not taken and every line
that runs is what shipped.

- Prototype types are referenced only inside `Native/AlManac/Prototypes/` plus that one gated
  branch — checked with a repo-wide search.
- `ReadinessDashboardView.swift` is **not modified** (verified against git; note that an
  earlier check of this was malformed and proved nothing — the conclusion was re-verified).
- No health data, persistence, or HealthKit behaviour was altered.
- To remove the prototypes entirely: delete `Native/AlManac/Prototypes/` and its
  `project.pbxproj` group plus six build-file entries.
