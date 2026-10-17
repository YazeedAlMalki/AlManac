import Testing
import Foundation
@testable import AlmanacCore

/// The rest of `docs/features/laboratory-catalog-coverage.md`'s "not seeded"
/// table (Slice 7, 2026-10-15): reticulocytes, the liver panel beyond ALT/AST,
/// free T3, TPO antibodies, homocysteine, vitamin D binding protein, free
/// 25-OH D, and urinalysis.
///
/// Every one of these carries a source citation, and none carries a reference
/// interval: ranges stay as each laboratory printed them (coverage doc,
/// "Reference intervals in the catalog — out of scope by decision").
@Suite("Remaining catalog coverage")
struct LabCatalogRemainingCoverageTests {
    let catalog: LabCatalogStore

    init() throws {
        catalog = LabCatalogStore(db: try TestDatabase())
        try LabCatalogSeed.seed(into: catalog)
    }

    /// Written out here rather than read from the seed, so the test states what
    /// was asked for instead of agreeing with whatever was seeded.
    static let added: [String] = [
        "almanac:lab.haematology.reticulocytes-absolute",
        "almanac:lab.haematology.reticulocytes-percentage",
        "almanac:lab.chemistry.alp",
        "almanac:lab.chemistry.ggt",
        "almanac:lab.chemistry.bilirubin-total",
        "almanac:lab.chemistry.bilirubin-direct",
        "almanac:lab.chemistry.albumin",
        "almanac:lab.thyroid.free-t3",
        "almanac:lab.thyroid.tpo-antibodies",
        "almanac:lab.chemistry.homocysteine",
        "almanac:lab.chemistry.vitamin-d-binding-protein",
        "almanac:lab.vitamin-d.25oh-free",
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
    ]

    private func matches(_ text: String) throws -> String? {
        try catalog.match(sourceText: text)?.analyteID
    }

    @Test("Every requested analyte is seeded")
    func allSeeded() throws {
        for id in Self.added {
            #expect(try catalog.analyte(id) != nil, "\(id) is not seeded")
        }
    }

    @Test("Every requested analyte cites a source with a title and an https link")
    func allCited() throws {
        for id in Self.added {
            let source = LabCatalogSeed.sources[id]
            #expect(source != nil, "\(id) has no source citation")
            #expect(source?.title.isEmpty == false, "\(id)'s citation has no title")
            #expect(source?.url.hasPrefix("https://") == true, "\(id)'s citation has no link")
        }
    }

    @Test("A citation is never attached to an id that is not seeded")
    func noOrphanCitations() throws {
        let seeded = Set(LabCatalogSeed.all.map(\.id))
        for id in LabCatalogSeed.sources.keys {
            #expect(seeded.contains(id), "\(id) is cited but not seeded")
        }
    }

    @Test("The liver analytes match their usual printed names")
    func liver() throws {
        #expect(try matches("ALP") == "almanac:lab.chemistry.alp")
        #expect(try matches("Alkaline phosphatase") == "almanac:lab.chemistry.alp")
        #expect(try matches("GGT") == "almanac:lab.chemistry.ggt")
        #expect(try matches("Gamma GT") == "almanac:lab.chemistry.ggt")
        #expect(try matches("Total bilirubin") == "almanac:lab.chemistry.bilirubin-total")
        #expect(try matches("Bilirubin") == "almanac:lab.chemistry.bilirubin-total")
        #expect(try matches("Direct bilirubin") == "almanac:lab.chemistry.bilirubin-direct")
        #expect(try matches("Albumin") == "almanac:lab.chemistry.albumin")
        // The existing pair is untouched.
        #expect(try matches("ALT") == "almanac:lab.chemistry.alt")
        #expect(try matches("AST") == "almanac:lab.chemistry.ast")
    }

    @Test("Reticulocytes follow the differential's rule: the bare name is the count, '%' is the percentage")
    func reticulocytes() throws {
        #expect(try matches("Reticulocytes") == "almanac:lab.haematology.reticulocytes-absolute")
        #expect(try matches("Reticulocytes %") == "almanac:lab.haematology.reticulocytes-percentage")
    }

    @Test("Thyroid, homocysteine and the vitamin D forms match")
    func thyroidAndOthers() throws {
        #expect(try matches("Free T3") == "almanac:lab.thyroid.free-t3")
        #expect(try matches("FT3") == "almanac:lab.thyroid.free-t3")
        #expect(try matches("Anti-TPO") == "almanac:lab.thyroid.tpo-antibodies")
        #expect(try matches("Free T4") == "almanac:lab.thyroid.free-t4", "the existing FT4 is untouched")
        #expect(try matches("Homocysteine") == "almanac:lab.chemistry.homocysteine")
        #expect(try matches("Vitamin D binding protein") == "almanac:lab.chemistry.vitamin-d-binding-protein")
        #expect(try matches("Free 25-OH vitamin D") == "almanac:lab.vitamin-d.25oh-free")
        #expect(try matches("25 OH Vitamin D") == "almanac:lab.vitamin-d.25oh-total",
                "a total 25-OH D is not read as the free fraction")
    }

    @Test("Urine analytes are named as urine, and never take a blood analyte's name")
    func urinalysis() throws {
        #expect(try matches("Urine glucose") == "almanac:lab.urine.glucose")
        #expect(try matches("Urine protein") == "almanac:lab.urine.protein")
        #expect(try matches("Urine bilirubin") == "almanac:lab.urine.bilirubin")
        #expect(try matches("Leukocyte esterase") == "almanac:lab.urine.leukocyte-esterase")
        #expect(try matches("Nitrite") == "almanac:lab.urine.nitrite")
        #expect(try matches("Urobilinogen") == "almanac:lab.urine.urobilinogen")
        #expect(try matches("Specific gravity") == "almanac:lab.urine.specific-gravity")
        #expect(try matches("Urine pH") == "almanac:lab.urine.ph")
        // A bare blood-chemistry name stays with blood.
        #expect(try matches("Bilirubin") == "almanac:lab.chemistry.bilirubin-total")
        #expect(try matches("Fasting glucose") == "almanac:lab.chemistry.glucose-fasting")
    }

    @Test("Dipstick results are graded, not measured: their value type says so")
    func urineValueTypes() throws {
        #expect(try catalog.analyte("almanac:lab.urine.protein")?.defaultValueType == .ordinal)
        #expect(try catalog.analyte("almanac:lab.urine.nitrite")?.defaultValueType == .qualitativeCoded)
        #expect(try catalog.analyte("almanac:lab.urine.specific-gravity")?.defaultValueType == .quantitative)
    }

    @Test("Homocysteine and the binding protein are not counted as vitamin measurements")
    func notVitamins() throws {
        let vitamins = Set(try catalog.analyteIDs(family: "vitamin"))
        #expect(!vitamins.contains("almanac:lab.chemistry.homocysteine"))
        #expect(!vitamins.contains("almanac:lab.chemistry.vitamin-d-binding-protein"))
        #expect(vitamins.contains("almanac:lab.vitamin-d.25oh-free"))
    }

    @Test("The liver and urinalysis panels name only seeded analytes")
    func panels() throws {
        #expect(try catalog.panelMembers("almanac:panel.liver").count == 7)
        #expect(try catalog.panelMembers("almanac:panel.urinalysis").count == 10)
    }
}
