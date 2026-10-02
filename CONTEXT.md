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

### Weighing

**Meter fraction**:
How far a reading has travelled from the oldest reading in the window towards a
target, as a fraction of travelled-plus-remaining. `nil` when there is no target,
no reading, fewer than two readings, no span, or the target is met — five
distinct reasons, none of which is "0%".
_Avoid_: progress, completion
