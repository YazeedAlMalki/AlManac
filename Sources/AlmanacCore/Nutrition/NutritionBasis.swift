import Foundation

/// Processing Design v0.1 §4, trap 1: per 100 g and per 100 mL are not
/// interchangeable, so the basis is a column, never an assumption.
public enum NutritionBasis: String, Codable, Sendable, CaseIterable, Hashable {
    case per100g = "per_100g"
    case per100ml = "per_100ml"
}
