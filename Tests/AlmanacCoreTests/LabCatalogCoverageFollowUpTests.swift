import Testing
import Foundation
@testable import AlmanacCore

/// The follow-up items the coverage document tracked as "not seeded": the five
/// differential percentages and the rest of the electrolytes panel.
///
/// The point of these tests is that the new analytes are *distinguishable*, not
/// merely present. Seeding "Neutrophils %" next to "Neutrophils" is the case that
/// found a real defect in `TextFold`, and a presence-only test would not have
/// caught it.
@Suite("Differential percentages and electrolytes")
struct LabCatalogCoverageFollowUpTests {
    let db: Database
    let catalog: LabCatalogStore

    init() throws {
        db = try TestDatabase()
        catalog = LabCatalogStore(db: db)
        try LabCatalogSeed.seed(into: catalog)
    }

    private func id(_ catalogID: String) throws -> CatalogAnalyte {
        try #require(try catalog.analyte(catalogID), "\(catalogID) is not seeded")
    }

    private func matches(_ text: String) throws -> String? {
        try catalog.match(sourceText: text)?.analyteID
    }

    // MARK: - The fold, which is where the defect was

    @Test("A percent sign survives the fold as its own token")
    func percentSurvivesTheFold() {
        #expect(TextFold.fold("Neutrophils %") == "neutrophils pct")
        #expect(TextFold.fold("Neutrophils") == "neutrophils")
        #expect(TextFold.fold("Neutrophils %") != TextFold.fold("Neutrophils"))
        #expect(TextFold.fold("100%") == "100 pct")
    }

    @Test("The fold still erases the differences that carry no identity")
    func foldStillErasesDecoration() {
        #expect(TextFold.fold("HbA1c") == TextFold.fold("HBA1C"))
        #expect(TextFold.fold("Ionised calcium") == TextFold.fold("ionised-calcium"))
    }

    @Test("A report line reading 'Neutrophils %' matches the percentage, not the absolute")
    func percentLineMatchesThePercentage() throws {
        #expect(try matches("Neutrophils %") == "almanac:lab.haematology.neutrophils-percentage")
        #expect(try matches("Neutrophils") == "almanac:lab.haematology.neutrophils-absolute")
    }

    /// Before the fold kept `%`, every one of these pairs resolved to the
    /// absolute count, and `testNoAliasIsSharedByTwoAnalytes` failed on all five
    /// at once. The aliases are checked through the database rather than through
    /// the seed, so what is asserted is what an import would actually match.
    @Test("All five percentage and absolute pairs resolve to different analytes")
    func everyPairIsDistinguishable() throws {
        for cell in ["neutrophils", "lymphocytes", "monocytes", "eosinophils", "basophils"] {
            let absolute = "almanac:lab.haematology.\(cell)-absolute"
            let percentage = "almanac:lab.haematology.\(cell)-percentage"
            let name = cell.capitalized
            #expect(try matches(name) == absolute, "\(name) should be the absolute count")
            #expect(try matches("\(name) %") == percentage, "\(name) % should be the percentage")
        }
    }

    // MARK: - The five percentages

    @Test("All five differential percentages are seeded")
    func allFivePercentagesSeeded() throws {
        for cell in ["neutrophils", "lymphocytes", "monocytes", "eosinophils", "basophils"] {
            let percentage = try id("almanac:lab.haematology.\(cell)-percentage")
            #expect(percentage.family == "haematology")
            #expect(percentage.form == "percentage")
        }
    }

    /// The percentages are derived views of the absolute counts, so a report that
    /// prints both has printed one number two ways. Putting them in the CBC panel
    /// would make an import assign a value the report never stated.
    @Test("The percentages are seeded but not in the CBC panel")
    func percentagesAreNotInTheCBCPanel() throws {
        let cbc = try #require(LabCatalogSeed.panels.first { $0.id == "almanac:panel.cbc" })
        for cell in ["neutrophils", "lymphocytes", "monocytes", "eosinophils", "basophils"] {
            #expect(cbc.members.contains("almanac:lab.haematology.\(cell)-absolute"))
            #expect(!cbc.members.contains("almanac:lab.haematology.\(cell)-percentage"))
        }
        // And the panel the app reads agrees, rather than the seed's own list
        // being the only witness.
        #expect(try catalog.panelMembers("almanac:panel.cbc").count == cbc.members.count)
    }

    // MARK: - Electrolytes

    @Test("The electrolytes panel is a panel, not a two-analyte subset")
    func electrolytesPanelIsComplete() throws {
        let panel = try #require(LabCatalogSeed.panels.first { $0.id == "almanac:panel.electrolytes" })
        #expect(panel.name == "Electrolytes")
        #expect(panel.members.count == 8)
        for member in panel.members { _ = try id(member) }
        for expected in ["sodium", "potassium", "chloride", "bicarbonate", "calcium",
                         "ionised-calcium", "magnesium", "phosphate"] {
            #expect(panel.members.contains("almanac:lab.chemistry.\(expected)"))
        }
        #expect(try catalog.panelMembers("almanac:panel.electrolytes").count == 8)
    }

    @Test("Total and ionised calcium are two analytes, not one with two units")
    func calciumIsTwoAnalytes() throws {
        let total = try id("almanac:lab.chemistry.calcium")
        let ionised = try id("almanac:lab.chemistry.ionised-calcium")
        #expect(total.id != ionised.id)
        #expect(try matches("Calcium") == total.id)
        #expect(try matches("Ionised calcium") == ionised.id)
    }

    @Test("The new analytes did not steal an abbreviation already in use")
    func newAliasesDoNotStealExistingOnes() throws {
        #expect(try matches("Chloride") == "almanac:lab.chemistry.chloride")
        #expect(try matches("Cl") == "almanac:lab.chemistry.chloride")
        #expect(try matches("Phosphate") == "almanac:lab.chemistry.phosphate")
        #expect(try matches("K") == "almanac:lab.chemistry.potassium")
        #expect(try matches("Na") == "almanac:lab.chemistry.sodium")
    }

    @Test("Every panel member exists, so no panel names a phantom analyte")
    func everyPanelMemberExists() throws {
        for (panelID, _, members) in LabCatalogSeed.panels {
            for member in members {
                #expect(try catalog.analyte(member) != nil, "\(panelID) → \(member)")
            }
        }
    }
}
