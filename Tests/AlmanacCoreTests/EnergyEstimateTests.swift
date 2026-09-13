import XCTest
@testable import AlmanacCore

/// Which calorie number a food shows: Almanac's general-Atwater figure when it can
/// be computed, else the publisher's own energy — labelled as such — else none.
final class EnergyEstimateTests: XCTestCase {

    private func value(_ nutrient: String, _ amount: Double?, _ qualifier: NutrientQualifier = .measured,
                       basis: NutritionBasis = .per100g) -> NutrientValue {
        NutrientValue(foodRef: SourceIdentifier(namespace: .cofid, localID: "900-001"), nutrientID: nutrient,
                      amount: amount, qualifier: qualifier,
                      sourceValue: qualifier == .trace ? "Tr" : amount.map { String($0) } ?? "N",
                      sourceNutrientID: nutrient, sourceUnit: "g", licenceGroup: .attribution, basis: basis)
    }

    func testGeneralAtwaterWinsOverThePublishersFigure() throws {
        // 4 × 13.2 + 9 × 6.5 + 4 × 67.7 + 7 × 0 = 382.1, not the publisher's 379
        let estimate = try XCTUnwrap(EnergyEstimate.preferred(from: [
            value("energy_kcal", 379, .calculatedFactor), value("protein", 13.2), value("fat_total", 6.5),
            value("carbohydrate_by_difference", 67.7), value("alcohol", 0, .zeroReported),
        ], basis: .per100g))
        XCTAssertEqual(estimate.kilocalories, 382.1, accuracy: 1e-9)
        XCTAssertEqual(estimate.method, .generalAtwater)
    }

    // CoFID leaves AOAC fibre blank for ~46 % of foods. Those still get a calorie
    // number: the publisher's, marked as the publisher's.
    func testPublisherEnergyIsTheFallbackAndSaysSo() throws {
        let estimate = try XCTUnwrap(EnergyEstimate.preferred(from: [
            value("energy_kcal", 151, .calculatedFactor), value("protein", 2.9), value("fat_total", 15.2),
            value("carbohydrate_available_monosaccharide", 0.8),
        ], basis: .per100g))
        XCTAssertEqual(estimate.kilocalories, 151)
        XCTAssertEqual(estimate.method, .publisherReported)
        XCTAssertNil(estimate.carbohydrateTerm)
        XCTAssertEqual(estimate.inputsTakenAsZero, [])
    }

    func testNoFigureWhenNeitherCanBeRead() {
        XCTAssertNil(EnergyEstimate.preferred(from: [value("protein", 2.9)], basis: .per100g))
        XCTAssertNil(EnergyEstimate.preferred(from: [value("energy_kcal", nil, .notAnalysed)],
                                              basis: .per100g), "an unanalysed energy is not 0 kcal")
    }

    // Processing Design v0.1 §4: per 100 g and per 100 mL never mix.
    func testEachBasisUsesOnlyItsOwnValues() throws {
        // CoFID wine, per 100 mL: 4 × 0 (trace) + 9 × 0 + 4 × (0.2 + 0) + 7 × 10.7 = 0.8 + 74.9 = 75.7
        let wine = [value("protein", nil, .trace, basis: .per100ml), value("fat_total", 0, .zeroReported, basis: .per100ml),
                    value("carbohydrate_available_monosaccharide", 0.2, basis: .per100ml),
                    value("fibre_total_dietary", 0, .zeroReported, basis: .per100ml),
                    value("alcohol", 10.7, basis: .per100ml)]
        XCTAssertEqual(try XCTUnwrap(EnergyEstimate.preferred(from: wine, basis: .per100ml)).kilocalories,
                       75.7, accuracy: 1e-9)
        XCTAssertNil(EnergyEstimate.preferred(from: wine, basis: .per100g))

        // AFCD liquid on both bases. per 100 g: 4 × 0.2 + 9 × 0.2 + 4 × (0.4 + 0) = 0.8 + 1.8 + 1.6 = 4.2
        // per 100 mL: 4 × 0.21 + 9 × 0.21 + 4 × (0.42 + 0) = 0.84 + 1.89 + 1.68 = 4.41
        let stock = [0.2, 0.21].enumerated().flatMap { index, protein -> [NutrientValue] in
            let basis: NutritionBasis = index == 0 ? .per100g : .per100ml
            return [value("protein", protein, basis: basis), value("fat_total", protein, basis: basis),
                    value("carbohydrate_available", protein * 2, basis: basis),
                    value("fibre_total_dietary", 0, .zeroReported, basis: basis),
                    value("alcohol", 0, .zeroReported, basis: basis)]
        }
        XCTAssertEqual(try XCTUnwrap(EnergyEstimate.preferred(from: stock, basis: .per100g)).kilocalories,
                       4.2, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(EnergyEstimate.preferred(from: stock, basis: .per100ml)).kilocalories,
                       4.41, accuracy: 1e-9)
    }
}
