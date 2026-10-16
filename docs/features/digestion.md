# Digestion & Urination — BRD §6.3

**Status (2026-10-15):** logging (2026-09-28) and the read side are built:
history, counts and a per-day chart at Modules → Records → Digestion; urine
colour feedback on the hydration target; the Bristol scale credited on the
Attributions page. **Two items wait on the owner and are not built:** the
medical advisory (gate G1, §3) and the digestion ring's fill rule (gate G2, §4).
Both gates were blank on 2026-10-15.

## 1. What exists

| Concern | Where | State |
|---|---|---|
| `bowel_movement` logging, per-day read | `Sources/AlmanacCore/Digestion/DigestionStore.swift` | done 2026-09-16 |
| `urination_record` logging, per-day read | `Sources/AlmanacCore/Digestion/UrinationStore.swift` | done 2026-09-16 |
| Range reads, deletes | both stores | added 2026-09-28 with the screen |
| Bristol and grade display vocabularies | both stores | added 2026-09-28 |
| Quick entry from Quick Log | `Native/Almanac/DigestionQuickEntryView.swift` | done 2026-09-28 |
| History, counts, chart | `DigestionHistory.swift`, `Native/Almanac/DigestionHistoryView.swift` | done 2026-10-15 — §7 |
| Urine colour → hydration target | `UrineColourHydrationFeedback.swift`, hydration screen | done 2026-10-15 — §8 |
| Bristol scale attribution | `AttributionCatalog` (`bristol-stool-form-scale`) | done 2026-10-15 — §5 |
| Three-level medical advisory | — | **not built: owner gate G1 open** — see §3 |
| Digestion ring | — | **removed from v1 (owner, G2, 2026-10-16)** — see §4 |

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

**Owner gate G1 (2026-10-15): blank.** The choice is "build now, with draft
wording marked *not clinician-reviewed*" or "remove from v1". Neither was
chosen, so nothing below changed.

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

**Owner gate G2 — closed 2026-10-16: the ring is removed from v1** (owner,
`docs/features/owner-decisions-2026-10-16.md`). `ActivityRingCalendar.digestionRingInV1`
is false, so every day reports the ring `.disabled` whatever is stored; the
Settings switch and the calendar's digestion row are gone. The stored setting
and its column are kept, so bringing the ring back is that flag and the switch,
not a migration. Tests: `ActivityRingCalendarTests.testDigestionRingSettingPersistsWithoutInventingAFillRule`,
`AttributionsUITests.testSettingsOffersNoDigestionRingInV1`.

What stood here before the answer:

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
  a label carrying the number *and* the name. **Credited 2026-10-15** on the
  Attributions page: Lewis SJ, Heaton KW, *Stool form scale as a useful guide to
  intestinal transit time*, Scand J Gastroenterol 1997;32(9):920–924. No
  licence for reproducing the wording was identified, and the entry says "No
  licence identified" rather than naming one (logged in `CONTEXT.md`).
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

## 7. History (2026-10-15)

Modules → Records → Digestion. A range control (7, 30, 90 days), then:

- totals for the range ("N bowel movements · N urinations");
- a bar per day for each kind, one neutral colour each, with the counts in
  the bars' accessibility values;
- counts **by Bristol type** — all seven, in scale order, zeros included, each
  row reading "Type 4, Smooth, soft sausage";
- counts **by colour** — only colours that occur; "Colour not recorded" for
  entries without one, and a hand-written spelling kept as written;
- counts **by urine grade** — all eight, each reading "Colour grade 8 of 8,
  Grade 8 — dark brown";
- each day's entries, newest day first.

Nothing is ranked, flagged or coloured by meaning. The footer repeats "Almanac
records what you saw and does not interpret it." Every count row carries its
number and its words, never a colour alone (BRD §6.20).

`DigestionHistoryReader.history(endingOn:days:)` is the one read: two range
queries, one pass. `LogicalDayRange` builds the range by calendar arithmetic on
the day labels, so a range across a daylight-saving change is still N days.

## 8. Urine colour and the water target (2026-10-15)

BRD §6.3: "Dark color despite target → raise target (suspended during
religious dry fasts)." On the hydration screen, when the day's **latest** urine
reading is grade 6, 7 or 8 **and** the day's intake has reached the goal, a
card offers "Raise target to N mL", N being the goal plus 250 mL. On a religious
fast day the card says instead that urine colour does not change the target on
a fast day. The wording is a draft and carries "not clinician-reviewed".

The thresholds are build decisions, logged unconfirmed in `CONTEXT.md` with how
to overrule them. The raise is offered, never applied silently.

## 9. Tests (2026-10-15)

- `DigestionHistoryTests` (10): range arithmetic across month and year ends,
  the day list, out-of-range entries, Bristol / colour / grade counts, the
  per-day series, and that nothing writes the escalation column.
- `UrineColourHydrationFeedbackTests` (9): dark despite the target raises one
  step; not before the target; only the latest reading counts; grade 5 is not
  dark and 6 is; no reading; suspended on a fast day; other days ignored; no
  target; the wording is labelled draft.
- `AttributionTests.bristolScaleIsCredited`.
- `DigestionHistoryUITests` (2), **passed** on a wiped iPhone 16e
  (2026-10-15): the screen offers its three ranges and says it does not
  interpret; logging a Type 4 through Quick Log raises the Type 4 count by one,
  and every count row carries its number and its name.
