import XCTest
@testable import AlmanacCore

/// Almanac's calorie number: general Atwater factors, 4/4/9/7 kcal per gram of
/// protein, total carbohydrate, fat and alcohol (handoff 2026-09-13).
/// Expected values are worked by hand in the comments, not recomputed.
final class GeneralAtwaterTests: XCTestCase {

    private let food = SourceIdentifier(namespace: .usda, localID: "900001")

    private func value(_ nutrient: String, _ amount: Double?, _ qualifier: NutrientQualifier = .measured,
                       basis: NutritionBasis = .per100g) -> NutrientValue {
        let cell: String
        switch qualifier {
        case .trace: cell = "Tr"
        case .notAnalysed: cell = "N"
        default: cell = amount.map { String($0) } ?? ""
        }
        return NutrientValue(foodRef: food, nutrientID: nutrient, amount: amount, qualifier: qualifier,
                             sourceValue: cell, sourceNutrientID: nutrient, sourceUnit: "g",
                             licenceGroup: .permissive, basis: basis)
    }

    func testTotalCarbohydrateByDifferenceTakesFourKilocaloriesPerGram() throws {
        // 4 × 13.2 + 9 × 6.5 + 4 × 67.7 + 7 × 0 = 52.8 + 58.5 + 270.8 + 0 = 382.1
        let estimate = try XCTUnwrap(GeneralAtwater.estimate(from: [
            value("protein", 13.2), value("fat_total", 6.5),
            value("carbohydrate_by_difference", 67.7), value("fibre_total_dietary", 10.1),
            value("alcohol", 0, .zeroReported),
        ], basis: .per100g))
        XCTAssertEqual(estimate.kilocalories, 382.1, accuracy: 1e-9)
        XCTAssertEqual(estimate.method, .generalAtwater)
        XCTAssertEqual(estimate.carbohydrateTerm, .byDifference)
        XCTAssertEqual(estimate.inputsTakenAsZero, [])
        XCTAssertEqual(estimate.qualifier, .calculatedFactor)
    }

    // CIQUAL and AFCD publish available carbohydrate, which excludes fibre.
    // Total = available + fibre; without the fibre term every fibre-rich food
    // would lose 4 kcal per gram of fibre.
    func testAvailableCarbohydrateIsMadeTotalByAddingFibre() throws {
        // 4 × 9 + 9 × 3 + 4 × (50 + 3) + 7 × 0 = 36 + 27 + 212 + 0 = 275
        let estimate = try XCTUnwrap(GeneralAtwater.estimate(from: [
            value("protein", 9), value("fat_total", 3), value("carbohydrate_available", 50),
            value("fibre_total_dietary", 3), value("alcohol", 0, .zeroReported),
        ], basis: .per100g))
        XCTAssertEqual(estimate.kilocalories, 275, accuracy: 1e-9)
        XCTAssertEqual(estimate.carbohydrateTerm, .availablePlusFibre)
    }

    // CoFID publishes available carbohydrate as monosaccharide equivalents. It is
    // used as published; the ~5-10 % hydration uplift is a v2 specific-factor matter.
    func testMonosaccharideEquivalentsArePairedWithFibreToo() throws {
        // 4 × 20 + 9 × 5 + 4 × (10 + 2) + 7 × 0 = 80 + 45 + 48 = 173
        let estimate = try XCTUnwrap(GeneralAtwater.estimate(from: [
            value("protein", 20), value("fat_total", 5),
            value("carbohydrate_available_monosaccharide", 10), value("fibre_total_dietary", 2),
            value("alcohol", 0, .zeroReported),
        ], basis: .per100g))
        XCTAssertEqual(estimate.kilocalories, 173, accuracy: 1e-9)
        XCTAssertEqual(estimate.carbohydrateTerm, .availableMonosaccharidePlusFibre)
    }

    func testAvailableCarbohydrateWithoutFibreHasNoEstimate() {
        XCTAssertNil(GeneralAtwater.estimate(from: [
            value("protein", 9), value("fat_total", 3), value("carbohydrate_available", 50),
            value("alcohol", 0, .zeroReported),
        ], basis: .per100g), "fibre is never assumed")
    }

    func testByDifferenceIsPreferredWhenBothArePublished() throws {
        // USDA can publish 1005 (by difference) and 1050 (by summation) for one food.
        // 4 × 1 + 9 × 1 + 4 × 20 + 7 × 0 = 93
        let estimate = try XCTUnwrap(GeneralAtwater.estimate(from: [
            value("protein", 1), value("fat_total", 1), value("carbohydrate_by_difference", 20),
            value("carbohydrate_available", 15), value("fibre_total_dietary", 2),
            value("alcohol", 0, .zeroReported),
        ], basis: .per100g))
        XCTAssertEqual(estimate.kilocalories, 93, accuracy: 1e-9)
        XCTAssertEqual(estimate.carbohydrateTerm, .byDifference)
    }

    // A trace has no number and a "< x" is an upper bound. In the sum both count as
    // zero (the lower bound) — and the estimate says so, rather than hiding it.
    func testTraceAndBelowLimitInputsEnterAsZeroAndAreDeclared() throws {
        // 4 × 0 + 9 × 0 + 4 × (50.3 + 3.1) + 7 × 0 = 213.6
        let estimate = try XCTUnwrap(GeneralAtwater.estimate(from: [
            value("protein", nil, .trace), value("fat_total", 0.5, .belowLOQ),
            value("carbohydrate_available", 50.3), value("fibre_total_dietary", 3.1),
            value("alcohol", 0, .zeroReported),
        ], basis: .per100g))
        XCTAssertEqual(estimate.kilocalories, 213.6, accuracy: 1e-9)
        XCTAssertEqual(estimate.inputsTakenAsZero, ["fat_total", "protein"])
    }

    // Most foods publish no alcohol row, and CIQUAL marks it "-" for most solids.
    // Every source's own energy figure counts alcohol only where present.
    func testAbsentOrUnanalysedAlcoholIsTakenAsZeroAndDeclared() throws {
        // 4 × 10 + 9 × 8 + 4 × (20 + 2) + 7 × 0 = 40 + 72 + 88 = 200
        let base = [value("protein", 10), value("fat_total", 8), value("carbohydrate_available", 20),
                    value("fibre_total_dietary", 2)]
        for values in [base, base + [value("alcohol", nil, .notAnalysed)]] {
            let estimate = try XCTUnwrap(GeneralAtwater.estimate(from: values, basis: .per100g))
            XCTAssertEqual(estimate.kilocalories, 200, accuracy: 1e-9)
            XCTAssertEqual(estimate.inputsTakenAsZero, ["alcohol"])
        }
    }

    func testUnanalysedOrMissingProteinFatCarbohydrateOrFibreGivesNoEstimate() {
        let complete = [value("protein", 10), value("fat_total", 8), value("carbohydrate_available", 20),
                        value("fibre_total_dietary", 2), value("alcohol", 0, .zeroReported)]
        for (index, nutrient) in ["protein", "fat_total", "carbohydrate_available",
                                  "fibre_total_dietary"].enumerated() {
            var unanalysed = complete
            unanalysed[index] = value(nutrient, nil, .notAnalysed)
            XCTAssertNil(GeneralAtwater.estimate(from: unanalysed, basis: .per100g), nutrient)
            var missing = complete
            missing.remove(at: index)
            XCTAssertNil(GeneralAtwater.estimate(from: missing, basis: .per100g), nutrient)
        }
    }
}
