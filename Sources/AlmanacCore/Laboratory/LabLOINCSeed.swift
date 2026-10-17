import Foundation

/// The LOINC codes the catalog matches on, each with LOINC's long common name.
///
/// **The owner accepted the LOINC licence on 2026-10-16** (gate G5), and this is
/// what that answer built. Every code here was checked on 2026-10-16 against
/// the U.S. National Library of Medicine's LOINC lookup
/// (`clinicaltables.nlm.nih.gov/api/loinc_items/v3`), which serves LOINC's own
/// table: the code exists and its long common name names this analyte, in the
/// specimen and property the catalog means. One code a first draft listed
/// (56536-6, for thyroid peroxidase antibodies) turned out to be thyroglobulin
/// antibodies and was dropped; that is what the check is for.
///
/// Several codes per analyte, because LOINC splits by unit and method where
/// the catalog does not: mass and molar concentration, and the "by Automated
/// count" variants analysers report for a blood count. No analyte is given a
/// code LOINC does not have for it — beta-carotene (LOINC has carotene, which
/// is total carotenes), free 25-OH vitamin D and EGRAC have none here.
///
/// The long common name is stored with each code because the licence requires
/// a LOINC display name with every LOINC code. The notice is on the
/// Attributions page (`AttributionCatalog`, `loinc`).
///
/// This material contains content from LOINC (http://loinc.org). LOINC is
/// copyright © Regenstrief Institute, Inc. and the Logical Observation
/// Identifiers Names and Codes (LOINC) Committee and is available at no cost
/// under the license at http://loinc.org/license. LOINC® is a registered United
/// States trademark of Regenstrief Institute, Inc.
public enum LabLOINCSeed {
    public struct Code: Sendable, Hashable {
        public let analyteID: String
        public let code: String
        public let longCommonName: String
    }

    /// Who checked, and against what, for `lab_catalog_external_code.verified_by`.
    public static let verifiedBy = "NLM Clinical Tables LOINC lookup, 2026-10-16"

    static func L(_ analyteID: String, _ code: String, _ name: String) -> Code {
        Code(analyteID: analyteID, code: code, longCommonName: name)
    }

    public static let codes: [Code] = [
        L("almanac:lab.chemistry.albumin", "1751-7", "Albumin [Mass/volume] in Serum or Plasma"),
        L("almanac:lab.chemistry.albumin", "61151-7", "Albumin [Mass/volume] in Serum or Plasma by Bromocresol green (BCG) dye binding method"),
        L("almanac:lab.chemistry.alp", "6768-6", "Alkaline phosphatase [Enzymatic activity/volume] in Serum or Plasma"),
        L("almanac:lab.chemistry.alt", "1742-6", "Alanine aminotransferase [Enzymatic activity/volume] in Serum or Plasma"),
        L("almanac:lab.chemistry.ast", "1920-8", "Aspartate aminotransferase [Enzymatic activity/volume] in Serum or Plasma"),
        L("almanac:lab.chemistry.bicarbonate", "1963-8", "Bicarbonate [Moles/volume] in Serum or Plasma"),
        L("almanac:lab.chemistry.bilirubin-direct", "14629-0", "Bilirubin.direct [Moles/volume] in Serum or Plasma"),
        L("almanac:lab.chemistry.bilirubin-direct", "1968-7", "Bilirubin.direct [Mass/volume] in Serum or Plasma"),
        L("almanac:lab.chemistry.bilirubin-total", "14631-6", "Bilirubin.total [Moles/volume] in Serum or Plasma"),
        L("almanac:lab.chemistry.bilirubin-total", "1975-2", "Bilirubin.total [Mass/volume] in Serum or Plasma"),
        L("almanac:lab.chemistry.calcium", "17861-6", "Calcium [Mass/volume] in Serum or Plasma"),
        L("almanac:lab.chemistry.calcium", "2000-8", "Calcium [Moles/volume] in Serum or Plasma"),
        L("almanac:lab.chemistry.chloride", "2075-0", "Chloride [Moles/volume] in Serum or Plasma"),
        L("almanac:lab.chemistry.creatinine", "14682-9", "Creatinine [Moles/volume] in Serum or Plasma"),
        L("almanac:lab.chemistry.creatinine", "2160-0", "Creatinine [Mass/volume] in Serum or Plasma"),
        L("almanac:lab.chemistry.crp", "1988-5", "C reactive protein [Mass/volume] in Serum or Plasma"),
        L("almanac:lab.chemistry.crp", "30522-7", "C reactive protein [Mass/volume] in Serum or Plasma by High sensitivity method"),
        L("almanac:lab.chemistry.egfr", "33914-3", "Glomerular filtration rate [Volume Rate/Area] in Serum or Plasma by Creatinine-based formula (MDRD)/1.73 sq M"),
        L("almanac:lab.chemistry.egfr", "62238-1", "Glomerular filtration rate [Volume Rate/Area] in Serum, Plasma or Blood by Creatinine-based formula (CKD-EPI)/1.73 sq M"),
        L("almanac:lab.chemistry.egfr", "98979-8", "Glomerular filtration rate [Volume Rate/Area] in Serum, Plasma or Blood by Creatinine-based formula (CKD-EPI 2021)/1.73 sq M"),
        L("almanac:lab.chemistry.ggt", "2324-2", "Gamma glutamyl transferase [Enzymatic activity/volume] in Serum or Plasma"),
        L("almanac:lab.chemistry.glucose-fasting", "14771-0", "Fasting glucose [Moles/volume] in Serum or Plasma"),
        L("almanac:lab.chemistry.glucose-fasting", "1558-6", "Fasting glucose [Mass/volume] in Serum or Plasma"),
        L("almanac:lab.chemistry.hba1c", "17856-6", "Hemoglobin A1c/Hemoglobin.total in Blood by HPLC"),
        L("almanac:lab.chemistry.hba1c", "4548-4", "Hemoglobin A1c/Hemoglobin.total in Blood"),
        L("almanac:lab.chemistry.homocysteine", "13965-9", "Homocysteine [Moles/volume] in Serum or Plasma"),
        L("almanac:lab.chemistry.ionised-calcium", "17863-2", "Calcium.ionized [Mass/volume] in Serum or Plasma"),
        L("almanac:lab.chemistry.ionised-calcium", "1995-0", "Calcium.ionized [Moles/volume] in Serum or Plasma"),
        L("almanac:lab.chemistry.magnesium", "19123-9", "Magnesium [Mass/volume] in Serum or Plasma"),
        L("almanac:lab.chemistry.magnesium", "2601-3", "Magnesium [Moles/volume] in Serum or Plasma"),
        L("almanac:lab.chemistry.phosphate", "14879-1", "Phosphate [Moles/volume] in Serum or Plasma"),
        L("almanac:lab.chemistry.phosphate", "2777-1", "Phosphate [Mass/volume] in Serum or Plasma"),
        L("almanac:lab.chemistry.potassium", "2823-3", "Potassium [Moles/volume] in Serum or Plasma"),
        L("almanac:lab.chemistry.sodium", "2951-2", "Sodium [Moles/volume] in Serum or Plasma"),
        L("almanac:lab.chemistry.urea", "22664-7", "Urea [Moles/volume] in Serum or Plasma"),
        L("almanac:lab.chemistry.urea", "3091-6", "Urea [Mass/volume] in Serum or Plasma"),
        L("almanac:lab.chemistry.vitamin-d-binding-protein", "107221-4", "Calciferol binding protein [Mass/volume] in Serum or Plasma"),
        L("almanac:lab.chemistry.vitamin-d-binding-protein", "1991-9", "Calciferol binding proteins [Mass/volume] in Serum"),
        L("almanac:lab.haematology.basophils-absolute", "26444-0", "Basophils [#/volume] in Blood"),
        L("almanac:lab.haematology.basophils-absolute", "704-7", "Basophils [#/volume] in Blood by Automated count"),
        L("almanac:lab.haematology.basophils-percentage", "30180-4", "Basophils/Leukocytes in Blood"),
        L("almanac:lab.haematology.basophils-percentage", "706-2", "Basophils/Leukocytes in Blood by Automated count"),
        L("almanac:lab.haematology.eosinophils-absolute", "26449-9", "Eosinophils [#/volume] in Blood"),
        L("almanac:lab.haematology.eosinophils-absolute", "711-2", "Eosinophils [#/volume] in Blood by Automated count"),
        L("almanac:lab.haematology.eosinophils-percentage", "26450-7", "Eosinophils/Leukocytes in Blood"),
        L("almanac:lab.haematology.eosinophils-percentage", "713-8", "Eosinophils/Leukocytes in Blood by Automated count"),
        L("almanac:lab.haematology.haematocrit", "20570-8", "Hematocrit [Volume Fraction] of Blood by calculation"),
        L("almanac:lab.haematology.haematocrit", "4544-3", "Hematocrit [Volume Fraction] of Blood by Automated count"),
        L("almanac:lab.haematology.haemoglobin", "59260-0", "Hemoglobin [Moles/volume] in Blood"),
        L("almanac:lab.haematology.haemoglobin", "718-7", "Hemoglobin [Mass/volume] in Blood"),
        L("almanac:lab.haematology.lymphocytes-absolute", "26474-7", "Lymphocytes [#/volume] in Blood"),
        L("almanac:lab.haematology.lymphocytes-absolute", "731-0", "Lymphocytes [#/volume] in Blood by Automated count"),
        L("almanac:lab.haematology.lymphocytes-percentage", "26478-8", "Lymphocytes/Leukocytes in Blood"),
        L("almanac:lab.haematology.lymphocytes-percentage", "736-9", "Lymphocytes/Leukocytes in Blood by Automated count"),
        L("almanac:lab.haematology.mch", "28539-5", "MCH [Entitic mass]"),
        L("almanac:lab.haematology.mch", "785-6", "MCH [Entitic mass] by Automated count"),
        L("almanac:lab.haematology.mchc", "28540-3", "MCHC [Entitic Mass/volume] in Red Blood Cells"),
        L("almanac:lab.haematology.mchc", "786-4", "MCHC [Entitic Mass/volume] in Red Blood Cells by Automated count"),
        L("almanac:lab.haematology.mcv", "30428-7", "MCV [Entitic mean volume] in Red Blood Cells"),
        L("almanac:lab.haematology.mcv", "787-2", "MCV [Entitic mean volume] in Red Blood Cells by Automated count"),
        L("almanac:lab.haematology.monocytes-absolute", "26484-6", "Monocytes [#/volume] in Blood"),
        L("almanac:lab.haematology.monocytes-absolute", "742-7", "Monocytes [#/volume] in Blood by Automated count"),
        L("almanac:lab.haematology.monocytes-percentage", "26485-3", "Monocytes/Leukocytes in Blood"),
        L("almanac:lab.haematology.monocytes-percentage", "5905-5", "Monocytes/Leukocytes in Blood by Automated count"),
        L("almanac:lab.haematology.mpv", "28542-9", "Platelet [Entitic mean volume] in Blood"),
        L("almanac:lab.haematology.mpv", "32623-1", "Platelet [Entitic mean volume] in Blood by Automated count"),
        L("almanac:lab.haematology.neutrophils-absolute", "26499-4", "Neutrophils [#/volume] in Blood"),
        L("almanac:lab.haematology.neutrophils-absolute", "751-8", "Neutrophils [#/volume] in Blood by Automated count"),
        L("almanac:lab.haematology.neutrophils-percentage", "26511-6", "Neutrophils/Leukocytes in Blood"),
        L("almanac:lab.haematology.neutrophils-percentage", "770-8", "Neutrophils/Leukocytes in Blood by Automated count"),
        L("almanac:lab.haematology.platelets", "26515-7", "Platelets [#/volume] in Blood"),
        L("almanac:lab.haematology.platelets", "777-3", "Platelets [#/volume] in Blood by Automated count"),
        L("almanac:lab.haematology.rbc", "26453-1", "Erythrocytes [#/volume] in Blood"),
        L("almanac:lab.haematology.rbc", "789-8", "Erythrocytes [#/volume] in Blood by Automated count"),
        L("almanac:lab.haematology.rdw", "30385-9", "Erythrocyte [DistWidth] in Blood"),
        L("almanac:lab.haematology.rdw", "788-0", "Erythrocyte [DistWidth] in Blood by Automated count"),
        L("almanac:lab.haematology.reticulocytes-absolute", "14196-0", "Reticulocytes [#/volume] in Blood"),
        L("almanac:lab.haematology.reticulocytes-absolute", "60474-4", "Reticulocytes [#/volume] in Blood by Automated count"),
        L("almanac:lab.haematology.reticulocytes-percentage", "17849-1", "Reticulocytes/Erythrocytes in Blood by Automated count"),
        L("almanac:lab.haematology.reticulocytes-percentage", "4679-7", "Reticulocytes/Erythrocytes in Blood"),
        L("almanac:lab.haematology.wbc", "26464-8", "Leukocytes [#/volume] in Blood"),
        L("almanac:lab.haematology.wbc", "6690-2", "Leukocytes [#/volume] in Blood by Automated count"),
        L("almanac:lab.iron.ferritin", "14723-1", "Ferritin [Moles/volume] in Serum or Plasma"),
        L("almanac:lab.iron.ferritin", "2276-4", "Ferritin [Mass/volume] in Serum or Plasma"),
        L("almanac:lab.iron.serum-iron", "14798-3", "Iron [Moles/volume] in Serum or Plasma"),
        L("almanac:lab.iron.serum-iron", "2498-4", "Iron [Mass/volume] in Serum or Plasma"),
        L("almanac:lab.iron.tibc", "14800-7", "Iron binding capacity [Moles/volume] in Serum or Plasma"),
        L("almanac:lab.iron.tibc", "2500-7", "Iron binding capacity [Mass/volume] in Serum or Plasma"),
        L("almanac:lab.iron.transferrin-saturation", "14801-5", "Iron saturation [Molar fraction] in Serum or Plasma"),
        L("almanac:lab.iron.transferrin-saturation", "2502-3", "Iron saturation [Mass Fraction] in Serum or Plasma"),
        L("almanac:lab.lipids.hdl", "14646-4", "Cholesterol in HDL [Moles/volume] in Serum or Plasma"),
        L("almanac:lab.lipids.hdl", "2085-9", "Cholesterol in HDL [Mass/volume] in Serum or Plasma"),
        L("almanac:lab.lipids.ldl-calculated", "13457-7", "Cholesterol in LDL [Mass/volume] in Serum or Plasma by calculation"),
        L("almanac:lab.lipids.ldl-calculated", "39469-2", "Cholesterol in LDL [Moles/volume] in Serum or Plasma by calculation"),
        L("almanac:lab.lipids.total-cholesterol", "14647-2", "Cholesterol [Moles/volume] in Serum or Plasma"),
        L("almanac:lab.lipids.total-cholesterol", "2093-3", "Cholesterol [Mass/volume] in Serum or Plasma"),
        L("almanac:lab.lipids.triglycerides", "14927-8", "Triglyceride [Moles/volume] in Serum or Plasma"),
        L("almanac:lab.lipids.triglycerides", "2571-8", "Triglyceride [Mass/volume] in Serum or Plasma"),
        L("almanac:lab.serology.ana-titer", "5048-4", "Nuclear Ab [Titer] in Serum by Immunofluorescence"),
        L("almanac:lab.serology.hepatitis-b-surface-antigen", "5195-3", "Hepatitis B virus surface Ag [Presence] in Serum"),
        L("almanac:lab.serology.hepatitis-b-surface-antigen", "5196-1", "Hepatitis B virus surface Ag [Presence] in Serum or Plasma by Immunoassay"),
        L("almanac:lab.thyroid.free-t3", "14928-6", "Triiodothyronine (T3) Free [Moles/volume] in Serum or Plasma"),
        L("almanac:lab.thyroid.free-t3", "3051-0", "Triiodothyronine (T3) Free [Mass/volume] in Serum or Plasma"),
        L("almanac:lab.thyroid.free-t4", "14920-3", "Thyroxine (T4) free [Moles/volume] in Serum or Plasma"),
        L("almanac:lab.thyroid.free-t4", "3024-7", "Thyroxine (T4) free [Mass/volume] in Serum or Plasma"),
        L("almanac:lab.thyroid.tpo-antibodies", "8099-4", "Thyroperoxidase Ab [Units/volume] in Serum or Plasma"),
        L("almanac:lab.thyroid.tsh", "11580-8", "Thyrotropin [Units/volume] in Serum or Plasma by Detection limit <= 0.005 mIU/L"),
        L("almanac:lab.thyroid.tsh", "3016-3", "Thyrotropin [Units/volume] in Serum or Plasma"),
        L("almanac:lab.urine.bilirubin", "5770-3", "Bilirubin.total [Presence] in Urine by Test strip"),
        L("almanac:lab.urine.blood", "5794-3", "Hemoglobin [Presence] in Urine by Test strip"),
        L("almanac:lab.urine.glucose", "25428-4", "Glucose [Presence] in Urine by Test strip"),
        L("almanac:lab.urine.glucose", "5792-7", "Glucose [Mass/volume] in Urine by Test strip"),
        L("almanac:lab.urine.ketones", "2514-8", "Ketones [Presence] in Urine by Test strip"),
        L("almanac:lab.urine.ketones", "5797-6", "Ketones [Mass/volume] in Urine by Test strip"),
        L("almanac:lab.urine.leukocyte-esterase", "5799-2", "Leukocyte esterase [Presence] in Urine by Test strip"),
        L("almanac:lab.urine.nitrite", "5802-4", "Nitrite [Presence] in Urine by Test strip"),
        L("almanac:lab.urine.ph", "2756-5", "pH of Urine"),
        L("almanac:lab.urine.ph", "5803-2", "pH of Urine by Test strip"),
        L("almanac:lab.urine.protein", "20454-5", "Protein [Presence] in Urine by Test strip"),
        L("almanac:lab.urine.protein", "5804-0", "Protein [Mass/volume] in Urine by Test strip"),
        L("almanac:lab.urine.specific-gravity", "2965-2", "Specific gravity of Urine"),
        L("almanac:lab.urine.specific-gravity", "5811-5", "Specific gravity of Urine by Test strip"),
        L("almanac:lab.urine.urobilinogen", "5818-0", "Urobilinogen [Presence] in Urine by Test strip"),
        L("almanac:lab.vitamin-a.retinol", "14905-4", "Retinol [Moles/volume] in Serum or Plasma"),
        L("almanac:lab.vitamin-a.retinol", "2923-1", "Retinol [Mass/volume] in Serum or Plasma"),
        L("almanac:lab.vitamin-b1.thiamine", "20468-5", "Thiamine [Moles/volume] in Serum or Plasma"),
        L("almanac:lab.vitamin-b1.thiamine", "2999-1", "Thiamine [Mass/volume] in Serum or Plasma"),
        L("almanac:lab.vitamin-b1.thiamine-pyrophosphate", "74444-1", "Thiamine pyrophosphate [Moles/volume] in Blood"),
        L("almanac:lab.vitamin-b12.holotranscobalamin", "72160-5", "Holo-transcobalamin II [Moles/volume] in Serum"),
        L("almanac:lab.vitamin-b12.methylmalonic-acid", "13964-2", "Methylmalonate [Moles/volume] in Serum or Plasma"),
        L("almanac:lab.vitamin-b12.methylmalonic-acid", "2629-4", "Methylmalonate [Mass/volume] in Serum or Plasma"),
        L("almanac:lab.vitamin-b12.total", "14685-2", "Cobalamin (Vitamin B12) [Moles/volume] in Serum or Plasma"),
        L("almanac:lab.vitamin-b12.total", "2132-9", "Cobalamin (Vitamin B12) [Mass/volume] in Serum or Plasma"),
        L("almanac:lab.vitamin-b2.riboflavin", "2924-9", "Riboflavin [Mass/volume] in Serum or Plasma"),
        L("almanac:lab.vitamin-b2.riboflavin", "49038-3", "Riboflavin [Moles/volume] in Serum or Plasma"),
        L("almanac:lab.vitamin-b3.niacin", "18244-4", "Niacin [Mass/volume] in Serum or Plasma"),
        L("almanac:lab.vitamin-b3.niacin", "34342-6", "Niacin [Moles/volume] in Serum or Plasma"),
        L("almanac:lab.vitamin-b5.pantothenic-acid", "75066-1", "Pantothenate [Moles/volume] in Serum or Plasma"),
        L("almanac:lab.vitamin-b6.plp", "30552-4", "Pyridoxal phosphate [Mass/volume] in Serum or Plasma"),
        L("almanac:lab.vitamin-b6.plp", "62236-5", "Pyridoxal phosphate [Moles/volume] in Serum or Plasma"),
        L("almanac:lab.vitamin-b7.biotin", "1980-2", "Biotin [Mass/volume] in Serum or Plasma"),
        L("almanac:lab.vitamin-b7.biotin", "34398-8", "Biotin [Moles/volume] in Serum or Plasma"),
        L("almanac:lab.vitamin-b9.folate-rbc", "14731-4", "Folate [Moles/volume] in Red Blood Cells"),
        L("almanac:lab.vitamin-b9.folate-rbc", "2283-0", "Folate [Mass/volume] in Red Blood Cells"),
        L("almanac:lab.vitamin-b9.folate-serum", "14732-2", "Folate [Moles/volume] in Serum or Plasma"),
        L("almanac:lab.vitamin-b9.folate-serum", "2284-8", "Folate [Mass/volume] in Serum or Plasma"),
        L("almanac:lab.vitamin-c.ascorbic-acid", "14622-5", "Ascorbate [Moles/volume] in Serum or Plasma"),
        L("almanac:lab.vitamin-c.ascorbic-acid", "1903-4", "Ascorbate [Mass/volume] in Serum or Plasma"),
        L("almanac:lab.vitamin-d.1-25-dihydroxy", "62290-2", "1,25-Dihydroxyvitamin D [Mass/volume] in Serum or Plasma"),
        L("almanac:lab.vitamin-d.25oh-d2", "46269-7", "25-hydroxyvitamin D2 [Moles/volume] in Serum or Plasma"),
        L("almanac:lab.vitamin-d.25oh-d2", "49054-0", "25-hydroxyvitamin D2 [Mass/volume] in Serum or Plasma"),
        L("almanac:lab.vitamin-d.25oh-d3", "14635-7", "25-hydroxyvitamin D3 [Moles/volume] in Serum or Plasma"),
        L("almanac:lab.vitamin-d.25oh-d3", "1989-3", "25-hydroxyvitamin D3 [Mass/volume] in Serum or Plasma"),
        L("almanac:lab.vitamin-d.25oh-total", "62292-8", "25-Hydroxyvitamin D3+25-Hydroxyvitamin D2 [Mass/volume] in Serum or Plasma"),
        L("almanac:lab.vitamin-d.25oh-total", "68438-1", "25-Hydroxyvitamin D3+25-Hydroxyvitamin D2 [Moles/volume] in Serum or Plasma"),
        L("almanac:lab.vitamin-e.alpha-tocopherol", "14590-4", "Alpha tocopherol [Moles/volume] in Serum or Plasma"),
        L("almanac:lab.vitamin-e.alpha-tocopherol", "1823-4", "Alpha tocopherol [Mass/volume] in Serum or Plasma"),
        L("almanac:lab.vitamin-e.gamma-tocopherol", "59205-5", "Gamma tocopherol [Moles/volume] in Serum or Plasma"),
        L("almanac:lab.vitamin-e.gamma-tocopherol", "63370-1", "Gamma tocopherol [Mass/volume] in Serum or Plasma"),
        L("almanac:lab.vitamin-k.phylloquinone", "58793-1", "Phytonadione [Moles/volume] in Serum or Plasma"),
        L("almanac:lab.vitamin-k.phylloquinone", "9622-2", "Phytonadione [Mass/volume] in Serum or Plasma"),
        L("almanac:lab.vitamin-k.pivka-ii", "34444-0", "Acarboxyprothrombin [Mass/volume] in Serum or Plasma"),
        L("almanac:lab.vitamin-k.pivka-ii", "93768-0", "Acarboxyprothrombin [Units/volume] in Serum or Plasma"),
    ]

    public static func seed(into catalog: LabCatalogStore) throws {
        for entry in codes {
            try catalog.addExternalCode(system: "loinc", code: entry.code, to: entry.analyteID,
                                        verified: true, verifiedBy: verifiedBy,
                                        displayName: entry.longCommonName)
        }
    }
}
