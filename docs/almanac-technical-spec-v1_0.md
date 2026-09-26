# Almanac — Technical Specification v1.0 (Reconciled)

**Status:** authoritative build reference, superseding the 2026‑08‑05 Technical
Spec v1.0.
**Date:** 2026‑09‑15
**Owner:** Yazeed
**Derived from:** BRD v1.0 (2026‑09‑08, four added domains) + the original BRD
v1.5 scope (sleep/food/energy/activity) + every architecture and domain
document produced since 2026‑09‑01 + the actual state of
`~/projects/almanac` on `yamal` as inspected 2026‑09‑15.

---

## 0. Why this document exists, and what it is not

The original Technical Spec v1.0 (2026‑08‑05) was written against BRD v1.5,
used GRDB.swift, and specified a single 48‑table schema up front. Its full
text was lost from reachable storage twice (2026‑08‑05 session output,
2026‑08‑08 re‑upload) and was never rebuilt against:

- the four domains BRD v1.0 added on 2026‑09‑08 (body measurement, hydration,
  GI, blood test),
- the architecture actually chosen since then (`docs/architecture/health-data-foundation.md`
  v0.2) — per‑module tables, no GRDB, no persisted event index, import jobs
  separated from sync cursors,
- or the code that already exists for three of the eight domains.

**This document does not resurrect the old spec.** It is a new v1.0, current
as of today, that does three things: (1) states the full goal scope, (2)
records what is actually built against that scope, with pointers to the
detailed per‑domain requirement docs rather than duplicating them, and (3)
lists every open decision that blocks further building, consolidated in one
place for the first time.

Where the old spec specified something this document does not re-derive —
the fasting engine, prayer‑time engine, circadian engine, the exact readiness
formula, the goals/targets engine, notification suppression matrix — that is
stated explicitly in §7, not silently carried forward. Recovering those
verbatim was considered and declined in favour of writing this reconciliation
first (see chat history 2026‑08‑05 `2c7d2488…` and 2026‑08‑08 `bfffc595…` if
verbatim recovery is wanted later).

---

## 1. Product and scope

Almanac is a personal body‑monitor: sleep, food, energy, activity, plus (per
BRD v1.0) body measurement, hydration, GI, and blood‑test tracking — eight
domains feeding a shared readiness engine. Bundle ID `com.yazeed.almanac`
(carried forward from the original spec; unchanged).

| Domain | BRD source | Design status | Code status |
|---|---|---|---|
| Laboratory (blood test) | v1.0, 09‑08 | Complete — `docs/features/laboratory.md` v0.2 | Built: schema, full CRUD/history/conflict UI |
| Hydration | v1.0, 09‑08 | Informal — folded in during build, no standalone BRD doc | Built: fullest module in the repo |
| Nutrition (food) | v1.5 original | Complete — `docs/processing-design-v0.1.md` | Built: data pipeline + schema; UI not confirmed |
| Exercise / activity | v1.5 original | Complete — `docs/prescription-model-v0.1.md` | Not started (0 code) |
| Sleep | v1.5 original | Not written | Not started |
| Body measurement | v1.0, 09‑08 | Not written | Not started |
| GI / bowel | v1.0, 09‑08 | Not written | Not started |
| Energy / readiness engine | v1.5 original | Original formula lost; readiness‑coupling rules exist per exercise type (`prescription-model-v0.1.md` §5) | Not started |

BRD v1.0's own text is still not present anywhere reachable (project, `yamal`,
Drive) — this affects every domain below and is item 1 of §8.

---

## 2. Shared architecture

Full detail: `docs/architecture/health-data-foundation.md` v0.2. Summarised
here because every domain spec below depends on it.

### 2.1 Reused infrastructure (built, works for every module)

| Component | File | Purpose |
|---|---|---|
| `Database` | `Persistence/Database.swift` | Thin SQL seam, not an ORM. Foreign keys on; `transaction` rolls back on throw. |
| `MigrationRunner` | `Persistence/MigrationRunner.swift` | Ordered, transactional, idempotent; refuses duplicate/out‑of‑order/edited migrations. |
| `TimeModel` / `LogicalDay` | `Time/TimeModel.swift` | Single day‑assignment rule. Boundary is an injected placeholder (`.midnight`) — **not yet the real rule.** |
| `Clock` | `Time/Clock.swift` | Injectable; `FixedClock` for tests. |
| `SourceIdentifier` | `Provenance/SourceIdentifier.swift` | `namespace:localID`. New namespace forces a licence classification at compile time. |
| `LicenceGroup` / `BundleGuard` | `Provenance/LicenceGroup.swift` | Failing build assertion for shipped reference data. |
| `SyncAnchorStore` | `Sync/SyncAnchorStore.swift` | Per‑domain sync cursor. Failure preserves the last good anchor. |
| `BackupService` | `Backup/BackupService.swift` | Online SQLite snapshot. **Does not cover document files** (see Laboratory, §3.1). `restore` throws by design — not implemented. |

**Rule, not a suggestion:** no ORM, no generic repository layer on top of
`Database`. No new generic shared table (`event`, `observation`, `sample`).
Every module claims its own table prefix (`lab_*`, `nutrition_*`,
`hydration_*`, and — once built — `sleep_*`, `body_*`, `gi_*`, `exercise_*`).

### 2.2 The four‑layer data model

| Layer | Definition | Mutability |
|---|---|---|
| Event | Something that happened at a time or over an interval (a specimen collected, a bout performed, a meal eaten). | Correctable by revision, never silently overwritten. |
| Measurement | A qualified value attached to an event or subject. | Append‑only; an amendment is a new revision. |
| Plan | A prescribed intention that may or may not be executed. | Has its own lifecycle, stored separately from its outcome. |
| Derived summary | Computed by a versioned rule from the above. | Droppable and rebuildable; records the rule version and its inputs. |

A plan is never stored in the same row as its outcome. A measurement is never
stored without its qualifying dimensions and preserved source text. A derived
summary is never the only copy of a fact.

### 2.3 Timeline: module‑provided queries, no persisted index

Each module implements `TimelineProviding`, returning its own entries for a
time range; a thin coordinator (`Timeline`) merges and orders them. **No
shared index table exists or is planned** — it was evaluated and rejected
(no performance problem exists to justify the dual‑write risk). Implemented
today by `LabStore` and `HealthSampleStore`.

```swift
public protocol TimelineProviding {
    static var domain: String { get }
    func entries(from: Date, to: Date, in db: Database) throws -> [TimelineEntry]
}
```

`TimelineEntry.value` is a `ValuePresentation` enum (`.none`, `.quantity`,
`.bounded`, `.coded`, `.narrative`, `.ratio`, `.titer`, `.missing(reason:)`,
`.derived(text:ruleVersion:)`) — missing, qualitative, and bounded values are
distinct cases, never collapsed into one `isEstimated: Bool`.

Trigger for revisiting the no‑index decision: a range view merging more than
four modules, or paging across more than a year of history, **and**
profiling shows the merge dominating. Neither condition holds today.

### 2.4 Time, precision, zone (every module)

Four distinct times, never interchangeable: **scheduled**, **occurrence**,
**recording**, **reported**. Every stored time carries a precision
(`instant`·`minute`·`hour`·`day`·`month`·`year`·`unknown`) and, where known,
an offset/zone. No timestamp is ever fabricated to fill a field. Day
assignment uses occurrence → reported → recording, in that order, and
records which was used. Interval overlap is `unknown` (a third value, not
`false`) unless both intervals have known start/end at minute precision or
finer.

### 2.5 Import jobs vs. sync cursors

| | Import job | Sync cursor |
|---|---|---|
| Input | A document/file the user supplied | A change stream the source exposes |
| Identity | The document | The stream position |
| Failure | The job fails; the document remains | The anchor must not advance past unpersisted data |

**Required, not yet implemented:** the imported rows and the cursor advance
must commit in one transaction (`SyncAnchorStore` currently allows writing
them separately — this is a live bug risk, not just a style note).

### 2.6 Identity and revisions (every module)

- Every record has an Almanac‑owned surrogate identifier; no natural key is
  primary.
- External identifiers are scoped to their issuing source:
  `(source_system, external_id)`, never `external_id` alone.
- Repeats are preserved, never deduplicated on the assumption a repeat is an
  error.
- A revision is a new record referencing the one it replaces, with a reason.
  The old record is retained, marked superseded. Nothing is overwritten in
  place.
- When idempotency can't be established, a new record is created and flagged
  `possible_duplicate_of` for review — never silently merged.

---

## 3. Domain: Laboratory (blood test tracking)

**Requirements doc:** `docs/features/laboratory.md` v0.2 (complete, 17
sections, R‑numbered). **Not duplicated here** — this section is the
reconciliation layer: what's built, what's open.

### 3.1 Built (migrations 002–006)

| Migration | Adds |
|---|---|
| 002 `laboratory_catalog` | `lab_catalog_analyte`, `lab_catalog_alias` (folded matching across script/punctuation/Arabic variants), `lab_catalog_external_code` (LOINC‑shaped, `verified` flag, **none seeded**), `lab_panel`/`lab_panel_member` |
| 003 `laboratory_records` | `lab_report`, `lab_observation` / `lab_observation_revision` (stable identity separate from revision identity), `content_fingerprint` for idempotent re‑import, `lab_document`/`lab_document_link` (many‑to‑many, role on the link) |
| 004 `health_samples` | `health_sample` — first HealthKit domain wired, `bodyMass` only |
| 005 | `lab_observation.specimen_kind` (blood/serum/plasma/whole blood/urine/other/unknown) |
| 006 | Manual‑entry APIs: `updateReport`, `reviseObservation`, `updateObservationMetadata` with full audit trail; stale‑import and revert‑vs‑replay detection; ambiguous alias‑match handling (never picks a winner) |

**Catalog coverage today:** 61 analytes, 5 panels, 37 core entries + 24
vitamin‑family entries (13 families; role‑tagged `direct` / `precursor` /
`functional marker` / `metabolic marker` so a marker is never trended as a
level by accident). CBC is complete (15 members: full differential as
absolute counts, red/platelet indices). **Not seeded:** differential
percentages, reticulocytes, most of the liver panel, most electrolytes,
thyroid beyond TSH/FT4, homocysteine, urinalysis analytes, any verified
external code.

**iOS screens (built, not Apple‑verified):** report list/create/edit/detail,
result entry with canonical/alias search, longitudinal history, report‑
conflict accept/reject.

**Known limitations, stated so they aren't rediscovered:** `LabStore.entries`
filters in Swift, not SQL (fine at current volume); `saveReport` doesn't
update an existing report's fields on re‑import, only observations revise;
`health_sample` uniqueness doesn't include `domain` (fine for HealthKit
UUIDs, would need widening for a source that reuses IDs across domains);
coarse‑precision entries sort at the start of their span (a `2019`‑precision
record can fall outside a range query landing inside that year).

### 3.2 Open — needs Yazeed (§17 of the requirements doc)

1. BRD v1.0 text — where does it differ from §4–§17 above?
2. Interpretation boundary for v1: flagging only / trend commentary /
   explanatory content.
3. Document storage medium: bytes in SQLite, files beside it, or references
   only. (Decision recorded — app‑managed copies + SQLite metadata + relative
   paths — but backup/restore doesn't cover it yet; still needs a product
   call on whether that's acceptable for v1.)
4. Catalog scope and LOINC licensing for redistribution.
5. Arabic in v1 or v2 (readiness — alias folding, RTL preserved‑text — is
   built either way; a full Arabic *interface* is a separate commitment).
6. Historical depth expected from users.

---

## 4. Domain: Nutrition (food)

**Requirements doc:** `docs/processing-design-v0.1.md` v0.1 (pipeline, value
model, licence boundary) + `calorie-database-build-prep-2026-09-13.md`
(native‑data decisions) + `handoff-2026-09-13-start-here.md` (build defaults).

### 4.1 Value model

A nutrient value is never a bare number:

```
nutrient_value(
  food_ref, nutrient_id,
  amount              REAL     NULL,   -- NULL only when genuinely unmeasured
  qualifier           TEXT     NOT NULL,  -- measured|trace|not_analysed|below_loq|
                                           -- borrowed|calculated_recipe|calculated_factor|zero_reported
  confidence          TEXT     NULL,   -- source's own grade, verbatim
  source_value        TEXT     NOT NULL,
  source_nutrient_id  TEXT     NOT NULL,
  source_unit         TEXT     NOT NULL,
  licence_group       CHAR(1)  NOT NULL  -- A|B|C|D|N
)
```

`Tr` (trace) and `N` (not analysed) must never be coerced to `0` — this is
the single most consequential correctness bug available in this domain.

### 4.2 Licence boundary

Shipping a food row in the app bundle is redistribution to every installer,
read at the strictest standing. Enforced structurally (a build‑time
assertion), not by discipline.

| Group | Rule | Sources |
|---|---|---|
| A / B | May ship in the bundle, attribution travels with B | USDA FDC (CC0), CIQUAL (CC BY), CoFID (OGL), AFCD (CC BY), Oman FCT 2024 (CC BY, Group B) |
| C | Never ships (share‑alike attaches to the shipped database) | Open Food Facts (ODbL) |
| D | Never ships | SFDA, NEVO, TBCA, IFCT, FAO/INFOODS, Bahrain, Lebanon |
| N (new, this phase) | Almanac‑native rows — Almanac's own IP, always ships | Native dish entries, once authored |

Build assertion: `group in ('A','B','N')` or fail the build.

### 4.3 Build defaults in force (superseding the six‑decision planning doc)

| Decision | Default |
|---|---|
| Calorie calculation | General Atwater factors, 4/4/9/7 kcal/g protein/carb/fat/alcohol. Per‑food factors are a v2 refinement. |
| Canonical nutrient set (this phase) | Energy, protein, carbohydrate, fat, fibre, alcohol only — not USDA's 477. |
| Branded Foods (95% of USDA's rows) | Held out of this phase. |
| SFDA‑as‑benchmark | Not legally cleared — informal internal reference only, never stored verbatim. Still needs the law‑firm confirmation. |

### 4.4 Built

Processing pipeline executed for USDA Foundation Foods + CIQUAL + CoFID +
AFCD: **8,354 foods, 49,036 values**, `build/almanac.sqlite`, QA passed (0
fidelity problems on re‑read raw cells). Migrations:

| Migration | Adds |
|---|---|
| 008 | Nutrition reference tables (`nutrition_food`, `nutrition_value` — schema conflict between two branches resolved in favour of this migration) |
| 009 | Food log |
| 010 | Portions + native‑dish support |
| 011 | Portion dedup fix |

**No dedicated food‑logging UI confirmed** in the current screen inventory
(§3.1's list is Laboratory + Hydration + Settings only). **0 Saudi/Gulf
dishes authored** — `NutritionDishEditor` exists, nothing has been entered.

### 4.5 Open — needs Yazeed

1. Saudi/Gulf dish reference material — the only hard blocker on native
   nutrition data; must come from Yazeed (recipes, personal knowledge, or a
   chosen reference).
2. SFDA‑as‑benchmark legal confirmation (route: the Riyadh law‑firm
   connection).
3. Send the SFDA licence enquiry, and the Open Food Facts (CSV format
   decided) and Frida downloads — all scripted, all still not run as of
   2026‑09‑12.
4. Branded Foods: hold to v2 confirmed as a default, but not yet a final
   product decision.
5. Whether nutrition needs its own logging screens before body‑measurement
   or GI get any (a build‑order question, not a data one).

---

## 5. Domain: Hydration

No standalone BRD/requirements doc exists for this domain — it was scoped
and built directly during the September build sessions. This section is
therefore the only specification it has; treat §5.1–5.3 as authoritative
until a requirements doc is written.

### 5.1 Built (migrations 012–013) — the fullest module in the repo

- `hydration_log`, extended with nullable `drink_id`, `drink_name`,
  `calories_kcal`, `sodium_mg`, `sugar_g`, `value_qualifier` — existing
  plain‑amount and HealthKit‑synced entries are untouched (columns stay
  NULL).
- `hydration_drink` — catalog, tagged `DrinkValueQualifier.catalogUnsourcedEstimate`,
  never asserted as verified nutrition data.
- `hydration_settings`, `hydration_profile` — singleton tables (`id =
  'local'`), no owner column (single‑user model, consistent with
  `Native/README.md`).
- Two‑way HealthKit `.water` sync (`HydrationHealthBridge`).
- `HydrationCalculator` — urgency/dehydration messaging, thresholds/strings
  ported as‑is from the donor branch, not re‑derived here.
- Double‑track detection (logging the same drink twice in a short window) is
  computed at read time from existing rows, never persisted as a flag — the
  "derived facts are droppable" rule applied.
- Reminder scheduling (`HydrationReminderService`) — local notifications.
- Custom (user‑entered) drinks tagged `DrinkValueQualifier.userEntered`,
  distinct from catalog estimates.

**iOS screens:** dashboard + logging, built.

### 5.2 Not built / open

- No requirements doc — the value model above should be reconciled against
  one if hydration's scope grows (e.g., does GI tracking share any of this
  module's read‑time double‑track pattern?).
- Not merged to `master`, not pushed to the remote (see §9).

---

## 6. Domain: Exercise / Activity

**Requirements doc:** `docs/prescription-model-v0.1.md` (complete) +
exercise data collection report (2026‑09‑02).

### 6.1 Design (complete, zero code)

**The core distinction:** in some prescription formats the reps are the
prescription; in others they are the outcome. A `sets`/`reps`/`weight`
schema cannot represent this and silently corrupts history once it
accumulates. Twelve prescription types solve it:

| # | Type | Prescribed | Measured |
|---|---|---|---|
| 1 | `reps_load` | sets×reps×load | completion, RPE, actual load |
| 2 | `reps_bodyweight` | sets×reps (+load) | completion, RPE, added load |
| 3 | `time_under_load` | sets×duration (+load) | duration held |
| 4 | `distance` | distance (+load) | time, pace |
| 5 | `duration` | time (+HR/RPE target) | avg HR, RPE, distance |
| 6 | `rounds_for_time` | fixed work, time cap | **elapsed time** |
| 7 | `work_in_time` | fixed time | **rounds+reps completed** |
| 8 | `interval` | work:rest×repeats | per‑rep output, HR recovery |
| 9 | `quality_reps` | attempt count, stop rule | attempts, technique rating |
| 10 | `hold_stretch` | duration×sides | duration, ROM |
| 11 | `release` | duration/passes per site | sites covered, tenderness |
| 12 | `session_only` | none — logged whole | duration, RPE, notes |

Types 6/7 have prescribed and measured fields **swapped** relative to each
other and progress in **opposite directions on the same clock** — a
generator that assumes "bigger number = improvement" gets one of them
backwards.

Ten container types (`straight_sets` … `flow`) are orthogonal to
prescription type. Readiness coupling differs by type (§ "Readiness
coupling" table in the source doc) — `release` is the only type that should
ever *increase* on a low‑readiness day; `quality_reps` holds volume and
drops complexity rather than reducing work.

`prescription_type` is an Almanac‑owned mapping — `(source, exercise_id) →
prescription_type`, held as data, defaulted by rule, overridable per row —
the same construct as nutrition's nutrient dictionary and laboratory's
alias map. The mapping has been **run** (not just designed) against the
collected 2,040‑exercise data lake:

| Type | Exercises | Share |
|---|---:|---:|
| `reps_load` | 1,323 | 64.9% |
| `reps_bodyweight` | 323 | 15.8% |
| `hold_stretch` | 179 | 8.8% |
| `duration` | 147 | 7.2% |
| `time_under_load` | 49 | 2.4% |
| `distance` | 11 | 0.5% |
| `release` | 8 | 0.4% |
| the other five types | 0 | 0% |

**Five of twelve types have zero source content** — every metcon format,
interval protocol, skill drill, and free‑form session is Almanac‑native
work under the `almanac:` namespace, and these are exactly the types a
future exercise generator needs the most product judgement about.

### 6.2 The MET / energy‑expenditure gap

Duration‑dominant types (4,5,6,7,8,12) compute calorie cost from MET×time.
**Nothing in a shippable licence group supplies MET values.** The 2024 Adult
Compendium — the reference source — publishes no licence terms anywhere in
either PDF. This blocks energy expenditure for six of twelve types until
resolved; it does not block the schema or the other six types.

### 6.3 Not built

No `exercise_*` migration exists. No code, no schema, no screens.

### 6.4 Open — needs Yazeed

1. Does this document's readiness‑coupling design match what BRD v1.0
   actually specifies for the readiness engine? (Blocked on BRD v1.0's
   text — §8 item 1.)
2. Email the Compendium authors re: commercial MET reuse; email
   yuhonas/wrkout re: photograph provenance (the public‑domain claim behind
   free‑exercise‑db is asserted, not traced).
3. Restyle the CC BY‑SA art (Everkinetic/workout‑guide/OpenTraining) and
   release it back, or ship it unmodified with attribution.
4. Is `quality_reps` worth shipping in v1, or does fencing‑style skill work
   wait for v2 alongside Arabic? (Zero source content, highest authoring
   cost of the twelve types.)
5. Does `session_only` stay in scope, or is an untyped session an escape
   hatch that swallows everything the taxonomy fails to model?
6. Does HealthKit's workout import map cleanly onto these twelve types, or
   force everything into `duration`+`distance`? (Unverified — no HealthKit
   workout bridge exists yet; only `bodyMass` and `.water` are wired.)

---

## 7. Domains with no requirements doc yet: Sleep, Body measurement, GI

None of these have been scoped. Per the shared architecture (§2), each
should — when scoped — follow the same shape already proven three times:

- its own `{domain}_*` tables, no shared generic table;
- a value/qualifier model with an explicit "unknown"/"not measured" state,
  never a bare number or a `0` standing in for missing data;
- `TimelineProviding` conformance;
- source‑scoped external identity and a revision chain if any external
  sync applies;
- for Sleep specifically, the architecture doc already flags **interval
  semantics with overlapping stages** and **device provenance** as the
  known hard parts (health‑data‑foundation.md §4) — worth knowing before
  scoping starts, since it's exactly the shape that broke the naive
  workout‑merge design on the exercise side.

**This document does not invent schemas for these three domains.** Doing so
without a scoping pass would repeat the mistake the rest of this project has
spent two months designing away from — guessing at a shape before the
failure modes are known. Recommended next step: a domain‑modeling session
per domain, same format as Laboratory's and Nutrition's, before any code.

---

## 8. Not yet re‑specified under this architecture

The original 2026‑08‑05 spec included a Readiness Engine formula (five
weighted inputs, provisional/final states, confidence levels, calibration at
21 valid days, three baseline types — per the recovered conversation
summary, not verbatim text), a workout‑merge confidence model (five factors,
thresholds at 75/40), fasting and prayer‑time engines, a circadian‑context
engine, a notification suppression matrix, a goals/targets engine
(Mifflin‑St Jeor BMR), and a full screen map across five tabs.

**None of these has been rebuilt against the current per‑module
architecture, and this document does not reproduce their old numeric
detail** — the summary above is all that was recoverable without paging
through the full original chat, and treating remembered fragments as
binding would risk shipping a formula nobody actually re‑verified. Hydration
already has its own local reminder scheduling (§5.1), which covers that
domain's notification needs without the general suppression matrix.

**Recommended treatment:** each of these is a scoping task, not a
transcription task, once its dependent domains (Sleep, Exercise, Nutrition
completion) are far enough along to feed it real data.

---

## 9. Actual repository state, as of 2026‑09‑15

- **iOS app target exists:** `Native/Almanac.xcodeproj`, iOS 17+, shared
  `Almanac` scheme. `Native/README.md` has the build command and a 12‑item
  interactive acceptance checklist — all outstanding.
- **Verification:** 174 Swift/XCTest + 102 Python (`tools/nutrition`) tests
  before the hydration fold‑in; **187 Swift tests, 1 skipped, 0 failures**
  after it — run by Yazeed on `yamal` against Swift 6.3.3. **No Apple SDK
  compilation, no Simulator launch, no interactive check has ever happened**
  — every prior run used Linux `swiftc -frontend -parse` or a Linux
  container build.
- **CI:** GitHub Actions builds and tests on every push (added on
  `claude/ponytail-anxf91`).
- **Branch state:** `codex/manual-entry` (current checkout) has two local
  commits — `be9dd3b` (three‑branch reconciliation: migration 008's schema
  won over a competing one; ponytail's food‑log/portions/dish/CI work folded
  in as 009–011; the leaner hydration module adopted as 012) and `658ce90`
  (hydration features folded in as 013). **2 commits ahead of
  `github/codex/manual-entry`, not pushed. `master` still frozen at
  `f62aa0e`, not fast‑forwarded.** The branch is a clean superset with no
  expected conflicts — this is a decision waiting on Yazeed, not an
  engineering blocker.
- **Migration ledger:**

| # | Name / adds | Domain |
|---|---|---|
| 001 | `core_infrastructure` | shared |
| 002 | `laboratory_catalog` | lab |
| 003 | `laboratory_records` | lab |
| 004 | `health_samples` (bodyMass) | shared/HealthKit |
| 005 | `specimen_kind` | lab |
| 006 | manual‑entry APIs | lab |
| 007 | *unaccounted — not referenced in any recovered status doc; verify directly against `Migrations.swift` before assuming it's free* | — |
| 008 | nutrition reference tables | nutrition |
| 009 | food log | nutrition |
| 010 | portions + native dish support | nutrition |
| 011 | portion dedup fix | nutrition |
| 012 | hydration core | hydration |
| 013 | hydration features (drink catalog, calorie/sodium/sugar, reminders, settings) | hydration |

Per §11 of the architecture doc: numbering is not frozen until the app
target creates its first durable database. Given the app target now exists,
**this may already have happened** — confirm before assuming 014 is free.

---

## 10. Build order, going forward

1. **Decide the branch/merge/push question** (§9) — nothing below is safe to
   build on top of until this is resolved, since three more agent sessions
   building on an unpushed, unmerged branch is exactly the coordination
   failure that produced the three‑branch reconciliation in the first place.
2. **Get a real Apple‑platform verification** — a Mac, rented cloud Mac, or
   at minimum a GitHub Actions macOS runner for CI — since *zero* of the 187
   tests or the 12‑item acceptance checklist has run against a real Apple
   SDK.
3. Resolve BRD v1.0's missing text (§8 item 1 blocks Laboratory, Exercise's
   readiness coupling, and any future readiness‑engine work simultaneously).
4. Close nutrition's native‑dish blocker (§4.5) — the only hard blocker on
   Saudi/Gulf coverage.
5. Scope Sleep, Body measurement, and GI (§7) — domain‑modeling sessions,
   not code, in whatever order Yazeed prioritises.
6. Build Exercise's schema against the already‑complete prescription model
   (§6) once the MET question (§6.2) and the five open product questions
   (§6.4) are far enough along not to force a rebuild.
7. Re‑scope the cross‑cutting engines (§8) once at least Sleep and Exercise
   exist to feed them.

---

## 11. Consolidated open decisions — needs Yazeed

Pulled from every domain doc into one list, so nothing is decided twice or
missed because it was filed under a different section.

| # | Decision | Domain |
|---|---|---|
| 1 | Branch/merge/push plan for `codex/manual-entry` | infra |
| 2 | The Mac/Xcode question — buy, rent, or CI‑only for now | infra |
| 3 | BRD v1.0's full text — locate, re‑paste, or confirm permanently lost | all |
| 4 | Interpretation boundary (flag‑only / trend commentary / explanatory) | lab |
| 5 | Document storage medium acceptability for v1 given backup doesn't cover it | lab |
| 6 | Catalog scope + LOINC licensing | lab |
| 7 | Arabic: interface commitment for v1 or v2 | lab (+ product‑wide) |
| 8 | Historical depth expected from users | lab |
| 9 | Saudi/Gulf dish reference material — the source itself | nutrition |
| 10 | SFDA‑as‑benchmark legal confirmation (route: the law firm) | nutrition |
| 11 | Send SFDA licence enquiry + run OFF/Frida downloads | nutrition |
| 12 | Branded Foods v1 vs v2 — final call, not just the working default | nutrition |
| 13 | Email Compendium authors (MET) + yuhonas/wrkout (photo provenance) | exercise |
| 14 | Restyle CC BY‑SA art or ship as‑is | exercise |
| 15 | `quality_reps` in v1 or v2 | exercise |
| 16 | Keep or drop `session_only` as a catch‑all | exercise |
| 17 | Scoping order for Sleep / Body measurement / GI | new domains |

---

## 12. Appendix A — Nutrition source licensing

| Dataset | Licence | Foods | Group |
|---|---|---:|---|
| USDA FoodData Central | CC0 1.0 | 2,101,280 | A |
| ANSES‑CIQUAL 2025 | CC BY 4.0 + Etalab 2.0 | 3,484 | B |
| CoFID 2021 | OGL v3.0 | 2,887 | B |
| AFCD Release 3 | CC BY 4.0 | 1,588 | B |
| Oman FCT 2024 | CC BY 4.0 | 221 | B |
| Open Food Facts | ODbL | — | C, never ships |
| SFDA, NEVO, TBCA, IFCT, FAO/INFOODS, Bahrain, Lebanon | various / unclear | — | D, never ships |

## Appendix B — Exercise source licensing

| Source | Licence | Records | Group |
|---|---|---:|---|
| free‑exercise‑db | Unlicense (asserted, unverified) | 876 | A* |
| wrkout | Unlicense (same underlying data as free‑exercise‑db) | 873 | A* |
| wger (CC0 subset) | CC0 | 21 | A |
| wger (CC BY‑SA subset) | CC BY‑SA 3/4 | 850 | C, shippable unmodified+attributed |
| Everkinetic / workout‑guide / OpenTraining | CC BY‑SA | — | C, shippable unmodified+attributed |
| Compendium of Physical Activities 2024 | no licence found | — | D, quarantined — MET gap |

---

*This document supersedes `almanac_technical-spec-v1_0.md` (2026‑08‑05) as
the canonical build reference. That file's pointer note should be updated to
point here once this is saved to the project.*
