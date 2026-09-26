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

---

# Second pass, same day

## 8. Load steps by arrows

**Asked:** "load should have taps".

**Built:** a `Stepper` over `0...500` in 1 kg steps, in place of the free-text
decimal field. Shows "—" at zero and writes `nil` rather than `0` so an unset
load is distinguishable from a zero-weight movement.

**On the step size:** 1 kg, not 2.5. Fractional plates are common enough that
2.5 would strand anyone not training in 5s. Like the rep ceiling, this is a UI
affordance rather than a decided limit.

## 9. Exercises are already tracked, and the graph already exists

**Asked:** "when an exercise is entered it should be later tracked so user can
know his past performance in the exercise" and "there should be a graph to make
the user see his training on the exercise".

**Both were already delivered in the first pass today**, and neither needed new
work here:

- Tracking is `ExerciseProgressStore`, built 2026-09-18, with
  `ExerciseProgressView` added to reach it.
- The graph plots load per set across sessions, plus heaviest load and largest
  single-session tonnage, and is reachable from the exercise picker and now
  from the library.

What changed in this pass is only the entry point: the graph button also exists
on every row of the new library view, so it is reachable without first opening
a form.

## 10. Exercises grouped muscle → method of training

**Asked:** "exercises should be grouped like this. Muscle group > method of
training (bar, cable, machine, etc). exercises that activate multiple muscles can
be grouped in multiple muscle group."

**Both halves of the data already existed**, which is why this was a browse view
rather than a classification project:

- `exerciseCatalog.category` is a muscle — the shipped catalogue has 16 distinct
  values (Core 45, Glutes 38, Quads 35, Chest 26, Shoulders 22, Back 19, …).
- `exerciseCatalog.equipment` is the method — 17 distinct values (Bodyweight 111,
  Dumbbell 45, Machine 35, Barbell 29, Cable 26, Resistance Band 19, …).

**The many-to-many did not, and could not.** One `category` per row is enough to
browse by group but structurally cannot express "this movement also works the
triceps". So `Migration042` adds `exerciseMuscle (exerciseCatalogId, muscle,
isPrimary)` — one row per pair, primary flag stored rather than inferred, seeded
from `category`.

**Secondary muscles are deliberately empty.** Naming the secondary movers of 302
movements is a claim about physiology, and this repo's standing rule is that a
guessed value written into user data is worse than an absent one. The table is
the missing half of the structure; populating it is a separate, reviewable data
import via `addMuscle(to:muscle:)`, and no UI has to change when it arrives. The
browse view already handles a group in which an exercise appears only as a
secondary — it says "also works" rather than presenting it as a main entry.

**A bug the tests caught, worth recording because it would have shipped:** the
migration's seed only covers rows that existed *when the migration ran*, and the
shipped catalogue is seeded at launch, *after* migrations. A backfill-only
approach left every real exercise with no muscle row, so the whole library would
have rendered as a single "Unassigned" group. Fixed by mirroring the primary
muscle in `ExerciseCatalogStore.insert`, which holds the invariant for every
write path. Verified against the live simulator database: 302 rows seeded, 0
categorised exercises missing a row.

## 11. Fasting mode is a toggle

**Asked:** "toggle (religious fasting/intermittent fasting)" — religious counts
Fajr→Maghrib immediately, intermittent takes the time you last ate and the time
the fast broke.

**More already existed than expected.** `FastingSessionType` has had `religious`
*and* `ifPlanned` since the schema, `ReligiousFastingService.ensureDay` already
maintains the religious session from cached prayer times, `FastingSessionStore`
has `start`/`endScheduled`, and `ReligiousFastScheduleStore` knows which days are
fast days. What did not exist was any way to *choose*.

**Built:** a segmented Religious/Intermittent toggle at the top of Fasting, and
two different bodies beneath it.

- **Religious** shows the session, Fajr, Maghrib, and the window in hours
  computed from those two cached times. Nil when prayer times are not cached —
  the screen says so rather than inventing a window, which is the whole reason
  `Prayer` has to be configured first.
- **Intermittent** offers a `DatePicker` for "I last ate at" and a start button
  that writes a *backdated* `ifPlanned` session, plus an "I broke the fast just
  now" button once one is running. Also protocol (16:8 / 18:6 / OMAD / not set),
  which the column already had.

**Two deliberate guards.** The break button is scoped to `.ifPlanned`, so it
cannot close a religious fast and contradict `ReligiousFastingService`'s own
prayer-driven arithmetic. And the default mode is religious, because that is what
the screen assumed before — flipping it would silently stop maintaining today's
religious session on launch.

## 12. Which source wins — the user's call, per domain

**Asked:** "a decision about which source wins when Whoop and HealthKit disagree
about sleep — user gets to pick when setting up their profile and can change it
later from settings."

**This closes the blocker recorded in the first pass.** It is deliberately the
*arbitration layer only*, and it does not make Whoop or Fitbit exist.

- `Migration043` adds `sync_source_preference (domain, sourceId, updatedAt)`,
  primary key on domain, so re-picking overwrites and "change it later" is an
  update rather than a second competing opinion.
- `sourceId` is free text, not a foreign key, because there is no providers
  table and inventing one for a provider that has not been written would be a
  table describing a fiction. It also makes adding Whoop a data change rather
  than a migration.
- `SyncSourcePreferenceStore` reads and writes per domain across seven domains
  (sleep, heart rate, HRV, steps, energy, body composition, workouts).
- Reachable at Settings → HealthKit → "Which source wins".

**An absent row is meaningful**, not a default: it means the user has not been
asked about that domain, which is different from having been asked and left it
alone. The UI says "Not decided".

**Why per domain and not one global switch:** there is no defensible default.
Two providers will not agree about sleep staging — different sensors, different
epoch definitions — and "prefer the specialist" is wrong for at least one domain
just as surely as "prefer the phone" is. So the user decides, per domain.

**On "when setting up their profile":** profile setup is a display name and a few
fields. Grafting a seven-domain arbitration question onto it would be the wrong
place, so only the Settings route exists. The store is the same either way, and
adding a setup step later is a small edit.

**Still not built:** the second provider. HealthKit remains the only source
Almanac can read, which is why every row currently has one real choice. Setting
the preference now is still worthwhile — a preference recorded before a provider
starts writing is one recorded against data the user has already formed an
opinion about, rather than one made blind.
