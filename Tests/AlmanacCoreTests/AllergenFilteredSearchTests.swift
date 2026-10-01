import Foundation
import Testing
@testable import AlmanacCore

/// The allergen filter as it behaves on a real catalog query.
///
/// `FoodAllergenTests` covers the vocabulary and the verdict in isolation. These
/// cover the part that only shows up against SQL: that the filter is applied at
/// all, that it costs no extra queries, and that what it leaves behind is
/// reported rather than implied.
@Suite("Allergen-filtered food search")
struct AllergenFilteredSearchTests {

    /// A catalog with the foods the tests reason about, named as a shop would.
    private func seeded() throws -> (Database, NutritionCatalog) {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        try db.execute("""
        INSERT INTO nutrition_source (namespace, dataset_id, name, release, licence, licence_group, attribution, url)
        VALUES ('cofid', 'cofid_2021', 'CoFID 2021', '2021', 'Open Government Licence v3.0', 'B',
                'Contains public sector information licensed under the Open Government Licence v3.0.',
                'https://www.gov.uk/');
        """)
        // Named so each one is a decision: two are caught by name, one is not
        // caught at all, and one would be caught only by the over-matching words
        // that are documented as accepted.
        let foods: [(localId: String, name: String, group: String)] = [
            ("1", "Peanut Sauce, Satay", "Sauces"),
            ("2", "Chicken Satay Skewers", "Meat dishes"),
            ("3", "Apple Juice, Unsweetened", "Fruit drinks"),
            ("4", "Cheddar Cheese, Mature", "Cheese"),
            ("5", "Almond Butter, Smooth", "Nut butters"),
            ("6", "Mixed Salad Leaves", "Leaf vegetables")
        ]
        for food in foods {
            // `food_ref` is derived, and the table enforces that it is
            // `namespace || ':' || local_id` rather than trusting the caller.
            let ref = "cofid:\(food.localId)"
            try db.execute("""
            INSERT INTO nutrition_food (food_ref, namespace, local_id, licence_group,
                                        food_group_code, food_group_name, source_record)
            VALUES ('\(ref)', 'cofid', '\(food.localId)', 'B', 'DG', '\(food.group)', 'fixture');
            INSERT INTO nutrition_food_name (food_ref, language, name, is_primary, name_fold)
            VALUES ('\(ref)', 'en', '\(food.name)', 1, '\(TextFold.fold(food.name))');
            """)
        }
        return (db, NutritionCatalog(db: db))
    }

    // MARK: - The filter runs

    @Test("A food naming an allergen is withheld")
    func allergenBearingFoodIsWithheld() throws {
        let (_, catalog) = try seeded()
        let results = try catalog.search("satay", excluding: [.peanuts])
        #expect(results.foods.map(\.primaryName) == ["Chicken Satay Skewers"])
        #expect(results.effect.removed == 1)
        #expect(results.effect.kept == 1)
        #expect(results.effect.triggeredBy == [.peanuts])
        // And it is withheld rather than flagged: the blocking verdict is kept
        // separately so a screen can say what was hidden, and the food is not in
        // `foods` at all.
        #expect(results.blocked.count == 1)
        #expect(results.verdict(for: results.foods[0].ref).status == .noDeclaration)
    }

    @Test("A withheld food arrives named, not just as a catalogue key")
    func withheldFoodCarriesItsName() throws {
        let (_, catalog) = try seeded()
        let results = try catalog.search("satay", excluding: [.peanuts])

        // The name is the only part of a withheld row a reader can act on.
        // `cofid:1` identifies nothing they can use, so a screen built on the ref
        // alone shows a receipt rather than an explanation.
        let hidden = try #require(results.blocked.first)
        // The *display* name, commas and all. `name_fold` would give
        // "peanut sauce satay", which the reader holding a jar of peanut sauce
        // cannot match against the label in front of them.
        #expect(hidden.name == "Peanut Sauce, Satay")
        #expect(hidden.verdict.declares(.peanuts))
        #expect(hidden.verdict.reason == "Names Peanuts")
        #expect(hidden.ref.description == "cofid:1")
    }

    @Test("Withheld foods come back in name order")
    func withheldFoodsAreSortedByName() throws {
        // Order is a lookup property, not a tidiness one: the list is shown when a
        // search came back empty, and the reader's question is whether the food
        // they wanted is on it.
        let (db, catalog) = try seeded()
        try db.execute("""
        INSERT INTO nutrition_food (food_ref, namespace, local_id, licence_group,
                                    food_group_code, food_group_name, source_record)
        VALUES ('cofid:7', 'cofid', '7', 'B', 'DG', 'Sauces', 'fixture');
        INSERT INTO nutrition_food_name (food_ref, language, name, is_primary, name_fold)
        VALUES ('cofid:7', 'en', 'Peanut Satay Sauce, Spicy', 1, 'peanut satay sauce spicy');
        """)
        let results = try catalog.search("satay", excluding: [.peanuts])

        // Both foods are withheld, so the assertion is about order and not about
        // which of the two the filter caught — a search for "satay" that also
        // matched something safe would put a third row in `kept` and make this
        // about something else.
        // "Peanut Satay…" before "Peanut Sauce,…": `name_fold` agrees, because
        // "sat" < "sau". Catalog order happens to be name order too — the sort is
        // there so that stays true when the catalogue is not sorted, not to fix
        // this fixture.
        #expect(results.blocked.map(\.name) == ["Peanut Satay Sauce, Spicy",
                                                "Peanut Sauce, Satay"])
        // And the one safe match survives, so the two lists are complementary
        // rather than one being a copy of the other with names changed.
        #expect(results.foods.map(\.primaryName) == ["Chicken Satay Skewers"])
    }

    @Test("No allergens means exactly the old behaviour")
    func noAllergensIsUnfiltered() throws {
        let (_, catalog) = try seeded()
        let plain = try catalog.search("satay")
        let gated = try catalog.search("satay", excluding: [])
        #expect(gated.foods.map(\.primaryName) == plain.map(\.primaryName))
        #expect(gated.foods.count == 2)
        #expect(gated.effect.removed == 0)
        #expect(gated.isFiltered == false)
        #expect(gated.note == nil)
        // Every kept food is `.notApplicable` rather than `.noDeclaration`:
        // there was no question to answer.
        #expect(gated.verdicts.values.allSatisfy { $0.status == .notApplicable })
    }

    @Test("Two allergens, one food caught by each")
    func twoAllergens() throws {
        // The report names only the allergens that actually caused a removal, not
        // the ones that were checked. Somebody with milk and peanut allergies who
        // searches "cheddar" should not be told their peanut allergy was involved.
        let (_, catalog) = try seeded()
        let cheese = try catalog.search("cheddar", excluding: [.peanuts, .milk])
        #expect(cheese.foods.isEmpty)
        #expect(cheese.effect.removed == 1)
        #expect(cheese.effect.triggeredBy == [.milk])
        #expect(cheese.effect.explanation == "Hidden 1 food naming Milk.")
    }

    // MARK: - What the filter cannot do

    @Test("A silent food stays, and the disclaimer is still shown")
    func silentFoodStaysWithDisclaimer() throws {
        // The case the whole design turns on. "Apple Juice" says nothing about
        // peanuts, so it is not withheld — and the screen still has to say the
        // app was only reading names.
        let (_, catalog) = try seeded()
        let results = try catalog.search("apple", excluding: [.peanuts])
        #expect(results.foods.count == 1)
        #expect(results.verdict(for: results.foods[0].ref).status == .noDeclaration)
        #expect(results.effect.removed == 0)
        #expect(results.effect.explanation == nil)
        #expect(results.disclaimer != nil)
        #expect(results.note?.contains("no ingredient lists") == true)
    }

    @Test("Over-matching survives the round trip into real query results")
    func overMatchingOnRealResults() throws {
        // "Almond Butter" contains "butter", so a milk allergy hides a nut butter.
        // Documented on `FoodAllergen.nameWords` as the accepted direction, and
        // checked here because a word table that behaves in isolation and not in a
        // query is a word table that has been miswired.
        let (_, catalog) = try seeded()
        let milk = try catalog.search("almond", excluding: [.milk])
        #expect(milk.foods.isEmpty)
        #expect(milk.effect.triggeredBy == [.milk])

        // And the same food is visible to somebody who is not allergic to milk.
        #expect(try catalog.search("almond", excluding: [.peanuts]).foods.count == 1)
    }

    // MARK: - Truncation

    @Test("A short list says whether it is truncated")
    func truncationIsReported() throws {
        let (_, catalog) = try seeded()
        // limit 1 with two satay matches: the SQL cut it, so there may be more.
        let capped = try catalog.search("satay", limit: 1, excluding: [.peanuts])
        #expect(capped.foods.count == 1)
        #expect(capped.hitTheLimit)
        // limit 10: both matched, so this is the whole set.
        let full = try catalog.search("satay", limit: 10, excluding: [.peanuts])
        #expect(full.hitTheLimit == false)
    }

    @Test("An empty query is an empty answer, with no allergen claim")
    func emptyQuery() throws {
        let (_, catalog) = try seeded()
        let results = try catalog.search("   ", excluding: [.peanuts])
        #expect(results.foods.isEmpty)
        #expect(results.effect.removed == 0)
        // The allergen set is still reported, so a screen in an empty state does
        // not need a second call to know whether to mention allergies.
        #expect(results.isFiltered)
        #expect(results.disclaimer != nil)
    }
}
