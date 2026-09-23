# Almanac: Exercise Sources (Commercially Usable, with Demo Graphics)

**Date:** 2026-09-23
**Requirement:** every exercise shipped in Almanac must include a demonstration graphic.
**Cost filter:** all sources below are free to download and free for commercial use.

Counts for exercises and graphics were measured on disk in the 2026-09-02 exercise data lake unless noted otherwise. GitHub does not publish download counts for repositories, so stars and forks are used as the popularity measure.

| Source | Link | Exercise types | Exercises | Graphic type | Graphics | License | Commercial use | Stars / forks | Maintenance |
|---|---|---|---:|---|---:|---|---|---|---|
| free-exercise-db | https://github.com/yuhonas/free-exercise-db | Gym strength, stretching, plyometrics, powerlifting, olympic lifts, strongman; only 14 cardio exercises, mostly gym machines | 876 | Photos (JPG), ~2 per exercise (start/end) | 1,721 | Unlicense (public domain claimed) | Yes, if the image provenance claim holds (unverified) | 1.9k / 489 | Active |
| wrkout/exercises.json | https://github.com/wrkout/exercises.json | Same as free-exercise-db | 873 | Same photos (byte-identical) | 1,721 | Unlicense | Same as free-exercise-db | Not checked | Upstream of free-exercise-db |
| Everkinetic | https://github.com/everkinetic/data | Gym strength: dumbbell, barbell, machine, bodyweight, Bosu | 293 | Line illustrations (SVG + PNG) | 1,109 SVG · 2,196 PNG | CC BY-SA 4.0 | Yes, with attribution; modified art must be released CC BY-SA | 112 / 48 | Low activity (last update Jan 2026) |
| workout-guide (Bryl Lim) | https://github.com/bryllim/workout-guide | Gym + bodyweight | 302 (web figure) | SVG frames, 3 per exercise (animatable) | 906 (web figure) | MIT code / CC BY-SA 4.0 art | Yes, with attribution; tinting at render time is not a modification | Not checked | Active (npm + Flutter packages) |
| OpenTraining | https://github.com/chaosbastler/opentraining-exercises | Gym strength | 246 | SVG converted from GIF | 780 | CC BY-SA 3.0 | Yes, with attribution + share-alike | Not checked | Unmaintained |
| wger | https://github.com/wger-project/wger | Strength, cardio, stretching, by muscle group | 871 | Photos + some videos | 374 images · 78 videos | Per exercise: 722 CC BY-SA 4 · 128 CC BY-SA 3 · 21 CC0 | Yes, per row (app code is AGPL; only the data is used) | Not checked | Active |
| exercemus/exercises | https://github.com/exercemus/exercises | Aggregate of wger + exercises.json | Not measured | Inherited from sources | Inherited | MIT code; each exercise keeps its own license | Per row | Not checked | Unknown |

## Notes against the graphic-per-exercise rule

- **wger alone does not meet the rule.** It has 374 images for 871 exercises, so more than half of its exercises have no graphic.
- **There are about three independent image sets, not seven.**
  - free-exercise-db and wrkout share one photo set.
  - OpenTraining's images are Everkinetic's.
  - 76 of workout-guide's 906 frames are traced from Everkinetic; the other 830 are new drawings by Bryl Lim.
- **The free-exercise-db photos have unverified provenance.** They are the largest photo set, and their public-domain claim is asserted by the publisher but not traced to a source.

## What shipped (2026-09-24)

**workout-guide**, credited to Bryl Lim (CC BY-SA 4.0). All 302 of its
exercises and the PNG for each are bundled; an Everkinetic entry covers the
76 frames derived from its art, with the derivation described as CC BY-SA
requires. `Sources/AlmanacCore/Training/WorkoutGuideSeed.swift` has the full
reasoning; the short version is that this table's rule could not be met any
other way.

Measured against the 21 exercises of the previous (wger CC0) seed, the rule
is unsatisfiable from the other sources:

| wger exercise | workout-guide | Everkinetic | free-exercise-db |
|---|---|---|---|
| Pause Bench | no match | no match | no match |
| Thruster | no match | no match | Kettlebell Thruster (provenance unverified) |
| Glute-Ham Raise | no match | no match | Glute Ham Raise (provenance unverified) |
| Renegade Row | Machine Row (wrong movement) | no match | Alternating Renegade Row (provenance unverified) |
| Wall Squat | Squat (wrong movement) | no match | no match |

A graphic that shows the wrong movement is worse than no graphic, and
free-exercise-db's public-domain claim is untraced, so borrowing graphics
name-by-name was rejected. Bundling one source whole means every graphic is
correct for the exercise it ships with by construction.

**What was given up:** the 21 curated wger exercises are withdrawn from the
catalogue (migration 035 soft-deletes them, so logged bouts keep resolving).
The 302 that replace them include the movements those rows covered that have
a source graphic — Squat Thrust, Leg Press, Leg Curl, Leg Extension, Reverse
Curl, Chin-up, Cycling — but not Pause Bench, Thruster, Glute-Ham Raise or
Renegade Row. Re-adding those needs a source with a compliant graphic, or
Almanac drawing them itself under its own `almanac:` namespace.
