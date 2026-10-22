# Almanac Requirement: In-App Attribution Page

**Date:** 2026-09-23
**Status:** Required before any third-party exercise or nutrition content ships
**Related:** `almanac_exercise-sources-commercial-with-graphics.md`, `docs/features/nutrition.md`

## Requirement

Almanac must include an **Attributions** page that credits every third-party dataset and image set shipped in the app. It must also show the license that applies to each one.

## Location

- The page sits under **Settings → App Settings → About → Attributions**. AboutScreen already exists in the Tech Spec screen map.
- It must be reachable offline, because the content is bundled in the app.

## What each entry must show

Each CC BY-SA source needs these four elements:

| Element | Example |
|---|---|
| Title / work | Everkinetic exercise illustrations |
| Author | Everkinetic |
| Source link | https://github.com/everkinetic/data |
| License + link | CC BY-SA 4.0 — https://creativecommons.org/licenses/by-sa/4.0/ |

If Almanac modified the files (recoloured, cropped, redrawn), the entry must also state that they were modified and what was changed. The modified files are then released under the same license.

## Obligations by license

| License | Sources | Attribution on page | Other obligation |
|---|---|---|---|
| CC BY-SA 4.0 | Everkinetic, workout-guide art, most wger rows | Required | Modified files must be released CC BY-SA 4.0 |
| CC BY-SA 3.0 | OpenTraining, some wger rows | Required | Modified files must be released CC BY-SA |
| Unlicense | free-exercise-db, wrkout | Not required | Credit anyway, pending provenance check |
| CC0 | 21 wger rows | Not required | None |
| MIT (code only) | workout-guide, exercemus | Include MIT notice if their code is shipped | None if only data/art is used |

## Per-exercise attribution (wger)

wger licenses each exercise separately and names an author per exercise. To support that:

- The row-level `license` and `license_author` fields must survive every processing stage into the app database.
- Each exercise's detail screen must show a short credit line, for example "Image: [author], CC BY-SA 4.0". Alternatively, the Attributions page must list each wger author individually.

## Acceptance criteria

- [x] Every source bundled in the build has an entry on the Attributions page.
- [x] Each CC BY-SA entry shows the title, author, source link, and license link.
- [x] Every modified image is marked as modified, with a description of the change.
- [x] wger license and author data is preserved per row and shown per exercise.
- [x] The build fails if a bundled source has no attribution entry.
- [x] The page works offline.

## How this was implemented (2026-09-24)

- `Sources/AlmanacCore/Provenance/Attribution.swift` — `Attribution` /
  `LicenseReference` / `AttributionCatalog` (the entries) and
  `AttributionAudit.assertAttributed`, which throws `MissingAttribution` or
  `IncompleteAttribution`. Mirrors `BundleGuard`: a test failure *is* the
  build failure. `AttributionTests` also runs it against the real
  `bundledSourceIds` / `entries` pair, so adding a bundled source without an
  entry breaks the suite.
- `Sources/AlmanacCore/Training/ExerciseAuthorCredits.swift` — the
  per-author list the page shows (the "alternatively" clause in the wger
  section), grouping the local catalog into distinct (author, licence) pairs.
- `exerciseCatalog.licenseAuthor` (migration 034) — the row-level author
  survives insert/read. Migration 035 adds `graphicPath` and **soft-deletes
  the old wger rows**, which have no compliant graphic.
- `Native/Almanac/AttributionsView.swift` — Settings → About → Attributions.
  Content is compiled into the app and read from the local database, so it
  works offline.
- Both `AttributionAudit` and `ExerciseGraphicAudit` also run in
  `LaboratoryModel.open()`, so a violating build cannot reach a device.

The bundled sources changed while implementing this: the wger-only catalog
could not satisfy the graphic-per-exercise rule, so the bundle is now
workout-guide (Bryl Lim, CC BY-SA 4.0) plus an Everkinetic entry for the 76
frames derived from its art. See `docs/exercise-sources.md` and
`WorkoutGuideSeed`'s header.

### Nutrition addendum (2026-09-25)

The production nutrition bundle added three more required build-guard IDs:
`usda`, `ciqual` and `cofid`. (`afcd` was a fourth until 2026-10-21: FSANZ's licence is
share-alike, so AFCD left the bundle and its entry went with it — `docs/adr/0002`.) Their
entries credit the USDA, ANSES and Public Health England, preserve each
publisher's source notice, link CC0, CC BY 4.0, Etalab Open Licence 2.0 or Open
Government Licence v3.0 as applicable, and describe the normalized-schema changes
made to the transformed releases. The existing `AttributionTests` suite now pins
all publisher, notice and licence details in addition to running
`AttributionAudit` over the real bundled-source list.

*This is a product requirement based on a reading of the license terms, not legal advice.*

### Data Sources & Licenses (2026-10-22)

The page is now titled **Data Sources & Licenses** (Settings → About), grouped into Nutrition data,
Packaged products, Recipes, Exercises and Other (`AttributionCatalog.sections`; a test fails if an
entry is missing from or repeated in the groups). It is the same page, the same entries and the same
build guard, not a second screen. Each entry still carries the publisher's own notice; the owner's
separately supplied wording has not been given and is not in the repository.
