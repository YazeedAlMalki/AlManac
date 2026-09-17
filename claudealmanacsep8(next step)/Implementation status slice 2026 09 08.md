# Almanac — Implementation status

**Date:** 2026-09-08
**Commits:** `9b7e0f8` (slice checkpoint), `e55080b` (correctness pass),
`6cbd49e` (status), `4b6f12e` (manual-entry APIs and targeted fixes). Local
only; nothing pushed.
**Slice:** first bounded implementation slice — Laboratory persistence, one
HealthProvider sample type, a shared timeline over module-provided queries, and
a recorded document-storage decision.
**Scope note:** this slice proves the core architecture. It does not complete
the Laboratory UI, and it does not complete the Almanac application.

---

## 1. Verification — what was actually run

**Environment:** Swift 6.0.3 (`swift-6.0.3-RELEASE`, ubuntu24.04 toolchain),
x86_64 Linux, in the session's cloud container. **Not** `yamal`'s Swift 6.3.3.

**Result:** `swift build` clean; `swift test` → **79 tests, 0 failures.**

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

## 4a. Correctness pass (commit `e55080b`)

| Fix | What was wrong | Where | Verified by |
|---|---|---|---|
| Coarse-date range queries | A partial date was filtered as though its span start were an exact occurrence, so a month-precision record vanished from any range starting later in that month | `Time/PartialDateTimeSpan.swift`, `LabStore.entries` | `testCoarseMonthObservationSurvivesARangeStartingInsideIt` |
| Specimen | No specimen field at all — a blood result and a urine result were indistinguishable | migration 005, `Laboratory/LabSpecimen.swift` | `testSpecimenIsOptionalAndBloodAndUrineDoNotMerge` |
| Catalog semantics | MMA, EGRAC and PIVKA-II were catalogued as vitamin measurements; beta-carotene as vitamin A | `measurement_role`, seed | `testVitaminEntriesAreClassifiedByWhatTheyMeasure` |
| Overstated count | "24 vitamin forms" — 24 entries, of which 20 are direct measurements | coverage doc, seed | `testTheVitaminCountIsNotOverstated` |
| CBC | A four-analyte "complete blood count" | seed, `almanac:panel.cbc` now 15 members | `testCBCPanelIsComplete` |
| Report metadata | Re-import silently discarded a corrected report date or laboratory name | `upsertReport`, `lab_report_revision` | `testReportMetadataCorrectionIsPreservedNotDiscarded` |

`RangeFit` is the new distinction that makes the first fix honest: `.definite`
means every instant the record could denote lies inside the range; `.potential`
means it overlaps and may belong. A `.potential` entry is shown and labelled,
never dropped, and storage still holds `"2019-03"` — no day or time is invented
to make the query easier.

All existing catalog ids and panel ids were preserved. Migrations 001-004 were
not edited; 005 is appended, on the rule that a committed migration is treated
the same as an applied one.

### Snapshot verification

All **49** build and test inputs — everything under `Sources/` and `Tests/`,
plus `Package.swift` and the vendored SQLite amalgamation — were compared by
`md5sum` between the tested container copy and this working tree, and are
byte-identical (the two manifests hash to one value). `Package.swift` declares no resource bundles, and there are no
non-source files under `Sources/` or `Tests/`.

### Toolchain, precisely

| | |
|---|---|
| Ran on | Swift 6.0.3 (`swift-6.0.3-RELEASE`, ubuntu24.04 build), x86_64 Linux, cloud container |
| Commands | `swift build` then `swift test` |
| Result | build clean, 79 tests, 0 failures |
| **Not** run on | the project's Swift 6.3.3 |

The 6.3.3 attempt and why it failed, so this is not repeated: access to
`~/.local/swift` and `~/.local/swiftdeps` was granted and the toolchain was
reached, but running it produced
`swift: /lib/x86_64-linux-gnu/libc.so.6: version 'GLIBC_2.38' not found`. The
sandbox that can reach this repository is **Ubuntu 22.04 with glibc 2.35**;
the toolchain needs 2.38 or newer. It cannot be relocated to the container
either — 3.3 GB across 2026 files, against a 50-file, 500 MB transfer limit.

**Outstanding, for Yazeed:**

    cd ~/projects/almanac && source env.sh && swift build && swift test

Expected: 79 tests, 0 failures. Any difference is a 6.3.3-specific finding.

---

## 4b. The native manual-entry flow — smallest next step

**There is no usable interface today.** 62 passing tests exercise a library.
No person can create a report, type a result, or look at anything: there is no
app target, no binary, and no screen. Core tests do not establish otherwise.

The flow *create report → add results → save → view history → reopen report*
needs two things, in this order.

### Core work — done (commit `4b6f12e`)

Every persistence call the flow needs now exists and is tested. See §4c.
Nothing further is required from the core before the app target starts.

### Then the app target — what it actually requires

| Requirement | Detail | Needed for this flow? |
|---|---|---|
| A Mac | Xcode is macOS-only; there is no supported way to build or sign an iOS app on Linux. Options: Apple silicon hardware, a rented cloud Mac (MacStadium, Scaleway, AWS EC2 mac), or GitHub Actions macOS runners for CI only — runners cannot do interactive UI work | **Yes. This is the blocker, unchanged since 2026-09-05** |
| Xcode + iOS SDK | The package declares `.iOS(.v17)` / `.macOS(.v14)`, so any current Xcode covers it | Yes |
| An app target | The repo has none — no `.xcodeproj`, no `.xcworkspace`, no `Info.plist`. Add an Xcode App target that depends on this package as a local SwiftPM dependency | Yes |
| Bundle identifier and a signing team | e.g. `com.<yours>.almanac` | Simulator: no. Device: yes |
| Apple Developer Program, $99/yr | A free personal team can sign for a device with 7-day certificates | **No** — the Simulator needs neither, and a personal team is enough for a first device install |
| HealthKit capability, entitlement, and the two `Info.plist` usage strings | `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription` | **No** — deliberately. The manual-entry flow touches no HealthKit code, so the first app target can skip the entitlement entirely and stay simple |
| A database location | The app creates the SQLite file in Application Support and runs `AlmanacMigrations.all` at launch | Yes — **and this is the moment migration numbering freezes** (§4) |

### Scope of the first app target

One SwiftUI target, no HealthKit, no import, no documents, no timeline screen.
Four views over the existing store: a report list, a report editor (laboratory
name optional, date with a precision picker), a result editor (analyte search,
value, unit, comparator, specimen optional), and a report detail that lists
results and opens one result's revision history.

Everything that flow needs from persistence already exists and is tested,
except the two read APIs above.

---

## 4c. Manual-entry APIs and targeted fixes (commit `4b6f12e`)

Migration 006 appended. 001-005 untouched.

| Area | What changed | Verified by |
|---|---|---|
| Editing by Almanac id | `updateReport(id:_:)`, `reviseObservation(id:content:)` — no source or external identifier needed to correct a manual record; a result correction keeps one observation identity | `ManualEntryTests.testReportIsEditableByAlmanacIDWithNoSourceIdentifiers`, `testCreateReopenEditHistoryAndASecondMeasurement` |
| Audited metadata corrections | `updateObservationMetadata` for specimen, collection time, catalog mapping and report association, writing previous values, actor, reason and touched fields to `lab_observation_metadata_revision`. These edits previously did **nothing**, because `record` compares result content | `testMetadataCorrectionIsAuditedAndAppliesWithUnchangedValue`, `testCatalogMappingCorrectionIsAttributedToTheUser` |
| leave-unchanged vs clear | `FieldEdit` — three cases where an optional has two | `testLeaveUnchangedIsNotTheSameAsClear` |
| Stale imports | `SourceOrdering` + replay detection. A → B → reimport A leaves B current, both retrievable | `ImportOrderingTests.testStaleReimportDoesNotBecomeCurrent` |
| Revert vs replay | A ranked version may set the record back to an earlier value; only the ordering marker distinguishes the two | `testExplicitRevertWithNewerOrderingIsAppliedNotTreatedAsReplay` |
| Unranked imports | `UnrankedImportPolicy` — default applies and records `superseded_unranked`; `.holdAsConflict` refuses and logs a conflict | `testUnrankedNewContentIsHeldAsAConflictUnderTheStrictPolicy`, `testUnrankedChangeUnderTheDefaultPolicyIsRecordedAsUnranked` |
| Ambiguous matching | `LIMIT 1` picked a winner by row order once a person added a colliding alias. Candidates are returned; the record stays unmatched | `LaboratoryTests.testAliasCollisionAfterSeedingLeavesTheRecordUnmatched`, `testExternalCodeCollisionIsAmbiguousNotArbitrary` |
| Sample query offsets | Bounds normalised to UTC before SQL; a `+03:00` window was compared lexically against `...Z` and was wrong by the offset | `HealthSyncTests.testSampleQueryNormalisesOffsetsBeforeComparing` |
| Unknown offsets | Span widened by 14 hours so nothing is wrongly excluded, and the fit can never be `.definite` | `TimelineTests.testUnknownOffsetIsNeverDefinite` |
| Specimen helper | `directlyComparable` → `sameSpecimen`, documented as specimen-only. `other` matches nothing, including another `other` | `LaboratoryTests.testSpecimenIsOptionalAndBloodAndUrineDoNotMerge` |
| Reading APIs | `reports(limit:offset:)` with a total ordering, `report(id:)`, `currentResults(inReport:)`, `LabCatalogStore.suggest`, `measurements(analyteID:specimenKind:)` | `testReportsPaginateDeterministically`, `testSuggestSearchesCanonicalNamesAndAliases` |

### Longitudinal history is not revision history

Two ferritin results a year apart are **two measurements with one revision
each**. One ferritin result the laboratory later amended is **one measurement
with two revisions**. `measurements(analyteID:)` answers the first,
`revisions(of:)` the second, and they are deliberately different calls with
different names — a screen that mixes them shows a correction as though the
value had changed in the body.

### The file-backed verification

`ManualEntryTests` writes to a real SQLite file, lets the connection close,
reopens it, and only then reads back: create a report → reopen → edit a result
→ inspect its revision history → add another measurement in a second report →
retrieve both measurements. An in-memory database would pass that sequence even
if nothing were ever written to disk.

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
