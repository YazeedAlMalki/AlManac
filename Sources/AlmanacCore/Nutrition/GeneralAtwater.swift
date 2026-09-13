import Foundation

/// A calorie figure and how it was reached. Always `calculatedFactor`: energy
/// in a food table is computed from components, never measured.
public struct EnergyEstimate: Sendable, Hashable {
    public enum Method: String, Sendable, Hashable {
        /// Almanac's own figure: 4/4/9/7 kcal per gram (handoff 2026-09-13).
        case generalAtwater = "general_atwater"
        /// The publisher's own energy value, made with the publisher's own factors.
        /// Used only when general Atwater cannot be computed; not comparable across
        /// publishers, so it is always labelled.
        case publisherReported = "publisher_reported"
    }

    /// General Atwater applies 4 kcal/g to *total* carbohydrate. Sources publish
    /// different quantities under "carbohydrate", so the term records which one
    /// was made total, and how (tools/nutrition/README.md, "Carbohydrate").
    public enum CarbohydrateTerm: String, Sendable, Hashable {
        /// Total carbohydrate by difference, fibre included (USDA).
        case byDifference = "by_difference"
        /// Available carbohydrate by weight plus total dietary fibre (CIQUAL, AFCD).
        case availablePlusFibre = "available_plus_fibre"
        /// Available carbohydrate as monosaccharide equivalents plus fibre (CoFID).
        case availableMonosaccharidePlusFibre = "available_monosaccharide_plus_fibre"
    }

    public let kilocalories: Double
    public let basis: NutritionBasis
    public let method: Method
    public let carbohydrateTerm: CarbohydrateTerm?
    /// Canonical nutrients that entered the sum as zero although the source did not
    /// report zero: traces, "< x" bounds, and absent or unanalysed alcohol. Sorted.
    public let inputsTakenAsZero: [String]

    public var qualifier: NutrientQualifier { .calculatedFactor }

    /// Almanac's calorie number for a food on one basis: general Atwater when it can
    /// be computed, else the publisher's own figure, else nil. A trace, an unanalysed
    /// value or a "< x" bound is never shown as a calorie figure.
    public static func preferred(from values: [NutrientValue], basis: NutritionBasis) -> EnergyEstimate? {
        if let atwater = GeneralAtwater.estimate(from: values, basis: basis) { return atwater }
        guard let published = values.first(where: { $0.basis == basis && $0.nutrientID == "energy_kcal" }),
              published.qualifier != .belowLOQ,
              let kilocalories = published.amount else { return nil }
        return EnergyEstimate(kilocalories: kilocalories, basis: basis, method: .publisherReported,
                              carbohydrateTerm: nil, inputsTakenAsZero: [])
    }
}

/// General Atwater factors. Per-food specific factors are a v2 refinement.
public enum GeneralAtwater {
    public static let proteinKilocaloriesPerGram = 4.0
    public static let carbohydrateKilocaloriesPerGram = 4.0
    public static let fatKilocaloriesPerGram = 9.0
    public static let alcoholKilocaloriesPerGram = 7.0

    /// nil when protein, fat or total carbohydrate cannot be read — never a guess.
    public static func estimate(from values: [NutrientValue], basis: NutritionBasis) -> EnergyEstimate? {
        var published: [String: NutrientValue] = [:]
        for value in values where value.basis == basis { published[value.nutrientID] = value }
        let read = { (nutrient: String) in Term(published[nutrient]) }

        guard let protein = read("protein"), let fat = read("fat_total"),
              let carbohydrate = totalCarbohydrate(read) else { return nil }
        // Every source's own energy figure counts alcohol only where it is present.
        let alcohol = read("alcohol") ?? Term(grams: 0, takenAsZero: ["alcohol"])

        let kilocalories = proteinKilocaloriesPerGram * protein.grams
            + carbohydrateKilocaloriesPerGram * carbohydrate.total.grams
            + fatKilocaloriesPerGram * fat.grams
            + alcoholKilocaloriesPerGram * alcohol.grams
        let zeros = protein.takenAsZero + fat.takenAsZero + carbohydrate.total.takenAsZero + alcohol.takenAsZero
        return EnergyEstimate(kilocalories: kilocalories, basis: basis, method: .generalAtwater,
                              carbohydrateTerm: carbohydrate.term, inputsTakenAsZero: zeros.sorted())
    }

    /// By difference if published; otherwise available carbohydrate plus fibre.
    /// Fibre is never assumed, so available carbohydrate alone gives no total.
    private static func totalCarbohydrate(_ read: (String) -> Term?)
        -> (total: Term, term: EnergyEstimate.CarbohydrateTerm)? {
        if let total = read("carbohydrate_by_difference") { return (total, .byDifference) }
        guard let fibre = read("fibre_total_dietary") else { return nil }
        if let available = read("carbohydrate_available") {
            return (available + fibre, .availablePlusFibre)
        }
        if let available = read("carbohydrate_available_monosaccharide") {
            return (available + fibre, .availableMonosaccharidePlusFibre)
        }
        return nil
    }

    /// Grams entering the sum, and which nutrients entered it as zero without the
    /// source saying zero.
    private struct Term {
        let grams: Double
        let takenAsZero: [String]

        init(grams: Double, takenAsZero: [String]) {
            self.grams = grams
            self.takenAsZero = takenAsZero
        }

        /// nil when the value is absent or has no reading at all.
        init?(_ value: NutrientValue?) {
            guard let value else { return nil }
            switch value.qualifier {
            case .notAnalysed:
                return nil
            case .trace, .belowLOQ:
                // No number, or only an upper bound: count the lower bound, and say so.
                self.init(grams: 0, takenAsZero: [value.nutrientID])
            default:
                guard let amount = value.amount else { return nil }
                self.init(grams: amount, takenAsZero: [])
            }
        }

        static func + (lhs: Term, rhs: Term) -> Term {
            Term(grams: lhs.grams + rhs.grams, takenAsZero: lhs.takenAsZero + rhs.takenAsZero)
        }
    }
}
