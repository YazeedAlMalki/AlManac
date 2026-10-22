# AFCD is share-alike and stays out of the shipped bundle

Status: accepted by the owner, 2026-10-21. The licence reading below is not legal
advice; if counsel says CC BY 4.0 is right after all, reversing this is cheap (see
Consequences).

## Context

The repository recorded Australian Food Composition Database Release 3 as CC BY 4.0,
licence group B, and the app told users "Licensed under CC BY 4.0". FSANZ's Data User
Licence Agreement
(<https://www.foodstandards.gov.au/science-data/monitoringnutrients/afcd/datauserlicenceagreement>)
says FSANZ licenses food composition publications under a licence based on Creative
Commons Attribution-ShareAlike 3.0 Australia. A derivative work may be distributed only
under that licence, and further terms that restrict recipients' rights are not allowed.
The AFCD pages and its data-files page name no other licence for the downloads. The
site-wide copyright page's CC BY 4.0 covers website material, not the data.

Almanac's own rows are proprietary (group N). Shipping AFCD rows in `almanac.sqlite`
next to them would make the bundle a derivative of a share-alike work. The repo already
treats that situation as a build failure for Open Food Facts (group C).

## Decision

1. AFCD moves to licence group **C** (share-alike, never ships). `sources.csv` records its
   licence as the FSANZ Data User Licence Agreement, based on CC BY-SA 3.0 AU.
2. The shipped bundle is built **without AFCD**. `union` withholds any source whose group
   is not shippable and names it in the union manifest (`withheld`); `all` does not
   extract or canonicalise it. `union --all-groups` keeps it for local research, and
   `bundle` refuses that union (the licence assertion is unchanged).
3. Almanac-native dishes may not use AFCD foods as components or benchmarks. The existing
   rule in `sources/almanac.py` already enforces it; none of the 15 dishes did.
4. The Swift side mirrors this: `SourceIdentifier.Namespace.afcd` stays, so old references
   still parse, but its licence group is `shareAlike`. The importer's licence assertion
   therefore rejects an AFCD row in any bundle.
5. The ingredient table behind the Wikibooks recipes no longer names AFCD foods.

## Options not taken

- **Separate tables plus a `UNION` view.** Keeps AFCD in the file, so the bundle is still a
  distribution of AFCD rows. The file would need its own licence story, and the Swift
  importer and every query would change. Rejected.
- **Ship AFCD and relicense Almanac's rows share-alike.** Contradicts group N ("always
  ships, Almanac owns outright").
- **Keep CC BY 4.0.** No primary source supports it for the data.

## Consequences

- The bundle loses 1,588 foods and their per-100 mL liquid values; the other sources
  carry the rest. Foundation, SR Legacy and FNDDS (Task 2) widen coverage again.
- Existing installs drop AFCD foods on the next import (the importer replaces every
  non-dish food wholesale). Logged entries keep their own snapshot values.
- Reversing: set AFCD back to group B in `sources.csv` and `Namespace.afcd.licenceGroup`,
  rebuild. Nothing else depends on the exclusion.
- Attribution entries for AFCD are removed from the app because nothing bundled needs
  them; the Data Sources & Licenses screen may still say AFCD was reviewed and excluded.
