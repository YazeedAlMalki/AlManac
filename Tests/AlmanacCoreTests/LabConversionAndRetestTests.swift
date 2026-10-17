import Testing
import Foundation
@testable import AlmanacCore

/// Unit conversion and re-test scheduling, queued for Slice 7.
///
/// The conversion rule is `docs/features/laboratory.md` §8 (R8.2, R8.3): decimal
/// scaling within one dimension is applied generally; mass ↔ substance amount
/// and activity units only with an analyte-specific factor, which the catalog
/// does not yet hold — so they are not converted, and say why. A converted
/// value sits beside the source value with its factor and class; it never
/// replaces it.
///
/// The re-test rule is a build decision (unconfirmed, `CONTEXT.md`): the
/// person's own median interval between results for that analyte, from at
/// least three dated results. No clinical interval is invented.
@Suite("Lab unit conversion and re-test suggestion")
struct LabConversionAndRetestTests {

    // MARK: - Conversion

    @Test("Same dimension, different scale: converted with its factor and class")
    func decimalScaling() {
        let outcome = LabUnitConversion.convert(1.2, from: "g/L", to: "mg/dL")
        guard case let .converted(value, unit, factor, conversionClass) = outcome else {
            Issue.record("expected a conversion, got \(outcome)")
            return
        }
        #expect(abs(value - 120) < 1e-9)
        #expect(unit == "mg/dL")
        #expect(abs(factor - 100) < 1e-9)
        #expect(conversionClass == .decimalScaling)
    }

    @Test("Substance concentrations scale too: 50 nmol/L is 0.05 µmol/L")
    func substanceScaling() {
        guard case let .converted(value, _, _, _) = LabUnitConversion.convert(50, from: "nmol/L", to: "µmol/L") else {
            Issue.record("not converted")
            return
        }
        #expect(abs(value - 0.05) < 1e-12)
    }

    @Test("The same unit is identity, class dimensionless for a percentage")
    func identity() {
        #expect(LabUnitConversion.convert(42, from: "%", to: "percent")
                == .converted(value: 42, unit: "percent", factor: 1, conversionClass: .dimensionless))
    }

    @Test("Mass to substance amount needs the analyte's factor, and none is held: not converted")
    func massToSubstance() {
        #expect(LabUnitConversion.convert(90, from: "mg/dL", to: "mmol/L") == .notConverted(.needsAnalyteFactor))
    }

    @Test("Activity units are not converted, even between two activity units")
    func activity() {
        #expect(LabUnitConversion.convert(30, from: "U/L", to: "IU/mL") == .notConverted(.activityUnits))
        #expect(LabUnitConversion.convert(30, from: "IU/L", to: "IU/L")
                == .converted(value: 30, unit: "IU/L", factor: 1, conversionClass: .activity),
                "the same unit needs no factor")
    }

    @Test("A percentage and a ratio are both dimensionless and still not interchangeable")
    func dimensionlessKindsStayApart() {
        #expect(LabUnitConversion.convert(0.4, from: "ratio", to: "%") == .notConverted(.differentDimension))
    }

    @Test("An unknown unit or no value is not converted, and says which")
    func unknowns() {
        #expect(LabUnitConversion.convert(5, from: "furlongs", to: "mg/dL") == .notConverted(.unknownUnit))
        #expect(LabUnitConversion.convert(5, from: nil, to: "mg/dL") == .notConverted(.unknownUnit))
        #expect(LabUnitConversion.convert(nil, from: "mg/dL", to: "mg/dL") == .notConverted(.notNumeric))
    }

    @Test("A series is put in the unit of its latest result; what cannot join it is listed with a reason")
    func series() {
        let series = LabUnitConversion.series([
            .init(id: "a", value: 1.0, unit: "g/L"),
            .init(id: "b", value: 5.5, unit: "mmol/L"),
            .init(id: "c", value: 110, unit: "mg/dL")
        ])
        #expect(series.unit == "mg/dL")
        #expect(series.points.map(\.id) == ["a", "c"])
        #expect(abs((series.points.first?.value ?? 0) - 100) < 1e-9)
        #expect(series.points.first?.sourceValue == 1.0, "the source value travels with the converted one")
        #expect(series.excluded.map(\.id) == ["b"])
        #expect(series.excluded.first?.reason == .needsAnalyteFactor)
    }

    // MARK: - Re-test

    @Test("Three dated results: the next is suggested one median interval after the last")
    func retestFromOwnCadence() throws {
        let suggestion = try #require(LabRetestSuggestion.suggest(
            collectionDays: ["2026-01-10", "2026-04-10", "2026-07-15"], today: "2026-08-01"))
        // Intervals 90 and 96 days; the median of two is their mean, 93.
        #expect(suggestion.typicalIntervalDays == 93)
        #expect(suggestion.lastDay == "2026-07-15")
        #expect(suggestion.suggestedDay == "2026-10-16")
        #expect(suggestion.basedOn == 3)
        #expect(!suggestion.isDue)
    }

    @Test("Fewer than three dated results: no suggestion, because there is no cadence to follow")
    func tooFew() {
        #expect(LabRetestSuggestion.suggest(collectionDays: ["2026-01-10", "2026-04-10"], today: "2026-08-01") == nil)
    }

    @Test("Results on the same day count once, and order does not matter")
    func sameDayRepeats() throws {
        let suggestion = try #require(LabRetestSuggestion.suggest(
            collectionDays: ["2026-03-01", "2026-01-01", "2026-03-01", "2026-02-01"], today: "2026-03-02"))
        #expect(suggestion.basedOn == 3)
        #expect(suggestion.lastDay == "2026-03-01")
    }

    @Test("A suggestion on or before today is due")
    func due() throws {
        let suggestion = try #require(LabRetestSuggestion.suggest(
            collectionDays: ["2025-01-01", "2025-02-01", "2025-03-01"], today: "2025-12-01"))
        #expect(suggestion.isDue)
    }

    @Test("Results dated only to a month or year are left out, not guessed into a day")
    func coarseDatesLeftOut() {
        let results: [(PartialDateTime)] = [
            PartialDateTime(text: "2026-01", precision: .month),
            PartialDateTime(text: "2026-02-10", precision: .day),
            PartialDateTime(text: "2026-03-10T08:00:00Z", precision: .instant),
            PartialDateTime(text: "2026", precision: .year)
        ]
        #expect(LabRetestSuggestion.collectionDays(results) == ["2026-02-10", "2026-03-10"])
    }
}
