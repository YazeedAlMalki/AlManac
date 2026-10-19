# Almanac exercise library — free-exercise-db and wger

Builds `Sources/AlmanacCore/Training/Resources/exercise-library.json`, the
photos in `Training/Resources/free-exercise-db/`, and
`docs/features/exercise-merge-log.md`. The app installs the library after
workout-guide's rows (`ExerciseLibrarySeed`, Migration 066).

```sh
cd tools/exercises
python3 -m almanac_exercises fetch   # pinned commits → ~/ALManac-exercise-data (or ALMANAC_EXERCISE_DATA)
python3 -m almanac_exercises build   # → the bundled JSON, photos and merge log
python3 -m unittest discover -s tests -t .
```

Needs Python ≥ 3.11 and Pillow (photos only). Source data never enters the
repository; the commits are pinned in `build.py`.

## The rule (owner, 2026-10-19)

One record per real exercise across workout-guide, free-exercise-db and wger.
Names are normalised (case, plurals, equipment words, `push-up` = `pushup`)
and compared together with muscle group and equipment:

- equal names: **same**, merged;
- names that differ only by neutral words (`NB`, `HD`, `Legend`), or overlap
  by 0.75 or more with no variation word between them: **unsure**, merged;
- a variation word (`incline`, `seated`, `weighted`, a body part…) keeps them
  apart.

Muscle group and equipment are checked per merged group, so a row that
states no equipment cannot chain a dumbbell curl to a machine curl. Every
member's fields are kept with its source; disagreements keep both values and
are listed in the merge log. A group with no graphic (wger-only) is held.
