# Almanac — Laboratory catalog coverage

**Version:** 0.2 (revises 0.1)
**Date:** 2026-09-08
**Generated from:** `Sources/AlmanacCore/Laboratory/LabCatalogSeed.swift`
**Pinned by:** `CatalogCoverageTests` — `testEveryDocumentedVitaminFormIsSeeded`,
`testVitaminEntriesAreClassifiedByWhatTheyMeasure`,
`testTheVitaminCountIsNotOverstated`, `testCBCPanelIsComplete`.

## What changed from 0.1

v0.1 claimed **"24 distinct vitamin forms."** That was wrong, and the error was
the same class the whole project is built to avoid: counting things that are not
the same kind of thing. Four of the 24 entries do not measure a vitamin at all.

| | Count |
|---|---:|
| Catalog entries in vitamin families | **24** |
| — direct measurements of the vitamin or one of its own metabolites | **20** |
| — precursor (beta-carotene) | 1 |
| — functional markers (EGRAC, PIVKA-II) | 2 |
| — metabolic marker (methylmalonic acid) | 1 |

`measurement_role` is now a column, not a comment, and
`MeasurementRole.reportsAmountOfTheSubstance` is false for everything except
`direct` — so a marker cannot be trended against a level by accident.

## How to read this

Coverage is claimed **per measurable entry**, never per family name. "Vitamin D
is covered" is not a claim this document makes: 25-OH D total, 25-OH D2,
25-OH D3 and 1,25-dihydroxy D are four different analytes, measured by different
assays, reported in different units, and not interchangeable.

Every id is an Almanac-owned string, stable for the life of the product.
**No external code (LOINC or otherwise) is seeded**, because none has been
verified against its issuing system. `lab_catalog_external_code` exists, carries
a `verified` flag, and unverified codes are never used for matching.

## Vitamins — 13 families, 24 entries

| Family | Entry | Almanac catalog id | Role |
|---|---|---|---|
| A | Retinol | `almanac:lab.vitamin-a.retinol` | direct |
|  | Beta-carotene | `almanac:lab.vitamin-a.beta-carotene` | **precursor** |
| B1 | Thiamine | `almanac:lab.vitamin-b1.thiamine` | direct |
|  | Thiamine pyrophosphate | `almanac:lab.vitamin-b1.thiamine-pyrophosphate` | direct |
| B2 | Riboflavin | `almanac:lab.vitamin-b2.riboflavin` | direct |
|  | EGRAC | `almanac:lab.vitamin-b2.egrac` | **functional marker** |
| B3 | Niacin | `almanac:lab.vitamin-b3.niacin` | direct |
| B5 | Pantothenic acid | `almanac:lab.vitamin-b5.pantothenic-acid` | direct |
| B6 | Pyridoxal 5-phosphate | `almanac:lab.vitamin-b6.plp` | direct |
| B7 | Biotin | `almanac:lab.vitamin-b7.biotin` | direct |
| B9 | Folate, serum | `almanac:lab.vitamin-b9.folate-serum` | direct |
|  | Folate, red cell | `almanac:lab.vitamin-b9.folate-rbc` | direct |
| B12 | Vitamin B12, total | `almanac:lab.vitamin-b12.total` | direct |
|  | Holotranscobalamin | `almanac:lab.vitamin-b12.holotranscobalamin` | direct |
|  | Methylmalonic acid | `almanac:lab.vitamin-b12.methylmalonic-acid` | **metabolic marker** |
| C | Ascorbic acid | `almanac:lab.vitamin-c.ascorbic-acid` | direct |
| D | 25-OH D, total | `almanac:lab.vitamin-d.25oh-total` | direct |
|  | 25-OH D2 | `almanac:lab.vitamin-d.25oh-d2` | direct |
|  | 25-OH D3 | `almanac:lab.vitamin-d.25oh-d3` | direct |
|  | 1,25-dihydroxy D | `almanac:lab.vitamin-d.1-25-dihydroxy` | direct |
| E | Alpha-tocopherol | `almanac:lab.vitamin-e.alpha-tocopherol` | direct |
|  | Gamma-tocopherol | `almanac:lab.vitamin-e.gamma-tocopherol` | direct |
| K | Phylloquinone (K1) | `almanac:lab.vitamin-k.phylloquinone` | direct |
|  | PIVKA-II | `almanac:lab.vitamin-k.pivka-ii` | **functional marker** |

### Why those three are not vitamin measurements

- **Methylmalonic acid** is a metabolite that accumulates when B12 is
  functionally insufficient. It measures MMA, not B12, and it moves in the
  *opposite direction* to a B12 level. Trending it beside a B12 result as
  though both were "B12" would invert the reading.
- **EGRAC** is an enzyme activation coefficient: how much a red-cell enzyme
  speeds up when riboflavin is added in vitro. It is a ratio, it has no
  riboflavin units, and a higher number means worse status.
- **PIVKA-II** is under-carboxylated prothrombin, a protein that appears when
  vitamin K is absent or antagonised. It measures a protein, not a vitamin.
- **Beta-carotene** is a dietary precursor the body converts to retinol.
  Conversion efficiency varies widely between people, so a normal
  beta-carotene does not establish vitamin A adequacy.

## Vitamin entries deliberately NOT seeded

Listing these is the point: a family name would have hidden them.

| Family | Not seeded | Why |
|---|---|---|
| A | Retinyl esters, alpha-carotene, lycopene, lutein | Rarely ordered outside research |
| B3 | N-methylnicotinamide, 2-pyridone | Urine metabolites; no matrix modelling in this slice |
| B6 | 4-pyridoxic acid, total B6 | PLP is the ordered form |
| B9 | Unmetabolised folic acid | Research assay |
| B9/B12 | Homocysteine | A shared metabolic marker for both; needs a many-to-many analyte→family link this slice does not have |
| D | 24,25-dihydroxy D, vitamin D binding protein, free 25-OH D | Specialist assays |
| E | Tocotrienols, lipid-adjusted tocopherol ratios | Needs a ratio wired to another analyte |
| K | Menaquinone-4, menaquinone-7, uncarboxylated osteocalcin | K2 forms are distinct from K1 and are not covered by the K1 entry |

## Haematology — CBC now complete

v0.1's "Complete blood count" had four members. That was not a complete blood
count, and it is now labelled and built as one: red indices, platelet indices
and a five-part differential — 15 members in `almanac:panel.cbc`.

| Added in 0.2 | Almanac catalog id |
|---|---|
| Red cell count | `almanac:lab.haematology.rbc` |
| Mean corpuscular volume | `almanac:lab.haematology.mcv` |
| Mean corpuscular haemoglobin | `almanac:lab.haematology.mch` |
| MCH concentration | `almanac:lab.haematology.mchc` |
| Red cell distribution width | `almanac:lab.haematology.rdw` |
| Mean platelet volume | `almanac:lab.haematology.mpv` |
| Neutrophils, absolute | `almanac:lab.haematology.neutrophils-absolute` |
| Lymphocytes, absolute | `almanac:lab.haematology.lymphocytes-absolute` |
| Monocytes, absolute | `almanac:lab.haematology.monocytes-absolute` |
| Eosinophils, absolute | `almanac:lab.haematology.eosinophils-absolute` |
| Basophils, absolute | `almanac:lab.haematology.basophils-absolute` |

Already present and retained with their original ids: haemoglobin,
haematocrit, WBC, platelets.

**The differential is seeded as absolute counts only.** Percentage forms are
tracked below, not implied.

## Remaining requested coverage — tracked, not claimed

| Area | Status |
|---|---|
| Differential percentages (neut %, lymph %, mono %, eos %, baso %) | **not seeded** — a percentage and an absolute count are different analytes, and `UnitRegistry` keeps `%` in its own dimension |
| Reticulocytes, nucleated RBC, immature granulocytes | **not seeded** |
| Liver panel beyond ALT/AST — ALP, GGT, bilirubin, albumin | **not seeded** |
| Full electrolytes — chloride, bicarbonate, calcium, magnesium, phosphate | **not seeded** (sodium and potassium are seeded) |
| Thyroid beyond TSH/FT4 — free T3, TPO antibodies | **not seeded** |
| Homocysteine | **not seeded** — see the vitamin table |
| Vitamin D binding protein, free 25-OH D | **not seeded** |
| Urinalysis | **not seeded** — `SpecimenKind.urine` exists and urine results store correctly; no urine analytes are catalogued |
| Verified LOINC codes | **none** — licensing unresolved; the table and `verified` flag are ready |
| Reference intervals in the catalog | **out of scope by decision** — ranges are preserved as the source printed them; no catalog fallback is applied |

Seeded totals: **24** vitamin-family entries, **37** core entries, **61**
analytes, **5** panels.

## Specimen

`lab_observation.specimen_kind` (migration 005) records blood, serum, plasma,
whole blood, urine, other, or unknown, alongside the source's own
`specimen_text`. It is optional and defaults to `unknown`, so an incomplete
manual entry is unaffected.

`SpecimenKind.directlyComparable` is deliberately strict: only an identical,
*stated* kind qualifies. Serum and plasma are kept apart, and `unknown` is
comparable with nothing — including another `unknown`, because two records that
both fail to say what they measured are not evidence that they match.
`observationsBySpecimen` groups an analyte's observations so a blood result and
a urine result cannot end up on one series.

## Aliases

Every analyte carries its canonical name plus abbreviations and spelling
variants; a subset carries an Arabic alias and an Arabic localized name.
Matching folds case, diacritics, punctuation, Arabic letter variants
(أ إ آ → ا, ى → ي, ة → ه) and Arabic-Indic digits.
`testNoAliasIsSharedByTwoAnalytes` asserts no fold maps to two analytes.

Not covered: fuzzy or nearest-neighbour matching. An unrecognised analyte
returns nil and the observation is stored unmatched with its source text intact.
