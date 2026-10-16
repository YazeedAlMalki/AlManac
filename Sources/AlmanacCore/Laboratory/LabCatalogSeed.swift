import Foundation

/// The seeded catalog for this slice.
///
/// Identity is Almanac's own and stable: `almanac:lab.<family>.<form>`.
/// External codes are LOINC only, each checked before it was seeded and stored
/// with LOINC's own name (`LabLOINCSeed`, owner G5, 2026-10-16); an unverified
/// code is never used for matching.
///
/// Vitamin families are enumerated by **distinct measurable form**, not by
/// family name. "Vitamin D" is not one analyte: 25-OH D total, 25-OH D2,
/// 25-OH D3 and 1,25-dihydroxy D are four, they are measured differently and
/// they are not interchangeable. `docs/features/laboratory-catalog-coverage.md`
/// lists each form against its seeded id, and `CatalogCoverageTests` asserts
/// that every id in that document exists here.
public enum LabCatalogSeed {

    public struct Entry: Sendable {
        public let id: String
        public let name: String
        public let family: String
        public let subfamily: String?
        public let form: String?
        public let valueType: LabValueType
        public let aliases: [String]
        public let arabic: String?
        public let role: MeasurementRole
    }

    static func e(_ id: String, _ name: String, _ family: String, _ subfamily: String?,
                  _ form: String?, _ type: LabValueType = .quantitative,
                  _ aliases: [String], _ arabic: String? = nil,
                  _ role: MeasurementRole = .direct) -> Entry {
        Entry(id: id, name: name, family: family, subfamily: subfamily, form: form,
              valueType: type, aliases: aliases, arabic: arabic, role: role)
    }

    // MARK: Vitamins — every family, every distinct form

    public static let vitamins: [Entry] = [
        e("almanac:lab.vitamin-a.retinol", "Retinol", "vitamin", "vitamin_a", "retinol",
          .quantitative, ["Retinol", "Vitamin A", "Vitamin A (retinol)"], "فيتامين أ"),
        // A dietary precursor the body converts to retinol — not a measurement
        // of vitamin A, and a normal beta-carotene does not establish adequacy.
        e("almanac:lab.vitamin-a.beta-carotene", "Beta-carotene", "vitamin", "vitamin_a",
          "beta_carotene", .quantitative, ["Beta carotene", "B-carotene", "Betacarotene"],
          nil, .precursor),

        e("almanac:lab.vitamin-b1.thiamine", "Thiamine", "vitamin", "vitamin_b1", "thiamine",
          .quantitative, ["Thiamine", "Thiamin", "Vitamin B1"], "فيتامين ب1"),
        e("almanac:lab.vitamin-b1.thiamine-pyrophosphate", "Thiamine pyrophosphate",
          "vitamin", "vitamin_b1", "thiamine_pyrophosphate", .quantitative,
          ["Thiamine pyrophosphate", "TPP", "Thiamine diphosphate", "TDP"]),

        e("almanac:lab.vitamin-b2.riboflavin", "Riboflavin", "vitamin", "vitamin_b2",
          "riboflavin", .quantitative, ["Riboflavin", "Vitamin B2"]),
        // An enzyme activation assay: how much a red-cell enzyme speeds up when
        // riboflavin is added. It reports a coefficient, never an amount of
        // riboflavin, so it is a functional marker of status.
        e("almanac:lab.vitamin-b2.egrac", "Erythrocyte glutathione reductase activation coefficient",
          "vitamin", "vitamin_b2", "egrac", .ratio, ["EGRAC", "Glutathione reductase activation"],
          nil, .functionalMarker),

        e("almanac:lab.vitamin-b3.niacin", "Niacin", "vitamin", "vitamin_b3", "niacin",
          .quantitative, ["Niacin", "Vitamin B3", "Nicotinic acid"]),

        e("almanac:lab.vitamin-b5.pantothenic-acid", "Pantothenic acid", "vitamin",
          "vitamin_b5", "pantothenic_acid", .quantitative,
          ["Pantothenic acid", "Vitamin B5"]),

        e("almanac:lab.vitamin-b6.plp", "Pyridoxal 5-phosphate", "vitamin", "vitamin_b6",
          "pyridoxal_5_phosphate", .quantitative,
          ["Pyridoxal 5 phosphate", "PLP", "P5P", "Vitamin B6"], "فيتامين ب6"),

        e("almanac:lab.vitamin-b7.biotin", "Biotin", "vitamin", "vitamin_b7", "biotin",
          .quantitative, ["Biotin", "Vitamin B7", "Vitamin H"]),

        e("almanac:lab.vitamin-b9.folate-serum", "Folate, serum", "vitamin", "vitamin_b9",
          "serum_folate", .quantitative,
          ["Folate", "Serum folate", "Folic acid", "Vitamin B9"], "حمض الفوليك"),
        e("almanac:lab.vitamin-b9.folate-rbc", "Folate, red cell", "vitamin", "vitamin_b9",
          "erythrocyte_folate", .quantitative,
          ["RBC folate", "Red cell folate", "Erythrocyte folate"]),

        e("almanac:lab.vitamin-b12.total", "Vitamin B12, total", "vitamin", "vitamin_b12",
          "total_cobalamin", .quantitative,
          ["Vitamin B12", "B12", "Cobalamin", "Total B12"], "فيتامين ب12"),
        e("almanac:lab.vitamin-b12.holotranscobalamin", "Holotranscobalamin", "vitamin",
          "vitamin_b12", "holotranscobalamin", .quantitative,
          ["Holotranscobalamin", "Active B12", "HoloTC"]),
        // A metabolite that accumulates when B12 is functionally insufficient.
        // It measures methylmalonic acid, not B12, and it rises as B12 status
        // falls — the opposite direction to a B12 level.
        e("almanac:lab.vitamin-b12.methylmalonic-acid", "Methylmalonic acid", "vitamin",
          "vitamin_b12", "methylmalonic_acid", .quantitative,
          ["Methylmalonic acid", "MMA"], nil, .metabolicMarker),

        e("almanac:lab.vitamin-c.ascorbic-acid", "Ascorbic acid", "vitamin", "vitamin_c",
          "ascorbic_acid", .quantitative,
          ["Vitamin C", "Ascorbic acid", "Ascorbate"], "فيتامين ج"),

        e("almanac:lab.vitamin-d.25oh-total", "25-hydroxyvitamin D, total", "vitamin",
          "vitamin_d", "25oh_total", .quantitative,
          ["25 OH Vitamin D", "25(OH)D", "Vitamin D total", "Vitamin D, 25-hydroxy",
           "25-hydroxyvitamin D"], "فيتامين د"),
        e("almanac:lab.vitamin-d.25oh-d2", "25-hydroxyvitamin D2", "vitamin", "vitamin_d",
          "25oh_d2", .quantitative, ["25 OH D2", "25-hydroxyvitamin D2", "Ergocalciferol"]),
        e("almanac:lab.vitamin-d.25oh-d3", "25-hydroxyvitamin D3", "vitamin", "vitamin_d",
          "25oh_d3", .quantitative, ["25 OH D3", "25-hydroxyvitamin D3", "Cholecalciferol"]),
        e("almanac:lab.vitamin-d.1-25-dihydroxy", "1,25-dihydroxyvitamin D", "vitamin",
          "vitamin_d", "1_25_dihydroxy", .quantitative,
          ["1,25 dihydroxyvitamin D", "Calcitriol", "1,25(OH)2D"]),
        // The unbound fraction of 25-OH D, measured directly or calculated from
        // total 25-OH D, DBP and albumin. A different quantity from the total
        // (most 25-OH D circulates bound), in different units, and never
        // interchangeable with it. Seeded 2026-10-15; source in `sources`.
        e("almanac:lab.vitamin-d.25oh-free", "25-hydroxyvitamin D, free", "vitamin",
          "vitamin_d", "25oh_free", .quantitative,
          ["Free 25 OH Vitamin D", "Free 25(OH)D", "Free vitamin D", "Free 25-hydroxyvitamin D"]),

        e("almanac:lab.vitamin-e.alpha-tocopherol", "Alpha-tocopherol", "vitamin",
          "vitamin_e", "alpha_tocopherol", .quantitative,
          ["Alpha tocopherol", "Vitamin E", "a-tocopherol"], "فيتامين هـ"),
        e("almanac:lab.vitamin-e.gamma-tocopherol", "Gamma-tocopherol", "vitamin",
          "vitamin_e", "gamma_tocopherol", .quantitative,
          ["Gamma tocopherol", "g-tocopherol"]),

        e("almanac:lab.vitamin-k.phylloquinone", "Phylloquinone", "vitamin", "vitamin_k",
          "phylloquinone", .quantitative, ["Phylloquinone", "Vitamin K1", "Vitamin K"]),
        // Under-carboxylated prothrombin, which appears when vitamin K is
        // absent or antagonised. A protein-based functional marker of K status,
        // not a measurement of vitamin K.
        e("almanac:lab.vitamin-k.pivka-ii", "PIVKA-II", "vitamin", "vitamin_k",
          "pivka_ii", .quantitative,
          ["PIVKA II", "Des-gamma-carboxy prothrombin", "DCP"], nil, .functionalMarker)
    ]

    /// The 24 vitamin-family entries are **not** 24 forms of vitamins.
    /// 20 are direct measurements; the other four are one precursor
    /// (beta-carotene), two functional markers (EGRAC, PIVKA-II) and one
    /// metabolic marker (methylmalonic acid). `CatalogCoverageTests` asserts
    /// these counts against the coverage document.
    public static var vitaminRoleCounts: [MeasurementRole: Int] {
        Dictionary(grouping: vitamins, by: \.role).mapValues(\.count)
    }

    // MARK: A working core, so a realistic report can be recorded

    public static let core: [Entry] = [
        e("almanac:lab.haematology.haemoglobin", "Haemoglobin", "haematology", nil, nil,
          .quantitative, ["Haemoglobin", "Hemoglobin", "Hb", "HGB"], "هيموغلوبين"),
        e("almanac:lab.haematology.haematocrit", "Haematocrit", "haematology", nil, nil,
          .quantitative, ["Haematocrit", "Hematocrit", "HCT", "PCV"]),
        e("almanac:lab.haematology.wbc", "White cell count", "haematology", nil, nil,
          .quantitative, ["WBC", "White blood cells", "Leucocytes", "White cell count"]),
        e("almanac:lab.haematology.platelets", "Platelet count", "haematology", nil, nil,
          .quantitative, ["Platelets", "PLT", "Platelet count"]),
        // Completing the CBC: a four-analyte "complete blood count" was not one.
        e("almanac:lab.haematology.rbc", "Red cell count", "haematology", nil, nil,
          .quantitative, ["RBC", "Red blood cells", "Red cell count", "Erythrocyte count"]),
        e("almanac:lab.haematology.mcv", "Mean corpuscular volume", "haematology", nil, nil,
          .quantitative, ["MCV", "Mean corpuscular volume", "Mean cell volume"]),
        e("almanac:lab.haematology.mch", "Mean corpuscular haemoglobin", "haematology", nil,
          nil, .quantitative, ["MCH", "Mean corpuscular hemoglobin"]),
        e("almanac:lab.haematology.mchc", "Mean corpuscular haemoglobin concentration",
          "haematology", nil, nil, .quantitative,
          ["MCHC", "Mean corpuscular hemoglobin concentration"]),
        e("almanac:lab.haematology.rdw", "Red cell distribution width", "haematology", nil,
          nil, .quantitative, ["RDW", "Red cell distribution width", "RDW-CV"]),
        e("almanac:lab.haematology.mpv", "Mean platelet volume", "haematology", nil, nil,
          .quantitative, ["MPV", "Mean platelet volume"]),
        e("almanac:lab.haematology.neutrophils-absolute", "Neutrophils, absolute",
          "haematology", nil, "absolute", .quantitative,
          ["Neutrophils", "Absolute neutrophils", "ANC", "Neutrophil count"]),
        e("almanac:lab.haematology.lymphocytes-absolute", "Lymphocytes, absolute",
          "haematology", nil, "absolute", .quantitative,
          ["Lymphocytes", "Absolute lymphocytes", "ALC", "Lymphocyte count"]),
        e("almanac:lab.haematology.monocytes-absolute", "Monocytes, absolute", "haematology",
          nil, "absolute", .quantitative,
          ["Monocytes", "Absolute monocytes", "Monocyte count"]),
        e("almanac:lab.haematology.eosinophils-absolute", "Eosinophils, absolute",
          "haematology", nil, "absolute", .quantitative,
          ["Eosinophils", "Absolute eosinophils", "Eosinophil count"]),
        e("almanac:lab.haematology.basophils-absolute", "Basophils, absolute", "haematology",
          nil, "absolute", .quantitative,
          ["Basophils", "Absolute basophils", "Basophil count"]),

        // The five percentage forms, seeded as five further analytes rather than
        // as a unit variant of the absolute counts above.
        //
        // A percentage and an absolute count are different measurements of the
        // same cell type, in different dimensions (`percentage` vs
        // `cellsPerVolume` in `UnitRegistry`), and they move independently — a
        // falling absolute count with a rising percentage is a real and common
        // finding. `docs/features/laboratory-catalog-coverage.md` recorded them
        // as "not seeded" for exactly that reason; this is that follow-up, and
        // the reason is now "seeded, and deliberately not interconvertible"
        // rather than "not claimed".
        //
        // They are deliberately *not* added to the CBC panel below. A full blood
        // count with differential reports the absolute counts; a laboratory that
        // also prints percentages is printing a derived view of the same numbers.
        // Putting them in the panel would make an import assign a percentage to a
        // report that never printed one.
        e("almanac:lab.haematology.neutrophils-percentage", "Neutrophils, percentage",
          "haematology", nil, "percentage", .quantitative,
          ["Neutrophils %", "Neutrophils percent", "% neutrophils", "Neutrophil percentage"]),
        e("almanac:lab.haematology.lymphocytes-percentage", "Lymphocytes, percentage",
          "haematology", nil, "percentage", .quantitative,
          ["Lymphocytes %", "Lymphocytes percent", "% lymphocytes", "Lymphocyte percentage"]),
        e("almanac:lab.haematology.monocytes-percentage", "Monocytes, percentage",
          "haematology", nil, "percentage", .quantitative,
          ["Monocytes %", "Monocytes percent", "% monocytes", "Monocyte percentage"]),
        e("almanac:lab.haematology.eosinophils-percentage", "Eosinophils, percentage",
          "haematology", nil, "percentage", .quantitative,
          ["Eosinophils %", "Eosinophils percent", "% eosinophils", "Eosinophil percentage"]),
        e("almanac:lab.haematology.basophils-percentage", "Basophils, percentage",
          "haematology", nil, "percentage", .quantitative,
          ["Basophils %", "Basophils percent", "% basophils", "Basophil percentage"]),

        // Reticulocytes, by the differential's rule: the bare name is the
        // absolute count and "%" is the percentage, two analytes in two
        // dimensions. Seeded 2026-10-15.
        e("almanac:lab.haematology.reticulocytes-absolute", "Reticulocytes, absolute",
          "haematology", nil, nil, .quantitative,
          ["Reticulocytes", "Reticulocyte count", "Absolute reticulocytes", "Retic count"]),
        e("almanac:lab.haematology.reticulocytes-percentage", "Reticulocytes, percentage",
          "haematology", nil, "percentage", .quantitative,
          ["Reticulocytes %", "Reticulocyte percentage", "% reticulocytes", "Retic %"]),

        e("almanac:lab.iron.ferritin", "Ferritin", "iron_studies", nil, nil, .quantitative,
          ["Ferritin", "Serum ferritin"], "فيريتين"),
        e("almanac:lab.iron.serum-iron", "Iron", "iron_studies", nil, nil, .quantitative,
          ["Iron", "Serum iron", "Fe"]),
        e("almanac:lab.iron.tibc", "Total iron binding capacity", "iron_studies", nil, nil,
          .quantitative, ["TIBC", "Total iron binding capacity"]),
        e("almanac:lab.iron.transferrin-saturation", "Transferrin saturation",
          "iron_studies", nil, nil, .quantitative,
          ["Transferrin saturation", "TSAT", "Iron saturation"]),

        e("almanac:lab.chemistry.glucose-fasting", "Glucose, fasting", "chemistry", nil, nil,
          .quantitative, ["Fasting glucose", "Glucose fasting", "FBG", "FPG"], "سكر صائم"),
        e("almanac:lab.chemistry.hba1c", "Haemoglobin A1c", "chemistry", nil, nil,
          .quantitative, ["HbA1c", "A1c", "Glycated haemoglobin", "Glycated hemoglobin"]),
        e("almanac:lab.chemistry.creatinine", "Creatinine", "chemistry", nil, nil,
          .quantitative, ["Creatinine", "Serum creatinine", "Cr"]),
        e("almanac:lab.chemistry.egfr", "Estimated GFR", "chemistry", nil, nil,
          .quantitative, ["eGFR", "Estimated GFR", "GFR estimated"]),
        e("almanac:lab.chemistry.urea", "Urea", "chemistry", nil, nil, .quantitative,
          ["Urea", "BUN", "Blood urea nitrogen"]),
        e("almanac:lab.chemistry.sodium", "Sodium", "chemistry", nil, nil, .quantitative,
          ["Sodium", "Na"]),
        e("almanac:lab.chemistry.potassium", "Potassium", "chemistry", nil, nil,
          .quantitative, ["Potassium", "K"]),
        // The rest of the panel, so "electrolytes" is a panel rather than the
        // two-analyte subset it was. Each is a distinct substance in a distinct
        // unit; none is derivable from another here, and a calcium that moved
        // while its ionised counterpart did not is exactly the kind of thing a
        // user needs both of for.
        e("almanac:lab.chemistry.chloride", "Chloride", "chemistry", nil, nil,
          .quantitative, ["Chloride", "Cl", "Serum chloride", "Chlorides"]),
        e("almanac:lab.chemistry.bicarbonate", "Bicarbonate", "chemistry", nil, nil,
          .quantitative, ["Bicarbonate", "HCO3", "HCO3-", "Total CO2", "Carbon dioxide"]),
        e("almanac:lab.chemistry.calcium", "Calcium, total", "chemistry", nil, nil,
          .quantitative, ["Calcium", "Total calcium", "Ca", "Serum calcium"]),
        e("almanac:lab.chemistry.ionised-calcium", "Calcium, ionised", "chemistry", nil, nil,
          .quantitative, ["Ionised calcium", "Ionized calcium", "Free calcium", "iCa"]),
        e("almanac:lab.chemistry.magnesium", "Magnesium", "chemistry", nil, nil,
          .quantitative, ["Magnesium", "Mg", "Serum magnesium"]),
        e("almanac:lab.chemistry.phosphate", "Phosphate", "chemistry", nil, nil,
          .quantitative, ["Phosphate", "Phosphorus", "PO4", "Serum phosphate"]),
        e("almanac:lab.chemistry.alt", "Alanine aminotransferase", "chemistry", nil, nil,
          .quantitative, ["ALT", "SGPT", "Alanine aminotransferase"]),
        e("almanac:lab.chemistry.ast", "Aspartate aminotransferase", "chemistry", nil, nil,
          .quantitative, ["AST", "SGOT", "Aspartate aminotransferase"]),
        // The liver panel beyond ALT/AST. Seeded 2026-10-15. Total and direct
        // bilirubin are two analytes; the bare name "Bilirubin" is the total,
        // which is what a report printing one bilirubin line means.
        e("almanac:lab.chemistry.alp", "Alkaline phosphatase", "chemistry", nil, nil,
          .quantitative, ["ALP", "Alk phos", "Alkaline phosphatase", "ALKP"]),
        e("almanac:lab.chemistry.ggt", "Gamma-glutamyl transferase", "chemistry", nil, nil,
          .quantitative, ["GGT", "Gamma GT", "GGTP", "Gamma glutamyl transferase",
                          "Gamma-glutamyltransferase"]),
        e("almanac:lab.chemistry.bilirubin-total", "Bilirubin, total", "chemistry", nil, "total",
          .quantitative, ["Total bilirubin", "Bilirubin", "TBIL", "T. bili", "Bilirubin total"]),
        e("almanac:lab.chemistry.bilirubin-direct", "Bilirubin, direct", "chemistry", nil, "direct",
          .quantitative, ["Direct bilirubin", "Conjugated bilirubin", "DBIL", "D. bili",
                          "Bilirubin direct"]),
        e("almanac:lab.chemistry.albumin", "Albumin", "chemistry", nil, nil,
          .quantitative, ["Albumin", "Serum albumin", "ALB"]),
        // Homocysteine is a marker for both B9 and B12, and the catalog has one
        // family per analyte, so it sits in chemistry rather than being claimed
        // by either vitamin. It measures homocysteine itself, hence `direct`.
        e("almanac:lab.chemistry.homocysteine", "Homocysteine", "chemistry", nil, nil,
          .quantitative, ["Homocysteine", "Total homocysteine", "tHcy", "Hcy"]),
        // The carrier protein, not a vitamin D measurement: its level is not set
        // by vitamin D status, so it is chemistry, not the vitamin family.
        e("almanac:lab.chemistry.vitamin-d-binding-protein", "Vitamin D binding protein",
          "chemistry", nil, nil, .quantitative,
          ["Vitamin D binding protein", "DBP", "VDBP", "Gc globulin", "Gc protein"]),
        e("almanac:lab.chemistry.crp", "C-reactive protein", "chemistry", nil, nil,
          .quantitative, ["CRP", "C reactive protein", "hs-CRP"]),

        e("almanac:lab.lipids.total-cholesterol", "Cholesterol, total", "lipids", nil, nil,
          .quantitative, ["Total cholesterol", "Cholesterol"]),
        e("almanac:lab.lipids.hdl", "HDL cholesterol", "lipids", nil, nil, .quantitative,
          ["HDL", "HDL cholesterol", "HDL-C"]),
        e("almanac:lab.lipids.ldl-calculated", "LDL cholesterol (calculated)", "lipids",
          nil, "calculated", .quantitative, ["LDL", "LDL cholesterol", "LDL-C"]),
        e("almanac:lab.lipids.triglycerides", "Triglycerides", "lipids", nil, nil,
          .quantitative, ["Triglycerides", "TG", "Trigs"]),

        e("almanac:lab.thyroid.tsh", "Thyroid stimulating hormone", "thyroid", nil, nil,
          .quantitative, ["TSH", "Thyroid stimulating hormone", "Thyrotropin"]),
        e("almanac:lab.thyroid.free-t4", "Free thyroxine", "thyroid", nil, nil,
          .quantitative, ["Free T4", "FT4", "Free thyroxine"]),

        e("almanac:lab.thyroid.free-t3", "Free triiodothyronine", "thyroid", nil, nil,
          .quantitative, ["Free T3", "FT3", "Free triiodothyronine"]),
        e("almanac:lab.thyroid.tpo-antibodies", "Thyroid peroxidase antibodies", "thyroid", nil, nil,
          .quantitative, ["TPO antibodies", "Anti-TPO", "TPOAb", "Anti thyroid peroxidase",
                          "Thyroid peroxidase antibodies", "Antithyroid peroxidase antibodies"]),

        // Urinalysis. Every name says "urine" unless the test exists only in
        // urine (leukocyte esterase, nitrite, urobilinogen, specific gravity),
        // so a blood line never matches a urine analyte. Dipstick results are
        // graded (negative, trace, 1+…), so they are ordinal; nitrite is
        // positive or negative. Seeded 2026-10-15.
        e("almanac:lab.urine.specific-gravity", "Urine specific gravity", "urinalysis", nil, nil,
          .quantitative, ["Specific gravity", "Urine specific gravity", "SG", "Sp gravity"]),
        e("almanac:lab.urine.ph", "Urine pH", "urinalysis", nil, nil,
          .quantitative, ["Urine pH", "pH urine", "pH, urine"]),
        e("almanac:lab.urine.protein", "Urine protein", "urinalysis", nil, nil,
          .ordinal, ["Urine protein", "Protein, urine", "Protein urine", "Urine albumin dipstick"]),
        e("almanac:lab.urine.glucose", "Urine glucose", "urinalysis", nil, nil,
          .ordinal, ["Urine glucose", "Glucose, urine", "Glucose urine"]),
        e("almanac:lab.urine.ketones", "Urine ketones", "urinalysis", nil, nil,
          .ordinal, ["Urine ketones", "Ketones, urine", "Ketones urine"]),
        e("almanac:lab.urine.blood", "Urine blood", "urinalysis", nil, nil,
          .ordinal, ["Urine blood", "Blood, urine", "Blood urine", "Urine haemoglobin",
                     "Urine hemoglobin"]),
        e("almanac:lab.urine.leukocyte-esterase", "Leukocyte esterase", "urinalysis", nil, nil,
          .ordinal, ["Leukocyte esterase", "Leucocyte esterase", "Urine leukocytes", "LEU"]),
        e("almanac:lab.urine.nitrite", "Urine nitrite", "urinalysis", nil, nil,
          .qualitativeCoded, ["Nitrite", "Nitrites", "Urine nitrite", "NIT"]),
        e("almanac:lab.urine.bilirubin", "Urine bilirubin", "urinalysis", nil, nil,
          .ordinal, ["Urine bilirubin", "Bilirubin, urine", "Bilirubin urine"]),
        e("almanac:lab.urine.urobilinogen", "Urobilinogen", "urinalysis", nil, nil,
          .ordinal, ["Urobilinogen", "Urine urobilinogen", "UBG"]),

        e("almanac:lab.serology.hepatitis-b-surface-antigen", "Hepatitis B surface antigen",
          "serology", nil, nil, .qualitativeCoded,
          ["HBsAg", "Hepatitis B surface antigen"]),
        e("almanac:lab.serology.ana-titer", "Antinuclear antibody titre", "serology", nil,
          nil, .titer, ["ANA", "Antinuclear antibody", "ANA titre", "ANA titer"])
    ]

    public static var all: [Entry] { vitamins + core }

    /// Where an analyte's identity is documented: what the test is called and
    /// what it measures. **Not a source of reference values** — the catalog
    /// holds none, and ranges stay as each laboratory printed them.
    ///
    /// Started 2026-10-15 for the analytes seeded that day; entries seeded
    /// earlier are not yet cited. MedlinePlus (U.S. National Library of
    /// Medicine) pages were each fetched on 2026-10-15 and returned HTTP 200.
    public struct Source: Sendable, Hashable {
        public let title: String
        public let url: String
    }

    static func medlinePlus(_ title: String, _ path: String) -> Source {
        Source(title: "MedlinePlus (U.S. National Library of Medicine): \(title)",
               url: "https://medlineplus.gov/\(path)")
    }

    static let bikleSchwartz2019 = Source(
        title: "Bikle DD, Schwartz J. Vitamin D Binding Protein, Total and Free Vitamin D Levels "
            + "in Different Physiological and Pathophysiological Conditions. "
            + "Frontiers in Endocrinology. 2019;10:317.",
        url: "https://doi.org/10.3389/fendo.2019.00317")

    public static let sources: [String: Source] = {
        let urinalysis = medlinePlus("Urinalysis", "ency/article/003579.htm")
        return [
            "almanac:lab.haematology.reticulocytes-absolute":
                medlinePlus("Reticulocyte Count", "lab-tests/reticulocyte-count/"),
            "almanac:lab.haematology.reticulocytes-percentage":
                medlinePlus("Reticulocyte Count", "lab-tests/reticulocyte-count/"),
            "almanac:lab.chemistry.alp":
                medlinePlus("Alkaline Phosphatase", "lab-tests/alkaline-phosphatase/"),
            "almanac:lab.chemistry.ggt":
                medlinePlus("Gamma-glutamyl Transferase (GGT) Test", "lab-tests/gamma-glutamyl-transferase-ggt-test/"),
            "almanac:lab.chemistry.bilirubin-total":
                medlinePlus("Bilirubin Blood Test", "lab-tests/bilirubin-blood-test/"),
            "almanac:lab.chemistry.bilirubin-direct":
                medlinePlus("Bilirubin Blood Test", "lab-tests/bilirubin-blood-test/"),
            "almanac:lab.chemistry.albumin":
                medlinePlus("Albumin Blood Test", "lab-tests/albumin-blood-test/"),
            "almanac:lab.thyroid.free-t3":
                medlinePlus("Triiodothyronine (T3) Tests", "lab-tests/triiodothyronine-t3-tests/"),
            "almanac:lab.thyroid.tpo-antibodies":
                medlinePlus("Thyroid Antibody Tests", "lab-tests/thyroid-antibody-tests/"),
            "almanac:lab.chemistry.homocysteine":
                medlinePlus("Homocysteine Test", "lab-tests/homocysteine-test/"),
            "almanac:lab.chemistry.vitamin-d-binding-protein": bikleSchwartz2019,
            "almanac:lab.vitamin-d.25oh-free": bikleSchwartz2019,
            "almanac:lab.urine.specific-gravity":
                medlinePlus("Urine specific gravity test", "ency/article/003587.htm"),
            "almanac:lab.urine.ph":
                medlinePlus("Urine pH test", "ency/article/003583.htm"),
            "almanac:lab.urine.protein":
                medlinePlus("Protein in Urine", "lab-tests/protein-in-urine/"),
            "almanac:lab.urine.glucose":
                medlinePlus("Glucose in Urine Test", "lab-tests/glucose-in-urine-test/"),
            "almanac:lab.urine.ketones":
                medlinePlus("Ketones in Urine", "lab-tests/ketones-in-urine/"),
            "almanac:lab.urine.blood":
                medlinePlus("Blood in Urine", "lab-tests/blood-in-urine/"),
            "almanac:lab.urine.leukocyte-esterase": urinalysis,
            "almanac:lab.urine.nitrite":
                medlinePlus("Nitrites in Urine", "lab-tests/nitrites-in-urine/"),
            "almanac:lab.urine.bilirubin":
                medlinePlus("Bilirubin in Urine", "lab-tests/bilirubin-in-urine/"),
            "almanac:lab.urine.urobilinogen":
                medlinePlus("Urobilinogen in Urine", "lab-tests/urobilinogen-in-urine/")
        ]
    }()

    public static let panels: [(id: String, name: String, members: [String])] = [
        // Complete, in the sense a laboratory means it: red indices, platelet
        // indices and a five-part differential. The differential is seeded as
        // absolute counts only; the percentage forms are tracked as not seeded
        // in docs/features/laboratory-catalog-coverage.md rather than implied.
        ("almanac:panel.cbc", "Complete blood count with differential", [
            "almanac:lab.haematology.rbc",
            "almanac:lab.haematology.haemoglobin",
            "almanac:lab.haematology.haematocrit",
            "almanac:lab.haematology.mcv",
            "almanac:lab.haematology.mch",
            "almanac:lab.haematology.mchc",
            "almanac:lab.haematology.rdw",
            "almanac:lab.haematology.platelets",
            "almanac:lab.haematology.mpv",
            "almanac:lab.haematology.wbc",
            "almanac:lab.haematology.neutrophils-absolute",
            "almanac:lab.haematology.lymphocytes-absolute",
            "almanac:lab.haematology.monocytes-absolute",
            "almanac:lab.haematology.eosinophils-absolute",
            "almanac:lab.haematology.basophils-absolute"
        ]),
        ("almanac:panel.lipids", "Lipid panel", [
            "almanac:lab.lipids.total-cholesterol",
            "almanac:lab.lipids.hdl",
            "almanac:lab.lipids.ldl-calculated",
            "almanac:lab.lipids.triglycerides"
        ]),
        ("almanac:panel.thyroid", "Thyroid panel", [
            "almanac:lab.thyroid.tsh",
            "almanac:lab.thyroid.free-t4"
        ]),
        // Seeded 2026-10-15. Free T3 and TPO antibodies are deliberately not
        // added to the thyroid panel above: a "thyroid panel" that grows would
        // make an older import's panel assign lines its report never printed.
        ("almanac:panel.liver", "Liver panel", [
            "almanac:lab.chemistry.alt",
            "almanac:lab.chemistry.ast",
            "almanac:lab.chemistry.alp",
            "almanac:lab.chemistry.ggt",
            "almanac:lab.chemistry.bilirubin-total",
            "almanac:lab.chemistry.bilirubin-direct",
            "almanac:lab.chemistry.albumin"
        ]),
        ("almanac:panel.urinalysis", "Urinalysis (dipstick)", [
            "almanac:lab.urine.specific-gravity",
            "almanac:lab.urine.ph",
            "almanac:lab.urine.protein",
            "almanac:lab.urine.glucose",
            "almanac:lab.urine.ketones",
            "almanac:lab.urine.blood",
            "almanac:lab.urine.leukocyte-esterase",
            "almanac:lab.urine.nitrite",
            "almanac:lab.urine.bilirubin",
            "almanac:lab.urine.urobilinogen"
        ]),
        ("almanac:panel.iron", "Iron studies", [
            "almanac:lab.iron.ferritin",
            "almanac:lab.iron.serum-iron",
            "almanac:lab.iron.tibc",
            "almanac:lab.iron.transferrin-saturation"
        ]),
        ("almanac:panel.vitamins", "Vitamin panel", [
            "almanac:lab.vitamin-d.25oh-total",
            "almanac:lab.vitamin-b12.total",
            "almanac:lab.vitamin-b9.folate-serum",
            "almanac:lab.vitamin-a.retinol",
            "almanac:lab.vitamin-e.alpha-tocopherol"
        ]),
        // Sodium, potassium, chloride, bicarbonate, calcium, ionised calcium,
        // magnesium and phosphate — the eight a "basic metabolic panel" or a
        // standalone electrolytes run reports.
        //
        // A *panel* here is a convenience grouping for the picker, not a claim
        // about what any one laboratory prints on any one form. Which of these
        // arrived on a given report is decided by that report's own text, and
        // the importer assigns what it finds.
        ("almanac:panel.electrolytes", "Electrolytes", [
            "almanac:lab.chemistry.sodium",
            "almanac:lab.chemistry.potassium",
            "almanac:lab.chemistry.chloride",
            "almanac:lab.chemistry.bicarbonate",
            "almanac:lab.chemistry.calcium",
            "almanac:lab.chemistry.ionised-calcium",
            "almanac:lab.chemistry.magnesium",
            "almanac:lab.chemistry.phosphate"
        ])
    ]

    public static func seed(into catalog: LabCatalogStore) throws {
        for entry in all {
            try catalog.upsert(CatalogAnalyte(
                id: entry.id, canonicalName: entry.name, family: entry.family,
                subfamily: entry.subfamily, form: entry.form,
                defaultValueType: entry.valueType, measurementRole: entry.role))
            try catalog.addAlias(entry.name, to: entry.id, locale: "en")
            for alias in entry.aliases {
                try catalog.addAlias(alias, to: entry.id, locale: "en")
            }
            if let arabic = entry.arabic {
                try catalog.addAlias(arabic, to: entry.id, locale: "ar")
                try catalog.setLocalizedName(arabic, for: entry.id, locale: "ar")
            }
            try catalog.setLocalizedName(entry.name, for: entry.id, locale: "en")
        }
        for panel in panels {
            try catalog.createPanel(id: panel.id, name: panel.name, analyteIDs: panel.members)
        }
        try LabLOINCSeed.seed(into: catalog)
    }
}
