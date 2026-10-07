import Foundation

/// A body composition metric: the subject of a card, a measurement, or a target.
///
/// **This is the vocabulary the storage layer was missing.** `body_composition_measurement.metric`
/// is a free `TEXT` column, and the only list of what may go in it was a
/// `let bodyMetricOptions = [...]` in the *view* target — so core could not
/// validate a write, a card grid could not be generated from it, and a typo
/// would be stored and read back forever. That is the same mistake `LabCatalogSeed`
/// would have been: one table's meanings living in a file that cannot see the
/// table.
///
/// `rawValue` is the stored string and is **not** a refactor away from it —
/// every existing row in every install already contains these exact values.
/// Renaming the case is free; changing `rawValue` is a data migration.
public enum BodyMetric: String, Sendable, Hashable, CaseIterable, Identifiable, Codable {
    case weight = "weight"
    case bodyFatPercent = "body_fat_pct"
    case leanMassKg = "lean_mass_kg"
    case skeletalMuscleKg = "skeletal_muscle_kg"
    case visceralRating = "visceral_rating"

    public var id: String { rawValue }

    /// The name on a card.
    public var title: String {
        switch self {
        case .weight: return localized("Weight")
        case .bodyFatPercent: return localized("Body fat")
        case .leanMassKg: return localized("Lean mass")
        case .skeletalMuscleKg: return localized("Skeletal muscle")
        case .visceralRating: return localized("Visceral rating")
        }
    }

    /// The unit a measurement in this metric is recorded in.
    public var unit: String {
        switch self {
        case .weight, .leanMassKg, .skeletalMuscleKg: return "kg"
        case .bodyFatPercent: return "pct"
        case .visceralRating: return "rating"
        }
    }

    /// The unit as a person should read it, which is not `unit`.
    ///
    /// `unit` is the stored token: `pct` rather than `%`, because a column read
    /// by a query and a label read by a person are different things and `%` in
    /// prose invites a format-string accident. So the two are separate, and a
    /// card that showed the raw `unit` would put "18.4 pct" in front of somebody
    /// where "18.4%" belongs.
    ///
    /// Empty for `visceralRating`, which is a rating on a scale and has no unit
    /// at all.
    public var displayUnit: String {
        isPercentage ? "%" : (isMass ? "kg" : "")
    }

    /// Whether the value is a proportion out of 100 rather than a mass.
    ///
    /// This is the one distinction the unit-basis toggle turns on, so it is a
    /// property of the metric rather than a comparison of unit strings at the
    /// call site. `unit == "pct"` would work today and break the day a second
    /// percentage metric arrives with a different unit.
    public var isPercentage: Bool {
        switch self {
        case .bodyFatPercent: return true
        case .weight, .leanMassKg, .skeletalMuscleKg, .visceralRating: return false
        }
    }

    /// Whether the metric is a mass in kilograms, and so has a kg form at all.
    ///
    /// `visceralRating` is deliberately not: it is a rating on a device's own
    /// scale, and dressing it as kilograms would be a unit the underlying
    /// number has never been in.
    public var isMass: Bool {
        switch self {
        case .weight, .leanMassKg, .skeletalMuscleKg: return true
        case .bodyFatPercent, .visceralRating: return false
        }
    }

    /// How many decimal places a reading of this metric is shown to.
    ///
    /// Not decoration. A visceral rating of "7.4" implies a precision the scale
    /// does not have, and a body-fat percentage shown to a tenth invites a
    /// reading of the decimal that is smaller than the error in the measurement
    /// behind it. The digit count is the app's claim about how precisely it
    /// knows this number.
    public var decimalPlaces: Int {
        switch self {
        case .weight, .leanMassKg, .skeletalMuscleKg: return 1
        case .bodyFatPercent: return 1
        case .visceralRating: return 0
        }
    }

    /// Which direction counts as progress toward a target.
    ///
    /// A meter has to know this to be honest. "Body fat 18% against a 15% target"
    /// is 60% of the way there by raw ratio and *going the wrong way* if the
    /// number has been falling. The three directions are the whole of the
    /// difference between a progress bar and a progress indicator, and getting
    /// it wrong is the kind of bug that makes a chart quietly lie.
    public var progressDirection: BodyMetricDirection {
        switch self {
        case .weight: return .towardLower
        case .bodyFatPercent, .visceralRating: return .towardLower
        case .leanMassKg, .skeletalMuscleKg: return .towardHigher
        }
    }

    /// Parses a stored `metric` string.
    ///
    /// Returns `nil` for anything not in the closed set rather than defaulting.
    /// A row this app wrote always parses; a row from a future version, a hand
    /// edit, or a bad import does not, and the card grid's answer to an unknown
    /// metric is to leave it out rather than show it under the wrong name.
    public static func parse(_ raw: String) -> BodyMetric? {
        BodyMetric(rawValue: raw)
    }
}

/// Which way a number has to move to reach its target.
public enum BodyMetricDirection: String, Sendable, Hashable, Codable {
    case towardLower
    case towardHigher

    /// Whether a change from `previous` to `current` is an improvement.
    ///
    /// A change of zero is an improvement only because there is nothing to
    /// report: a meter that called a flat week "going backwards" would be
    /// wrong in a way nobody could argue with, and one that called it
    /// "progress" would be inventing progress. So zero is neither, and
    /// `BodyCompositionProgress` renders it as unchanged.
    public func isImprovement(previous: Double?, current: Double) -> Bool {
        guard let previous, previous != current else { return false }
        switch self {
        case .towardLower: return current < previous
        case .towardHigher: return current > previous
        }
    }
}

/// Which unit the body composition screens show masses in.
///
/// **App-wide, and that is the decision the handoff flagged for confirmation.** It
/// is a property of the person reading the numbers, not of one card: someone
/// who thinks in pounds wants every mass in pounds, and a per-card toggle
/// would leave a screen showing weight in lb beside lean mass in kg with
/// nothing on screen to explain the difference. It lives in `profile` so it
/// survives leaving the screen, which a `@State` would not.
public enum UnitBasis: String, Sendable, Hashable, CaseIterable, Identifiable, Codable {
    case kilograms
    case pounds

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .kilograms: return localized("Kilograms (kg)")
        case .pounds: return localized("Pounds (lb)")
        }
    }

    public var shortTitle: String {
        switch self {
        case .kilograms: return "kg"
        case .pounds: return "lb"
        }
    }

    /// The factor from kilograms. One, because the alternative is a chain of
    /// multiply/divide at each call site and the day one of them forgets is the
    /// day a card shows a mass twice as large as it should.
    public var fromKilograms: Double {
        switch self {
        case .kilograms: return 1
        case .pounds: return 2.2046226018
        }
    }

    public func mass(_ kilograms: Double) -> Double {
        kilograms * fromKilograms
    }

    /// Kilograms back from a value in this basis. The inverse matters because a
    /// *target* the person typed in pounds has to come back to the unit the
    /// database stores, or the meter would compare pounds against kilograms and
    /// report a fraction of 2.2.
    public func kilograms(fromMass mass: Double) -> Double {
        switch self {
        case .kilograms: return mass
        case .pounds: return mass / fromKilograms
        }
    }

    public var defaultBasis: UnitBasis { .kilograms }

    /// Parses a stored `unitBasis`, with blank and unrecognised both meaning
    /// kilograms.
    ///
    /// Kilograms is the fallback because it is what every existing install
    /// already stores: `body_composition_measurement.unit` has always been `kg`,
    /// so reading the basis as pounds for a database that has never been told
    /// otherwise would convert every number in it on the strength of a value
    /// nobody wrote.
    public static func parse(_ raw: String?) -> UnitBasis {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              let parsed = UnitBasis(rawValue: trimmed) else { return .kilograms }
        return parsed
    }
}

// MARK: - Formatting in a basis

public extension UnitBasis {
    /// The unit this basis shows for `metric`, or `""` when it has none.
    ///
    /// Derived from the metric rather than stored per metric, so adding a
    /// percentage metric or a second mass does not mean adding a column to a
    /// conversion table that has to be kept in step.
    func unit(for metric: BodyMetric) -> String {
        guard metric.isMass else { return metric.displayUnit }
        return shortTitle
    }

    /// The value as a person should see it in this basis.
    ///
    /// A no-op for anything that is not a mass: a percentage and a rating are the
    /// same number in every unit basis, and converting them would be a bug with a
    /// clean-looking answer.
    func value(_ value: Double, metric: BodyMetric) -> Double {
        metric.isMass ? mass(value) : value
    }

    /// The value in this basis, at the metric's precision.
    func format(_ value: Double, metric: BodyMetric) -> String {
        BodyMetric.format(self.value(value, metric: metric), metric: metric)
    }

    /// The value in this basis with its unit, for prose and VoiceOver.
    func formatWithUnit(_ value: Double, metric: BodyMetric) -> String {
        let number = format(value, metric: metric)
        // No space before `%`: it is a suffix on the number, not a unit beside
        // it. "18.4 %" is how a spreadsheet writes it and how nobody speaks it.
        if metric.isPercentage { return "\(number)%" }
        let unit = unit(for: metric)
        return unit.isEmpty ? number : "\(number) \(unit)"
    }
}
