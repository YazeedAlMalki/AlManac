import Foundation

public enum NutritionError: Error, CustomStringConvertible, Sendable {
    case foodNotFound(SourceIdentifier)
    case invalidGramWeight(Double)
    case invalidAmount(Double)
    case notANativeFood(SourceIdentifier)
    case recipeCycle(SourceIdentifier)
    case dishHasNoRecipe(SourceIdentifier)

    public var description: String {
        switch self {
        case .foodNotFound(let ref):
            return "no food '\(ref)' in the nutrition catalog."
        case .invalidGramWeight(let g):
            return "a portion's gram weight must be finite and greater than zero; got \(g)."
        case .invalidAmount(let a):
            return "a measure's amount must be finite and greater than zero; got \(a)."
        case .notANativeFood(let ref):
            return "'\(ref)' is published by \(ref.namespace.rawValue); only 'almanac:' foods "
                 + "may be authored here. A publisher's row is corrected upstream, not edited."
        case .recipeCycle(let ref):
            return "'\(ref)' would end up an ingredient of itself, directly or through "
                 + "another dish. The reduction would then compute each from the other's "
                 + "previous answer and report a number with nothing behind it."
        case .dishHasNoRecipe(let ref):
            return "'\(ref)' has no recipe to recompute from. Its values were entered "
                 + "directly, and reducing an empty ingredient list would replace them "
                 + "with nothing."
        }
    }
}
