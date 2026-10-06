# Almanac

A local-first health and fitness record for one person: what they eat, drink,
train, sleep and measure, kept in a database on their own device and turned
into scores, trends and suggestions.

## Language

### Laboratory import

**Import job**:
One attempt to bring an external laboratory file into the record. It has a
start, an outcome and a count of rows.
_Avoid_: import, sync, run

**Sync cursor**:
A position marking how far a repeating sync has got. It has no outcome and no
row count — knowing "how far" is not knowing "how well".
_Avoid_: job, import, checkpoint

**Import status**:
The single-word outcome of a job. One of *matched*, *partial*, *unmatched*,
*invalid*, *conflicted*, *failed*. A job always has exactly one.
_Avoid_: result, error, state

**Unmatched row**:
A row whose reported test name the catalog could not resolve to exactly one
analyte. A normal, expected outcome — the catalog refuses to guess — and not an
error.
_Avoid_: bad row, failed row, orphan

**Ambiguity**:
The catalog found more than one candidate analyte for a name and declined to
choose. Distinct from an unmatched row: here candidates exist and only the
choice is missing.
_Avoid_: duplicate, conflict

**Report conflict**:
An import found report-level metadata that disagrees with what is already
stored. Held for a person, because arrival order is not authority.

### Goals and body composition

**Goal**:
The direction of travel — bulk, cut, maintain or performance. A goal carries no
numbers of its own.
_Avoid_: plan, target, programme

**Target**:
A number for one metric, inside one goal. A cut goal implies a body-fat target;
it does not imply a weight or lean-mass target. Targets are per metric.
_Avoid_: goal, limit

**Goal snapshot**:
The immutable record of the targets in force from a given date. A goal change
inserts a new snapshot; snapshots are never rewritten.
_Avoid_: goal record, current targets

**Derived measure**:
A number the app computes from other measurements — fat mass in kilograms is
weight × body-fat percent. It is legitimate to show and never legitimate to
store as a measurement or trend as one.
_Avoid_: measurement, reading

**Unit basis**:
The choice between showing body composition in percent and in kilograms. One
choice for the app, not one per card.
_Avoid_: units, display mode

**Meter**:
A control showing how far a metric has travelled toward its target. It always
has a target: with none set it shows the absence rather than a bar.
_Avoid_: progress bar, gauge

### Profile

**Registration**:
The first-run flow that collects the required profile fields. Until it
completes, features are locked; saving is not.
_Avoid_: onboarding, sign-up

**First name / Last name**:
The two halves of a person's name, stored separately. The name shown in the
interface is the **display name**, which is derived from them.
_Avoid_: full name, given name (for Last name)

**Biological sex**:
A closed set — male, female, other, not set. The interface offers a subset; the
schema holds the whole set.
_Avoid_: gender, sex assigned at birth

**Training experience**:
How long a person has trained seriously: novice, beginner, moderate or expert,
with the years behind that label.
_Avoid_: skill level, fitness level

**Blood type**:
One of the eight ABO/Rh combinations. Recorded, not yet used to advise.
_Avoid_: blood group (acceptable variant)

**Allergen**:
One of the fourteen allergens named by regulation. A closed set with a fixed
vocabulary — not free text, because a free-text allergen can be misspelled into
being ignored.
_Avoid_: allergy, intolerance, sensitivity

**Allergen-safe**:
A food whose declared allergens do not intersect the person's allergens. Being
allergen-safe requires the food's allergens to be *known*.

**Unverified**:
A food with no allergen data. Not the same as safe, and never presented as it.
_Avoid_: unknown, probably fine

**Feature gate**:
What registration locks, and what it does not. Features are gated; writing data
is not, so a person mid-setup can still log.
_Avoid_: lockout, restriction

### Navigation

**Destination**:
A screen a person can be sent to from anywhere, naming both the tab that owns
it and the route inside that tab.
_Avoid_: screen, page, view

**Tab coordinator**:
The single owner of which tab is selected and how deep each tab's navigation
stack is. Above the bar, injected downward.
_Avoid_: router, navigator, coordinator (alone)

## Decisions taken without an answer

Four product questions were put to the owner on 2026-09-30 and not answered
before the work continued. Each was resolved by taking the narrowest option that
honours the request, and each is recorded here so it can be overruled without
having to reverse-engineer the reasoning. **None of these has been confirmed.**

Two more were put on 2026-10-01 with the Training Program handoff and resolved
the same way. Both are recorded here for the same reason, and the first one
reconstructed a table rather than choosing among options.

Four more were settled while making a readiness score reachable on a device with
no watch (2026-10-04), where the BRD's "manual fallback" left the scope, the
bounds and the read-for-which-day open. None is confirmed either.

More were settled on 2026-10-06 while carrying out that day's handoff (readiness,
vitals, Kitchen, workout templates). Each sits in the subsection for its area and
is marked with that date. **None of these has been confirmed.** Where the owner
*did* answer, the entry says "confirmed by the owner" and names the date.

**Macro targets — left null.** `goal_target_snapshot`'s protein, carbohydrate and
fat columns are nullable and stay empty. Nothing in the BRD, the spec or the
handoff says how to derive a macro split, and this repository does not invent a
number nobody chose. Only calories (Mifflin-St Jeor, which needs a sex and a
height) and hydration (35 mL/kg) are generated. *Overrule by:* naming a rule —
fixed calorie share, or g/kg bodyweight.

**Greeting name — first name, falling back to `displayName`.** Already
implemented as `UserProfile.preferredName`. "First Last" and `displayName` only
were the alternatives. *Overrule by:* changing `preferredName`.

**Registration gate — Insights and the calorie target only.** Narrowest thing
that honours "lock features until registration" without blocking data entry. All
four modules stay open for logging. *Overrule by:* widening to all four modules
or narrowing to the calorie card alone.

**Allergen filter scope — food search only.** What was built. Saved meals are
**not** covered, and this is the one gap here with a safety argument behind it: a
saved meal is a suggestion the app itself made, and somebody with a peanut
allergy logging one deserves the same warning the search gives. It was not built
because the owner's decision was "food allergies gate food suggestions", and
saved meals are not suggestions. *Overrule by:* adding a warning at
`NutritionSavedMealsView`.

**Answered and closed, 2026-10-06 (confirmed by the owner): "same rule
everywhere."** Saved meals and Kitchen recipes are the same rows and now share
one check, `DishAllergenCheck`. On both screens a dish naming a recorded allergen
is hidden by default, listed under a collapsed "Hidden because of your
allergens" entry, and opens on its own page under a warning naming the allergen.
The fail-closed error on an unreadable allergen list stays on both. Food search
is unchanged (it still lists withheld foods by name and reason, not openable);
aligning it was not trivial, because a food has no page of its own to open.

### Training program (2026-10-01)

**Readiness→prescription coupling — reconstructed, and overrulable in one place.**
The handoff asks for "readiness adjustment computation" and points at
`prescription-model-v0.1.md` for the table. That file was never committed to
this repository (`docs/features/training.md` §1 records why), so the coupling is
gone. Two rules survive, quoted in the technical spec §5.17: `release` is the
only prescription type that should ever *increase* on a low-readiness day, and
`quality_reps` holds volume and drops complexity rather than reducing work.
Everything else — every multiplier, every band boundary — was reconstructed from
the two rules plus `ReadinessFormula`'s own six bands and its real 40/70
thresholds. No threshold was invented; no new band was invented.
`ReadinessAdjustment.BandRule` is the entire table, in one array, one row per
band: load / duration / rest / release multipliers. *Overrule by:* editing that
one array. Do not scatter the numbers into callers.
`_Avoid_`: scaling the prescription in place, mutating a pool item on a low day

**Volume graph — reps performed, not kilogram-reps.** The handoff says Graph B
is "volume (sets × reps × load)". Built as sets × reps instead, because
weighting volume by load makes the axis a statement about the barbell rather
than about the session: a heavy triple outweighs a light set of twenty, and a
heavy day's volume would spike for a reason the graph cannot explain. `ProgressGraph.volume`
documents this; `EquipmentVariantGraphTests.theTwoGraphsMeasureDifferentThings`
pins it. *Overrule by:* changing `EquipmentVariantGraph.value(row:graph:)`.

### Readiness and vitals (2026-10-04)

**Manual entry covers RHR and HRV, not all four vitals §6.7 names.** The BRD
lists resting HR, HRV, steps and active energy with "manual fallback", and only
the first two have a readiness term to land on; a step field with nothing behind
it is a control waiting to become a lie. *Overrule by:* naming where steps or
active energy are consumed — which is a §9.x change, not a screen change.
`VitalsMetric` is the whole hand-enterable vocabulary and `recordManual` is the
only way in.

**The plausibility bounds are a typo guard, and "Save anyway" is always
offered.** 25–250 bpm and 1–500 ms catch the failures a keyboard makes and
claim nothing clinical; nothing in the BRD or spec states a normal range, and
this repository does not invent one. `BodyMeasurementType.plausibleRange` set the
precedent and the wording. *Overrule by:* replacing the ranges with sourced
ones — and then saying so in the error copy.

**A score reads the vitals of the day it is scoring, or nothing at all.**
`latestValue(for:since:)` is bounded to the last primary episode's start, else
the start of the logical day, and returns nil when neither resolves. The
earlier "newest row wins" read was correct while the HealthKit bridge was the
only writer and stopped being correct the moment a person types "this morning,
about last night". *Overrule by:* removing the `since` argument — which restores
the bug, in the specific shape of a score borrowing another night's reading.
`nil` means missing; it never means zero and never falls back to history.

**§9.8's baseline can be today's own reading, and the score is inflated when it
is.** `meanPerDay` averages within a day and `recent(_:through:)` keeps
`$0 <= date`, so today is inside the 28-valid-day window — but a window day
contributes to a metric's mean only if it *carries* that metric. When today is
the only day in the window with an RHR, the "28-day baseline" is one day long and
*is* the reading being scored, so `delta ≡ 0` and §9.2's `delta ≤ 0 → 95` and
`pct ≥ -5% → 75` rows pay out **+95 and +75 of unearned credit** instead of
reporting that no baseline exists.

**Corrected 2026-10-04.** This was first recorded as "a single-reading day always
scores 66", which was an artefact of measuring it with no sleep data. The real
shape is an 8-hour night plus that first reading, which scores **74 — green,
"Recovery is good — ready for a strong session"** — while `confidence` reads
`medium`, because the two vacuous inputs are counted as present. It is also not
a calibration-phase artefact: with 27 prior sleep-only valid days,
`validDayCount = 28` and `calibrationDay = nil`, and the degenerate score is
still produced. It recurs on every first entry after a gap, forever, for the
sporadic manual-entry user §6.7's fallback exists to serve.

**Fixed 2026-10-05, by the narrowest reading that removes it.** A baseline
assembled *only* from the day being scored is now reported as **no baseline**
(§9.1's own redistribution rule then treats both vitals inputs as missing). The
realistic case moves 74 → 72 and `confidence` `medium → veryLow`; the number
barely moves because an 8-hour night legitimately scores high, so what was wrong
was the *confidence claim*. `validDayCount` is deliberately unchanged — §9.8
counts valid days. This is the degenerate case rather than a calibration choice:
a baseline made only of the day it scores is vacuous by identity, not by being
short, so it invents no threshold the spec does not already state.

**Confirmed by the owner, 2026-10-06: a missing personal baseline withholds the
recommendation**, rather than merely marking it preliminary. He also confirmed
the same day that the score's colour and the Training Program's score-based
scaling stay exactly as they are. Built in `ReadinessEngine`; see
`docs/features/readiness.md` ("No personal baseline withholds the
recommendation"). The two overrules recorded earlier for the baseline itself
still stand: excluding today from the window — which is a different reading of
§9.8 than the one the spec states, and would need every band re-read — or making
`ReadinessBaseline` carry the number of days behind each metric and having
`ReadinessEngine` refuse to score against a depth it can name. Measured figures
are in `docs/features/readiness.md`; what it cost the two checklist rows that
were asserting on the defect, and the launch-argument seeding hook that repaired
them, are in `docs/implementation-status.md`.

**When the withhold applies — unconfirmed (2026-10-06).** The owner confirmed
*that* a missing baseline withholds; *what counts as missing* was read here as:
the scored day carries at least one resting-HR or HRV reading, and **none** of
the readings it carries has a baseline. A sleep-only day is "inputs missing" and
unchanged; a day where one reading was compared against a real baseline keeps
its sentence. What is withheld is the band sentence, in `textDescription` and
`recommendation`; the score, colour, confidence and context text stay.
*Overrule by:* the stricter reading — withhold when **any** reading present lacks
a baseline — by making `ReadinessEngine.lacksPersonalBaseline` return
`(rhrPresent && baseline.restingHeartRate == nil) || (hrvPresent && baseline.hrv == nil)`,
and inverting `testOneComparedReadingKeepsTheBandSentence`.

### Kitchen (2026-10-06)

The owner's six Kitchen calls are logged in `docs/features/kitchen.md` §3. The
details below were left to the build. **None of these has been confirmed.**

**Logging a hidden dish asks first.** A dish hidden by the allergen check can be
opened and logged, and "Log anyway…" on its page raises a confirmation naming the
warning before the dish reaches the logging form. The owner said a hidden recipe
is reachable and carries a warning; he did not say whether logging it should ask
again. *Overrule by:* calling `onLogAnyway()` directly in `HiddenDishPage`
(`Native/Almanac/HiddenDishViews.swift`) instead of setting `confirming`.

**The warning's wording and place.** On the dish's own page, first, as a problem
note: "Allergen warning: this names Peanuts, which you have recorded as an
allergen. Found in: Peanut sauce." — the allergen by the title he chose it under,
and the names it was found in. It says "names", not "contains", because the check
reads names. The disclaimer follows lower on the page. *Overrule by:* editing
`DishAllergenJudgement.warning` (one string, shared by both screens).

### Weighing

**Meter fraction**:
How far a reading has travelled from the oldest reading in the window towards a
target, as a fraction of travelled-plus-remaining. `nil` when there is no target,
no reading, fewer than two readings, no span, or the target is met — five
distinct reasons, none of which is "0%".
_Avoid_: progress, completion
