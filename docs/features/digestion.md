# Digestion & Urination — BRD §6.3

**Status:** the stores have been complete and tested since 2026-09-16
(`DigestionStore`, `UrinationStore`, Migration032) with **zero** `Native/` call
sites. A quick-entry surface is now built and reachable from Quick Log
(2026-09-28). The read side — history, trends, charts — is not built.

## 1. What exists

| Concern | Where | State |
|---|---|---|
| `bowel_movement` logging, per-day read | `Sources/AlmanacCore/Digestion/DigestionStore.swift` | done 2026-09-16 |
| `urination_record` logging, per-day read | `Sources/AlmanacCore/Digestion/UrinationStore.swift` | done 2026-09-16 |
| Range reads, deletes | both stores | added 2026-09-28 with the screen |
| Bristol and grade display vocabularies | both stores | added 2026-09-28 |
| Quick entry from Quick Log | `Native/Almanac/DigestionQuickEntryView.swift` | done 2026-09-28 |
| History, trends, charts | — | **not built** |
| Three-level medical advisory | — | **not built, deliberately** — see §3 |
| Digestion ring fill rule | — | **not built, deliberately** — see §4 |

## 2. The screen

One sheet, a segmented control for the two kinds, time, the type or grade, the
flags, notes, and today's entries with swipe-to-delete. Saving returns the user
to Quick Log rather than closing it, which is Quick Log's existing convention —
a second entry is one tap away.

**The Bristol scale and the grade chart are pushed screens, not inline lists.**
Seven described rows plus eight grade rows inside the log form would push the
colour field, the symptoms, the notes and today's list most of a screen down —
and this is a *log* form, so everything below the fold is something the user
came here to do. The link carries the current choice, which is the part that has
to stay on screen; `BristolScaleView` and `UrinationGradeView` are where the
comparing happens, and all seven or eight rows render there at once. A seven
option wheel would have hidden six of them behind a spin, which defeats the
point of a *reference* scale.

**Colour is offered as text, never as a swatch.** BRD §6.3's accessibility rule
is "never rely on colour alone; numeric grades + text + VoiceOver", and a colour
chip *is* relying on colour alone — it is invisible to a VoiceOver user, and
"brown" and "pale yellow" are near-identical on screen at picker sizes.

## 3. No advisory, and the BRD says why

BRD §6.3 asks for a three-level non-diagnostic advisory (informational /
contact a professional / seek urgent attention) and then says its wording
**"requires clinician review before App Store release"**.

`clinicianEscalationLevel` is therefore written by nothing, and the screen
displays **no interpretation of any entry** — no colour is called concerning, no
grade is called dark, blood is shown as the fact the user recorded it as. The
section footer says so outright: "Almanac records what you saw and does not
interpret it."

The escalation rule the BRD *does* specify would key on "amount/type of blood,
black stool, persistent symptoms, bloody diarrhoea, severe pain,
dizziness/weakness". Building the display half of that rule is how the other
half would get written by accident, so neither half is built.

**Blood amount is a value, not a yes/no**, because the BRD's trigger is
"amount/type of blood" — a boolean cannot carry it. The four amounts
(none/streak/small/large) are this codebase's vocabulary, not the BRD's: it names
no amounts. That is recorded rather than presented as spec-derived.

**Gas has three states, not two.** `unstated` is a real value, distinct from
"no": a user who was not asked has recorded something different from a user who
noticed nothing, and the row's own footer says so — a user cannot otherwise
interpret a nil.

## 4. The digestion ring's fill rule is explicitly undecided

BRD §350: *"Fill condition explicitly undecided and not gated on anything. There
is no universal daily bowel-movement target, since normal ranges vary by
individual; the ring needs its own definition later and does not block this
section."*

So `ActivityRingDigestionState` has only `.disabled` and `.fillRuleUnavailable`,
and the Settings toggle turns on a ring that then says its fill rule is
unavailable. That is the spec working as written, not a bug. **No fill rule was
invented here**, and defining one needs a product decision, not a migration.

## 5. Vocabularies, and what is missing from them

- **`BristolType.displayName` / `.summary` / `.accessibilityLabel`** — the seven
  standard names after Heaton & Lewis (1997), with a one-clause summary each and
  a label carrying the number *and* the name. **Attribution is an open item**: the
  Attributions screen has not been extended to credit the scale, and these are
  reproduced published wording.
- **`StoolColor`** — BRD §6.3's own six (`brown, pale, yellow, green, black,
  red`), as a closed enum rather than the column's free `String?`. They are the
  values an escalation rule would key on, and a query over a spelling nobody
  fixed in advance finds nothing.
- **`UrinationColorGrade.displayName`** — **only the two ends are named** (1
  pale, 8 dark brown, from the type's own doc comment). Grades 2–7 stay "Grade
  N". A plausible ladder of eight colour descriptions would be eight clinical
  claims written by this codebase, a clause earlier and in a smaller font than
  the clinician review that §6.3's advisory section is itself held back for.
  `UrinationStoreTests` fails if anyone names one.
- **`urgency` is not offered.** The column is a bare `Int?` and neither the BRD
  nor the technical spec says what its numbers mean, so a picker would be
  inventing the scale. The screen writes nil.

## 6. Tests

`DigestionStoreTests` + `UrinationStoreTests` = 16 tests: range reads are
half-open and ordered by timestamp (not by insertion), deletes are hard deletes,
every display name is distinct, every accessibility label carries the number as
well as the words, `StoolColor`'s raw values are the six the column stores, and
the two named urine grades are the only two.

`DigestionQuickEntryUITests` = 7 tests: Quick Log offers the destination, the
scale offers seven named types carrying both number and name, choosing one marks
it *and reaches the form*, the chart offers eight grades each carrying number,
scale and name, the blood amount only appears after blood is said to be present,
gas offers "not stated" as its own value, and a logged entry appears in today's
list.

**The UI suite needs a wiped data container** — `xcrun simctl uninstall <udid>
com.almanac.personal` — because the tests share one installed app and the
database persists between them.
