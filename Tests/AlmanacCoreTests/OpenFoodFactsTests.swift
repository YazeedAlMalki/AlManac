import Testing
import Foundation
@testable import AlmanacCore

/// Open Food Facts products on the shipped file (owner, 2026-10-19): their
/// own tables, licence group C, read through the catalog like any food.
@Suite("Open Food Facts products")
struct OpenFoodFactsTests {
    let db = try! TestDatabase()
    var catalog: NutritionCatalog { NutritionCatalog(db: db) }
    let tuna = SourceIdentifier(namespace: .openFoodFacts, localID: "0032894015518")

    init() throws {
        try OpenFoodFactsBundle.installIfNeeded(into: db)
    }

    @Test("The bundled file installs once")
    func installsOnce() throws {
        let count = try #require(try db.query("SELECT COUNT(*) AS n FROM off_product;").first?.int("n"))
        #expect(count > 3000)
        #expect(try OpenFoodFactsBundle.installIfNeeded(into: db) == nil)
    }

    @Test("Every row is licence group C and none enters the reference tables")
    func keptApart() throws {
        #expect(try db.query("SELECT 1 FROM off_product WHERE licence_group <> 'C';").isEmpty)
        #expect(try db.query("SELECT 1 FROM nutrition_food WHERE food_ref LIKE 'off:%';").isEmpty)
        #expect(try catalog.food(tuna)?.licenceGroup == .shareAlike)
        #expect(try catalog.food(tuna)?.sourceName == "Open Food Facts products")
    }

    @Test("A product is found by name and by barcode, with or without leading zeros")
    func search() throws {
        #expect(try catalog.search("light solid tuna").contains { $0.ref == tuna })
        #expect(try catalog.search("32894015518").contains { $0.ref == tuna })
    }

    @Test("Values, calories and the label's serving come through the catalog")
    func valuesAndServing() throws {
        #expect(try catalog.bases(for: tuna) == [.per100g])
        let protein = try #require(try catalog.values(for: tuna, basis: .per100g).first { $0.nutrientID == "protein" })
        #expect(abs((protein.amount ?? 0) - 18.46) < 0.01)
        #expect(protein.qualifier == .borrowed)
        #expect(protein.licenceGroup == .shareAlike)
        #expect(try catalog.energy(for: tuna, basis: .per100g) != nil)
        #expect(try catalog.grams(of: tuna, amount: 2, unit: "serving") == 260)
    }

    @Test("Every barcode of a merged record resolves to that record")
    func mergedBarcodes() throws {
        let record = SourceIdentifier(namespace: .openFoodFacts, localID: "0012000051692")
        for code in ["0012000002977", "0012000052590", "0012000051692"] {
            let food = try #require(try catalog.food(SourceIdentifier(namespace: .openFoodFacts, localID: code)))
            #expect(food.ref == record, "\(code)")
        }
        let hits = try catalog.search("mountain dew").filter { $0.ref.namespace == .openFoodFacts }
        #expect(hits.filter { $0.ref == record }.count == 1, "one record, not one row per barcode")
    }

    @Test("The allergen filter withholds products by name like any food")
    func allergenFilter() throws {
        let results = try catalog.search("peanut", excluding: [.peanuts])
        #expect(results.foods.allSatisfy { !$0.primaryName.lowercased().contains("peanut") })
        #expect(results.blocked.contains { $0.ref.namespace == .openFoodFacts })
    }
}
