# Almanac — Shared Health-Data Foundation

**Version:** 0.2 (revises 0.1 of the same date)
**Status:** proposal. No application code has been changed.
**Scope:** architecture. Laboratory's own requirements are in
`docs/features/laboratory.md` and are not repeated or replaced here.
**Evidence:** the repository at `/home/yamal/projects/almanac`, commit
`e9e6aa1`, 15 source files, 4 test suites.

---

## 0. What changed in v0.2

v0.1 was written against a finding that still stands — Almanac has
infrastructure and no implemented tracking modules — but it overstated five
things and under-specified four. This version fixes both. §13 lists the
corrections explicitly so nothing is quietly revised.

The one change of substance: **v0.1 proposed a persisted `health_event` index.
v0.2 does not.** §7 is the reassessment and the concrete reason.

---

## 1. Repository finding, and the applied-migration evidence

The finding from v0.1 is accepted and unchanged: no tracking module exists in
code. `Sources/AlmanacCore/` contains a SQLite seam, a migration runner, a time
model, provenance enums, a sync-anchor store, a HealthKit protocol with a fake,
and a backup service. There is no nutrition, exercise, sleep, hydration, GI,
body-measurement or laboratory module; no authorization beyond a HealthKit
consent method; no file import; no document storage; no reporting layer; and no
table that stores what a sync returns.

New evidence gathered for this revision, bearing on §11:

| Question | Answer |
|---|---|
| Migrations **declared** | Exactly one: version 1, `core_infrastructure` (`Persistence/Migrations.swift:17-19`). |
| Migrations **applied** in any durable database | **None.** No `*.sqlite`, `*.db` or `*.sqlite3` file exists anywhere in the repository or its build directory. The only `.db` present is `.build/build.db`, which is SwiftPM's own build database. |
| Where tests get their databases | `Database.inMemory()` in most cases; three tests use `NSTemporaryDirectory()` with UUID-suffixed names (`SyncAndBackupTests.swift:68-69`, `MigrationRunnerTests.swift:41`). |
| Any application database path configured in source | None. A grep for application-support or document-directory paths returns only those temporary test paths. |

So `schema_migrations` has never been written to a durable database. Nothing is
frozen. This materially changes §11.

---

## 2. What exists and should be reused

Reuse all of it unchanged. Modularity is preserved by keeping every module's
records in its own tables and letting these serve all of them.

| Component | File | Why it serves the whole application |
|---|---|---|
| `Database` | `Persistence/Database.swift` | A seam, not an ORM (`:43-50`). Plain SQL keeps schema knowledge in migrations, where the runner can enforce it. Foreign keys on (`:68`); `transaction` rolls back on throw (`:168-178`). |
| `MigrationRunner` | `Persistence/MigrationRunner.swift` | Ordered, transactional, idempotent; refuses duplicate versions, out-of-order insertion (`:58-60`) and edited applied migrations (`:53-56`). |
| `TimeModel` / `LogicalDay` | `Time/TimeModel.swift` | The single day-assignment rule. Boundary injected, `.midnight` a placeholder (`:16-33`). `bounds(of:)` adds a calendar day, not 86,400 seconds (`:78-82`). |
| `Clock` | `Time/Clock.swift` | Injectable now, with `FixedClock` for tests. |
| `SourceIdentifier` | `Provenance/SourceIdentifier.swift` | `namespace:localID`, never replaced by an internal key. Adding a namespace forces a licence classification at compile time (`:22-33`). |
| `LicenceGroup` / `BundleGuard` | `Provenance/LicenceGroup.swift` | A failing build assertion for shipped reference data (`:42-49`). |
| `SyncAnchorStore` | `Sync/SyncAnchorStore.swift` | Keyed by `domain` (`Migrations.swift:23-28`), so already generic. Failure preserves the last good anchor (`:59-67`). §9 changes how it is *used*, not what it stores. |
| `BackupService` | `Backup/BackupService.swift` | Online-backup snapshot covers new tables for free (`:35-55`). `restore` throws by design (`:62-67`). |

**Do not** add an ORM or a generic repository layer on top of `Database`. A
shared foundation is exactly the change that invites one, and it would move
schema knowledge out of migrations.

---

## 3. Capabilities duplicated across the designed modules

No module has code, so the duplication is across design documents. Each item
below appears in at least two independent places, which is what distinguishes
it from speculation.

1. **Qualified values.** Nutrients (Processing Design §2) and laboratory
   results (`docs/features/laboratory.md` §5) both need value type, comparator,
   derivation, missing reason and preserved source text.
2. **Prescribed versus achieved.** Prescription Model §1-2, and the
   order-versus-result split in Laboratory.
3. **Source identifier plus a mapping held as data.** Nutrient dictionary
   (Processing Design §6), prescription map (Prescription Model §6), analyte
   catalog (Laboratory §4.5). Three instances of one construct.
4. **Licence classification of shipped reference data.** Already implemented.
5. **Day assignment.** Every module; one rule; already implemented in `TimeModel`.
6. **Time precision and zone.** §8 — newly recognised as shared in v0.2.
7. **Import jobs and sync cursors.** §9 — newly separated in v0.2.
8. **Identity and external references.** §10 — newly recognised as shared.
9. **Units with an explicit basis.** Per-100 g versus per-100 mL (Processing
   Design §4) and lab unit classes (Laboratory §8).

---

## 4. What stays specific to each module

- **Nutrition** — nutrient dictionary, portion and gram-weight conversion,
  per-100 g versus per-100 mL basis, and the refusal to deduplicate foods
  across sources (Processing Design §6).
- **Exercise** — twelve prescription types × ten containers, per-type
  progression axes including two that move in opposite directions on the same
  clock, and readiness coupling (Prescription Model §2-5). A bout's *measured
  field* is determined by its type.
- **Laboratory** — catalog and aliases, panels, reports, source documents,
  reference ranges as printed, revision chains, and the five value dimensions.
- **Sleep and device samples** — interval semantics with overlapping stages,
  device provenance, deletion by external identifier.

None of these generalise. The foundation's job is to serve them, not to
absorb them.

---

## 5. Events, measurements, plans, derived summaries

| | Definition | Mutability | Example |
|---|---|---|---|
| **Event** | Something that happened at a time or over an interval. | Correctable by revision, never silently overwritten. | A specimen collected; a bout performed; a meal eaten. |
| **Measurement** | A qualified value attached to an event or subject. | Append-only; an amendment is a new revision. | A ferritin observation; a nutrient amount; an HR sample. |
| **Plan** | A prescribed intention that may or may not be executed. | Has its own lifecycle. | An ordered panel; a prescribed 5×5; a protein target. |
| **Derived summary** | Computed by a versioned rule from the above. | Droppable and rebuildable. | Daily macro totals; a readiness score; an eGFR Almanac computed. |

Three rules, each with direct evidence:

1. **A plan is never stored in the same row as its outcome** — Prescription
   Model §1. An ordered panel that returned "insufficient specimen" is a plan
   with no measurement and must stay visible as exactly that.
2. **A measurement is never stored without its qualifying dimensions and its
   preserved source text** — Processing Design §2; Laboratory §5.
3. **A derived summary records the rule version and its inputs, and is never
   the only copy of a fact** — Laboratory §6.2 is the concrete instance.

---

## 6. Shared measurement storage versus shared interfaces

v0.1 said a shared measurement model is information-destroying. That was
wrong, and §13 records the correction. A shared model with enough dimensions —
value type, comparator, derivation, missing reason, source text, unit class,
precision — destroys nothing. What destroys information is an *under-specified*
shared model: a bare `value REAL` with an untyped `metadata JSON` beside it.

So the real question is not "shared or specialised" but **what would a shared
model have to carry, and what does it cost to make every module pay for it.**

| | One shared measurement table | Per-module tables |
|---|---|---|
| Dimensions | Must be the union of every module's: lab's five plus comparator plus ranges plus revision chain, nutrition's qualifier plus basis, exercise's type-dependent measured field. | Each module carries only its own. |
| Constraints | Table-level constraints must hold for every module, so most become nullable and unenforced; per-module validity moves into application code. | `CHECK` and `NOT NULL` express each module's real rules. |
| Foreign keys | Cannot point at module-specific parents (specimen, meal, bout) from one table without polymorphism. | Direct and enforced. |
| Aggregation | No shared aggregation is meaningful across modules anyway; every query re-adds module knowledge in its predicates. | Each module aggregates its own. |
| Schema change | A new module's dimension widens the shared table for all modules and rewrites one large table. | Additive, isolated. |
| Cross-module queries | Single table scan. | Requires a union or per-module queries. |
| Migration cost if reversed | Splitting a populated shared table per module is a data migration. | Merging later is also a data migration. |

The deciding factor is not information loss. It is that the union of
dimensions is large, mostly nullable outside its own module, and unenforceable
at the table level — and the only benefit, one-table cross-module querying, is
addressed by §7 without a shared payload table.

**Chosen: per-module tables, with shared behaviour expressed as protocols.**

---

## 7. The timeline — reassessment

v0.1 proposed a persisted `health_event` index. This section reconsiders it
against the alternative of module-provided queries.

**Module-provided queries:** each module implements a protocol returning its
own entries for a time range from its own tables; a thin coordinator merges the
results and orders them. No shared table, no second copy of anything.

**Persisted event index:** each module also writes a row into a shared index
table; the coordinator queries that one table.

| | Module-provided queries | Persisted event index |
|---|---|---|
| Second copy of data | None. | Yes — index rows duplicate identity and time. |
| Consistency risk | None. The module's record is the only copy. | Dual write; index can drift on insert, update, delete or revision. |
| Cross-module day view | N queries, merged in memory. | One indexed query. |
| Paging across long history | Needs an N-way merge cursor. | Natural. |
| Deletions and revisions | Automatic — the record is the truth. | Needs cascade rules and orphan repair. |
| New shared table names | None. | Occupies a generic name the unavailable spec may want (§12). |
| Cost to introduce later | Additive; buildable from module records at any time. | — |
| Cost to remove later | — | Modules already write to it; removal is a migration. |

**Chosen: module-provided queries. The index is deferred.**

*Implemented in exactly this form:* `TimelineProviding` on `LabStore` and
`HealthSampleStore`, merged by `Timeline` with a total order, and **no index
table**. See `docs/implementation-status.md` §2C.

The concrete reason: the index's only genuine advantage is query performance
and paging ergonomics, and **there is no performance problem to solve** —
there are no modules, no data, no UI, and no measurement showing that an
N-way merge is too slow. Every other row favours the queries, and the
asymmetry is decisive: the index can be added later from module records
without changing a single module table, whereas removing it after modules
write to it is a data migration. Choosing the reversible option costs nothing
today.

The trigger for revisiting, stated so the deferral is not indefinite: when a
range view must merge more than four modules, or page across more than a year
of history, **and** profiling shows the merge dominating.

### 7.1 The protocol

```swift
public protocol TimelineProviding {
    static var domain: String { get }
    func entries(from: Date, to: Date, in db: Database) throws -> [TimelineEntry]
}

public struct TimelineEntry: Sendable {
    public let domain: String
    public let kind: String
    public let recordTable: String
    public let recordID: String
    public let occurrence: OccurrenceTime      // §8 — precision and zone
    public let title: String
    public let detail: String?
    public let value: ValuePresentation
    public let lifecycle: String               // module's own vocabulary
}

public enum ValuePresentation: Sendable {
    case none
    case quantity(text: String, unit: String?)
    case bounded(comparator: String, text: String, unit: String?)
    case coded(text: String)
    case narrative(text: String)
    case ratio(text: String)
    case titer(text: String)
    case missing(reason: String)
    case derived(text: String, ruleVersion: String)
}
```

v0.1's `isEstimated: Bool` is removed. Missing, qualitative and bounded values
are three different things and each has its own case; the module formats its
own value and the timeline never reinterprets it.

### 7.2 If the index is later adopted

Requirements, so that the deferral does not become a trap:

- **Fully rebuildable from domain records alone.** A maintenance routine must
  be able to drop the table and repopulate it entirely from module data.
- **Update, delete and revision coverage.** Each module exposes a
  `changes(since:)` contract; the index is not maintained by hand-written
  call sites.
- **Orphan repair.** An index row whose target no longer exists is detected
  and removed by a routine, not by a foreign key — SQLite cannot enforce one
  against a polymorphic target.
- **Staleness detection.** The table records the schema version and the day
  boundary tag it was built under, so a boundary change or a schema change is
  detectable rather than silent.
- **A derived artefact, never a source.** Losing the index must never lose a
  fact.

---

## 8. Time, precision and zone

Shared across every module. Laboratory §12 is the module-specific application.

- Four distinct times, never interchangeable: **scheduled** (a plan's intended
  time), **occurrence** (when the thing happened — collection, meal, bout,
  sleep segment), **recording** (when it entered Almanac), and where a source
  issues records, **reported** (when the source issued it).
- Every stored time carries a **precision**: `instant` · `minute` · `hour` ·
  `day` · `month` · `year` · `unknown`.
- Every stored time carries an offset and, where known, a zone identifier, so
  a record made in another zone is not reinterpreted in the device's current
  one.
- **No timestamp is ever fabricated to fill a field.** A date-only fact stays
  at `day` precision.

Day assignment:

- Uses the occurrence time where present, else the reported time, else the
  recording time, and **records which was used**.
- Goes through `TimeModel` (`Time/TimeModel.swift`); no module formats a date.
- At `day` precision or coarser with a non-midnight boundary, the assignment
  is marked approximate. The boundary is still a placeholder
  (`TimeModel.swift:16-20`), so this case is currently the common one and must
  not be resolved by assuming a time.

Interval overlap:

- Defined only when both intervals have known start and end at `minute`
  precision or finer with known offsets.
- Otherwise the answer is **unknown**, which is a third value and not `false`.
  Sleep stage overlap, fasting windows and workout merging all depend on this.

Ordering:

- Records at `minute` precision or finer order against each other.
- Coarser records group as time-unknown within their day rather than sorting
  against an invented time.

---

## 9. Import jobs and synchronisation cursors

v0.1 conflated these. They are different mechanisms with different failure
modes.

| | Import job | Sync cursor |
|---|---|---|
| Input | A document or file the user supplied. | A change stream the source exposes. |
| Identity | The document. | The stream position. |
| Progress record | Job row: status, counts, per-row outcomes, errors, document link. | Opaque anchor token per domain. |
| Re-running | Idempotent by source identity; produces the same rows. | Resumes from the anchor. |
| Failure | The job fails; the document remains; nothing is lost. | The anchor must not advance past unpersisted data. |
| Existing code | None. | `Sync/SyncAnchorStore.swift`, `sync_anchor` table. |

Two requirements follow.

- **R9.1** File imports get their own job record. They do not use
  `sync_anchor`, and a cursor is not invented for them.
- **R9.2** For incremental sync, **the imported records and the cursor advance
  commit in one transaction.** Today `SyncAnchorStore.save` is an independent
  call (`Sync/SyncAnchorStore.swift:44`), so advancing the anchor without
  persisting the rows it covers is expressible — and if it happened, the next
  sync would start after data that was never stored, skipping it permanently.
  `Database.transaction` (`Database.swift:168-178`) already supports the fix;
  what is needed is an API shape that takes the row-writing work and the
  advance together, so the unsafe ordering cannot be written.

  This is a required interface change to `SyncAnchorStore`. It is **not made in
  this revision** — no application code has been changed. The stored schema
  does not change; only the call shape does.

- **R9.3** `recordFailure` keeps its current behaviour: a failure never clears
  the last good anchor (`:59-67`).

---

## 10. Identity and external references

Shared rules; Laboratory §9 is the module-specific application.

- **R10.1** Every record has an Almanac-owned surrogate identifier. No natural
  key serves as primary identity.
- **R10.2** External identifiers are **scoped to their issuing source**.
  Uniqueness applies to `(source_system, external_id)`, never to `external_id`
  alone. Two sources may legitimately use the same string.
- **R10.3** Repeated observations of the same thing are preserved as distinct
  records. Nothing is deduplicated on the assumption that a repeat is an error.
- **R10.4** Revisions form a chain: a new record referencing the one it
  replaces, with a reason. The replaced record is retained and marked
  superseded. Nothing is overwritten in place.
- **R10.5** When idempotency cannot be established, the import creates a new
  record and marks it as a possible duplicate for review. Silent merging is
  prohibited.

This applies equally to HealthKit samples: `HealthChangeSet.deletedExternalIDs`
(`Health/HealthProvider.swift:48`) deletes by external identifier, and that
deletion must be scoped to the providing source.

---

## 11. Migration numbering

### 11.1 What is actually applied

Nothing. Per §1: one migration is *declared* (version 1, `core_infrastructure`),
and no durable database exists in the repository, in `.build/`, or at any path
configured in source. Tests build in-memory or UUID-named temporary databases.

Consequences:

- **Preserving applied migrations is satisfied trivially** — there are none.
- **Migration 001 is preserved as declared anyway.** Its version and `name`
  stay exactly as they are. It is referenced by `AlmanacMigrations.all`
  (`Migrations.swift:50-56`), by the tests, and by `README.md`; changing it
  buys nothing and would invalidate the runner's drift check the moment a
  database exists.
- **Numbering is not yet frozen, and freezes the moment an app target creates
  its first durable database.** That is the deadline, and it is worth writing
  down because it will arrive without an announcement.

### 11.2 The sequence

| | Number new work 002 upward now | Reserve a block for the spec's schema |
|---|---|---|
| Requires knowing how many migrations the spec needs | No | Yes — which is inference about an unavailable document |
| If the spec's schema must land first | Renumber the not-yet-applied local migrations, free while nothing is applied | No renumber |
| If the reserved block is the wrong size | — | Either wasted numbers or the same renumber anyway |
| Risk after the first durable database exists | Renumber is no longer free; the fix becomes a new higher migration | Same |

**Recommended sequence:** keep `001 core_infrastructure` unchanged; number new
module migrations `002` upward contiguously as they are authored; and treat
renumbering as available until the first durable database is created. Record
the freeze point in `README.md` when the app target lands.

*Taken:* migration 001 `core_infrastructure` unchanged; 002
`laboratory_catalog`, 003 `laboratory_records`, 004 `health_samples`. The
target-database check that preceded this, and how far its evidence reaches,
is recorded in `docs/implementation-status.md` §4.

### 11.3 Correcting v0.1 on recoverability

v0.1 said applying a migration above the spec's reserved number would make
that number "unrecoverable". That is wrong. `MigrationError.outOfOrder`
(`MigrationRunner.swift:58-60`) is a policy in code, and the situation has at
least three exits: renumber the pending migration above the applied head; ship
the same schema change as a new higher-numbered migration; or, before any
release, reset development databases. The real costs are narrower and worth
stating accurately — installs that applied different orders can diverge, and
after field installs a correction must be a new migration rather than an edit.

---

## 12. Does the missing Technical Spec create schema conflicts beyond numbering?

Yes — three, all semantic rather than mechanical. None of them is a numbering
problem, and numbering is the least of them.

1. **Duplicate definition of the same concept.** If the spec's 48 tables
   already define laboratory, sleep or timeline structures, building them now
   creates two homes for one fact. Reconciling that later is a data migration,
   not a rename.
2. **Name occupation.** A 48-table schema plausibly wants generic names —
   `event`, `observation`, `measurement`, `sample`, `source`, `document`. Any
   taken now forces the transcription to rename as it goes, and renaming
   during transcription is exactly where transcription errors enter.
3. **Contradicting invariants.** The spec defines the day-boundary rule, the
   readiness definition and the workout merge model. A module that hard-codes
   an assumption about any of them will disagree with the transcription
   silently rather than loudly.

Mitigations, all cheap and all adopted by this proposal:

- Prefix every new table with its module (`lab_*`). Claim no generic name.
- Introduce no new shared table at all — which §7 already concluded on other
  grounds, and which removes conflict class 2 for the timeline entirely.
- Hard-code no boundary, readiness or merge assumption; take them from
  injected configuration.
- Keep everything additive, so the transcription adds tables rather than
  reconciling them.

One scoping observation worth stating: blood-test tracking entered Almanac's
scope on 2026-09-08, and the spec is dated 2026-08-05. It is therefore
**likely, though unverified, that Laboratory is not among the 48 tables** — in
which case conflict class 1 does not apply to this module. That is a
probability, not a finding, and it is listed as an open question in §15.

---

## 13. Corrections to v0.1

| v0.1 said | Correction |
|---|---|
| Only results with matching measured/calculated status are comparable. | Matching derivation status does **not** establish comparability. Analyte identity, method, assay, unit and reference frame must also agree, and often cannot be determined from the report. Almanac surfaces the differences rather than asserting comparability. Laboratory §15.1. |
| Unit conversion is analyte-specific because it needs molar mass. | Only mass↔substance-amount conversion needs molar mass. Decimal scaling within one dimension is general, and dimensionless values need nothing. Laboratory §8. |
| A generic value column is "the coercion promoted to an architecture"; a shared measurement model destroys information. | A sufficiently dimensioned shared model destroys nothing. The objection is to *under-specified* shared storage. Per-module tables are chosen for constraint enforcement, foreign keys and isolated schema change — §6. |
| Applying a migration above the reserved number makes it permanently unapplicable. | The refusal is a recoverable policy. The real costs are divergence between installs and needing a new migration rather than an edit after release. §11.3. |
| Almanac does not interpret results, ever. | Interpretation is deferred for v1, not permanently prohibited. The data model supports adding it, provided interpretation is stored separately from source facts, versioned and attributable. Laboratory §18.2. |
| A single `lab_qualifier` enum. | Five orthogonal dimensions, plus mandatory preserved source text. Laboratory §5. |
| Uniqueness on (lab, report, analyte). | Surrogate identity, source-scoped external identifiers, preserved repeats and revision chains. §10, Laboratory §9. |
| Lab imports use `sync_anchor`. | Import jobs and sync cursors are separate mechanisms. §9. |
| A persisted `health_event` index. | Module-provided timeline queries; index deferred with a stated trigger. §7. |
| `TimelineSummary.isEstimated: Bool`. | Structured `ValuePresentation`; missing, qualitative and bounded are distinct. §7.1. |

---

## 14. Verification

**Nothing below has been run.** The Swift toolchain lives at
`~/.local/swift/` on `yamal`, outside the folder this session can reach, so no
build or test was executed during this revision. The last recorded successful
run is in the 2026-09-05 status note; this revision changed only Markdown under
`docs/`, and `git diff --stat` over tracked files is empty.

When the module work begins, these are the checks that matter:

1. **Baseline** — `source env.sh && swift build && swift test` before any code
   change, to establish the current count rather than assume it.
2. **Cursor atomicity** — a sync whose row write throws must leave the anchor
   unmoved, so the next run re-reads the same range. This is §9's R9.2 and is
   the single most consequential test in the list.
3. **Revision chains** — an amendment produces a new record, marks the old one
   superseded, and both remain retrievable.
4. **Repeat preservation** — two observations of one analyte on one specimen
   survive an import and a re-import without merging.
5. **Source-scoped identity** — the same `external_id` from two sources
   produces two records.
6. **Time precision** — a date-only record is not assigned a time, does not
   order against timed records, and returns *unknown* for overlap.
7. **Day assignment under a changed boundary** — assignments are recomputed,
   not stale, when the boundary moves from `.midnight`.
8. **Unmatched analytes** — an observation with no catalog match imports,
   stores, and displays in full.
9. **Timeline merge** — two modules with interleaved times produce one ordered
   result, and neither module knows the other exists.
10. **Migration ordering** — the declared set applies in order on a fresh
    database and is idempotent on a second run.

---

## 15. Engineering decisions taken, and product questions still open

### Resolved here, no input needed

- Per-module tables rather than a shared measurement table (§6).
- Module-provided timeline queries; persisted index deferred with a trigger (§7).
- Four distinct times, explicit precision, explicit zone, no fabricated
  timestamps, unknown-not-false interval overlap (§8).
- Import jobs separated from sync cursors; cursor advance and row writes must
  commit together (§9).
- Surrogate identity, source-scoped external identifiers, preserved repeats,
  revision chains, no silent merging (§10).
- Keep migration 001 as declared; number new work 002 upward; renumbering
  stays available until the first durable database exists (§11).
- Module-prefixed table names; no new generic shared table (§12).

### Needs Yazeed

1. **BRD v1.0 text.** Where does it differ from `docs/features/laboratory.md`?
2. **Technical Spec v1.0 text.** Unavailable since 2026-08-05. Does it contain
   laboratory tables, and does it define a timeline or event concept?
3. **Interpretation boundary for v1** — flagging only, trend commentary, or
   explanatory content (Laboratory §18.2).
4. **Document storage** — bytes in SQLite, files beside it, or references only
   (Laboratory §18.3).
5. **Catalog scope and LOINC licensing** (Laboratory §18.4).
6. **Arabic in v1 or v2** (Laboratory §18.5).
7. **The Mac question**, unchanged since 2026-09-05. Nothing past this package
   compiles for iOS without a resolution.
