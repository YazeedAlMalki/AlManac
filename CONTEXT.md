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

### Fasting and prayer

**Fast day**:
A civil date on which a religious fast is kept — by the calendar (Ramadan,
Mondays and Thursdays, the White Days) or by the user's own correction, which
always wins. Eid and the days of Tashreeq are never one by the calendar.
_Avoid_: fasting day, day type

**Correction**:
The user's word on one date — a fast, not a fast, or back to the calendar.
Logged, never overwritten; the newest one wins.
_Avoid_: override, exception

**Religious session**:
A fast day's Fajr→Maghrib fast as recorded. *Derived*, not entered: from the
fast day, its prayer times and the first intake after Fajr. It does not exist
before Fajr; everything before Fajr is suhoor.
_Avoid_: dry fast (that is a property of it), Ramadan session

**Intake**:
Anything logged as eaten or drunk with a precise time. Any intake breaks a
religious fast; only a calorie-bearing one breaks an intermittent fast.
_Avoid_: entry, meal (a drink is an intake too)

**Night window**:
Maghrib of a fast day to the next Fajr — iftar to suhoor, one night even past
midnight. Its date is the fast day's, not the date suhoor falls on.
_Avoid_: eating window, evening

**Chosen city**:
A location the user picked from the bundled list. It stays until they ask for
their current location; detected travel does not replace it.
_Avoid_: manual location, fallback

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

Seven more were settled while making fasting and prayer times work end to end
(2026-10-06), where the spec gave the rule but not the default or the edge. None
is confirmed.

More were settled on 2026-10-15 while taking Slices 7 and 9 toward done; they
are under "Digestion and urination" and "Body and wellness" below.

Four more were settled on 2026-10-16 while building the recovery day a person
declares (§9.6); they are under "Readiness: the declared recovery day" below.

More were settled on 2026-10-16 while carrying out that day's AI handoff (fasting,
dish servings, reminder times, backup checksums); they are under "The
2026-10-16 handoff" below. None is confirmed.

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

### Readiness: the declared recovery day (2026-10-16)

Settled while building §9.6's "manually selected recovery day (user set via
UI)". The spec gives the rule, its rank and its wording, and says nothing about
where it is set or for which days. **None of these has been confirmed.**

**It is a switch on Today, under the "For this cycle" card, and it writes the
moment it moves.** Not a field in the mood & soreness check-in: that sheet
saves on Save, so Cancel would drop a declaration, and a recovery day needs no
mood score to be true. Writing immediately is what keeps it changeable for as
long as the screen is open, as the readiness switch on a training session is.
*Overrule by:* moving `ReadinessDashboardView.recoveryDay` into
`MoodSorenessCheckInView` and calling `ReadinessModel.setRecoveryDay` from its
`save()`.

**The screen declares today only.** `RecoveryDayStore` takes any logical day and
a back-dated declaration is attributed to the day it names, but no screen offers
another day, and declaring one does not rewrite that day's stored score (§9.9).
*Overrule by:* a day picker that calls `RecoveryDayStore.set` with the chosen
day — and, if the past record should change too, an explicit rescore of that
day, which is a §9.9 question rather than a screen one.

**Clearing deletes the row.** A declaration is a switch, not a reading, so its
own history is not kept; whether the rule held on a scored day is already in
that day's `readiness_record.precedenceApplied`. *Overrule by:* a `clearedAt`
column on `recovery_day_declaration` (a migration) and a `clear` that sets it.

**It changes the recommendation and nothing else on screen.** The headline
gets no suffix (§9.4 lists none for a recovery day, where it does for a planned
rest day and a deload), and the switch is labelled "Recovery day", described as
"Your own call for today. It changes the advice, not the score." It never says
"rest day". *Overrule by:* adding a suffix in `ReadinessEngine.describe`, or
rewording the two strings in `ReadinessDashboardView.recoveryDay` (and their
Arabic in `Localizable.xcstrings`).

### Fasting and prayer (2026-10-06)

**Ramadan is observed by default; Mondays/Thursdays and the White Days are not.**
§6.13's flow starts from a day "pre-typed Religious Fast by Ramadan schedule", and
the 2026-09-17 decision was "auto-create, always correctable". The two voluntary
rules are off until switched on, because a voluntary fast the app assumed is a
claim about the user's worship. Turning Ramadan off carries forward to next
year's row. *Overrule by:* `ReligiousFastScheduleStore.isRamadanEnabled`'s
default.

**An intermittent fast still running at Fajr on a fast day ends at Fajr.** Only
one session can be active, and the religious fast cannot be the one that waits.
The IF session keeps the hours it really ran. *Overrule by:*
`ReligiousFastingService.yieldActiveIntermittentSession`.

**Un-marking a day deletes the session the calendar made for it**, and its night
window. It was derived state; every input (schedule, correction, prayer times,
intake) is kept, so re-marking the day rebuilds it exactly. *Overrule by:*
invalidating instead of deleting in `ReligiousFastingService.ensureDay`.

**A chosen city stops automatic location until the user asks for it again.**
§12.4 says a detected move clears the override, which would undo a chosen city
on the next foreground for anyone whose phone is somewhere else. The engine still
follows §12.4; the app simply does not feed it fixes while a city is chosen.
*Overrule by:* calling `refreshLocationIfAutomatic` regardless of
`manualCityOverride` in `PrayerModel`.

**Seven calculation methods beyond §12.1's five, plus custom angles and the Hanafi
Asr.** All already in the vendored library; without them a user in Kuwait,
Qatar, the Emirates, Turkey, Iran, Singapore or following the Moonsighting
Committee had no correct Fajr. Asr needed a column (Migration050). *Overrule by:*
trimming `PrayerCalculationMethod.storedVocabulary`.

**Prayer-time alerts exist, are off by default, and nothing suppresses them.** The
owner asked for the adhan to work; the BRD's notification list predates it. On a
fast day Maghrib's alert is the iftar reminder rather than a second notification
at the same second. *Overrule by:* the `prayer` row in
`NotificationSuppressionMatrix`.

**The Fasting screen opens on Religious every time.** The UI acceptance test pins
that default, and the religious state is maintained whichever tab is showing.
*Overrule by:* persisting `FastingModel.mode`.

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

**Imported recipes get a serving count by asking, not by estimate.** The owner
chose "one serving" as the default amount; a dish nobody has counted is the
whole dish. For an imported recipe that default is the whole pot, and an
estimate ("TheMealDB recipes serve 4") would be a number nobody chose. So when an
import is built, imported recipes are stored with no count and Kitchen asks "How
many servings does this make?" the first time one is chosen, storing the answer
in `serving_count`. Not built: there is no import (the terms gate is shut).
*Overrule by:* having the importer write an estimate into `serving_count`.

**Pantry suggestions: 3 distinct days in the last 14, recipes excluded.** The
owner chose "declared, with suggestions" and left the threshold open. A food is
offered when it was logged on at least 3 distinct logical days among the last 14
(today included) — days rather than entries, so three eggs at one breakfast are
one day of eggs — and is not already in the pantry, not dismissed, and not a
recipe (a recipe is made from a pantry, not kept in one). Only foods logged
directly count; a logged recipe's ingredients do not. A dismissal is permanent
for that food. *Overrule by:* changing `PantrySuggestions.minimumDays` /
`windowDays`, or the filters in `PantrySuggestions.suggestions`.

**The ingredient-merge rule.** The owner chose to build the ingredient table;
the rule is a build decision. Two catalog foods are one ingredient when their
names agree once preparation (raw, roasted, grilled, frozen, organic…) and
cut-and-skin qualifiers (meat only, without skin, lean flesh…) are set aside.
Form words (dried, canned, smoked, salted, juice, powder) are kept. A name that
says something was *added* — coated, breaded, battered, sauce, stuffed,
marinated, glazed, filled, nuggets, ready meal — is never merged with anything,
because the addition is where an allergen hides. Skin-on and skin-off breast are
the same ingredient; dried and fresh apricots are not. The allergen check reads
each food's own names plus the canonical name, never fewer. *Overrule by:*
editing the word lists in `IngredientNormaliser`, adding aliases to
`IngredientTable.curatedAliases`, or pinning a food with `IngredientTable.curate`.

### Training templates (2026-10-06)

**Confirmed by the owner, 2026-10-06: a template is exercises, but editable.**
Applying one fills the session with its exercises, with sets and reps where the
template has them, as a starting point. The session then stays his to change.
Built: `TemplateApplier`, Migration 055; see `docs/features/training.md`. The
calls below were left to the build. **None of these has been confirmed.**

**A session that already has logged bouts asks first.** The template's exercises
are added after them only on "Add after them". Replacing is never offered,
because it would delete logged work. *Overrule by:* passing
`appendingAfterExisting: true` from the start in `TrainingDashboardView.apply`,
or refusing outright.

**Applying records nothing as done.** The plan goes in the `prescribed*`
columns, `actual*` stays empty, and the row reads "Planned · …" until something
is recorded. *Overrule by:* copying the plan into `actual*` in
`TemplateApplier.apply`, which would make an untrained session read as done.

**One entry point: "Start from a template" on the Training screen, applied to
today.** It fills his own ad-hoc session for the day, never a watch workout or a
program day's session. The first template applied names the session. *Overrule
by:* adding a "Use today" action to `TrainingTemplateView`'s rows, which the
proposal had suggested.

**A plan is not load (2026-10-07).** Applying a template writes only planned
numbers, and `WorkloadComputer` used to count a bout's planned numbers when it
had no actual ones, so starting a template added its full tonnage to Today's
load, readiness and Insights before anything was done. Now a bout with nothing
recorded as done (no actual value, no elapsed time, no RPE) adds nothing. A bout
with some actuals still fills the rest from its plan. The same rule stops a
program exercise skipped for the session from counting as done work. Raised by
the Codex review on PR #6. *Overrule by:* removing the `wasPerformed` filter in
`WorkloadComputer.summary(for:)`.

### Digestion and urination (2026-10-15)

Settled while taking Slice 9 toward done. **None of these has been confirmed.**
The two owner gates for this slice (the medical advisory and the digestion ring's
fill rule) were left blank and are **not** decided here; see
`docs/features/digestion.md` §3–§4.

**History lives at Modules → Records → Digestion, over 7, 30 or 90 days.** It
lists counts by Bristol type (all seven, zeros included), by urine grade (all
eight), by colour name (only colours that occur), a bar per day, and each day's
entries. It interprets nothing. *Overrule by:* `AppRoute.digestion`'s section,
or `DigestionHistoryView.Span`.

**A colour the user did not record is counted as "Colour not recorded", and a
spelling outside the six is kept as written**, never folded into the nearest
named colour. *Overrule by:* `DigestionColourTally.init(stored:)`.

**Urine colour feedback: "dark" is grade 6, 7 or 8; "despite the target" means
the day's intake has reached the day's goal; only the latest reading of the day
counts; the raise is 250 mL; it is offered as a button, never applied
silently; and it is suspended for the whole of a religious fast day.** BRD §6.3
gives the rule's shape and no numbers. The wording is a draft and says "not
clinician-reviewed". *Overrule by:* `UrineColourHydrationFeedback.darkGrades`,
`.raiseStepMilliliters`, or `.evaluate`; to apply the raise automatically, call
`HydrationModel.saveDailyGoal` from `refresh()` instead of showing the button.

**The Bristol scale is credited with "No licence identified".** The seven type
names are the published wording of Lewis & Heaton (1997). No licence or
permission for reproducing them was found, so the Attributions entry says so
rather than naming one. *Overrule by:* recording the licence or permission in
the `bristol-stool-form-scale` entry of `AttributionCatalog`, or rewording the
type names in Almanac's own words.

### Body and wellness (2026-10-15)

Settled while taking Slice 7 toward done. **None of these has been confirmed.**
The three owner gates for this slice (progress photos, the lab import-job
failure row, verified LOINC codes) were left blank and are **not** decided here.

**Only a reading the person typed can be corrected or deleted.** An imported
reading belongs to Health or the device (BRD §5.6). A correction does not change
a copy already sent to Health; a deletion takes a not-yet-sent reading off the
Health queue. Same rule as the waist store. *Overrule by:*
`BodyCompositionMeasurementStore.correct` / `.delete`.

**The seven built-in circumference points stay, and the owner can hide any of
them and add their own.** The built-ins carry left/right sides, the waist's
Health sync and a typo guard, which a free-text point does not. Owner points are
`custom_measurement_definition` rows in centimetres, with no sides and no typo
guard beyond "positive". Hiding a point keeps its readings (Migration 056).
*Overrule by:* migrating the seven into `custom_measurement_definition` and
retiring `BodyMeasurementType`, which is a data migration with a decision
about existing sided rows.

**Turning a supplement plan's reminder on also turns on supplement reminders as
a type.** §5.25 seeds the type off, so without this a reminder set on a plan
would never fire. Turning one plan's reminder off leaves the type alone.
*Overrule by:* `SupplementReminderSetting.set`.

**Lab unit conversion: a series is shown in its latest result's unit;
everything else is converted only by decimal scaling within one dimension;
mass ↔ substance and two different activity units are not converted; nothing is
stored.** `docs/features/laboratory.md` §8a. *Overrule by:*
`LabUnitConversion.series` (target unit) or `.convert`.

**Lab re-test suggestion: the last result's day plus the person's own median
interval, from at least three results on distinct days; month- or year-dated
results are left out.** No clinical interval is used. *Overrule by:*
`LabRetestSuggestion.minimumResults` / `.suggest`.

**Where the new analytes sit.** Homocysteine and vitamin D binding protein are
chemistry, not vitamins (one is a marker shared by B9 and B12, the other a
carrier protein). Free 25-OH D is the fifth vitamin D form, so the vitamin
counts are now 25 entries, 21 direct. A bare "Bilirubin" is the total, a bare
"Reticulocytes" the absolute count. Urine analytes carry "urine" in their names
unless the test exists only in urine. New panels: liver (7) and urinalysis (10);
the thyroid panel is unchanged. *Overrule by:* `LabCatalogSeed`.

**Lab citations name where a test is described, not where a range comes from.**
MedlinePlus pages, and Bikle & Schwartz (2019) for the two vitamin D entries.
Entries seeded before 2026-10-15 are not yet cited. *Overrule by:*
`LabCatalogSeed.sources`.

### The 2026-10-16 handoff

Settled while carrying out the AI tasks of the 2026-10-16 handoff. **None of
these has been confirmed.**

**A fast left open from before yesterday is closed at its own Maghrib.** The
fix for a religious fast nobody re-derived because the app was not opened for
two or more days. Only the one active religious session is closed this way; an
intermittent fast left running is not, because it has no scheduled end and
§11.1 ends it at the next meal. *Overrule by:* the `if let open = …` block at
the top of `FastingCoordinator.refresh`.

**Dish servings are set from Saved meals, by a swipe.** No screen edits a dish,
and Saved meals is the only screen that lists them, so the count is a
"Servings" swipe action there, opening a small sheet. *Overrule by:* moving
`DishServingCountSheet` (`Native/Almanac/NutritionSavedMealsView.swift`) to
wherever a dish editor is built.

**A serving count, when first turned on, starts at 2; it runs 1 to 50.** Two is
the smallest count that changes what one serving is. A dish with no count stays
one serving whole, which is the owner's rule (2026-10-06), and turning the count
off goes back to that. *Overrule by:* `DishServingCountSheet.firstCount` and the
`Stepper` range in the same file.

**The Kitchen test seed takes back serving counts.** It is "authoritative", and
a count left by one UI test would change the 200 g pre-fill another test
expects. *Overrule by:* the `.servings(nil)` loop in `KitchenSeedPlan.apply`.

**Suhoor and iftar times are a distance from the prayer, not a clock time.** Both
are derived from prayer times that move every day, so a clock time would drift
off them. Suhoor: 5 to 90 minutes before Fajr, default §14.2's 20. Iftar: 0 to
60 minutes after Maghrib, default §14.2's 0. Steps of 5. Stored in a new column
(Migration 058, `notification_rule.offsetMinutes`) rather than in
`scheduledTimeHHMM`, which holds a time of day. *Overrule by:*
`NotificationRule.offsetRange(for:)`, or by reading `scheduledTimeHHMM` as an
override in `NotificationPlanner.appendSuhoor` / `appendIftar`.

**An iftar reminder set after Maghrib says when Maghrib was.** §14.2's "Maghrib
has arrived" would be late news 15 minutes on, so the body becomes "Maghrib was
at [time]. Your fast has ended." At 0 minutes the spec's own words are kept.
Suhoor's title says the minutes chosen. *Overrule by:*
`NotificationText.iftarBody(maghribText:)` / `suhoorTitle(fajrText:minutesRemaining:)`.

**A readiness or bedtime time is a fallback, never an override.** §14.2 says
bedtime "falls back to user-set time"; readiness is treated the same way. The
set time is used only on a day with no sleep episode, shift time or (for
readiness) 7-day wake average to go by. A time before 04:00 belongs to the end
of the logical day. When first turned on, the picker starts at 07:00 for
readiness and 22:30 for bedtime. *Overrule by:* the `?? fallbackTime(…)` in
`NotificationPlanner.appendReadiness` / `appendBedtime`, and
`NotificationSettingsView.firstMinute(for:)`.

**"Which fasts do you keep?" is a card on Today, not a screen before the app.**
The owner chose "ask me first" (T02). There is no first-run screen in the app,
and a sheet over the first launch would stand in front of every UI test on a
fresh simulator. Today is the first screen, so the card is the first thing seen;
it stays until answered, and until then Ramadan stays on. *Overrule by:* moving
`FastsQuestionCard` (`Native/Almanac/FastingViews.swift`) into a sheet presented
from `AlmanacApp` while `FastingModel.needsFastsQuestion` is true.

**A backup from before document checksums still restores.** Bundles written
before 2026-10-16 have no `sha256` column in `bundle_files`; their database is
checked and their documents cannot be. A bundle that has the column and a
missing digest is refused as corrupt. *Overrule by:* returning an error instead
of `return` in `BackupService.verifyDocumentChecksums` when the column is absent.

### Kitchen recipes from Wikibooks (2026-10-16)

The owner picked the Wikibooks Cookbook (T04). How it was built was left to
the build; **none of these has been confirmed.**

**Recipes with pork or alcohol are left out.** Eight recipes were dropped
for an ingredient marked `pork` (bacon, ham, pork, pork sausage, lard,
gelatine) or `alcohol` (wine, rum, beer). Almanac keeps Islamic fasts and
prayer times, so a recipe list that offered them by default seemed wrong; it
is a guess about the owner's wishes, not something he said. Vinegar and
vanilla extract are kept. *Overrule by:* `python3 -m almanac_recipes build
--allow-excluded`, or clearing the `exclude` column in
`tools/recipes/ingredients.csv`.

**An imported recipe is an `almanac:` dish, marked by its own source row.**
So logging, serving counts, the ingredient table and the allergen check need
no second path. Its `nutrition_food.licence_group` is `N`, because that column
describes nutrition values, these are reduced on the device from licensed
components, and the column admits only A, B and N. The recipe's own licence
(CC BY-SA 4.0), title, link and revision are in `kitchen_recipe_source`
(Migration 062). This does stretch `N`'s comment ("rows Almanac authors and
owns outright"). *Overrule by:* a new `SourceIdentifier.Namespace` for
imported recipes, which also means widening `requireNative` in
`NutritionDishEditor`, the importer's `namespace <> 'almanac'` rule, and the
`licence_group` CHECK.

**Methods are not shipped; each recipe links to its page.** Only the name and
the ingredient list, converted to grams, are in the bundle. Kitchen picks a
recipe to log, not to cook from, and leaving the text out keeps the CC BY-SA
material small. *Overrule by:* adding the procedure section to `build.py`'s
output and a recipe page in `KitchenRecipesView.swift`.

**A stated serving count is used; otherwise Kitchen asks.** A page's
"Servings = 4" is the author's figure, not an estimate, so it sets the count
on first install (70 of 298). For the rest, the 2026-10-06 rule stands: the
first time one is chosen, "How many servings does this make?", starting at 2
like the Saved meals control (1–50). "Not now" logs the whole recipe as one
serving and asks again next time. A later install never overwrites a count
the person set. *Overrule by:* `WikibooksRecipeBundle.install` (the
`isNew, let servings` line) and `RecipeServingsQuestion` in
`KitchenRecipesView.swift`.

**How a line becomes grams.** Volumes and counts go through one USDA SR
Legacy household measure per ingredient, chosen in `ingredients.csv` (onion:
"1 cup, chopped", 160 g; egg: "large", 50 g). A range is its midpoint. A
seasoning with no amount, a pinch or a dash is set aside, which leaves a
negligible amount of energy out. Any other unreadable line drops the recipe.
The conversions are typical weights, not the author's. *Overrule by:* the
rows of `tools/recipes/ingredients.csv` and the rules in
`tools/recipes/almanac_recipes/build.py`.

**Imported recipes are Kitchen's, not Saved meals'.** Saved meals lists only
the person's own dishes, and "All" in Kitchen lists the person's own recipes
first, then the imported ones, all of them (no limit of 50). *Overrule by:*
the `imported` filter in `SavedMeals.list(excluding:)`, `RecipeFinder.ownFirst`,
and the `limit:` in `NutritionModel.browseRecipes`.

**The credit is one line on every imported recipe, plus a link.** "From the
Wikibooks Cookbook, CC BY-SA 4.0. Amounts converted to grams." under the
recipe's name, a book button that opens its page, and the full statement of
changes on the Attributions page. *Overrule by:* `ImportedRecipeSource.credit`
and `RecipeRow` in `KitchenRecipesView.swift`.

### Weighing

**Meter fraction**:
How far a reading has travelled from the oldest reading in the window towards a
target, as a fraction of travelled-plus-remaining. `nil` when there is no target,
no reading, fewer than two readings, no span, or the target is met — five
distinct reasons, none of which is "0%".
_Avoid_: progress, completion
