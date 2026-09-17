# Almanac — Laboratory catalog coverage

**Version:** 0.1
**Date:** 2026-09-08
**Generated from:** `Sources/AlmanacCore/Laboratory/LabCatalogSeed.swift`
**Pinned by:** `CatalogCoverageTests` — `testEveryDocumentedVitaminFormIsSeeded`
asserts that the seeded vitamin set equals exactly the ids listed below, so this
document cannot silently drift from the code.

## How to read this

Coverage is claimed **per measurable form**, never per family name. "Vitamin D
is covered" is not a claim this document makes: 25-OH D total, 25-OH D2,
25-OH D3 and 1,25-dihydroxy D are four different analytes, measured by
different assays, reported in different units, and not interchangeable.

Every id is an Almanac-owned string that is stable for the life of the product.
**No external code (LOINC or otherwise) is seeded**, because none has been
verified against its issuing system. `lab_catalog_external_code` exists, carries
a `verified` flag, and unverified codes are never used for matching —
`testUnverifiedExternalCodeDoesNotMatch` and `testNoExternalCodeIsSeeded` hold
that line.

## Vitamins — 13 families, 24 distinct forms

| Family | Form | Almanac catalog id | Seeded | External code |
|---|---|---|:--:|:--:|
| A | Retinol | `almanac:lab.vitamin-a.retinol` | yes | none |
|  | Beta-carotene | `almanac:lab.vitamin-a.beta-carotene` | yes | none |
| B1 (thiamine) | Thiamine | `almanac:lab.vitamin-b1.thiamine` | yes | none |
|  | Thiamine pyrophosphate | `almanac:lab.vitamin-b1.thiamine-pyrophosphate` | yes | none |
| B2 (riboflavin) | Riboflavin | `almanac:lab.vitamin-b2.riboflavin` | yes | none |
|  | Erythrocyte glutathione reductase activation coefficient | `almanac:lab.vitamin-b2.egrac` | yes | none |
| B3 (niacin) | Niacin | `almanac:lab.vitamin-b3.niacin` | yes | none |
| B5 (pantothenic acid) | Pantothenic acid | `almanac:lab.vitamin-b5.pantothenic-acid` | yes | none |
| B6 | Pyridoxal 5-phosphate | `almanac:lab.vitamin-b6.plp` | yes | none |
| B7 (biotin) | Biotin | `almanac:lab.vitamin-b7.biotin` | yes | none |
| B9 (folate) | Folate, serum | `almanac:lab.vitamin-b9.folate-serum` | yes | none |
|  | Folate, red cell | `almanac:lab.vitamin-b9.folate-rbc` | yes | none |
| B12 | Vitamin B12, total | `almanac:lab.vitamin-b12.total` | yes | none |
|  | Holotranscobalamin | `almanac:lab.vitamin-b12.holotranscobalamin` | yes | none |
|  | Methylmalonic acid | `almanac:lab.vitamin-b12.methylmalonic-acid` | yes | none |
| C | Ascorbic acid | `almanac:lab.vitamin-c.ascorbic-acid` | yes | none |
| D | 25-hydroxyvitamin D, total | `almanac:lab.vitamin-d.25oh-total` | yes | none |
|  | 25-hydroxyvitamin D2 | `almanac:lab.vitamin-d.25oh-d2` | yes | none |
|  | 25-hydroxyvitamin D3 | `almanac:lab.vitamin-d.25oh-d3` | yes | none |
|  | 1,25-dihydroxyvitamin D | `almanac:lab.vitamin-d.1-25-dihydroxy` | yes | none |
| E | Alpha-tocopherol | `almanac:lab.vitamin-e.alpha-tocopherol` | yes | none |
|  | Gamma-tocopherol | `almanac:lab.vitamin-e.gamma-tocopherol` | yes | none |
| K | Phylloquinone | `almanac:lab.vitamin-k.phylloquinone` | yes | none |
|  | PIVKA-II | `almanac:lab.vitamin-k.pivka-ii` | yes | none |

Total seeded vitamin forms: **24** across **13** families.

## Vitamin forms deliberately NOT seeded

Listing these is the point of the exercise: a category name would have hidden
them. Each is a real measurable form that this slice does not cover.

| Family | Form not seeded | Why |
|---|---|---|
| A | Retinyl esters, other carotenoids (alpha-carotene, lycopene, lutein) | Rarely ordered outside research; add on demand. |
| B3 | N-methylnicotinamide, 2-pyridone (urinary metabolites) | Urine matrix; this slice models blood only. |
| B6 | 4-pyridoxic acid, total vitamin B6 | PLP is the ordered form; the others need a matrix field. |
| B9 | Unmetabolised folic acid | Research assay. |
| D | 24,25-dihydroxyvitamin D, vitamin D binding protein, free 25-OH D | Specialist assays. |
| E | Tocotrienols, lipid-adjusted tocopherol ratios | Ratio-to-lipid needs the ratio model wired to another analyte. |
| K | Menaquinone-4 and menaquinone-7 (K2 forms), uncarboxylated osteocalcin | K2 forms are distinct from K1 and are not covered by the K1 entry. |
| All | Urine and hair matrices for any vitamin | No specimen-matrix dimension in this slice. |

## Working core — 26 analytes

Seeded so a realistic report can be recorded end to end. Not a claim of
comprehensive chemistry coverage.

| Analyte | Almanac catalog id |
|---|---|
| Haemoglobin | `almanac:lab.haematology.haemoglobin` |
| Haematocrit | `almanac:lab.haematology.haematocrit` |
| White cell count | `almanac:lab.haematology.wbc` |
| Platelet count | `almanac:lab.haematology.platelets` |
| Ferritin | `almanac:lab.iron.ferritin` |
| Iron | `almanac:lab.iron.serum-iron` |
| Total iron binding capacity | `almanac:lab.iron.tibc` |
| Transferrin saturation | `almanac:lab.iron.transferrin-saturation` |
| Glucose, fasting | `almanac:lab.chemistry.glucose-fasting` |
| Haemoglobin A1c | `almanac:lab.chemistry.hba1c` |
| Creatinine | `almanac:lab.chemistry.creatinine` |
| Estimated GFR | `almanac:lab.chemistry.egfr` |
| Urea | `almanac:lab.chemistry.urea` |
| Sodium | `almanac:lab.chemistry.sodium` |
| Potassium | `almanac:lab.chemistry.potassium` |
| Alanine aminotransferase | `almanac:lab.chemistry.alt` |
| Aspartate aminotransferase | `almanac:lab.chemistry.ast` |
| C-reactive protein | `almanac:lab.chemistry.crp` |
| Cholesterol, total | `almanac:lab.lipids.total-cholesterol` |
| HDL cholesterol | `almanac:lab.lipids.hdl` |
| LDL cholesterol (calculated) | `almanac:lab.lipids.ldl-calculated` |
| Triglycerides | `almanac:lab.lipids.triglycerides` |
| Thyroid stimulating hormone | `almanac:lab.thyroid.tsh` |
| Free thyroxine | `almanac:lab.thyroid.free-t4` |
| Hepatitis B surface antigen | `almanac:lab.serology.hepatitis-b-surface-antigen` |
| Antinuclear antibody titre | `almanac:lab.serology.ana-titer` |

## Panels

Reusable templates, not report structure. A report may contain several panels
and loose analytes.

| Panel | Members |
|---|---|
| Complete blood count | haemoglobin, haematocrit, WBC, platelets |
| Lipid panel | total cholesterol, HDL, LDL (calculated), triglycerides |
| Thyroid panel | TSH, free T4 |
| Iron studies | ferritin, iron, TIBC, transferrin saturation |
| Vitamin panel | 25-OH D total, B12 total, serum folate, retinol, alpha-tocopherol |

User-defined panels use the same tables with `origin = 'user'`
(`testPanelsAreReusable`).

## Aliases

Every analyte carries its canonical name plus abbreviations and spelling
variants; a subset carries an Arabic alias and an Arabic localized name.
Matching folds case, diacritics, punctuation, Arabic letter variants
(أ إ آ → ا, ى → ي, ة → ه) and Arabic-Indic digits.
`testNoAliasIsSharedByTwoAnalytes` asserts no fold maps to two analytes, so a
match is never arbitrary.

Not covered: fuzzy or nearest-neighbour matching. An unrecognised analyte
returns nil and the observation is stored unmatched with its source text
intact (`testUnmatchedResultIsPreserved`).
