# Almanac — Implementation status

**Date:** 2026-09-08
**Slice:** first bounded implementation slice — Laboratory persistence, one
HealthProvider sample type, a shared timeline over module-provided queries, and
a recorded document-storage decision.
**Scope note:** this slice proves the core architecture. It does not complete
the Laboratory UI, and it does not complete the Almanac application.

---

## 1. Verification — what was actually run

**Environment:** Swift 6.0.3 (`swift-6.0.3-RELEASE`, ubuntu24.04 toolchain),
x86_64 Linux, in the session's cloud container. **Not** `yamal`'s Swift 6.3.3.

**Result:** `swift build` clean; `swift test` → **56 tests, 0 failures.**

Commands as run:

    swift build
    swift test

**Access blocker, stated precisely.** The shell this session has on `yamal`
reaches only the connected folder `~/projects/almanac`. The toolchain lives at
`~/.local/swift/swift-6.3.3-RELEASE-ubuntu24.04` with its library shims in
`~/.local/swiftdeps`, both outside that folder, so `env.sh` cannot be sourced
and `swift` is not on the path there. The package was therefore copied into the
container and built against 6.0.3.

The repository files and the tested files are byte-identical — verified by
`md5sum` on both sides for every file changed in this pass. What differs is only
the toolchain version.

**To reproduce on `yamal`:**

    cd ~/projects/almanac
    source env.sh
    swift build
    swift test

If 6.3.3 reports anything 6.0.3 did not, that difference is unverified here and
is the first thing to check.

### The nine required demonstrations

| Required | Test |
|---|---|
| Save and retrieve a report with several results | `LaboratoryTests.testReportWithSeveralResultsRoundTrips` |
| Alias lookup | `LaboratoryTests.testAliasLookup` |
| A qualitative result | `LaboratoryTests.testQualitativeResult` |
| A bounded result | `LaboratoryTests.testBoundedResultDoesNotInventAQuantificationLimit` |
| An unmatched result | `LaboratoryTests.testUnmatchedResultIsPreserved` |
| Incomplete historical entry | `LaboratoryTests.testIncompleteHistoricalEntry`, `testEntryWithoutAnySourceTextIsAllowed` |
| Two legitimate repeats of the same test | `LaboratoryTests.testTwoLegitimateRepeatsArePreserved` |
| An amendment retaining the same external observation ID | `LaboratoryTests.testAmendmentKeepsExternalIDAndReimportIsIdempotent` |
| Reimport without duplicates | same test — re-importing both the current and the superseded revision is a no-op |
| Failed synchronisation leaves the cursor unchanged | `HealthSyncTests.testFailedSyncLeavesTheCursorUnchanged`, `testResyncAfterFailureReplaysTheSameRange` |
| Both domains in the combined timeline | `TimelineTests.testBothDomainsAppearInTheCombinedTimeline` |

---

## 2. Completed and verified

### A. Laboratory persistence — migrations 002 and 003

| Requirement | Where | Verified by |
|---|---|---|
| Catalog definitions, stable Almanac ids | `lab_catalog_analyte` | `CatalogCoverageTests` |
| Optional external codes, unverified codes never match | `lab_catalog_external_code.verified` | `testUnverifiedExternalCodeDoesNotMatch`, `testNoExternalCodeIsSeeded` |
| Aliases, folded across script and punctuation | `lab_catalog_alias.alias_fold`, `TextFold` | `testAliasLookup`, `testFoldingNormalisesScriptAndPunctuation`, `testNoAliasIsSharedByTwoAnalytes` |
| Reusable panel definitions, built-in and user | `lab_panel`, `lab_panel_member` | `testPanelsAreReusable` |
| Reports as explicit records | `lab_report` | `testReportWithSeveralResultsRoundTrips` |
| **Stable observation identity separate from revision identity** | `lab_observation` / `lab_observation_revision` | `testAmendmentKeepsExternalIDAndReimportIsIdempotent` |
| Idempotent re-import of an existing revision | `content_fingerprint`, unique per observation | same test |
| Original values, units, ranges, flags preserved | `source_*`, `range_text`, `flag_text`, `unit_text` | `testBoundedResultDoesNotInventAQuantificationLimit` |
| Incomplete and unmatched observations | nullable `catalog_analyte_id`, `report_id`, `collected_at` | `testUnmatchedResultIsPreserved`, `testIncompleteHistoricalEntry` |
| Five separate value dimensions | `LabValue.swift` | throughout |
| Absence always carries a reason | two `CHECK` constraints | `testAbsentValueRequiresAReason` |

### B. One second domain — migration 004

Body weight (`HealthDomain.bodyMass`), the type the existing `HealthProvider`
interface already supports. Source-scoped import identity
(`UNIQUE (source_system, external_id)`), soft deletion scoped to the issuing
source, and **the imported rows and the cursor advance commit in one
transaction** — `HealthSyncService.syncOnce`.

Only `bodyMass` is wired. No other HealthKit domain was built.

### C. Shared timeline

`TimelineProviding` implemented by `LabStore` and `HealthSampleStore`.
`Timeline` merges with a total order over fields every entry carries, so the
result does not depend on provider order — asserted by re-running with the
providers reversed. **No persisted event index**, as decided in
`docs/architecture/health-data-foundation.md` §7.

`TimeBasis` distinguishes an occurrence from a report time from an entry-date
fallback. Current revisions are returned by default; history stays reachable
through `LabStore.revisions(of:)`.

### D. Documents — decision recorded, implementation deferred

Private app-managed copies plus SQLite metadata and **relative** paths; the
root is injected (`DocumentStoring`), so a test temp directory and an app
container use the same code. `lab_document` and `lab_document_link` exist, and
links are many-to-many with a role.

**`BackupService.snapshot` does not cover these files.** It backs up the SQLite
database only, so after a restore the metadata rows can reference files that are
not present. This is stated in `Documents/DocumentStore.swift` and is not
worked around.

---

## 3. Defects found and fixed in this pass

| Defect | Fix |
|---|---|
| `Timeline.undatedEntries` could only ever return an empty array — every module resolves a placement, so no entry reaches the timeline with an unknown time. A public accessor implying a bucket that does not exist. | Removed, with a comment saying why `TimelineEntry.basis` is the real distinction. |
| The `fingerprint` comment named `actor` and `reasonText` as the excluded provenance fields but `contentOrigin` is also excluded. | Comment corrected; behaviour unchanged and intentional. |
| "Current revision by default" rested on a `WHERE rev.is_current = 1` clause that no test exercised after an amendment. | Added `TimelineTests.testTimelineShowsCurrentRevisionAndHistoryRemainsReachable`. |

---

## 4. Migration numbering — what was checked, and how far the check reaches

Migration 001 (`core_infrastructure`) is **unchanged**: same version, same name,
same SQL. New migrations are numbered 002, 003, 004, sequentially after it.

**What was actually inspected:** the connected folder `~/projects/almanac`. It
contains no `*.sqlite`, `*.sqlite3` or `*.db` other than `.build/build.db`,
which is SwiftPM's build database. No source file configures an application
database path — a search finds only `NSTemporaryDirectory()` paths with UUID
names in tests. There is no Xcode project, workspace or `Info.plist`, so no app
target exists that could have created one.

**How far that reaches:** this session can see only that folder on `yamal`. It
is not a claim that no Almanac database exists anywhere. Before applying these
migrations to any database that does exist, read its `schema_migrations` table
first: `MigrationRunner` refuses a version behind the applied head
(`MigrationRunner.swift:58-60`), and at that point the correct fix is to
renumber 002-004, not to edit 001.

Numbering freezes the moment an app target creates its first durable database.

---

## 5. Deferred — explicitly incomplete

| Deferred | Why |
|---|---|
| Full document import — reading a PDF or photo into the store and linking it | This slice records the decision and the interface only |
| Backup/restore integration for document files | `snapshot` covers SQLite only; restore still throws by design |
| Automatic unit conversion | `UnitRegistry` returns a verdict, never a converted number |
| Catalog reference-range fallback | Ranges are preserved as reported; no catalog fallback is applied |
| Verified external codes (LOINC) | None seeded; licensing unresolved |
| Reference-range personalisation, interpretation, flag computation | Product decisions still open |
| Every other HealthKit domain | Only `bodyMass` is wired |
| Laboratory UI | Out of scope for this slice |
| The 48-table Technical Spec schema | Spec text still unavailable |
| The real day-boundary rule | Still `.midnight`, still a placeholder |
| Pushing timeline range filtering into SQL | Currently filtered in Swift so the placement choice is visible per row |

---

## 6. Known limitations worth stating

- `LabStore.entries` reads all current revisions and filters in Swift. Correct,
  and not yet efficient. It becomes a problem at a data volume that does not
  exist yet.
- `saveReport` is find-or-create on `(source_system, source_report_id)`; a
  re-import carrying changed report-level fields returns the existing row
  without updating it. Observations revise; reports do not, yet.
- `health_sample`'s uniqueness is `(source_system, external_id)` without
  `domain`. Correct where a source's identifiers are unique across its own
  domains, which holds for HealthKit UUIDs. A source that reuses an identifier
  across domains would need the index widened.
- Coarse-precision entries sort at the start of their span, so a `2019`-precision
  record sorts before `2019-01-01T00:00`. Deliberate and pinned by
  `testCoarsePrecisionSortsAtTheStartOfItsSpan`, but it means a month-precision
  record can fall outside a range query whose bound lands inside that month.
- Verified against Swift 6.0.3, not the 6.3.3 the project uses.
