# Almanac — Laboratory (blood test tracking)

**Status:** requirements, derived. Nothing built.
**Date:** 2026-09-08
**Provenance:** derived from first principles and the existing project design
documents, **not transcribed from BRD v1.0 (2026-09-08)**, whose text was not
available in the project, on `yamal`, or in Drive at the time of writing.
Correct against the BRD before building.
**Architecture:** `docs/architecture/health-data-foundation.md`. Storage shape,
the shared timeline and migration numbering live there and are not repeated
here.

---

## 1. Purpose

Almanac records the user's own laboratory results over time, keeps every
result traceable to the lab that issued it, and makes a value's *status* —
measured, censored, not detected, not reportable — as visible as its number.

Almanac does not interpret results, does not diagnose, and does not advise.
It reports what the lab said, flags what the lab flagged, and shows change
over time. Any language beyond that belongs to the user's clinician.

---

## 2. The failure to design against

The same failure the project has now documented twice — in Processing Design
v0.1 §2 for nutrients and Prescription & Container Model v0.1 §1 for exercise
— appears in laboratory data in three distinct forms.

| What the lab reported | What a naive float column stores | What was true |
|---|---|---|
| `<0.01 ng/mL` | `0.01`, or `0` | Below the assay's limit. The real value is unknown and smaller. |
| `Not detected` | `0` | Nothing found by *this* assay at *this* sensitivity. Not "zero". |
| `Haemolysed — not reportable` | `NULL`, or the row dropped | A specimen was drawn and failed. The draw happened; the result did not. |
| `Ferritin 42` | `42` | Meaningless without units, and mg/dL vs mmol/L differ by ~18× for glucose. |
| `TSH 4.1, range 0.4–4.0` | `4.1` flagged high | High *against that lab's range for that method*. Another lab's range makes it normal. |
| eGFR `88` | a measurement | Calculated from creatinine by a formula, not measured. Change the formula, change the number. |

Three of these are the `Tr` / `N` / reported-zero collapse in a different
vocabulary. Two are new to this domain: **a reference range is not a property
of the analyte**, and **some results are calculated rather than measured**.

---

## 3. Domain model

Four things, and they are not the same thing:

```
  order (a panel was requested)
     └── specimen (blood was drawn at an instant)
            └── result (one analyte, one value, one status)
                   └── reference range (the interpretation frame in force)
```

Requirements that follow directly:

- **R3.1** An order may exist with no specimen (booked, not attended).
- **R3.2** A specimen may exist with no results (rejected, insufficient,
  lost). This must remain visible; it is a real event.
- **R3.3** A result belongs to exactly one specimen and one analyte.
- **R3.4** A result carries the reference range that was in force *for it*,
  copied onto the result — not looked up at display time from a table that may
  since have changed.
- **R3.5** An amended result never overwrites the original. It is a new row
  that supersedes it, and both remain retrievable.

Per §4 of the architecture doc: the order is a **plan**, the specimen is an
**event**, the result is a **measurement**, and a trend is a **derived
summary**. They do not share a table.

---

## 4. Analytes

- **R4.1** An analyte is identified by a namespaced source identifier, per
  Processing Design §3 and `Provenance/SourceIdentifier.swift`. LOINC codes
  where available (`loinc:718-7`), `almanac:` for anything Almanac defines.
- **R4.2** The lab's own code, the lab's own analyte name, and the lab's own
  unit string are stored verbatim on every result and never discarded. This is
  the `sourceValue` guarantee from `NutrientQualifier.swift:32-35`.
- **R4.3** The mapping `(lab, lab_analyte_code) → analyte_id` is held **as
  data, not code**, defaulted by rule and overridable per row — the same
  construct as the nutrient dictionary (Processing Design §6) and the
  prescription map (Prescription Model §6).
- **R4.4** An unmapped analyte is stored and displayed under the lab's own
  name rather than dropped. An import must never silently discard a row it
  did not recognise.
- **R4.5** Any shipped analyte dictionary is subject to
  `BundleGuard.assertShippable`. LOINC's licence terms must be established and
  classified into a `LicenceGroup` before the module compiles — adding a
  namespace breaks the exhaustive switch at `SourceIdentifier.swift:22-33` by
  design.

---

## 5. The result value model

A laboratory result is never a bare number.

- **R5.1** Every result carries a closed `lab_qualifier`:

| Qualifier | Meaning | Has a number the UI may display as a quantity |
|---|---|---|
| `measured` | Analysed and reported numerically. | yes |
| `below_loq` | Reported as `< x`. True value unknown, below `x`. | the limit, shown as `<x` |
| `above_loq` | Reported as `> x`. | the limit, shown as `>x` |
| `not_detected` | Assay found none at its sensitivity. | no — never render as 0 |
| `qualitative` | Positive / negative / reactive. No number exists. | no |
| `calculated` | Derived by the lab from other analytes (eGFR, Friedewald LDL, non-HDL). | yes, with the formula named where the lab states it |
| `not_reportable` | Specimen failed — haemolysed, clotted, insufficient. | no |
| `pending` | Ordered, not yet resulted. | no |
| `cancelled` | Order withdrawn. | no |
| `superseded` | Replaced by an amended result. | historical only |

- **R5.2** `amount` is nullable, and NULL means *no number exists*, never
  zero. Rendering `not_detected` as `0` is the exact bug Processing Design §2
  calls the most consequential available in the project.
- **R5.3** `source_value` holds the lab's original cell unparsed (`"<0.01"`,
  `"Not Detected"`, `"NEG"`), so any parse is reversible without returning to
  the source document.
- **R5.4** A censored result (`below_loq` / `above_loq`) must never be used in
  a mean, a sum or a trend line as if it were its limit. It may be shown on a
  chart as a bounded marker.
- **R5.5** Only `measured` and `calculated` results are directly comparable
  across time, and `calculated` only when the formula matches — mirroring
  `NutrientQualifier.isDirectlyObserved` (`NutrientQualifier.swift:26-28`).

---

## 6. Reference ranges

- **R6.1** A reference range is keyed by **analyte × method × issuing lab ×
  sex × age band × physiological state × unit**, not by analyte alone.
- **R6.2** The range in force is copied onto the result at ingest (R3.4).
- **R6.3** Ranges may be one-sided (`> 60`), two-sided, or absent. Absent is a
  valid state and must not be rendered as "normal".
- **R6.4** The lab's own abnormal flag (`H`, `L`, `HH`, `LL`, `A`, critical)
  is stored verbatim and takes precedence over any flag Almanac would compute.
  Almanac computes a flag only when the lab supplied none, and marks it as
  Almanac-derived.
- **R6.5** Two results for the same analyte from two labs are **not**
  normalised into one range. They are shown with their own ranges, the way
  Processing Design §6 refuses to deduplicate foods across sources: the values
  differ legitimately by method, and merging is irreversible.
- **R6.6** A user-supplied personal target (e.g. a clinician's individual
  goal) is a separate concept from a reference range and is never written into
  the range fields.

---

## 7. Units

- **R7.1** The lab's unit string is stored verbatim on every result.
- **R7.2** A canonical unit per analyte may be stored *alongside* the source
  unit, never in place of it.
- **R7.3** Conversion between conventional and SI units is analyte-specific
  (it needs molar mass) and is therefore a property of the analyte dictionary,
  held as data. There is no general numeric conversion.
- **R7.4** A result whose unit cannot be mapped is stored and displayed in the
  lab's unit, excluded from cross-lab trends, and marked as such — the
  per-100 g / per-100 mL discipline from Processing Design §4 Trap 1: the
  basis is a column, not an assumption.

---

## 8. Ingestion

- **R8.1** Manual entry is the v1 path and must be complete on its own: panel,
  lab, draw time, analyte, value, unit, range, flag.
- **R8.2** Any file-based import (CSV, PDF, photo) is a separate stage that
  produces the same rows manual entry produces, and every imported result
  records the document it came from.
- **R8.3** Imports use `SyncAnchorStore` with a `laboratory` domain key. A
  failed import must not clear the last good anchor
  (`SyncAnchorStore.swift:59-67`).
- **R8.4** Import is idempotent: re-importing the same report produces no
  duplicate results, keyed on (lab, lab report id, analyte).
- **R8.5** An import that cannot parse a row surfaces the row for manual
  completion rather than dropping it or guessing.
- **R8.6** External ingestion sits behind a protocol with a fake, the way
  `HealthProvider` / `FakeHealthProvider` do (`Health/HealthProvider.swift`),
  so the import algorithm is testable on Linux.

---

## 9. Timeline and reporting

- **R9.1** A specimen appears on the day view at its draw time, assigned to a
  logical day by the shared `TimeModel` — never by formatting a date locally.
- **R9.2** A pending order, a rejected specimen and a resulted panel are three
  visually distinct states on the timeline.
- **R9.3** The Laboratory module supplies its own timeline summary through
  `TimelineSummarising` (architecture §5.3). The timeline layer never reads a
  lab value directly.
- **R9.4** A trend for one analyte plots only comparable results (R5.5), shows
  censored values as bounded markers, and marks any point whose lab or method
  differs from the series baseline.
- **R9.5** Any computed trend or summary records the rule version that
  produced it and is rebuildable — a derived summary, per architecture §4.
- **R9.6** No interpretive text. Almanac states what was reported and what the
  lab flagged. It does not name conditions, suggest causes, or recommend
  action.

---

## 10. Out of scope for v1

Fasting status, medication context, and specimen-condition annotations beyond
the lab's own `not_reportable` flag; HL7/FHIR ingestion; clinician sharing or
export formats; coupling lab values into the readiness engine (blocked on the
spec's readiness definition); reference-range personalisation (R6.6 defines
the concept only); attachment storage for report documents — no storage
strategy exists anywhere in the repo yet.

---

## 11. Open questions

1. Does BRD v1.0 (2026-09-08) define a panel vocabulary, or is a panel just a
   set of analytes drawn together?
2. Does the Technical Spec's 48-table schema already contain lab tables? It is
   still unavailable, so this could not be checked — the same gap recorded on
   2026-09-05.
3. Is LOINC licensable for redistribution inside the app bundle, or must the
   analyte dictionary be Almanac-native under the `almanac:` namespace?
4. Should a `calculated` result (eGFR, Friedewald LDL) be stored at all, or
   recomputed from its inputs on display? Storing it preserves what the lab
   said; recomputing it keeps the formula current. Both cannot be the primary.
5. How far back does the user intend to enter historical results, and does
   that change manual entry's ergonomics enough to matter for v1?
