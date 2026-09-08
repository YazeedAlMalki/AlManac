import Foundation

/// The seeded catalog for this slice.
///
/// Identity is Almanac's own and stable: `almanac:lab.<family>.<form>`. No
/// external code is seeded, because none has been verified against its issuing
/// system — `lab_catalog_external_code` exists and carries a `verified` flag so
/// codes can be added once checked, and an unverified code is never used for
/// matching.
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
    }

    static func e(_ id: String, _ name: String, _ family: String, _ subfamily: String?,
                  _ form: String?, _ type: LabValueType = .quantitative,
                  _ aliases: [String], _ arabic: String? = nil) -> Entry {
        Entry(id: id, name: name, family: family, subfamily: subfamily, form: form,
              valueType: type, aliases: aliases, arabic: arabic)
    }

    // MARK: Vitamins — every family, every distinct form

    public static let vitamins: [Entry] = [
        e("almanac:lab.vitamin-a.retinol", "Retinol", "vitamin", "vitamin_a", "retinol",
          .quantitative, ["Retinol", "Vitamin A", "Vitamin A (retinol)"], "فيتامين أ"),
        e("almanac:lab.vitamin-a.beta-carotene", "Beta-carotene", "vitamin", "vitamin_a",
          "beta_carotene", .quantitative, ["Beta carotene", "B-carotene", "Betacarotene"]),

        e("almanac:lab.vitamin-b1.thiamine", "Thiamine", "vitamin", "vitamin_b1", "thiamine",
          .quantitative, ["Thiamine", "Thiamin", "Vitamin B1"], "فيتامين ب1"),
        e("almanac:lab.vitamin-b1.thiamine-pyrophosphate", "Thiamine pyrophosphate",
          "vitamin", "vitamin_b1", "thiamine_pyrophosphate", .quantitative,
          ["Thiamine pyrophosphate", "TPP", "Thiamine diphosphate", "TDP"]),

        e("almanac:lab.vitamin-b2.riboflavin", "Riboflavin", "vitamin", "vitamin_b2",
          "riboflavin", .quantitative, ["Riboflavin", "Vitamin B2"]),
        e("almanac:lab.vitamin-b2.egrac", "Erythrocyte glutathione reductase activation coefficient",
          "vitamin", "vitamin_b2", "egrac", .ratio, ["EGRAC", "Glutathione reductase activation"]),

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
        e("almanac:lab.vitamin-b12.methylmalonic-acid", "Methylmalonic acid", "vitamin",
          "vitamin_b12", "methylmalonic_acid", .quantitative,
          ["Methylmalonic acid", "MMA"]),

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

        e("almanac:lab.vitamin-e.alpha-tocopherol", "Alpha-tocopherol", "vitamin",
          "vitamin_e", "alpha_tocopherol", .quantitative,
          ["Alpha tocopherol", "Vitamin E", "a-tocopherol"], "فيتامين هـ"),
        e("almanac:lab.vitamin-e.gamma-tocopherol", "Gamma-tocopherol", "vitamin",
          "vitamin_e", "gamma_tocopherol", .quantitative,
          ["Gamma tocopherol", "g-tocopherol"]),

        e("almanac:lab.vitamin-k.phylloquinone", "Phylloquinone", "vitamin", "vitamin_k",
          "phylloquinone", .quantitative, ["Phylloquinone", "Vitamin K1", "Vitamin K"]),
        e("almanac:lab.vitamin-k.pivka-ii", "PIVKA-II", "vitamin", "vitamin_k",
          "pivka_ii", .quantitative,
          ["PIVKA II", "Des-gamma-carboxy prothrombin", "DCP"])
    ]

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
        e("almanac:lab.chemistry.alt", "Alanine aminotransferase", "chemistry", nil, nil,
          .quantitative, ["ALT", "SGPT", "Alanine aminotransferase"]),
        e("almanac:lab.chemistry.ast", "Aspartate aminotransferase", "chemistry", nil, nil,
          .quantitative, ["AST", "SGOT", "Aspartate aminotransferase"]),
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

        e("almanac:lab.serology.hepatitis-b-surface-antigen", "Hepatitis B surface antigen",
          "serology", nil, nil, .qualitativeCoded,
          ["HBsAg", "Hepatitis B surface antigen"]),
        e("almanac:lab.serology.ana-titer", "Antinuclear antibody titre", "serology", nil,
          nil, .titer, ["ANA", "Antinuclear antibody", "ANA titre", "ANA titer"])
    ]

    public static var all: [Entry] { vitamins + core }

    public static let panels: [(id: String, name: String, members: [String])] = [
        ("almanac:panel.cbc", "Complete blood count", [
            "almanac:lab.haematology.haemoglobin",
            "almanac:lab.haematology.haematocrit",
            "almanac:lab.haematology.wbc",
            "almanac:lab.haematology.platelets"
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
        ])
    ]

    public static func seed(into catalog: LabCatalogStore) throws {
        for entry in all {
            try catalog.upsert(CatalogAnalyte(
                id: entry.id, canonicalName: entry.name, family: entry.family,
                subfamily: entry.subfamily, form: entry.form,
                defaultValueType: entry.valueType))
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
    }
}
