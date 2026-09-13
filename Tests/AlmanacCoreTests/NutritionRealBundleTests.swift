import XCTest
@testable import AlmanacCore

/// The real bundle, end to end: tools/nutrition's output imported through the
/// device-side licence assertion and read back. Opt-in, because the bundle lives in
/// the food-data lake rather than the repository:
///
///     ALMANAC_NUTRITION_BUNDLE=~/ALManac-food-data/build/almanac.sqlite swift test \
///         --filter NutritionRealBundleTests
final class NutritionRealBundleTests: XCTestCase {

    func testTheRealBundleImportsThroughTheGuardAndAgreesWithUSDAsOwnFigure() throws {
        guard let path = ProcessInfo.processInfo.environment["ALMANAC_NUTRITION_BUNDLE"] else {
            throw XCTSkip("set ALMANAC_NUTRITION_BUNDLE to a bundle built by tools/nutrition")
        }
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let report = try NutritionReferenceImporter(db: db).importBundle(at: (path as NSString).expandingTildeInPath)
        XCTAssertEqual(report.namespaces, [.afcd, .ciqual, .cofid, .usda])
        XCTAssertEqual(report.foodCount, 8354)
        XCTAssertEqual(report.valueCount, 49036)

        let catalog = NutritionCatalog(db: db)
        func ref(_ text: String) -> SourceIdentifier { SourceIdentifier(parsing: text)! }

        // No token became a number anywhere.
        XCTAssertEqual(try db.query("""
            SELECT COUNT(*) AS n FROM nutrition_value
            WHERE source_value IN ('Tr', 'N', 'traces', '-') AND amount IS NOT NULL;
            """).first?.int("n"), 0)

        // CoFID ackee has no AOAC fibre, so it shows CoFID's own 151 kcal, labelled as CoFID's.
        let ackee = try XCTUnwrap(try catalog.energy(for: ref("cofid:13-145"), basis: .per100g))
        XCTAssertEqual(ackee.method, .publisherReported)
        XCTAssertEqual(ackee.kilocalories, 151)

        // Both foods behind CoFID's repeated code 13-669 are there, and findable.
        XCTAssertEqual(try catalog.food(ref("cofid:13-669@row2827"))?.primaryName, "Watercress, raw")
        XCTAssertTrue(try catalog.search("watercress").map(\.ref).contains(ref("cofid:13-669@row2827")))

        // AlmanacCore's general Atwater against USDA's own published general-Atwater
        // figure (nutrient 2047): an independent check of the calorie implementation.
        var differences: [Double] = []
        for row in try db.query("""
            SELECT food_ref, amount FROM nutrition_value
            WHERE nutrient_id = 'energy_general_atwater_kcal' AND amount IS NOT NULL;
            """) {
            guard let food = row.string("food_ref").flatMap(SourceIdentifier.init(parsing:)),
                  let published = row.double("amount"),
                  let estimate = try catalog.energy(for: food, basis: .per100g),
                  estimate.method == .generalAtwater else { continue }
            differences.append(abs(estimate.kilocalories - published))
        }
        XCTAssertGreaterThanOrEqual(differences.count, 300)
        XCTAssertLessThan(differences.sorted()[differences.count / 2], 0.5, "median |Almanac − USDA 2047| in kcal")
    }
}
