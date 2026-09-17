# Almanac — Shared Health-Data Foundation

**Status:** proposal. No application code has been changed.
**Date:** 2026-09-08
**Scope:** architecture only. Laboratory's own requirements live in
`docs/features/laboratory.md` and are deliberately not repeated here.
**Evidence base:** the repository at `/home/yamal/projects/almanac` (commit
`e9e6aa1`, 15 source files, 4 test suites, 27 tests) plus Processing Design
v0.1, Prescription & Container Model v0.1, and the Slice 1 status note.

---

## 0. What the inspection actually found

The brief assumed several tracking modules already exist and asked which of
their capabilities are duplicated. **They do not exist yet.** This is not a
quibble — it changes the whole risk profile of the answer, so it is recorded
first.

| Asked about | Found in the repo |
|---|---|
| Tracking modules | **None.** No nutrition, exercise, sleep, hydration, GI or body-measurement module exists in code. |
| Database | `Sources/AlmanacCore/Persistence/Database.swift` — a 183-line SQLite seam. Deliberately not an ORM (`Database.swift:43-50`). |
| Domain schema | **Not built.** `Migrations.swift:53-55` reserves migration 002 for the spec's 48 tables and refuses to author them from inference. Only `sync_anchor` and `backup_manifest` exist (`Migrations.swift:22-45`). |
| Authorization | Only HealthKit read consent, as a protocol method — `HealthProvider.swift:13`. No user accounts, no roles, no per-record access control. Single-user on-device app. |
| Time handling | `Time/TimeModel.swift` — built and tested. The day boundary is **injected, not decided** (`TimeModel.swift:21-33`). |
| Documents / imports | **None.** No file import, no PDF or CSV path, no attachment storage. |
| History | Partly. `HealthSample` is defined (`HealthProvider.swift:25-44`) and returned by `changes(in:since:)`, but **no table stores it** — `Migration001_CoreInfrastructure` persists the sync anchor and nothing the sync returns. |
| Reporting | **None.** No aggregation, no daily rollup, no query layer above `Database.query`. |

So there is nothing to de-duplicate and nothing to refactor. What there *is*
is the moment before the domain schema gets written — which is the only
moment at which this question is cheap to answer. After Migration 002 lands
and user rows accumulate against it, every answer here costs a data migration.

**The duplication is real, but it is in the design documents, not the code.**
That is where the evidence in §2 comes from, and it is why the proposal is
worth writing now rather than after the trackers are built.

---

## 1. What already exists and should be reused

Reuse everything below as-is. None of it needs changing to support Laboratory
or a shared timeline.

### 1.1 The database seam — `Persistence/Database.swift`

`Database` is a non-generic wrapper over the SQLite C API: `SQLValue`
(`:5-11`), `Row` with column-name access (`:14-39`), `execute` / `run` /
`query`, and `transaction` (`:168-178`). Its own comment states the intent —
"a seam, not an ORM: the schema lives in migrations, and everything above this
type works in plain SQL" (`:45-47`).

**Reuse verbatim. Do not introduce an ORM or a repository generic on top of
it.** A shared foundation is exactly the kind of change that tempts one, and
an ORM would relocate schema knowledge out of migrations, which is where the
migration runner's guarantees can see it.

Two properties the foundation depends on:

- Foreign keys are ON (`:68`), so `ON DELETE CASCADE` is available for
  parent/child relationships inside a module.
- `transaction` rolls back on any thrown error (`:174-176`). Section 5's
  spine/record dual write is only safe because of this.

### 1.2 The migration runner — `Persistence/MigrationRunner.swift`

Three guarantees, in its own words (`:5-9`): a throwing migration leaves the
database untouched; an applied migration never runs twice; an *edited* applied
migration is refused rather than silently producing two field schemas.

The enforcement worth knowing before adding tables:

- `MigrationError.outOfOrder` (`MigrationRunner.swift:58-60`) refuses a
  migration numbered *behind* the applied head. This is the single most
  important constraint on this proposal and §6.1 is about it.
- `MigrationError.checksumDrift` (`:53-56`) freezes a migration's `name`
  once applied.

**Reuse. Laboratory's tables arrive as new appended migrations. Nothing in
`Migration001_CoreInfrastructure` is edited.**

### 1.3 The time model — `Time/TimeModel.swift`

`LogicalDay` is a `yyyy-MM-dd` label, explicitly not a calendar date, and
arithmetic on it must go through `TimeModel` (`:5-12`). `DayBoundary`
(`:21-33`) is injected with `.midnight` as a placeholder — the README and the
Slice 1 note both say this is a placeholder, not a decision. `bounds(of:)`
adds a calendar day rather than 86,400 seconds (`:78-82`), so DST days are 23
or 25 hours.

**This is the shared timeline primitive, and it already exists.** Every domain
that timestamps anything must obtain its logical day from a single injected
`TimeModel`. No module formats a date itself. Section 6.4 covers what happens
when the boundary placeholder is replaced.

`Clock` (`Time/Clock.swift:5-7`) and `FixedClock` are the matching injection
point for "now".

### 1.4 Provenance — `Provenance/`

Three types that already generalise beyond food:

- `SourceIdentifier` (`SourceIdentifier.swift:10-49`) — `namespace:localID`,
  never replaced by an internal integer key, so "remove a whole source" stays
  a one-line delete. Laboratory analytes and issuing labs are the same shape.
- `LicenceGroup` + `BundleGuard.assertShippable` (`LicenceGroup.swift:8-49`)
  — a failing build assertion, not documentation. Any reference dictionary
  Almanac ships is subject to it, including a lab analyte dictionary.
- `NutrientQualifier` + `NutrientValue` (`NutrientQualifier.swift:10-66`) —
  the reusable idea is not the enum, it is the **shape**: a nullable amount, a
  closed qualifier, the source's own grade, and `sourceValue` holding the
  original cell verbatim so any parse is reversible (`:32-35`).

One structural detail worth naming: `Namespace.licenceGroup`
(`SourceIdentifier.swift:22-33`) is an exhaustive switch. Adding a lab
namespace is therefore a **compile error until its licence group is
classified**. That is the guard working as intended, and it means LOINC's
terms must be established before the Laboratory code compiles, not after.

### 1.5 The sync anchor — `Sync/SyncAnchorStore.swift`

`sync_anchor` is keyed by `domain TEXT PRIMARY KEY`
(`Migrations.swift:23-28`), not by "HealthKit". It is already a **generic
incremental-import anchor**, and `recordFailure` deliberately preserves the
last good anchor so a failed run never re-imports from the beginning
(`SyncAnchorStore.swift:59-67`).

**Reuse for Laboratory imports unchanged.** A lab-report import run is a
domain string.

### 1.6 The HealthKit seam — `Health/HealthProvider.swift`

`HealthProvider` (`:12-16`) plus `FakeHealthProvider` (`:64-101`) keep
`import HealthKit` confined to one iOS file. `HealthDomain` (`:21-23`) names
eight domains in Almanac's vocabulary, not HealthKit's.

**Reuse as the model for every external ingest**, including lab-report import:
a protocol, a fake, and an anchor.

### 1.7 Backup — `Backup/BackupService.swift`

`snapshot` uses the SQLite online backup API rather than copying the file
(`:6-8`, `:35-55`), so **new tables are covered for free**. `restore` still
throws by design (`:62-67`).

---

## 2. Capabilities duplicated across trackers

None of these are duplicated in code — no tracker has code. They are
duplicated across the *designs*, and each already exists in at least two
independent places, which is what makes them foundation candidates rather
than speculation.

### 2.1 The qualified value

Processing Design v0.1 §2 establishes that a nutrient value is never a bare
number: `Tr` means trace, `N` means nobody measured it, and casting either to
a float writes `0`, telling a user their iron intake was zero when the truth
is unknown. Encoded at `NutrientQualifier.swift:10-29`.

A laboratory result has the identical problem in different vocabulary:
`<0.01`, "not detected", "haemolysed — not reportable", "specimen quantity
insufficient". Same three facts, same float collapse, same irreversibility.

**Duplicated.** Belongs in the foundation as a shape, not as one enum — §3.3.

### 2.2 The prescribed / achieved split

Prescription & Container Model v0.1 §1 is an entire document about one
failure: a schema that cannot say whether reps were the *prescription* or the
*outcome* reports a good AMRAP and a bad AMRAP identically. Types 6 and 7 have
those fields swapped relative to each other (§2).

The same split appears in every domain: an ordered lab panel versus a resulted
value; a nutrition target versus an intake; a hydration goal versus a drink
logged; a planned sleep window versus a measured one.

**Duplicated.** This is the plan/observation distinction in §4.

### 2.3 Source-owned identifier plus an Almanac-owned mapping held as data

Two independent instances of one construct:

- Nutrition — canonical `nutrient_id` with `(source, source_nutrient_id) →
  nutrient_id` "held as data, not code" (Processing Design §6).
- Exercise — `(source, exercise_id) → prescription_type`, "held as data
  exactly like the nutrient dictionary", defaulted by rule and overridable per
  row (Prescription Model §6), already run to
  `processed/mapping/prescription_map.csv` (§6.1).

Laboratory needs a third: `(lab, lab_analyte_code) → analyte_id`.

**Duplicated three times over.** The pattern — never discard the source's own
code, unit or name; keep the mapping as data so a fix is an update rather than
a re-extraction — is a foundation rule.

### 2.4 Licence classification of reference data

Processing Design §1 makes shipping a row an act of redistribution and §5
makes the bundle step assert rather than filter. Prescription Model §6 notes
exercise sources carry per-entry licences; `SourceIdentifier.swift:29-31`
already records that exercise rows must carry their own group column rather
than inherit one from the source.

Lab analyte dictionaries are reference data with licence terms too.

**Duplicated.** Already implemented (`BundleGuard`) and simply needs to be
applied to a third dictionary.

### 2.5 Logical-day assignment

Every domain assigns entries to a day, and a body monitor's day almost
certainly does not begin at midnight (`TimeModel.swift:16-20`). If each module
formats its own date, the boundary rule exists in N places and the sleep
module and the food module will disagree about which day 01:30 belongs to.

**Duplicated by construction.** Already solved once in `TimeModel` — the
foundation's job is to make it the *only* implementation.

### 2.6 Incremental import with a failure-preserving anchor

HealthKit sync needs it today. Lab report import, a scale, a CGM and a
hydration bottle all need the same thing. Already generic
(`SyncAnchorStore.swift:44-67`).

### 2.7 Units carrying an explicit basis

Processing Design §4 Trap 1: AFCD ships per-100 g and per-100 mL as separate
sheets because they are not interchangeable, and merging them into one
`per_100` column silently corrupts every liquid — "the basis is a column, not
an assumption."

Laboratory has the same trap with sharper teeth: mg/dL versus mmol/L for
glucose differ by a factor of ~18, and the conversion is analyte-specific
(it needs molar mass). A stored number without its unit *and* the unit the lab
reported it in is not recoverable.

**Duplicated.** Foundation rule: a stored quantity always carries the source
unit verbatim alongside any canonical value.

---

## 3. What must stay specific to each module

The instruction not to force health data into a generic value/metadata table
is correct, and this section is the evidence for why. Each item below has a
validity rule, a unit system or an aggregation rule that no other domain
shares.

### 3.1 Nutrition

Nutrient dictionary (477 USDA nutrients alone), portion conversion via
`food_portion` → `gram_weight`, per-100 g versus per-100 mL basis, specific
gravity and edible proportion, and the explicit refusal to deduplicate foods
across sources (Processing Design §6: "merging is irreversible"). Four rows
for "raw carrot" is correct behaviour, not a defect.

None of this generalises. A lab has no portion size; a workout has no edible
proportion.

### 3.2 Exercise

Twelve prescription types crossed with ten containers, orthogonal by design
(Prescription Model §2-3). Progression axes that differ per type, including
two that progress in **opposite directions on the same clock** (§4). Readiness
coupling where `release` is the only type that increases on a low-readiness
day (§5).

A bout is not a measurement. It is a plan and an outcome whose *measured
field* is determined by the type — elapsed time for `rounds_for_time`, rounds
completed for `work_in_time`. A generic `value` column cannot express which
field it is holding, which is precisely the failure §1 of that document
describes.

### 3.3 Laboratory

Reference range, specimen, method, analysing lab, panel grouping,
abnormal/critical flagging, and censoring operators (`<`, `>`).

The load-bearing one: **a reference range is not a property of the analyte.**
It is a property of (analyte × method × lab × sex × age band × physiological
state). Two labs testing the same blood report different ranges and both are
right. Storing one range per analyte is the lab equivalent of writing `0` for
`N`. Details in `docs/features/laboratory.md`.

### 3.4 Sleep and device-sourced samples

Interval semantics with overlapping stages, device provenance
(`HealthSample.sourceName`, `HealthProvider.swift:32`), deletion by external
ID (`HealthChangeSet.deletedExternalIDs`, `:48`), and the fact that the same
night can be reported differently by two devices.

---

## 4. Events, measurements, plans, and derived summaries

Four categories that a single table would merge. Keeping them apart is most of
the foundation.

| | Definition | Identity | Mutability | Lives on the timeline? |
|---|---|---|---|---|
| **Event** | Something that happened at an instant or over an interval, attested by user or device. | External ID where one exists, else generated. | Correctable; never silently overwritten. | **Yes** — this is what the timeline is made of. |
| **Measurement** | A qualified quantity attached to an event or a subject. | (event or subject) × analyte/nutrient/metric. | Append-only; an amended result is a new row, not an edit. | No — reached by joining from its event. |
| **Plan** | A prescribed intention that may or may not be executed. | Its own id, with a fulfilment link. | Has a lifecycle: prescribed → executed / skipped / superseded. | Yes, as a *scheduled* entry distinct from an occurred one. |
| **Derived summary** | Computed from the above by a versioned rule. | (subject, period, rule version). | Droppable and rebuildable. | Rendered alongside, never mixed in. |

Worked examples:

| Real thing | Event | Measurement | Plan | Derived summary |
|---|---|---|---|---|
| Blood draw at 08:10, ferritin 42 ng/mL | specimen collected | ferritin result, with range and flag | the ordered panel | 12-month ferritin trend |
| Ate 180 g rice | meal entry | nutrient amounts for that portion | today's protein target | daily macro totals |
| 5×5 back squat at 80 kg | bout performed | load, reps, RPE achieved | the prescribed 5×5 | weekly tonnage, readiness |
| Slept 23:40–06:55 | sleep segment | duration, stages, HRV | intended bedtime | readiness score |

Three rules follow, and each has direct evidence behind it:

1. **A plan is never stored in the same row as its outcome.** Prescription
   Model §1 is the whole argument. An ordered panel that came back
   "insufficient specimen" is a plan with no measurement, and it must remain
   visible as exactly that.
2. **A measurement is never stored without its qualifier and its source
   value.** Processing Design §2; `NutrientQualifier.swift:32-35`.
3. **A derived summary is never the only copy of a fact.** It records the
   rule version that produced it and can be dropped and rebuilt. A readiness
   score computed under one formula must not be indistinguishable from one
   computed under the next.

---

## 5. Shared measurement storage, or shared interfaces over specialised records?

**Recommendation: shared interfaces over specialised records, plus one narrow
shared table that is an index, not a store.**

### 5.1 Why not a shared measurement table

A single `measurement(subject, metric, value, unit, metadata JSON)` would have
to hold, at minimum:

- a nutrient amount that may be NULL-with-meaning and carries a qualifier, a
  source grade and an unparsed source cell;
- a lab result that carries a censoring operator, a reference range, a
  specimen, a method and an issuing lab;
- an exercise outcome whose *semantic field* changes by prescription type —
  elapsed time in one type, rounds completed in another.

These share a column type and nothing else. They share no validity rule, no
unit system, and no aggregation rule — you cannot average across them, and any
query that tries has to re-implement per-domain knowledge in the WHERE clause.
The `metadata JSON` column is where that knowledge would go, and a JSON blob
is a schema with no migration runner, no foreign keys and no constraints —
which forfeits every guarantee `MigrationRunner` provides.

The decisive evidence is that this project has already written two documents
about exactly this failure. Prescription Model §1: three facts "collapsed into
one integer, and the collapse is irreversible once user history accumulates
against it." Processing Design §2: "the single most consequential bug
available in this entire project, and it is introduced by a one-line type
coercion." A generic measurement table is that coercion promoted to an
architecture.

### 5.2 What is genuinely shared

Not the payload. The **addressing**: what happened, to whom, when, on which
logical day, from which source. Every domain needs that and every domain
computes it identically.

### 5.3 The proposal — a spine, not a store

One table, `health_event`, with **no value column and no metadata blob**:

```sql
CREATE TABLE health_event (
    id            TEXT PRIMARY KEY,        -- uuid
    domain        TEXT NOT NULL,           -- 'laboratory' | 'sleep' | ...
    kind          TEXT NOT NULL,           -- domain-owned vocabulary
    occurred_at   TEXT NOT NULL,           -- ISO8601 instant. The truth.
    occurred_end  TEXT,                    -- NULL for point events
    logical_day   TEXT NOT NULL,           -- rebuildable index, see 6.4
    boundary_tag  TEXT NOT NULL,           -- which rule produced logical_day
    source_ref    TEXT,                    -- SourceIdentifier, e.g. 'almanac:...'
    external_id   TEXT,                    -- device/lab id, for dedup
    record_table  TEXT NOT NULL,           -- the specialised table
    record_id     TEXT NOT NULL,           -- its primary key
    status        TEXT NOT NULL,           -- 'occurred' | 'planned' | 'skipped'
    recorded_at   TEXT NOT NULL
);
CREATE INDEX idx_health_event_day    ON health_event (logical_day, occurred_at);
CREATE INDEX idx_health_event_domain ON health_event (domain, occurred_at);
CREATE UNIQUE INDEX idx_health_event_record ON health_event (record_table, record_id);
CREATE UNIQUE INDEX idx_health_event_external
    ON health_event (domain, external_id) WHERE external_id IS NOT NULL;
```

It answers one question: *what happened on this logical day, across all
domains, in order.* To render or aggregate anything, you join out to
`record_table` / `record_id`, and the specialised table — the only thing that
knows what its numbers mean — supplies the value.

Each module owns its tables completely and implements one small protocol so
the timeline can render an entry without knowing the domain:

```swift
public protocol TimelineSummarising {
    static var domain: String { get }
    func summary(for recordID: String, in db: Database) throws -> TimelineSummary
}

public struct TimelineSummary: Sendable {
    public let title: String
    public let detail: String?
    public let isEstimated: Bool     // any qualifier other than directly observed
}
```

`isEstimated` is the one place the qualifier idea surfaces on the shared
layer, and it is a Bool, not a value — derived per domain by its own rule
(`NutrientQualifier.isDirectlyObserved`, `NutrientQualifier.swift:26-28`, is
the nutrition implementation).

### 5.4 What this buys, and what it costs

| | |
|---|---|
| Buys | One timeline query across all domains. One logical-day rule. One dedup story. A reporting layer that adds a domain without changing. Specialised models untouched. |
| Costs | A dual write — spine row plus domain row — which must be in one transaction. The spine cannot have a foreign key to a polymorphic target, so referential integrity is a checked invariant rather than an enforced one (§6.3). |

The cost is real and is not hidden. It is smaller than the cost of a generic
value column, because a missing spine row is detectable by a query and
repairable, whereas a nutrient amount written as `0` instead of `not_analysed`
is not recoverable at all.

---

### 5.5 The minimal implementation slice

The brief asks for a minimal implementation connecting Laboratory and one
existing tracker to the shared layer. **The only tracker with code is the
HealthKit sync path** — `HealthProvider` returns `HealthSample`
(`HealthProvider.swift:25-44`) and nothing stores it. That gap makes it the
right second domain: connecting it costs one table it needs anyway.

Migrations, numbered per §6.1 option A:

| Migration | Tables |
|---|---|
| `002_HealthTimeline` | `health_event` and its four indexes (§5.3). |
| `003_HealthSampleStore` | `health_sample` — persists what `changes(in:since:)` returns, keyed on `(domain, external_id)`. Closes the gap where synced samples are dropped. |
| `004_Laboratory` | `lab_analyte`, `lab_analyte_map`, `lab_order`, `lab_specimen`, `lab_result`, `lab_reference_range`. Fields per `docs/features/laboratory.md`. |

Swift, all in `AlmanacCore` so it compiles and tests on Linux today:

| File | Contents |
|---|---|
| `Timeline/HealthEvent.swift` | `HealthEvent`, `EventStatus`, `TimelineSummary`, `TimelineSummarising`. |
| `Timeline/HealthEventStore.swift` | `append(event:record:)` writing both rows in one `Database.transaction`; `events(on: LogicalDay)`; `rebuildLogicalDays(using: TimeModel)`. |
| `Timeline/DailyReport.swift` | `entries(for: LogicalDay)` → `[TimelineEntry]` ordered by `occurred_at`, resolving each through the registered `TimelineSummarising` for its domain. |
| `Laboratory/LabResult.swift` | `LabQualifier`, `LabResult`, `ReferenceRange` — the value model, mirroring `NutrientValue`'s shape. |
| `Laboratory/LabStore.swift` | Writes a specimen as an event plus results as measurements. Implements `TimelineSummarising`. |
| `Health/HealthSampleStore.swift` | Persists a `HealthChangeSet`, applies `deletedExternalIDs`, writes spine rows. Implements `TimelineSummarising`. |

What the slice proves, and it is the whole point of doing it before the
trackers exist: a day view can list a blood draw at 08:10 and a sleep segment
ending 06:55 in one ordered result, with neither module knowing the other
exists, and with the lab result still carrying its qualifier, its range and
the lab's own unit.

No application code is written until §6.1 is decided.

---

## 6. Migration risks

### 6.1 Migration numbering — the highest-severity risk

`Migrations.swift:53-55` reserves 002 for the 48-table domain schema, which is
still blocked on the unavailable Technical Spec. `MigrationRunner.swift:58-60`
refuses any migration numbered behind the applied head.

So if a foundation migration is numbered, say, 010 and applied to any database
before the spec arrives, **migration 002 can never be applied to that
database**. On a developer machine that means deleting the file. In the field
it would be unrecoverable.

Two options; nothing has shipped, so both are still free.

| | Take 002-004 for the foundation, spec schema starts at 005 | Leave 002+ reserved, foundation waits |
|---|---|---|
| Effect on the spec transcription | Renumber the spec's `Migration_001` to 005. `README.md:53-56` already anticipates a renumber. | No renumber. |
| Effect on this work | Proceeds now. | Blocked on the spec, which has been unavailable since 2026-08-05. |
| Risk | The spec's own build order may assume its numbering; the renumber must be recorded. | The foundation question stays unanswered while the schema that depends on it is written. |
| Cost if reversed later | Free until first install. | Free. |

### 6.2 Frozen names

`MigrationError.checksumDrift` (`MigrationRunner.swift:53-56`) freezes a
migration's `name` once applied. Names must be final at authoring time.

### 6.3 Spine/record drift

A domain row written without its spine row is invisible on the timeline; a
spine row whose target was deleted is a dangling entry. SQLite cannot enforce
a foreign key to a polymorphic target, so this is a checked invariant.

Mitigations: both writes inside one `Database.transaction`
(`Database.swift:168-178`), a single `HealthEventStore.append` that writes
both, and an integrity query in the test suite (§7).

### 6.4 The logical-day placeholder

`DayBoundary.midnight` is explicitly a placeholder, not a decision
(`TimeModel.swift:16-20`). If `logical_day` is stored denormalised and the
boundary later becomes `.wakeOffset(hours: 4)`, **every stored `logical_day`
is silently wrong** and a body monitor starts attributing late-night entries
to the wrong day.

Mitigation, and the reason `boundary_tag` is in the schema above:
`occurred_at` is the truth, `logical_day` is a derived index, and
`boundary_tag` records which rule produced it. A boundary change becomes a
detectable rebuild (`UPDATE ... WHERE boundary_tag != current`) instead of an
invisible corruption.

### 6.5 Licence classification is forced at compile time

Adding a lab namespace to `SourceIdentifier.Namespace` breaks the exhaustive
`licenceGroup` switch (`SourceIdentifier.swift:22-33`). This is the guard
working, but it means LOINC's licence terms must be established before the
Laboratory module compiles. Treat it as a scheduling input, not a surprise.

### 6.6 Backup and restore

Snapshot covers new tables at no cost (`BackupService.swift:35-55`). Restore
still throws (`:62-67`), so the foundation adds tables to a database that has
no restore path — unchanged from today, but worth stating rather than
discovering.

---

## 7. Verification steps

Baseline before any change: `source env.sh && swift build && swift test` —
27 tests, 0 failures.

Tests the foundation must add before it can be trusted:

1. **Dual-write atomicity.** A failing domain insert leaves no spine row.
   Mirrors the existing pattern in `MigrationRunnerTests` where a migration
   creates a table and then throws.
2. **Orphan detection.** A query returning spine rows with no target and
   domain rows with no spine row, asserted empty. This is the substitute for
   the foreign key SQLite cannot give.
3. **Logical-day rebuild.** Write events under `.midnight`, switch to
   `.wakeOffset(hours: 4)`, rebuild, and assert an entry at 01:30 moves to the
   previous logical day and that `boundary_tag` marks every row as rebuilt.
4. **Migration ordering.** Assert the foundation migrations apply in order on
   a fresh database and are idempotent on a second run.
5. **Timeline ordering across domains.** Two domains, interleaved timestamps,
   one ordered result.
6. **Anchor survival.** Extend the existing `SyncAndBackupTests` coverage to a
   lab-import domain: a failed import must not clear the last good anchor.

Manual check after Laboratory lands: a resulted panel, an ordered-but-unresulted
panel, and a rejected specimen must each be distinguishable on the day view.

---

## 8. Deferred work

| Deferred | Why |
|---|---|
| The 48-table domain schema | Technical Spec v1.0 text still unavailable. Unchanged since 2026-09-05. |
| The real day-boundary rule | Same. §6.4 makes waiting safe rather than blocking. |
| Readiness engine, and lab values feeding it | Needs the spec's readiness definition. |
| Restore semantics | `BackupService.swift:62-67`. |
| Nutrition and exercise modules | No code yet; the foundation is designed to accept them, not to anticipate them. |
| Reference-range personalisation | `docs/features/laboratory.md`. |
| Document/attachment storage for lab reports | No storage strategy exists anywhere in the repo. |
| The Mac question | Nothing past this package compiles for iOS without a resolution. |

---

## 9. Summary of the recommendation

1. Reuse `Database`, `MigrationRunner`, `TimeModel`, `Clock`,
   `SourceIdentifier`, `LicenceGroup`, `SyncAnchorStore`, `BackupService`
   unchanged.
2. Add one narrow spine table, `health_event`, that indexes events and stores
   no values.
3. Keep every domain's records in its own tables with its own vocabulary.
4. Share behaviour through small protocols — `TimelineSummarising` — not
   through a common row shape.
5. Keep events, measurements, plans and derived summaries in separate tables.
6. Settle migration numbering (§6.1) before applying anything.
