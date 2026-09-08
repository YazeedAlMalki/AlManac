# Almanac — Laboratory (blood test tracking)

**Version:** 0.2 (revises 0.1 of the same date)
**Status:** requirements. Nothing built. No application code has been changed.
**Provenance:** v0.1 was derived from first principles. v0.2 restores the
requirement set Yazeed supplied on 2026-09-08 — canonical catalog with
vitamins, aliases, reusable panels, explicit reports, source-document
relationships, original ranges and units, qualitative/text/ratio/titer values,
unknown tests, optional context metadata, correction history, localization
readiness. Where a requirement below came from that list it is authoritative
over anything v0.1 derived. BRD v1.0 (2026-09-08) itself is still not in the
project, on `yamal`, or in Drive; §18 lists what remains open because of that.
**Architecture:** `docs/architecture/health-data-foundation.md`.

---

## 1. Purpose

Almanac records laboratory results over time, preserves exactly what the
issuing source reported, and never destroys or infers a fact the source did
not state.

Two rules govern every requirement below:

- **Preserve first.** The source's own text for analyte, value, unit, range,
  flag and comment is stored verbatim and permanently, alongside any Almanac
  interpretation of it. Interpretation is additive and revisable; the source
  text is neither.
- **Unknown is a value.** Missing collection time, specimen, order, method or
  laboratory are recordable states, distinct from "not yet entered" and
  distinct from any default. Almanac never invents a fact to satisfy a schema.

---

## 2. Failure classes to design against

| Reported | Naive handling | Why it is wrong |
|---|---|---|
| `<0.01` | store `0.01`, or `0` | The comparator is part of the value. It says the true value is below a stated point — it does **not** by itself tell you what the assay's limit of quantification is. |
| `Not detected` | store `0` | A coded result, not a number. |
| `Haemolysed — not reportable` | drop the row | A specimen was collected and produced no value. Both facts are real. |
| `eGFR 88` | treat as measured | Calculated by the source from other analytes. |
| `TSH 4.1 (0.4–4.0)` | flag high globally | Flagged against that source's range for that method. |
| A vitamin D result from 2019 with no lab named | reject, or invent a lab | Historical manual entry with unknown context is a supported case. |
| Two glucose values 120 min apart | dedupe to one | Repeated observations are data, not duplicates. |
| An amended potassium result | overwrite the original | Correction history is a requirement. |

---

## 3. Entities

```
catalog_analyte ─┐                      report ──── source_document
   aliases       │                        │  (explicit, user- or import-created)
catalog_panel ───┤                        │
                 │   order ── specimen ── observation ──┬── original range (verbatim)
                 └──────────────────────  (0..n per     ├── revision chain
                     all optional          specimen)     └── context metadata
```

- **R3.1** `order`, `specimen`, `report` and `source_document` are each
  optional for an observation. An observation with none of them is valid and
  complete.
- **R3.2** A specimen may exist with no observations (rejected, insufficient,
  lost). This remains visible.
- **R3.3** An order may exist with no specimen.
- **R3.4** A **report** is an explicit first-class record — the thing the user
  received — not an implicit grouping inferred from a shared timestamp. A
  report groups observations, may reference one or more source documents, and
  may itself have unknown issuing laboratory.
- **R3.5** A **source document** (PDF, photo, CSV, transcription note) is a
  separate record. The relationship between documents and observations is
  many-to-many: one document may back many observations, and one observation
  may be evidenced by more than one document (an original plus an amendment
  letter).

---

## 4. Canonical catalog

- **R4.1** Almanac maintains a canonical catalog of analytes covering, at
  minimum, general chemistry, haematology, lipids, **vitamins and
  micronutrients**, hormones, inflammatory markers, and urinalysis. Vitamins
  are named explicitly because they are the join point with the nutrition
  module and were omitted from v0.1.
- **R4.2** Each catalog analyte carries a namespaced identifier
  (`Provenance/SourceIdentifier.swift`): LOINC where available
  (`loinc:718-7`), `almanac:` for Almanac-defined entries.
- **R4.3** Each catalog analyte carries **aliases** — a many-to-one set of
  alternate names, abbreviations, and per-source spellings ("Hb", "HGB",
  "Haemoglobin", "هيموغلوبين"). Aliases are data, matched case- and
  diacritic-insensitively, and are the primary mapping mechanism.
- **R4.4** **Reusable panels** are catalog entities: a named, ordered set of
  analytes (CBC, CMP, lipid panel, thyroid panel, a user's own "quarterly
  bloods"). A panel is a template for ordering and a grouping for display. A
  report is not a panel; a report may contain several panels and loose
  analytes.
- **R4.5** The mapping `(source_system, source_analyte_text) → catalog_analyte`
  is held **as data, not code**, with a confidence and an origin
  (`rule` | `alias_match` | `user`), and is overridable per row — the same
  construct as the nutrient dictionary (Processing Design §6) and the
  prescription map (Prescription Model §6).
- **R4.6** Catalog and alias records must be localizable — see §16.
- **R4.7** Any catalog content Almanac ships is subject to
  `BundleGuard.assertShippable` (`Provenance/LicenceGroup.swift:42-49`).
  Adding a source namespace breaks the exhaustive `licenceGroup` switch
  (`SourceIdentifier.swift:22-33`), so a licence classification is forced at
  compile time.

### 4.8 Unknown tests

- **R4.8** An observation whose analyte matches nothing in the catalog is
  stored, displayed and retained in full, using its source text as its name.
  It is never dropped, never merged into a near neighbour, and never blocks an
  import.
- **R4.9** `catalog_analyte_id` is **nullable**, and this is the resolution of
  the contradiction in v0.1: catalog matching is an *annotation*, not a
  precondition for storage. Matching may be applied, corrected or removed at
  any later time without touching the observation's preserved fields.
- **R4.10** Only features that genuinely require canonical identity —
  cross-source trends, aggregation, catalog-driven reference lookup, nutrition
  cross-linking — are unavailable for an unmatched observation. The interface
  states which feature is unavailable and why; it does not hide the row.

---

## 5. The observation value model — five orthogonal dimensions

v0.1 used a single `lab_qualifier` enum. That conflated independent facts: a
pending result and a qualitative result and a `<` result are not points on one
scale. v0.2 replaces it with five dimensions, each independently settable,
each defaulting to `unknown` rather than to a guess.

### 5.1 Lifecycle status

Per entity, because the lifecycles differ.

| Entity | Values |
|---|---|
| `order` | `planned` · `placed` · `collected` · `partially_resulted` · `resulted` · `cancelled` · `unknown` |
| `specimen` | `collected` · `rejected` · `quantity_insufficient` · `lost` · `unknown` |
| `observation` | `pending` · `final` · `amended` · `corrected` · `cancelled` · `entered_in_error` · `superseded` · `unknown` |

`amended` and `corrected` are distinct: an amendment adds or refines, a
correction replaces a value the source states was wrong. Both produce a new
revision (§9).

### 5.2 Value type

`quantitative` · `semi_quantitative` · `ordinal` · `qualitative_coded` ·
`ratio` · `titer` · `text` · `absent`

- `ratio` covers A/G ratio, LDL:HDL, and any value reported as a dimensionless
  quotient. Stored as its reported quotient, not silently expanded.
- `titer` covers `1:160` and similar. Stored with numerator and denominator
  preserved, plus the source text. Titers are ordinal on a log-2-ish scale and
  must never be averaged.
- `text` covers narrative results ("Occasional atypical lymphocytes noted").
  Full text preserved; no truncation.
- `qualitative_coded` covers positive/negative/reactive/not-detected, with the
  source's own token preserved.
- `absent` means no value exists — see §5.5 for why.

### 5.3 Comparator

`none` · `lt` · `lte` · `gt` · `gte` · `approx`

- **R5.1** The comparator is stored exactly as the source reported it and is
  part of the value, not a flag on it.
- **R5.2** **A comparator must never be read as a limit of detection or
  quantification.** `<0.01` states that the value is below 0.01 as this source
  reported it. LOD and LOQ are separate, optional, independently stored fields,
  populated only when the source explicitly states them. Inferring an LOQ from
  a `<` is the v0.1 error and is prohibited.
- **R5.3** A bounded value is never used as its bound in a mean, a sum, or a
  regression. It may be plotted as a bounded marker.

### 5.4 Derivation

`measured` · `calculated_by_source` · `reported_without_derivation_stated` ·
`unknown`

- **R5.4** The default is `unknown`, not `measured`. Most reports do not state
  how a value was produced, and asserting `measured` would be inference.
- **R5.5** `reported_without_derivation_stated` is distinct from `unknown`: the
  first means the document was read and said nothing, the second means nobody
  has looked.

### 5.5 Missing-value reason

Set only when no value exists (`value_type = absent`).

`not_performed` · `specimen_rejected` · `quantity_insufficient` · `pending` ·
`not_reported_by_source` · `illegible_in_document` · `not_entered` · `unknown`

- **R5.6** Absence always carries a reason, even if the reason is `unknown`.
  A NULL value with no reason is not a valid state.

### 5.6 Preserved source text — mandatory on every observation

`source_analyte_text` · `source_value_text` · `source_unit_text` ·
`source_range_text` · `source_flag_text` · `source_comment_text` ·
`source_method_text` · `source_specimen_text`

- **R5.7** These are captured verbatim, are never overwritten by any
  interpretation, and are sufficient on their own to re-derive every parsed
  field without returning to the source document. This is the `sourceValue`
  guarantee from `Provenance/NutrientQualifier.swift:32-35`, widened.

---

## 6. Calculated values

- **R6.1** A value the laboratory reported as calculated (eGFR, Friedewald
  LDL, non-HDL, anion gap, corrected calcium) is stored **permanently and
  immutably** as an observation with `derivation = calculated_by_source`. It
  is never recomputed, never replaced by an Almanac calculation, and never
  hidden when Almanac's own formula would give a different number.
- **R6.2** An Almanac-computed value is a **separate record of a separate
  kind**, never written into an observation. It carries:
  `formula_id`, `formula_version`, `computed_at`, and explicit references to
  every input observation used.
- **R6.3** Recomputation under a new formula version creates a new record. The
  previous one is retained and remains attributable to its version.
- **R6.4** Where both exist for the same analyte and time, both are shown, and
  the source-reported one is identified as the source's.
- **R6.5** An Almanac-computed value whose inputs include a bounded, absent or
  unmatched observation records that dependency and is marked as such rather
  than silently produced.

---

## 7. Reference ranges

- **R7.1** The reference range **as printed on the report** is preserved
  verbatim (`source_range_text`) on every observation, along with its unit as
  printed. This is required even when the range is also parsed.
- **R7.2** A parsed range is stored alongside, with low/high bounds, bound
  inclusivity, and the unit the range was expressed in. One-sided and absent
  ranges are valid; absent is never rendered as "normal".
- **R7.3** A range is qualified by whatever the source stated about it —
  method, sex, age band, physiological state — and those qualifiers are
  preserved as stated. Almanac does not complete them.
- **R7.4** A catalog-level range may exist as a fallback for display when a
  source supplied none. It is labelled as Almanac's, never merged into the
  source's fields.
- **R7.5** The source's own flag (`H`, `L`, `HH`, `LL`, `A`, `critical`) is
  preserved verbatim and takes precedence over any Almanac-computed flag.
  Almanac computes a flag only where the source gave none, and marks it as
  Almanac-derived.
- **R7.6** A user's personal target from a clinician is a separate concept and
  is never written into range fields.

---

## 8. Units

Correcting a v0.1 overstatement: not all unit conversion needs analyte-specific
molar mass.

| Conversion class | Needs | Example |
|---|---|---|
| Decimal scaling within one dimension | A general factor. Safe and analyte-independent. | g/L → mg/dL, µmol/L → nmol/L |
| Dimensionless | Nothing. | %, ratios, titers |
| Mass ↔ substance amount | Analyte-specific molar mass or a stated conversion factor. | mg/dL ↔ mmol/L for glucose |
| Activity units | A per-assay factor that is not always defined. | IU/mL, U/L |

- **R8.1** The source's unit text is preserved on every observation.
- **R8.2** A canonical value may be stored **alongside** the source value,
  never in place of it, and always with the conversion factor and its class
  recorded.
- **R8.3** Conversions of the first two classes may be applied generally.
  Conversions of the third and fourth are applied only where the catalog
  supplies the analyte-specific factor; otherwise no canonical value is stored
  and the observation is excluded from cross-unit comparison, with the reason
  stated.

---

## 9. Identity, repeats, and correction history

v0.1 proposed uniqueness on `(lab, report id, analyte)`. That is wrong twice:
it treats legitimate repeats as duplicates, and it makes amendments
unrepresentable.

- **R9.1** Every observation has an Almanac-owned surrogate identifier. No
  natural key is used as the primary identity.
- **R9.2** External identifiers are **scoped to their issuing source**.
  Uniqueness applies to `(source_system, source_observation_id)` only, and
  only where the source supplied an identifier. Two sources may use the same
  identifier string without collision.
- **R9.3** **Repeated observations are preserved.** Several observations of the
  same analyte on the same specimen, on the same day, or across a timed series
  (OGTT, cortisol curve, serial troponins) are distinct records. A `time_point_label`
  and a sequence number carry their ordering when the source supplies one.
- **R9.4** An amendment or correction creates a **new observation** carrying
  `replaces_observation_id`, a revision number, and the source's stated reason.
  The replaced observation is retained in full, its lifecycle set to
  `superseded`. Nothing is overwritten and nothing is deleted.
- **R9.5** The full revision chain is retrievable and displayable. "What did I
  know on 12 March, and what does the corrected record say now" must both be
  answerable.
- **R9.6** Import idempotency, in order: match on
  `(source_system, source_document_id, source_observation_id)` where the source
  supplies them; otherwise on a content fingerprint that includes collection
  time and sequence; otherwise **create a new record and mark it
  `possible_duplicate_of`** for user review. Silent merging is prohibited.

---

## 10. Historical and incomplete entry

- **R10.1** Manual entry must succeed with an analyte, a value, and nothing
  else. Every other field is optional.
- **R10.2** Unknown collection time, specimen, order, method, issuing
  laboratory and reference range are each recordable as `unknown`, distinct
  from `not_entered`.
- **R10.3** Almanac never substitutes a default for an unknown: not "today"
  for a missing date, not "venous blood" for a missing specimen, not the last
  used lab.
- **R10.4** An observation may be completed later. Adding a laboratory to a
  ten-year-old entry is an edit to that field with its own recorded time, not
  a new observation.
- **R10.5** Features that need a field state their requirement rather than
  failing: a trend excludes observations with unknown collection date and says
  how many it excluded.

---

## 11. Reports and source documents

- **R11.1** A report records: issuing laboratory (nullable/unknown), report
  identifier as printed (nullable), report date with precision (§12),
  ordering clinician (optional), and free-text header content preserved.
- **R11.2** A source document records its kind, its bytes or a reference to
  them, a checksum, and the time it was added. Storage location is an open
  architecture question (§18) — the requirement here is the relationship, not
  the storage medium.
- **R11.3** Document-to-observation is many-to-many, with a role on the link
  (`original`, `amendment`, `transcription_source`, `supporting`).
- **R11.4** Deleting a document never deletes observations derived from it;
  the observations retain their preserved source text and record that their
  evidence was removed.

---

## 12. Time

Four distinct times, none interchangeable:

| Time | Belongs to | Meaning |
|---|---|---|
| `scheduled_at` | order | when the draw was planned |
| `collected_at` | specimen | when the sample was actually taken |
| `reported_at` | report / observation | when the source issued it |
| `recorded_at` | any record | when it entered Almanac |

- **R12.1** Every one of these is optional and may be `unknown`.
- **R12.2** Every stored time carries a **precision**: `instant` · `minute` ·
  `hour` · `day` · `month` · `year` · `unknown`. A date-only report is stored
  at `day` precision. **No time-of-day is invented to fill an instant field.**
- **R12.3** Every stored time carries the offset and, where known, the zone
  identifier in force where it was recorded. A historical result entered from
  a report issued abroad keeps that context rather than being reinterpreted in
  the device's current zone.
- **R12.4** Day assignment uses `collected_at` where available, else
  `reported_at`, else `recorded_at`, and records **which** it used. Assignment
  goes through the shared `TimeModel` (`Time/TimeModel.swift`); no module
  formats a date itself.
- **R12.5** Where the chosen time has `day` precision or coarser and the day
  boundary is not midnight, the assignment is marked approximate rather than
  resolved by assuming a time.
- **R12.6** Ordering within a day applies only to records with `minute`
  precision or finer. Coarser records group together as time-unknown rather
  than being sorted against a fabricated time.
- **R12.7** Interval overlap is defined only when both intervals have known
  start and end at `minute` precision or finer with known offsets. Otherwise
  the answer is *unknown*, never false.

---

## 13. Optional context metadata

- **R13.1** Fasting status is optional, tri-state (`fasting` · `not_fasting` ·
  `unknown`), and defaults to `unknown`.
- **R13.2** Further optional context, each independently nullable and never
  inferred: time since last meal, medications in effect as free text,
  supplements in effect, menstrual-cycle day, recent exercise, hydration note,
  posture at draw, and a general free-text note.
- **R13.3** Context is recorded as the user or source stated it. Almanac does
  not populate it from other Almanac modules — a food log near the draw time
  is not evidence of fasting.
- **R13.4** Context never gates storage or display of a result.

---

## 14. Ingestion

Two mechanisms, and they are not the same thing (architecture doc §9):

- **R14.1** **File-based import is a job.** It has a job record with status,
  counts, per-row outcomes, errors, and a link to the source document.
  Re-running it is idempotent per §9.6. It has no cursor.
- **R14.2** **Incremental synchronisation uses a cursor.** It applies only to
  sources that expose a change stream. It has no source document.
- **R14.3** For any incremental sync, the imported records and the cursor
  advance **commit in a single transaction**. A cursor that advances without
  its rows being persisted would skip data permanently; this is a hard
  requirement, not a convention.
- **R14.4** A failed import surfaces unparsed rows for manual completion. It
  does not drop them and does not guess.
- **R14.5** External ingestion sits behind a protocol with a fake, the pattern
  of `Health/HealthProvider.swift`, so it is testable without a device.

---

## 15. Presentation and comparability

- **R15.1** Matching derivation status does **not** establish comparability.
  Two `measured` results are comparable only when analyte identity, method,
  assay, unit and reference frame agree — and often that cannot be determined
  from the report. Almanac therefore **surfaces the differences** (different
  lab, different method, different unit, different range) rather than
  asserting that two points belong on one line.
- **R15.2** A trend may include points across sources, provided every
  difference is visible on the chart and in the legend. Excluding them
  silently is as wrong as merging them silently.
- **R15.3** Missing, qualitative and bounded results are three distinct
  presentations and are never collapsed into a single "estimated" flag.
- **R15.4** A pending order, a rejected specimen, a resulted observation, an
  absent value with a reason, and a superseded revision are five visually
  distinct states.

---

## 16. Localization readiness

- **R16.1** All user-visible catalog content — analyte names, panel names,
  units where they are words, category names — is stored as localizable
  entries keyed by locale, with a fallback locale. Arabic and English are the
  target pair.
- **R16.2** Preserved source text is **never** localized, translated or
  normalized. It is displayed as printed, with its own direction.
- **R16.3** Alias matching is diacritic- and case-insensitive and works across
  scripts, so an Arabic report can match an English catalog entry.
- **R16.4** Numeric formatting, digit shape and date display are locale
  decisions at render time, never at storage time.
- **R16.5** Mixed-direction display (an Arabic report name beside a Latin
  analyte code) is a layout requirement, not a data one, but the data layer
  must not strip direction marks from preserved text.

---

## 17. Preserve now, automate later

The distinction Yazeed asked to be made explicit. Everything in the left
column is a v1 storage requirement. Everything in the right column is
behaviour that can be added later **only because** the left column was
captured.

| Preserve now (v1) | Automate later |
|---|---|
| Source analyte text on every observation | Automatic catalog matching by alias and rule |
| Source unit text and conversion class | Automatic canonical-unit conversion and cross-lab trends |
| Source range text and its stated qualifiers | Personalised or catalog-driven range fallback |
| Comparator, LOD/LOQ only when stated | Statistically correct handling of censored series |
| `derivation` per observation | Almanac-computed values with formula versioning (§6.2) |
| Revision chain and reasons | "What changed since last time" notifications |
| Time precision, zone, and which time was used | Day-boundary-aware grouping under the spec's real rule |
| Optional context metadata fields | Correlating results with food, sleep and training |
| Document-to-observation links with roles | OCR and automated report parsing |
| Localizable catalog entries | Full Arabic interface |
| Panels as reusable templates | Suggested re-test scheduling |

- **R17.1** No later automation may modify a preserved field. Automation writes
  to its own fields, attributably and reversibly.

---

## 18. Open product questions

These need Yazeed, not an engineering decision.

1. **BRD v1.0 text.** Still not in the project. Which of §4-§17 does it define
   differently?
2. **Interpretation.** v0.1 stated Almanac "does not interpret, ever". That
   was an overstatement of a v1 scope decision. Interpretation is deferred,
   not prohibited — but the boundary is a product choice: flagging against a
   stated range only, trend commentary, or explanatory content. The data model
   above supports any of them, provided interpretation is stored separately
   from source facts with its own versioning.
3. **Document storage.** Bytes in SQLite, files beside the database, or
   references only? No storage strategy exists anywhere in the repo.
4. **Catalog scope for v1.** How many analytes and panels ship, and is LOINC
   licensable for redistribution in the app bundle, or must the catalog be
   Almanac-native under the `almanac:` namespace?
5. **Arabic in v1 or v2.** §16 is written as readiness. Shipping Arabic is a
   larger commitment than being ready for it.
6. **Historical depth.** How far back will results be entered, and does that
   change manual-entry ergonomics enough to matter for v1?
