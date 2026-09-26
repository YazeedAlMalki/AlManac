# Almanac Requirement: In-App Attribution Page

**Date:** 2026-09-23
**Status:** Required before any third-party exercise content ships
**Related:** `almanac_exercise-sources-commercial-with-graphics.md`

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

- [ ] Every source bundled in the build has an entry on the Attributions page.
- [ ] Each CC BY-SA entry shows the title, author, source link, and license link.
- [ ] Every modified image is marked as modified, with a description of the change.
- [ ] wger license and author data is preserved per row and shown per exercise.
- [ ] The build fails if a bundled source has no attribution entry.
- [ ] The page works offline.

*This is a product requirement based on a reading of the license terms, not legal advice.*
