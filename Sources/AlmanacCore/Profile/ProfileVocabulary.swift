import Foundation

/// How long a person has been training, as the handoff names it.
///
/// **Levels, not years.** The handoff asks for "Novice / beginner / moderate /
/// expert" and the column stores those; `yearsOfTraining` is deliberately not
/// here, because it would be a second answer to the same question and the two
/// disagree — somebody with four years of marathon running and somebody with four
/// years of couch-to-5k are not at the same point, and a year count cannot say
/// which. What the levels are *for* is calibrating advice, so the axis is
/// experience rather than elapsed time.
///
/// `notSet` is a member rather than `nil` being the only absence, matching
/// `BiologicalSex`: "I have not said" is the state of every install until somebody
/// opens Settings, and it must not present as an error the way a corrupt value
/// should.
public enum TrainingExperience: String, Sendable, Hashable, CaseIterable, Identifiable, Codable {
    case notSet = "not_set"
    case novice
    case beginner
    case intermediate
    case advanced

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .notSet: return localized("Prefer not to say")
        case .novice: return localized("Novice")
        case .beginner: return localized("Beginner")
        case .intermediate: return localized("Intermediate")
        case .advanced: return localized("Advanced")
        }
    }

    public var explanation: String {
        switch self {
        case .notSet: return localized("The app will not tailor advice to your level.")
        case .novice: return localized("New to structured training.")
        case .beginner: return localized("A few months of regular training.")
        case .intermediate: return localized("Consistent training, and comfortable progressing it.")
        case .advanced: return localized("Years of training, including competition or coaching.")
        }
    }

    /// Whether advice may assume the app knows how much to push.
    ///
    /// `notSet` is false, deliberately: the point of declining to say is that
    /// nothing is assumed, and treating the absence as "moderate" would be the
    /// app guessing on the person's behalf about the one thing they withheld.
    public var allowsProgressiveAdvice: Bool { self != .notSet }

    /// Parses a stored value, with blank and unrecognised both meaning `notSet`.
    ///
    /// Case- and whitespace-insensitive, for the same reason as
    /// `BiologicalSex.parse`: a value typed by hand has to read the same as one
    /// picked from a list.
    public static func parse(_ raw: String?) -> TrainingExperience {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              let parsed = TrainingExperience(rawValue: trimmed) else { return .notSet }
        return parsed
    }
}

/// A blood type, including the Rh factor as part of the value.
///
/// **Eight types plus `unknown`, and `unknown` is not the null.** "I don't know
/// my blood type" is a true and common thing to be; "nobody has asked yet" is a
/// different statement and would silently become the first one if the column
/// stored NULL for both. So the value a person declines to give is storable, and
/// the picker shows it.
///
/// A+ as one value rather than a type column and an Rh column, because the two
/// are never observed separately — there is no record anywhere that says A
/// without a factor — and two columns would allow a row that cannot exist.
public enum BloodType: String, Sendable, Hashable, CaseIterable, Identifiable, Codable {
    case aPositive = "A+"
    case aNegative = "A-"
    case bPositive = "B+"
    case bNegative = "B-"
    case abPositive = "AB+"
    case abNegative = "AB-"
    case oPositive = "O+"
    case oNegative = "O-"
    case unknown

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .aPositive: return "A+"
        case .aNegative: return "A-"
        case .bPositive: return "B+"
        case .bNegative: return "B-"
        case .abPositive: return "AB+"
        case .abNegative: return "AB-"
        case .oPositive: return "O+"
        case .oNegative: return "O-"
        case .unknown: return localized("I don't know")
        }
    }

    public var explanation: String {
        switch self {
        case .unknown: return localized("Leave it blank and nothing depends on it.")
        default: return localized("Not used anywhere in the app yet. Recorded for when it is.")
        }
    }

    /// Whether a value is a real type rather than a stated absence.
    public var isKnown: Bool { self != .unknown }

    /// Parses a stored value, with blank and unrecognised both meaning `unknown`.
    ///
    /// Case- and whitespace-insensitive: the "A+" a person types is `a+`, and
    /// blood type is the one place where silently reading a stated value as an
    /// unknown one is least acceptable, because the app is recording something a
    /// clinician asked for.
    public static func parse(_ raw: String?) -> BloodType {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              let parsed = BloodType(rawValue: trimmed) else { return .unknown }
        return parsed
    }
}
