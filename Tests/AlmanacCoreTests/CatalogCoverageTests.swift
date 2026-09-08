import XCTest
@testable import AlmanacCore

/// Pins the catalog against `docs/features/laboratory-catalog-coverage.md`.
///
/// The point is that coverage is asserted per **form**, never inferred from a
/// family name: "vitamin D is covered" is not a claim this test can make, and
/// four separate ids are.
final class CatalogCoverageTests: XCTestCase {

    static let expectedVitaminIDs: Set<String> = [
        "almanac:lab.vitamin-a.retinol",
        "almanac:lab.vitamin-a.beta-carotene",
        "almanac:lab.vitamin-b1.thiamine",
        "almanac:lab.vitamin-b1.thiamine-pyrophosphate",
        "almanac:lab.vitamin-b2.riboflavin",
        "almanac:lab.vitamin-b2.egrac",
        "almanac:lab.vitamin-b3.niacin",
        "almanac:lab.vitamin-b5.pantothenic-acid",
        "almanac:lab.vitamin-b6.plp",
        "almanac:lab.vitamin-b7.biotin",
        "almanac:lab.vitamin-b9.folate-serum",
        "almanac:lab.vitamin-b9.folate-rbc",
        "almanac:lab.vitamin-b12.total",
        "almanac:lab.vitamin-b12.holotranscobalamin",
        "almanac:lab.vitamin-b12.methylmalonic-acid",
        "almanac:lab.vitamin-c.ascorbic-acid",
        "almanac:lab.vitamin-d.25oh-total",
        "almanac:lab.vitamin-d.25oh-d2",
        "almanac:lab.vitamin-d.25oh-d3",
        "almanac:lab.vitamin-d.1-25-dihydroxy",
        "almanac:lab.vitamin-e.alpha-tocopherol",
        "almanac:lab.vitamin-e.gamma-tocopherol",
        "almanac:lab.vitamin-k.phylloquinone",
        "almanac:lab.vitamin-k.pivka-ii"
    ]

    static let expectedVitaminFamilies: Set<String> = [
        "vitamin_a", "vitamin_b1", "vitamin_b2", "vitamin_b3", "vitamin_b5",
        "vitamin_b6", "vitamin_b7", "vitamin_b9", "vitamin_b12", "vitamin_c",
        "vitamin_d", "vitamin_e", "vitamin_k"
    ]

    private func seeded() throws -> (Database, LabCatalogStore) {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let catalog = LabCatalogStore(db: db)
        try LabCatalogSeed.seed(into: catalog)
        return (db, catalog)
    }

    func testEveryDocumentedVitaminFormIsSeeded() throws {
        let (_, catalog) = try seeded()
        let seeded = Set(try catalog.analyteIDs(family: "vitamin"))
        XCTAssertEqual(seeded, Self.expectedVitaminIDs)
    }

    func testEveryVitaminFamilyIsPresentAndNamedBySubfamily() throws {
        let (db, _) = try seeded()
        let families = Set(try db.query("""
            SELECT DISTINCT subfamily FROM lab_catalog_analyte WHERE family = 'vitamin';
            """).compactMap { $0.string("subfamily") })
        XCTAssertEqual(families, Self.expectedVitaminFamilies)
    }

    func testFamiliesWithSeveralFormsCarryDistinctAnalytes() throws {
        let (db, _) = try seeded()
        for (subfamily, count) in [("vitamin_d", 4), ("vitamin_b12", 3), ("vitamin_b9", 2),
                                   ("vitamin_e", 2), ("vitamin_k", 2), ("vitamin_a", 2),
                                   ("vitamin_b1", 2), ("vitamin_b2", 2)] {
            let n = Int(try db.query("""
                SELECT COUNT(*) AS n FROM lab_catalog_analyte WHERE subfamily = ?;
                """, [.text(subfamily)]).first?.int("n") ?? 0)
            XCTAssertEqual(n, count, "\(subfamily) should carry \(count) distinct forms")
            let forms = try db.query("""
                SELECT form FROM lab_catalog_analyte WHERE subfamily = ?;
                """, [.text(subfamily)]).compactMap { $0.string("form") }
            XCTAssertEqual(Set(forms).count, count, "\(subfamily) forms must be distinct")
        }
    }

    // Not every entry in a vitamin family measures the vitamin. Classifying
    // them is what stops "24 vitamin forms" from being a false claim.
    func testVitaminEntriesAreClassifiedByWhatTheyMeasure() throws {
        let (db, _) = try seeded()
        func role(_ id: String) throws -> String? {
            try db.query("SELECT measurement_role FROM lab_catalog_analyte WHERE id = ?;",
                         [.text(id)]).first?.string("measurement_role")
        }
        XCTAssertEqual(try role("almanac:lab.vitamin-b12.methylmalonic-acid"), "metabolic_marker",
                       "MMA is a metabolite that rises when B12 is short, not a B12 measurement")
        XCTAssertEqual(try role("almanac:lab.vitamin-b2.egrac"), "functional_marker",
                       "EGRAC is an enzyme activation coefficient, not an amount of riboflavin")
        XCTAssertEqual(try role("almanac:lab.vitamin-k.pivka-ii"), "functional_marker",
                       "PIVKA-II is under-carboxylated prothrombin, not vitamin K")
        XCTAssertEqual(try role("almanac:lab.vitamin-a.beta-carotene"), "precursor",
                       "beta-carotene is converted to retinol; it is not retinol")
        XCTAssertEqual(try role("almanac:lab.vitamin-d.25oh-total"), "direct")
        XCTAssertEqual(try role("almanac:lab.vitamin-b12.holotranscobalamin"), "direct",
                       "the active B12 fraction is still a B12 measurement")
    }

    func testTheVitaminCountIsNotOverstated() throws {
        let (_, catalog) = try seeded()
        XCTAssertEqual(try catalog.analyteIDs(family: "vitamin").count, 24,
                       "24 catalog entries in vitamin families")
        XCTAssertEqual(try catalog.directAnalyteIDs(family: "vitamin").count, 20,
                       "of which 20 are direct measurements — not 24 vitamin forms")
        XCTAssertEqual(LabCatalogSeed.vitaminRoleCounts[.precursor], 1)
        XCTAssertEqual(LabCatalogSeed.vitaminRoleCounts[.functionalMarker], 2)
        XCTAssertEqual(LabCatalogSeed.vitaminRoleCounts[.metabolicMarker], 1)
        XCTAssertFalse(MeasurementRole.functionalMarker.reportsAmountOfTheSubstance)
        XCTAssertTrue(MeasurementRole.direct.reportsAmountOfTheSubstance)
    }

    // A four-analyte "complete blood count" was not complete.
    func testCBCPanelIsComplete() throws {
        let (_, catalog) = try seeded()
        let members = try catalog.panelMembers("almanac:panel.cbc")
        XCTAssertEqual(members.count, 15)
        for suffix in ["rbc", "haemoglobin", "haematocrit", "mcv", "mch", "mchc", "rdw",
                       "platelets", "mpv", "wbc", "neutrophils-absolute",
                       "lymphocytes-absolute", "monocytes-absolute",
                       "eosinophils-absolute", "basophils-absolute"] {
            XCTAssertTrue(members.contains("almanac:lab.haematology.\(suffix)"),
                          "CBC is missing \(suffix)")
        }
    }

    func testNoAliasIsSharedByTwoAnalytes() throws {
        let (db, _) = try seeded()
        let clashes = try db.query("""
            SELECT alias_fold, COUNT(DISTINCT analyte_id) AS n
            FROM lab_catalog_alias GROUP BY alias_fold HAVING n > 1;
            """).compactMap { $0.string("alias_fold") }
        XCTAssertEqual(clashes, [], "an ambiguous alias would make matching arbitrary")
    }

    func testNoExternalCodeIsSeeded() throws {
        let (db, _) = try seeded()
        let n = Int(try db.query("SELECT COUNT(*) AS n FROM lab_catalog_external_code;")
                        .first?.int("n") ?? 0)
        XCTAssertEqual(n, 0, "no external code is seeded unverified")
    }

    func testLocalizationIsStoredPerLocale() throws {
        let (_, catalog) = try seeded()
        XCTAssertEqual(try catalog.localizedName(for: "almanac:lab.vitamin-d.25oh-total",
                                                 locale: "ar"), "فيتامين د")
        XCTAssertEqual(try catalog.localizedName(for: "almanac:lab.iron.ferritin",
                                                 locale: "en"), "Ferritin")
    }

    func testFoldingNormalisesScriptAndPunctuation() {
        XCTAssertEqual(TextFold.fold("25(OH)D"), "25 oh d")
        XCTAssertEqual(TextFold.fold("  Hb  "), "hb")
        XCTAssertEqual(TextFold.fold("Café"), "cafe")
        XCTAssertEqual(TextFold.fold("إسم"), TextFold.fold("اسم"))
        XCTAssertEqual(TextFold.fold("٢٥"), "25")
    }
}
