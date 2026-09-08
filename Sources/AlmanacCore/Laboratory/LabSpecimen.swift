import Foundation

/// The broad material a specimen came from.
///
/// Kept separate from `SpecimenKind` because the merge rule is a statement
/// about matrices: a urine result and a blood result describe different
/// compartments and are never two points on one series, whatever the analyte.
public enum SpecimenMatrix: String, Codable, Sendable, CaseIterable, Hashable {
    case blood, urine, other, unknown
}

/// The specimen a result was measured in. Optional everywhere: a historical
/// paper report frequently does not say, and `unknown` is the recorded answer
/// rather than a reason to refuse the entry or to assume blood.
public enum SpecimenKind: String, Codable, Sendable, CaseIterable, Hashable {
    /// Stated as blood without saying which fraction.
    case blood
    case serum
    case plasma
    case wholeBlood = "whole_blood"
    case urine
    /// Stated, and not one of the above — saliva, CSF, stool, hair.
    case other
    /// Not stated. Distinct from `other`, which means stated-and-different.
    case unknown

    public var matrix: SpecimenMatrix {
        switch self {
        case .blood, .serum, .plasma, .wholeBlood: return .blood
        case .urine:   return .urine
        case .other:   return .other
        case .unknown: return .unknown
        }
    }

    /// Whether two results may be placed on one series.
    ///
    /// Conservative on purpose: only an identical, stated kind qualifies.
    /// `unknown` is comparable with nothing, **including another `unknown`** —
    /// two records that both fail to say what they measured are not evidence
    /// that they measured the same thing. Serum and plasma are also kept apart:
    /// they are different fractions and their reference intervals differ.
    public static func directlyComparable(_ a: SpecimenKind, _ b: SpecimenKind) -> Bool {
        a != .unknown && a == b
    }

    /// Whether two results are *known* to describe different material. This is
    /// the guard against merging a blood result with a urine one; it answers
    /// false when either side is unstated, because that is not knowledge.
    public static func knownDifferentMaterial(_ a: SpecimenKind, _ b: SpecimenKind) -> Bool {
        guard a.matrix != .unknown, b.matrix != .unknown else { return false }
        return a.matrix != b.matrix
    }
}

/// What a catalog entry actually measures.
///
/// A vitamin family contains more than direct measurements of the vitamin.
/// Beta-carotene is a dietary **precursor** of vitamin A, not vitamin A.
/// Methylmalonic acid rises when B12 is functionally insufficient — it is a
/// **metabolic marker** of B12 status, not a B12 measurement. EGRAC and
/// PIVKA-II are enzyme- and protein-based **functional markers** of riboflavin
/// and vitamin K status respectively, and neither reports an amount of the
/// vitamin at all. Counting all of these as "forms of the vitamin" overstates
/// coverage, which is why the role is a column and not a comment.
public enum MeasurementRole: String, Codable, Sendable, CaseIterable, Hashable {
    /// Measures the substance itself, or one of its own metabolites.
    case direct
    /// Measures something the body converts into the substance.
    case precursor
    /// Measures an enzyme or protein whose behaviour depends on the substance.
    case functionalMarker = "functional_marker"
    /// Measures a metabolite that accumulates when the substance is short.
    case metabolicMarker = "metabolic_marker"

    /// True only for `direct`. A functional or metabolic marker answers
    /// "is status adequate", never "how much is present", so the two must not
    /// be trended together or counted as the same measurement.
    public var reportsAmountOfTheSubstance: Bool { self == .direct }
}
