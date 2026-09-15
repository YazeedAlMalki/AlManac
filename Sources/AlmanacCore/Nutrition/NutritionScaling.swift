import Foundation

extension EnergyEstimate {
    /// Scales a per-100 g estimate to an actual mass.
    public func scaled(toGrams grams: Double) -> EnergyEstimate {
        EnergyEstimate(kilocalories: kilocalories * grams / 100, basis: basis, method: method,
                       carbohydrateTerm: carbohydrateTerm, inputsTakenAsZero: inputsTakenAsZero)
    }
}

extension NutrientValue {
    /// This value scaled from its per-100 g basis to an actual mass.
    ///
    /// Nil for `notAnalysed`, which carries no number to scale. `trace` and
    /// `belowLOQ` scale to zero and keep their qualifier, so a total can still
    /// report that the food contributed something too small to count.
    public func scaled(toGrams grams: Double) -> Double? {
        switch qualifier {
        case .notAnalysed: return nil
        case .trace, .belowLOQ: return 0
        default: return amount.map { $0 * grams / 100 }
        }
    }
}
