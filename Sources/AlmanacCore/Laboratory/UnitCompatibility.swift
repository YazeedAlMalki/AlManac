import Foundation

/// Whether two reported units may be compared — **not** a converter.
///
/// This slice performs no automatic conversion. Blanket permission to convert
/// "dimensionless" quantities was withdrawn: a percentage, a ratio and a titer
/// are all dimensionless and none of them is interchangeable with another.
/// So compatibility requires the same semantic dimension *and* a known scale
/// relationship, and even then the answer is a verdict, not a converted number.
public enum UnitDimension: String, Sendable, CaseIterable, Hashable {
    case massPerVolume, substancePerVolume, mass, volume
    case percentage, ratio, titer, activityPerVolume, cellsPerVolume
}

public enum UnitCompatibility: Sendable, Hashable {
    /// Same dimension and same scale — directly comparable.
    case identical(UnitDimension)
    /// Same dimension, different scale. `factor` converts left to right, but
    /// this slice does not apply it.
    case sameDimensionDifferentScale(UnitDimension, factor: Double)
    /// Known to be different dimensions — never comparable without an
    /// analyte-specific factor that this slice does not hold.
    case differentDimension(UnitDimension, UnitDimension)
    /// One or both units are not in the table. Not an assertion of anything.
    case undetermined
}

public enum UnitRegistry {
    /// Deliberately small and explicit. An unknown unit yields `.undetermined`
    /// rather than a guess, and adding one is a data change with a stated
    /// dimension and scale.
    static let table: [String: (dimension: UnitDimension, scale: Double)] = [
        "g/l":      (.massPerVolume, 1.0),
        "mg/dl":    (.massPerVolume, 0.01),
        "mg/l":     (.massPerVolume, 0.001),
        "ug/l":     (.massPerVolume, 0.000001),
        "ng/ml":    (.massPerVolume, 0.000001),
        "ug/dl":    (.massPerVolume, 0.00001),
        "ng/dl":    (.massPerVolume, 0.00000001),
        "pg/ml":    (.massPerVolume, 0.000000001),
        "mol/l":    (.substancePerVolume, 1.0),
        "mmol/l":   (.substancePerVolume, 0.001),
        "umol/l":   (.substancePerVolume, 0.000001),
        "nmol/l":   (.substancePerVolume, 0.000000001),
        "pmol/l":   (.substancePerVolume, 0.000000000001),
        "kg":       (.mass, 1.0),
        "g":        (.mass, 0.001),
        "lb":       (.mass, 0.45359237),
        "%":        (.percentage, 1.0),
        "percent":  (.percentage, 1.0),
        "ratio":    (.ratio, 1.0),
        "titer":    (.titer, 1.0),
        "u/l":      (.activityPerVolume, 1.0),
        "iu/l":     (.activityPerVolume, 1.0),
        "iu/ml":    (.activityPerVolume, 1000.0),
        "10^9/l":   (.cellsPerVolume, 1.0),
        "10^12/l":  (.cellsPerVolume, 1000.0)
    ]

    static func key(_ unitText: String) -> String {
        unitText.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "µ", with: "u")
            .replacingOccurrences(of: "μ", with: "u")
    }

    public static func assess(_ a: String?, _ b: String?) -> UnitCompatibility {
        guard let a, let b,
              let left = table[key(a)], let right = table[key(b)] else { return .undetermined }
        guard left.dimension == right.dimension else {
            return .differentDimension(left.dimension, right.dimension)
        }
        if left.scale == right.scale { return .identical(left.dimension) }
        return .sameDimensionDifferentScale(left.dimension, factor: left.scale / right.scale)
    }

    /// Whether two observations may be placed on one series without conversion.
    /// `sameDimensionDifferentScale` is false here on purpose: conversion is
    /// deferred, so a scaled pair is comparable only once conversion lands.
    public static func directlyComparable(_ a: String?, _ b: String?) -> Bool {
        if case .identical = assess(a, b) { return true }
        return false
    }
}
