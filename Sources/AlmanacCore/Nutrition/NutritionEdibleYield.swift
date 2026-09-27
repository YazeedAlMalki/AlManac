import Foundation

/// What a food's own data can and cannot say about turning an *as-purchased*
/// mass into an *edible* one.
///
/// This is the answer `edibleGrams` gives, and it is deliberately a four-way
/// split rather than a `Double?`. The reason is the shape of the data: CoFID
/// ships an edible proportion for 2,887 of the bundle's 8,354 foods, so the
/// common case is *nobody stated one*. Collapsing that into `nil` next to a
/// genuine "not analysed" would invite the two most tempting wrong moves —
///
/// ```swift
/// factor?.value ?? 1.0   // invents "nothing is discarded" for ~65% of foods
/// factor?.value ?? gross // silently reports a gross mass as an edible one
/// ```
///
/// — and both produce a plausible number for a food the data says nothing
/// about. `NutritionTotals` already treats an unmeasured nutrient as a named
/// gap (`incompleteNutrients`) rather than a zero; this follows the same rule
/// one step earlier, at the point the mass is decided.
public enum EdibleYield: Sendable, Hashable {
    /// The publisher stated a proportion and it is usable.
    case known(proportion: Double, source: NutritionFactorSource)
    /// A factor row exists but carries no number (CoFID's `N`, "not
    /// analysed"). The proportion is unknown, and the source said so.
    case notAnalysed(source: NutritionFactorSource)
    /// The food has no factor row of this kind at all — the majority of the
    /// catalogue, and every food outside CoFID.
    case unstated
    /// A proportion that cannot be used: outside `(0, 1]`, or not finite.
    /// Kept separate from `unstated` because the data *claimed* something and
    /// it is the bundle's problem, not the caller's.
    case unusable(reason: String)
}

/// Where a factor came from, so a derived mass can name its own provenance.
public enum NutritionFactorSource: Sendable, Hashable {
    /// A device-authored `almanac:` dish's own `nutrition_dish.edible_proportion`.
    case dish
    /// A bundle reference food's `nutrition_food_factor`, with the publisher's
    /// own text for the number.
    case reference(record: String, value: String, licence: LicenceGroup)

    public var shortDescription: String {
        switch self {
        case .dish: return "your recipe"
        case .reference(_, let value, _): return value
        }
    }
}

/// Gross (as-purchased) mass -> edible mass.
///
/// The rule is the publisher's, never an assumption: an edible proportion is
/// applied when one was actually stated, and the absence of one is reported as
/// the absence of one.
public struct EdibleYieldCalculator: Sendable {
    private let db: Database
    private let catalog: NutritionCatalog

    public init(db: Database) {
        self.db = db
        self.catalog = NutritionCatalog(db: db)
    }

    /// The edible mass of `grossGrams` of `ref`.
    ///
    /// A dish carries its own `edible_proportion` (`nutrition_dish`) and a
    /// reference food carries the bundle's `nutrition_food_factor`; a dish's
    /// own authored figure wins, because it is the one the user decided.
    ///
    /// `grossGrams` must be a real mass — a non-finite or non-positive input is
    /// a caller error, not a data gap, and throws rather than reporting
    /// `.unusable`.
    public func edibleGrams(fromGrossGrams grossGrams: Double,
                             for ref: SourceIdentifier) throws -> EdibleYieldResult {
        guard grossGrams.isFinite, grossGrams > 0 else {
            throw NutritionError.invalidGramWeight(grossGrams)
        }
        return try Self.resolve(grossGrams: grossGrams, proportion: try edibleProportion(for: ref))
    }

    /// The proportion alone, without applying it. Exposed because a UI that
    /// lets someone say "this is as-purchased" needs to know whether that claim
    /// is supportable *before* they say it, and "unstated" is the answer it
    /// must be able to show.
    public func edibleProportion(for ref: SourceIdentifier) throws -> EdibleProportion {
        if ref.namespace == .almanac {
            guard let dish = try NutritionDishEditor(db: db).dish(ref) else { return .unstated }
            guard let value = dish.edibleProportion else { return .unstated }
            return Self.checked(value, from: .dish)
        }
        guard let factor = try catalog.foodFactor(of: ref, kind: .edibleProportion) else {
            return .unstated
        }
        let source = NutritionFactorSource.reference(
            record: ref.description, value: factor.sourceValue, licence: factor.licenceGroup)
        guard let value = factor.value else { return .notAnalysed(source: source) }
        return Self.checked(value, from: source)
    }

    /// A mass from a volume, using the food's density (`specific_gravity`,
    /// grams per millilitre).
    ///
    /// The only case this answers is a volume a person typed, because mL is
    /// nowhere in the device schema: `nutrition_portion.gram_weight` already
    /// converts a household measure straight to grams, so a "1 cup" is better
    /// served by `catalog.grams(of:amount:unit:)` and never reaches here.
    public func grams(fromVolumeMillilitres millilitres: Double,
                      for ref: SourceIdentifier) throws -> EdibleYieldResult {
        guard millilitres.isFinite, millilitres > 0 else {
            throw NutritionError.invalidAmount(millilitres)
        }
        guard let factor = try catalog.foodFactor(of: ref, kind: .specificGravity) else {
            return .unstated
        }
        let source = NutritionFactorSource.reference(
            record: ref.description, value: factor.sourceValue, licence: factor.licenceGroup)
        guard let gramsPerMillilitre = factor.value else { return .notAnalysed(source: source) }
        guard gramsPerMillilitre.isFinite, gramsPerMillilitre > 0 else {
            return .unusable(reason: "stated density \(factor.sourceValue) is not a positive number of grams per millilitre")
        }
        return .known(edibleGrams: try Self.checkedMass(millilitres * gramsPerMillilitre), source: source)
    }

    private static func resolve(grossGrams: Double, proportion: EdibleProportion) throws -> EdibleYieldResult {
        switch proportion {
        case .unstated:
            return .unstated
        case .notAnalysed(let source):
            return .notAnalysed(source: source)
        case .unusable(let reason):
            return .unusable(reason: reason)
        case .known(let value, let source):
            return .known(edibleGrams: try checkedMass(grossGrams * value), source: source)
        }
    }

    private static func checked(_ value: Double, from source: NutritionFactorSource) -> EdibleProportion {
        // A proportion is a fraction: (0, 1]. Zero would mean "nothing of it is
        // eaten", which is not what a missing-but-nonzero row means, and above
        // 1 is a unit error the device cannot interpret. Neither is silently
        // clamped.
        guard value.isFinite, value > 0, value <= 1 else {
            return .unusable(reason: "edible proportion \(source.shortDescription) is outside (0, 1]")
        }
        return .known(value, from: source)
    }

    private static func checkedMass(_ grams: Double) throws -> Double {
        guard grams.isFinite, grams >= 0 else {
            throw NutritionError.invalidGramWeight(grams)
        }
        return grams
    }
}

/// The proportion behind an edible-mass decision, kept separate from the
/// outcome so a caller can ask the question without performing the arithmetic.
public enum EdibleProportion: Sendable, Hashable {
    case known(Double, from: NutritionFactorSource)
    case notAnalysed(source: NutritionFactorSource)
    case unstated
    case unusable(reason: String)
}

/// The outcome of an edible-mass derivation.
///
/// A `known` result carries the edible grams *and* the proportion used, so a
/// caller can persist either and re-derive neither. A stored edible mass with
/// no record of the proportion that produced it is a number nobody can check.
public enum EdibleYieldResult: Sendable, Hashable {
    case known(edibleGrams: Double, source: NutritionFactorSource)
    case notAnalysed(source: NutritionFactorSource)
    case unstated
    case unusable(reason: String)

    /// The edible grams, or nil when the food's data does not support one.
    ///
    /// Callers that genuinely have to store something should store the *gross*
    /// mass and this nil together; see `EdibleYieldCalculator` for why the
    /// other two defaults are wrong.
    public var edibleGrams: Double? {
        if case .known(let grams, _) = self { return grams }
        return nil
    }

    /// Whether the caller may treat the entered mass as already-edible.
    ///
    /// True only for `known`, and explicitly *not* for `unstated`: a food
    /// nobody published a proportion for is very often eaten with nothing
    /// discarded, and sometimes very much is. The distinction is not something
    /// this function can make.
    public var isStated: Bool { edibleGrams != nil }
}
