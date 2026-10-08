import Testing
import Foundation
@testable import AlmanacCore

/// `NutritionSummary` — the food log read against the reference catalog.
///
/// This type had no coverage at all: `DayEnergyTests` builds `NutritionTotals`
/// by hand, so the arithmetic that actually produces them was untested. What is
/// worth pinning down here is not the summing, it is the four ways a total
/// declines to be complete. Every one of them is a field the UI has to be able
/// to show, and each is a case where the tempting shortcut silently reports a
/// smaller, wrong number.
@Suite("NutritionSummary")
struct NutritionSummaryTests {
    let db = try! TestDatabase()
    let clock = FixedClock(Date(timeIntervalSince1970: 2_000_000))

    private let rice = SourceIdentifier(namespace: .usda, localID: "rice")
    private let beans = SourceIdentifier(namespace: .usda, localID: "beans")
    private let ghost = SourceIdentifier(namespace: .usda, localID: "never-seeded")

    init() throws {
        // `nutrition_food.namespace` references `nutrition_source`, so the
        // source row has to exist before any food can be seeded.
        try db.execute("""
            INSERT INTO nutrition_source (namespace, dataset_id, name, release, licence, licence_group,
                                          attribution, url)
            VALUES ('usda', 'usda', 'USDA', '2026', 'CC0', 'A', '', '');
            """)
    }

    private var summary: NutritionSummary {
        NutritionSummary(db: db, clock: clock, zone: ZoneContext(TimeZone(identifier: "UTC")!))
    }
    private var log: NutritionLogStore {
        NutritionLogStore(db: db, clock: clock, zone: ZoneContext(TimeZone(identifier: "UTC")!))
    }

    /// Seeds a food whose macros make general Atwater computable, so energy has
    /// a first route and `publisherReported` is a fallback rather than the only
    /// one.
    private func seedAtwaterFood(_ ref: SourceIdentifier, protein: Double, fat: Double,
                                 carbohydrate: Double) throws {
        try seedFood(ref)
        try seedValues(ref, [("protein", protein, "g"), ("fat_total", fat, "g"),
                             ("carbohydrate_by_difference", carbohydrate, "g")])
    }

    private func seedFood(_ ref: SourceIdentifier) throws {
        try db.run("""
            INSERT INTO nutrition_food (food_ref, namespace, local_id, licence_group, food_group_code,
                                        food_group_name, source_record)
            VALUES (?, ?, ?, 'A', '', '', 'fixture');
            """, [.text(ref.description), .text(ref.namespace.rawValue), .text(ref.localID)])
    }

    private func seedValues(_ ref: SourceIdentifier, _ rows: [(String, Double, String)]) throws {
        for (nutrient, amount, unit) in rows {
            try db.run("""
                INSERT INTO nutrition_nutrient (nutrient_id, infoods_tag, name, unit, description)
                VALUES (?, ?, ?, ?, '')
                ON CONFLICT(nutrient_id) DO NOTHING;
                """, [.text(nutrient), .text(nutrient), .text(nutrient), .text(unit)])
            try db.run("""
                INSERT INTO nutrition_value (food_ref, nutrient_id, basis, amount, qualifier, confidence,
                                             source_value, source_nutrient_id, source_unit, licence_group)
                VALUES (?, ?, 'per_100g', ?, 'measured', NULL, ?, ?, ?, 'A');
                """, [.text(ref.description), .text(nutrient), .real(amount),
                      .text("\(amount)"), .text(nutrient), .text(unit)])
        }
    }

    /// Seeds a food with no macros at all and no published energy, so
    /// `EnergyEstimate.preferred` returns nil for it.
    private func seedUnpriceableFood(_ ref: SourceIdentifier) throws {
        try seedFood(ref)
        try seedValues(ref, [("fibre_total_dietary", 2.0, "g")])
    }

    /// 2026-09-11T22:26:40Z — inside the range every read below queries, so a
    /// missed row is a logic failure rather than a fixture accident.
    private static let anchor: TimeInterval = 1_789_000_000

    private func eat(_ ref: SourceIdentifier, grams: Double?, at: TimeInterval = Self.anchor) throws {
        _ = try log.record(NutritionLogDraft(
            foodRef: ref, grams: grams,
            eatenAt: PartialDateTime(instant: Date(timeIntervalSince1970: at),
                                     zone: ZoneContext(TimeZone(identifier: "UTC")!))))
    }

    private func totals() throws -> NutritionTotals {
        try summary.totals(from: "2000-01-01T00:00:00Z", to: "2100-01-01T00:00:00Z")
    }

    // MARK: The complete case

    @Test("A day's meals add up, and the count is the number that carried an amount")
    func sumsTheDay() throws {
        try seedAtwaterFood(rice, protein: 2.5, fat: 0.5, carbohydrate: 28.0)
        try seedAtwaterFood(beans, protein: 8.0, fat: 0.5, carbohydrate: 22.0)
        // 100 g rice = 4(2.5) + 4(28) + 9(0.5) = 116.5 ; 200 g beans = 2 × (32 + 88 + 4.5) = 249
        try eat(rice, grams: 100)
        try eat(beans, grams: 200)

        let result = try totals()
        #expect(result.kcal == 375.5)
        #expect(result.mealsCounted == 2)
        #expect(result.energyBases == [.generalAtwater])
        #expect(result.nutrients["protein"] == 18.5)   // 2.5 + 16
        #expect(result.nutrients["fat_total"] == 1.5)  // 0.5 + 1
        #expect(result.nutrients["carbohydrate_by_difference"] == 72.0)  // 28 + 44
        #expect(result.isComplete, "nothing about this day is missing")
    }

    @Test("A day with no meals is a zero total, not a nil and not a failure")
    func emptyDayIsZeroNotNil() throws {
        let result = try totals()
        #expect(result.kcal == 0)
        #expect(result.mealsCounted == 0)
        #expect(result.nutrients.isEmpty)
        #expect(result.isComplete, "an empty day has nothing missing from it")
    }

    // MARK: The four ways a total is not complete

    @Test("A meal with no stated amount contributes nothing and is named, not zeroed")
    func mealWithoutAmountIsNamed() throws {
        try seedAtwaterFood(rice, protein: 2.5, fat: 0.5, carbohydrate: 28.0)
        try eat(rice, grams: nil)

        let result = try totals()
        #expect(result.kcal == 0, "an unpriced meal is not a zero-calorie meal")
        #expect(result.mealsCounted == 0)
        #expect(result.mealsWithoutAmount.count == 1)
        #expect(!result.isComplete)
    }

    @Test("A meal against a food the catalog does not hold is named by its ref")
    func mealWithoutReferenceIsNamed() throws {
        try seedAtwaterFood(rice, protein: 2.5, fat: 0.5, carbohydrate: 28.0)
        try eat(rice, grams: 100)
        try eat(ghost, grams: 150)

        let result = try totals()
        #expect(result.kcal == 126.5, "the meal that could be priced still counts")
        #expect(result.mealsCounted == 1)
        #expect(result.mealsWithoutReference == [ghost])
        #expect(!result.isComplete)
    }

    @Test("A meal with no computable energy makes the total partial under the energy sentinel")
    func unpriceableMealIsNamedUnderTheEnergySentinel() throws {
        try seedAtwaterFood(rice, protein: 2.5, fat: 0.5, carbohydrate: 28.0)
        try seedUnpriceableFood(beans)
        try eat(rice, grams: 100)
        try eat(beans, grams: 100)

        let result = try totals()
        #expect(result.kcal == 126.5, "the priceable meal is still counted")
        #expect(result.mealsCounted == 2, "the unpriceable one was logged with an amount")
        #expect(result.incompleteNutrients.contains("energy_kcal"),
                "a total that quietly omits an unpriceable meal is the failure this exists to stop")
        #expect(!result.isComplete)
        #expect(result.mealsWithoutEnergy.count == 1)
        #expect(!result.isEnergyComplete)
        #expect(result.energyCaveat == "Partial total: 1 food has no calorie figure. Their calories are not counted.")
    }

    @Test("A day whose meals report carbohydrate under different ids still has a complete calorie total")
    func mixedCarbohydrateIdsDoNotMakeTheCalorieTotalPartial() throws {
        // USDA states carbohydrate by difference; CIQUAL states available
        // carbohydrate plus fibre. Every meal is priced, so the energy is whole
        // even though no carbohydrate id is reported by both.
        try seedAtwaterFood(rice, protein: 2.5, fat: 0.5, carbohydrate: 28.0)
        try seedFood(beans)
        try seedValues(beans, [("protein", 8.0, "g"), ("fat_total", 0.5, "g"),
                               ("carbohydrate_available", 16.0, "g"), ("fibre_total_dietary", 6.0, "g")])
        try eat(rice, grams: 100)
        try eat(beans, grams: 100)

        let result = try totals()
        #expect(!result.isComplete, "carbohydrate ids genuinely differ")
        #expect(result.isEnergyComplete)
        #expect(result.energyCaveat == nil)
        #expect(DayEnergy.total(food: result, drinks: [])?.isFoodComplete == true)
    }

    @Test("The caveat names every cause, counted")
    func caveatNamesEachCause() throws {
        try seedAtwaterFood(rice, protein: 2.5, fat: 0.5, carbohydrate: 28.0)
        try eat(rice, grams: nil)
        try eat(rice, grams: nil)
        try eat(ghost, grams: 100)
        #expect(try totals().energyCaveat
                == "Partial total: 2 foods have no amount and 1 food is not in the food catalogue. Their calories are not counted.")
    }

    @Test("A nutrient one meal does not report is absent from the total, not smaller in it")
    func missingNutrientIsOmittedNotUndercounted() throws {
        try seedAtwaterFood(rice, protein: 2.5, fat: 0.5, carbohydrate: 28.0)
        try seedFood(beans)
        try seedValues(beans, [("protein", 8.0, "g")])
        try eat(rice, grams: 100)
        try eat(beans, grams: 100)

        let result = try totals()
        #expect(result.nutrients["protein"] == 10.5, "both meals reported it")
        #expect(result.nutrients["fat_total"] == nil,
                "beans reported no fat; 0.5 is not the answer, and neither is an empty sum")
        #expect(result.incompleteNutrients.contains("fat_total"))
    }

    @Test("A nutrient reported on two different scales is dropped rather than added")
    func unitConflictDropsTheNutrient() throws {
        try seedFood(rice)
        try seedValues(rice, [("protein", 2.5, "g")])
        try seedFood(beans)
        try seedValues(beans, [("protein", 800.0, "mg")])
        try eat(rice, grams: 100)
        try eat(beans, grams: 100)

        let result = try totals()
        #expect(result.nutrients["protein"] == nil,
                "nothing here converts units, so 2.5 g and 800 mg are not a sum of 10.5 g")
        #expect(result.incompleteNutrients.contains("protein"))
    }

    @Test("A nutrient reported as not analysed leaves the total incomplete rather than adding zero")
    func notAnalysedLeavesAGap() throws {
        try seedFood(rice)
        try seedValues(rice, [("protein", 2.5, "g")])
        try db.run("""
            INSERT INTO nutrition_nutrient (nutrient_id, infoods_tag, name, unit, description)
            VALUES ('fat_total', 'fat_total', 'Fat', 'g', '') ON CONFLICT(nutrient_id) DO NOTHING;
            """)
        try db.run("""
            INSERT INTO nutrition_value (food_ref, nutrient_id, basis, amount, qualifier, confidence,
                                         source_value, source_nutrient_id, source_unit, licence_group)
            VALUES (?, 'fat_total', 'per_100g', NULL, 'not_analysed', NULL, '-', 'fat', 'g', 'A');
            """, [.text(rice.description)])

        try eat(rice, grams: 100)
        let result = try totals()
        #expect(result.nutrients["protein"] == 2.5, "the readable nutrient is unaffected")
        #expect(result.nutrients["fat_total"] == nil)
        #expect(result.incompleteNutrients.contains("fat_total"))
    }

    // MARK: Two energy routes, and saying so

    @Test("A day mixing a computed and a published energy figure says which routes it used")
    func mixedEnergyBasesAreReported() throws {
        try seedAtwaterFood(rice, protein: 2.5, fat: 0.5, carbohydrate: 28.0)  // Atwater
        try seedFood(beans)
        try seedValues(beans, [("energy_kcal", 130.0, "kcal")])              // publisher only
        try eat(rice, grams: 100)
        try eat(beans, grams: 100)

        let result = try totals()
        #expect(result.kcal == 256.5)   // 126.5 Atwater + 130 published
        #expect(result.energyBases == [.generalAtwater, .publisherReported],
                "a mixed-quality total is the caller's to label, and it can only do that if told")
    }

    // MARK: loggedFoods

    @Test("A logged meal joins to its reference row and its scaled energy")
    func loggedFoodsJoinToTheCatalog() throws {
        try seedAtwaterFood(rice, protein: 2.5, fat: 0.5, carbohydrate: 28.0)
        try eat(rice, grams: 50, at: Self.anchor)
        try eat(ghost, grams: 100, at: Self.anchor + 100)

        let foods = try summary.loggedFoods(from: "2000-01-01T00:00:00Z", to: "2100-01-01T00:00:00Z")
        #expect(foods.count == 2)
        let riceEntry = try #require(foods.first { $0.entry.foodRef == rice })
        #expect(riceEntry.food?.primaryName != nil)
        #expect(try #require(riceEntry.energy).kilocalories == 63.25)  // 126.5 / 2
        #expect(riceEntry.basis == .occurrence)

        // The ref that is gone still reads: the name the person saw survives.
        let ghostEntry = try #require(foods.first { $0.entry.foodRef == ghost })
        #expect(ghostEntry.food == nil)
        #expect(ghostEntry.entry.foodNameText == nil, "nothing was typed, and nothing is invented")
    }

    @Test("A meal with no amount has no energy, which is not the same as zero energy")
    func loggedFoodWithoutAmountHasNoEnergy() throws {
        try seedAtwaterFood(rice, protein: 2.5, fat: 0.5, carbohydrate: 28.0)
        try eat(rice, grams: nil)

        let foods = try summary.loggedFoods(from: "2000-01-01T00:00:00Z", to: "2100-01-01T00:00:00Z")
        #expect(try #require(foods.first).energy == nil)
    }

    @Test("A soft-deleted meal is not in the day's total")
    func deletedMealsAreExcluded() throws {
        try seedAtwaterFood(rice, protein: 2.5, fat: 0.5, carbohydrate: 28.0)
        let outcome = try log.record(NutritionLogDraft(
            foodRef: rice, grams: 100,
            eatenAt: PartialDateTime(instant: Date(timeIntervalSince1970: Self.anchor),
                                     zone: ZoneContext(TimeZone(identifier: "UTC")!))))
        let id = outcome.logID
        #expect(try totals().mealsCounted == 1)

        try log.delete(id: id)
        #expect(try totals().mealsCounted == 0, "a correction removes the meal, it does not zero it")
    }

    // MARK: The logical-day read

    @Test("A logical day is read through TimeModel, not as a UTC date range")
    func logicalDayGoesThroughTimeModel() throws {
        try seedAtwaterFood(rice, protein: 2.5, fat: 0.5, carbohydrate: 28.0)
        try seedAtwaterFood(beans, protein: 8.0, fat: 0.5, carbohydrate: 22.0)
        // Riyadh is UTC+3 and a logical day opens at 04:00 local, so the 17th runs
        // 01:00Z → 01:00Z. Two meals sit either side of that, close enough to
        // midnight UTC that a naive date range assigns both to the wrong day —
        // one late, one early. TimeModel swaps them.
        //
        //   2026-09-17T00:30Z = 03:30 local on the 17th → the 16th
        //   2026-09-18T00:30Z = 03:30 local on the 18th → the 17th
        try eat(rice, grams: 100, at: Self.utcInstant(2026, 9, 17, 0, 30))
        try eat(beans, grams: 100, at: Self.utcInstant(2026, 9, 18, 0, 30))

        let riyadh = TimeModel.riyadh()
        let seventeenth = try #require(try summary.totals(on: LogicalDay("2026-09-17"), in: riyadh))
        let sixteenth = try #require(try summary.totals(on: LogicalDay("2026-09-16"), in: riyadh))
        #expect(seventeenth.mealsCounted == 1, "the meal a UTC range would have filed under the 18th")
        #expect(sixteenth.mealsCounted == 1, "and the one a UTC range would have filed under the 17th")
        #expect(sixteenth.nutrients["protein"] == 2.5, "the 16th holds rice, not beans")
        #expect(seventeenth.nutrients["protein"] == 8.0, "and the 17th holds beans, not rice")
    }

    private static func utcInstant(_ year: Int, _ month: Int, _ day: Int,
                                   _ hour: Int, _ minute: Int) throws -> TimeInterval {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        return try #require(utc.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute))).timeIntervalSince1970
    }

    @Test("A day the model cannot place is nil, not an empty total")
    func unplaceableDayIsNil() throws {
        let riyadh = TimeModel.riyadh()
        #expect(try summary.totals(on: LogicalDay("not-a-date"), in: riyadh) == nil)
        #expect(try summary.loggedFoods(on: LogicalDay("not-a-date"), in: riyadh) == nil)
    }
}
