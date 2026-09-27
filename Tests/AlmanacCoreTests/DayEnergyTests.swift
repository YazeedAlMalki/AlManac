import XCTest
@testable import AlmanacCore

/// The day's energy as one figure, from food and from logged drinks together.
///
/// A catalog drink's calories are an uncited typical value and a food's are a
/// cited composition figure, so the sum is a mixed-quality number. That is a
/// reason to be able to *say* so, not a reason to show two numbers. The
/// per-row qualifier is unaffected either way: it is still written to
/// `hydration_log.value_qualifier`, which is what `Migration013` exists for.
///
/// The rule these tests actually protect is narrower and older than any of
/// that: an unlogged day is not a zero. `nil` and `0` are different answers
/// and only one of them may be rendered as a number.
final class DayEnergyTests: XCTestCase {

    private func food(kcal: Double, mealsCounted: Int, isComplete: Bool = true) -> NutritionTotals {
        NutritionTotals(kcal: kcal, energyBases: [], nutrients: [:], mealsCounted: mealsCounted,
                        mealsWithoutAmount: isComplete ? [] : ["oats"],
                        mealsWithoutReference: [], incompleteNutrients: [])
    }

    func testNothingLoggedHasNoEnergyRatherThanZero() {
        // The distinction the whole type exists for: no reading is not a
        // reading of zero.
        XCTAssertNil(DayEnergy.total(food: nil, drinks: []))
    }

    func testADayOfOnlyDrinksStillReportsItsEnergy() {
        // The regression this type was added to prevent. Log a Pepsi and no
        // food, and a combined total guarded on `mealsCounted > 0` renders an
        // em dash -- discarding a figure the user actually recorded.
        let energy = DayEnergy.total(food: nil, drinks: [150])
        XCTAssertEqual(energy?.kcal, 150)
        XCTAssertEqual(energy?.drinkCount, 1)
    }

    func testADayOfOnlyFoodIsUnchangedByHavingNoDrinks() {
        let energy = DayEnergy.total(food: food(kcal: 500, mealsCounted: 3), drinks: [])
        XCTAssertEqual(energy?.kcal, 500)
        XCTAssertEqual(energy?.drinkCount, 0)
    }

    func testFoodAndDrinksAddIntoASingleFigure() {
        let energy = DayEnergy.total(food: food(kcal: 500, mealsCounted: 3), drinks: [150])
        XCTAssertEqual(energy?.kcal, 650)
        XCTAssertEqual(energy?.drinkCount, 1)
    }

    func testSeveralDrinksAreSummedAndCounted() {
        let energy = DayEnergy.total(food: nil, drinks: [150, 90])
        XCTAssertEqual(energy?.kcal, 240)
        XCTAssertEqual(energy?.drinkCount, 2)
    }

    func testFoodLoggedWithoutAnAmountContributesNothing() {
        // A meal with no stated amount is logged but counted nothing. It must
        // not be read as a zero-calorie meal that dilutes the total, and it
        // must not suppress a real drink figure either.
        let energy = DayEnergy.total(food: food(kcal: 0, mealsCounted: 0, isComplete: false), drinks: [150])
        XCTAssertEqual(energy?.kcal, 150)
    }

    func testAnEmptyDayAndADayOfZeroCaloriesAreNotConfused() {
        // Both are zero, and they are not the same day. A food logged at
        // exactly 0 kcal is a recorded reading; no food at all is not.
        XCTAssertNil(DayEnergy.total(food: nil, drinks: []))
        XCTAssertEqual(DayEnergy.total(food: food(kcal: 0, mealsCounted: 2), drinks: [])?.kcal, 0)
    }

    // MARK: - Naming the total

    func testTheTotalIsNamedInWordsRatherThanSplitIntoNumbers() {
        let energy = DayEnergy.total(food: food(kcal: 500, mealsCounted: 3), drinks: [150, 90])
        XCTAssertEqual(energy?.summary, "3 foods and 2 drinks counted")
        XCTAssertEqual(energy?.foodCount, 3)
        XCTAssertEqual(energy?.drinkCount, 2)
    }

    func testASingleDrinkIsNotWrittenAsDrinks() {
        let energy = DayEnergy.total(food: nil, drinks: [150])
        XCTAssertEqual(energy?.summary, "1 drink counted")
    }

    func testAFoodOnlyDayReadsTheSameAsItAlwaysDid() {
        let energy = DayEnergy.total(food: food(kcal: 500, mealsCounted: 3), drinks: [])
        XCTAssertEqual(energy?.summary, "3 foods counted")
    }

    func testADayOfOnlyDrinksIsCompleteRatherThanPartial() {
        // The wording trap. `todaysTotals` is nil when no food was logged, and
        // a nil `isComplete` compared with `== true` is false — so a day with
        // nothing but a logged drink renders "Partial total" forever, calling
        // a complete record incomplete because the other half of it is empty.
        let energy = DayEnergy.total(food: nil, drinks: [150, 90])
        XCTAssertEqual(energy?.summary, "2 drinks counted")
        XCTAssertEqual(energy?.isFoodComplete, true)
    }

    func testFoodLoggedWithoutAnAmountSaysSo() {
        let energy = DayEnergy.total(food: food(kcal: 0, mealsCounted: 0, isComplete: false), drinks: [150])
        XCTAssertEqual(energy?.isFoodComplete, false)
        XCTAssertEqual(energy?.summary, "Partial total — some values are unavailable")
    }

    func testAnIncompleteFoodDaySaysSoEvenWithDrinksCounted() {
        let energy = DayEnergy.total(food: food(kcal: 500, mealsCounted: 3, isComplete: false), drinks: [150])
        XCTAssertEqual(energy?.isFoodComplete, false)
        XCTAssertEqual(energy?.summary, "Partial total — some values are unavailable")
    }
}
