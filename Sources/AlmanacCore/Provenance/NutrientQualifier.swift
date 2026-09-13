import Foundation

/// Processing Design v0.1 §2.
///
/// A nutrient value is never a bare number. `Tr` (trace) and `N` (not analysed)
/// in CoFID are not zero; casting them to Double yields NaN, and writing 0 tells
/// a user their iron intake was zero when the truth is that nobody measured it.
/// Three distinct facts — reported zero, trace, unmeasured — that a Double
/// collapses into one.
public enum NutrientQualifier: String, Codable, Sendable, CaseIterable, Hashable {
    case measured
    case trace
    case notAnalysed = "not_analysed"
    case belowLOQ = "below_loq"
    case borrowed
    case calculatedRecipe = "calculated_recipe"
    case calculatedFactor = "calculated_factor"
    case zeroReported = "zero_reported"

    /// True when the value has a defensible numeric reading. For `trace` that
    /// reading is "negligible": no source publishes a number for a trace, so its
    /// `amount` is nil, and arithmetic takes it as zero and says so
    /// (`EnergyEstimate.inputsTakenAsZero`). `notAnalysed` has no reading at all.
    public var hasQuantity: Bool { self != .notAnalysed }

    /// True when the value is known rather than inferred or absent.
    /// The UI greys anything that is not `measured` or `zeroReported`.
    public var isDirectlyObserved: Bool {
        self == .measured || self == .zeroReported
    }
}

/// The value model from Processing Design v0.1 §2, as a Swift type.
/// `sourceValue` is the reversibility guarantee: whatever the parser gets
/// wrong, the original cell is still here to re-derive from without going
/// back to `raw/`.
public struct NutrientValue: Codable, Sendable, Hashable {
    public let foodRef: SourceIdentifier
    public let nutrientID: String
    public let amount: Double?
    public let qualifier: NutrientQualifier
    public let confidence: String?
    public let sourceValue: String
    public let sourceNutrientID: String
    public let sourceUnit: String
    public let licenceGroup: LicenceGroup
    public let basis: NutritionBasis

    public init(
        foodRef: SourceIdentifier,
        nutrientID: String,
        amount: Double?,
        qualifier: NutrientQualifier,
        confidence: String? = nil,
        sourceValue: String,
        sourceNutrientID: String,
        sourceUnit: String,
        licenceGroup: LicenceGroup,
        basis: NutritionBasis = .per100g
    ) {
        self.foodRef = foodRef
        self.nutrientID = nutrientID
        self.amount = amount
        self.qualifier = qualifier
        self.confidence = confidence
        self.sourceValue = sourceValue
        self.sourceNutrientID = sourceNutrientID
        self.sourceUnit = sourceUnit
        self.licenceGroup = licenceGroup
        self.basis = basis
    }
}
