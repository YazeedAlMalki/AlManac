# Owner decisions — 2026-09-26

These are product decisions made by the owner, not spec requirements. They are
recorded here because the recurring failure in this repo is a decision living
only in someone's head and being "reconstructed" later from a document that was
never committed — see `WorkloadComputer.swift:27-28` and
`docs/architecture/spec-reconciliation.md` §"a fifth divergence". A decision that
is not written down gets re-derived wrong.

Each entry states what was asked, what the specs did and did not say, what was
built, and what was deliberately not done.

---

## 1. Sets are chosen from a fixed list: 1–5

**Asked:** "sets in log training should be choosing from a fixed number
(1,2,3,4,5)".

**What the specs say:** nothing. `workout_day_exercise.targetSets` and
`set_entry.setNumber` (`almanac-tech-spec-v1_0.md` §5.17) are unconstrained
nullable `INTEGER`s with no `CHECK`, no default and no range comment, and the
built `workoutBout.actualSets` (`Migration016.swift:142`) matches. The only
numeric `CHECK` anywhere in the training schema is
`sessionRPE BETWEEN 1 AND 10`.

**Built:** `LogBoutView` presents a segmented picker over `[1,2,3,4,5]`,
defaulting to 3. The distance/duration types, where sets are an optional repeat
multiplier, get the same list plus a "Not repeated" option.

**Why it is a change, not a fix:** the old free-text field was empty by default,
so forgetting it wrote a silent `NULL` rather than a number. A picker removes
that failure mode. It also caps what a `reps_load` bout can express at 5 sets,
which is a real constraint — 6+ set sets are now unrepresentable in the UI.

## 2. Reps use arrows, open at 6, floor at 1

**Asked:** "reps should be done by arrows (starts at 6 but you can go at low at
1)".

**What the specs say:** nothing about a rep entry mechanism, a default, or a
minimum. The only "1–10" bound in training is *session RPE*
(`brd-v1_6.md:216`), and per-set RPE is explicitly deferred.

**Built:** a `Stepper` over `1...999`, opening at 6.

**Note on the upper bound:** 999 is a UI affordance, not a limit anyone decided.
A `Stepper` needs a closed range and nothing in the specs caps reps, so it is set
well above any real set rather than asserting a maximum. Raise it if it ever
bites.

## 3. Volume is shown while logging

**Asked:** "user would want to track how much he did on this training".

**What already existed:** the Training dashboard has shown session totals —
tonnage, distance, time under load, reps, rounds, average RPE — since
`WorkloadComputer` shipped. That part was not missing.

**What was missing:** per-bout feedback *at the moment of logging*. You could
only see what you had done after leaving the sheet.

**Built:** `LogBoutView` shows a "This set" section with the tonnage the bout
will add (sets × reps × load), for the two types where that product means
something. It is `nil` — never `0` — for `reps_bodyweight`, which has no load to
multiply, so a bodyweight set does not claim to be "0 kg" of work.

**Not touched:** `WorkloadComputer` and the session summary. Also unchanged: the
spec's own cross-sport "volume" is `duration(min) × sessionRPE`
(`brd-v1_6.md:217`), *not* tonnage. Tonnage is an implementation-level
reconstruction covering 7 of 12 prescription types, and that gap is documented
rather than closed here.

## 4. Exercise progress graph

**Asked:** "btw im still waiting on exercise graph".

**What the specs say:** nothing, on any axis. `ExerciseDetailScreen` is "view
exercise info" (`almanac-tech-spec-v1_0.md:2072`); `SetListView` is per-session,
not per-exercise; the only chart in the screen map is the metric-scoped Trends
tab. Personal Records are listed as "Owner decision" and deferred
(`brd-v1_6.md:414`). `ExerciseProgressStore`'s doc comment says its history is
returned "so a trend/progress view has something to draw" — that is a code
comment, and it had no view.

**Built:** `ExerciseProgressView`, reachable from a per-row chart button in the
exercise picker. It plots **load per set** over sessions, lists every logged
bout, and reports the heaviest load and the largest single-session tonnage.

**Deliberate limits, because the spec warns about them:**

- **Load, not volume, is the plotted series.** Volume needs a set and rep count
  that a `reps_bodyweight` bout has no meaningful value for; a chart that
  silently drops half an exercise's history is worse than one plotting the
  number that is always present.
- **No personal records are claimed.** Heaviest and most-work are stated as
  maxima over two specific sessions, not as progress.
- **No "bigger is better" framing.** `almanac-tech-spec-v1_0.md` §types warns
  that two prescription types have prescribed and measured fields swapped and
  progress in *opposite* directions on the same clock. A naive upward-is-good
  reading would be wrong for those.
- **Only `actual*` fields are read**, never prescribed ones
  (`docs/features/training.md` §2).

## 5. Fasting state is not lumped in with logging a body number

**Asked:** "conditions = fasting/not fasting shouldnt be lumped with log body".

**Ambiguity, and how it was read:** this could mean (a) the picker should stop
being a third field of the measurement form, or (b) the condition should be
removed from body logging entirely and owned only by the Fasting module. (b)
would delete data the schema stores and the BRD asks for — body composition is
only comparable between like-conditioned measurements — so **(a) was built**:
`QuickBodyLogView` now has its own "Conditions" section, stating that it is not
a fasting session and that Fasting keeps that.

**Also built:** the picker pre-fills from `FastingModel.isFastDay`, so the user
is not asked to re-declare in two places what the Fasting module already
records. It stays "Unknown" when there is no session today — the measurement is
still valid, just not comparable, and saying so beats guessing.

**If (b) was meant**, the change is to drop the section and derive the stored
`conditions` value from the fasting session at save time. Say so and it is a
small edit.

## 6. Drinks, counted with their calories

**Asked:** "with logging water, user should have the ability to add other drinks
and should counted with his calories".

**What already existed:** all of it, in `AlmanacCore`, since Migration013 and
with nothing reaching it. `CatalogDrinks` ships ~20 named drinks with calories,
sodium and sugar. `HydrationLoggingService.logDrink` scales every figure to the
amount actually drunk, attaches a `DrinkAttachment`, flags a possible double
tap, and warns on high sugar and high sodium. `saveCustomDrink` persists
user-authored drinks. `grep DrinkCatalog Native/` returned **nothing** — the
whole capability was unreachable from the app.

**Built:** `HydrationLoggingView` is now a drink logger — catalog plus the
user's own drinks, amount with volume-scaled figures, and a "New drink" sheet
that persists through the service. `HydrationDashboardView` shows each entry's
drink name, its per-entry calories, and a day's drink-calorie total.

**Provenance is shown, not hidden.** `CatalogDrinks` states: "Do not present
these as measured anywhere in the UI without that qualifier visible." So every
catalog row is labelled "Typical value, not measured" and every custom row "Your
figures", in the picker, on the dashboard row, and in the scaling footnote.

**Drink calories are NOT merged into `NutritionTotals.kcal`.** They are a
separate "From drinks" line. A catalog drink is an uncited typical value and
food is a cited composition figure; summing them would launder an estimate into
a measurement, which is the exact distinction `Migration013` exists to protect.
This is the one place where the literal request ("counted with his calories")
was implemented as a labelled second number rather than one combined total, and
the reason is worth disagreeing with if you disagree.

## 7. Not built: Whoop, Fitbit, and other health-kit services

**Asked:** "we should also be able to sync other health kits (whoop, fitbit,
etc)" and "sync to weight scale".

**Not built, deliberately.** `grep -ril 'whoop\|fitbit' docs/` returns nothing —
no spec, no data model, no licence position, no credential handling, no decision
about which of them is authoritative when Whoop and HealthKit disagree about
sleep. Each is an external API integration with OAuth, rate limits and a
third-party data model that Almanac would have to map onto its own. Building it
unattended would mean inventing all of that and shipping it unverifiable: the
simulator has no Health app and no network credentials, so nothing written could
be confirmed to work.

**What already covers part of the intent:** weight *is* synced —
`HealthKitProvider` reads `bodyMass`, `bodyFatPercentage` and `leanBodyMass`, and
`BodyCompositionMeasurementHealthBridge` writes them. A Bluetooth scale that
writes into HealthKit therefore already lands in Almanac with no work. A scale
with its own app or API is a different problem and is not started.

**To actually do this, three things are needed from the owner first:** which
services (Whoop alone, or more), which fields Almanac should read from each, and
what happens on conflict when two sources disagree. That last one is a real
product decision, not an implementation detail — sleep staging from a watch and
from Whoop will not match, and something has to lose.

---

## Also changed in this pass, for the record

- **Quick Log sheet no longer states its name twice.** It had both
  `Text("Quick log")` in Fraunces 34pt and `.navigationTitle("Quick log")` in
  17pt semibold about 24pt apart. The navigation title is gone; the heading
  stays.
- **The four section icons on that sheet share one definition.** Water's was
  22pt with no chip while Food, Training and Body were 21pt in a 44pt
  `surfaceMuted` well, so the first header read as a different kind of thing
  from the three below it. Now `QuickLogSectionIcon`, used by all four.
