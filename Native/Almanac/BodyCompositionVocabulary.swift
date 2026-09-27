import Foundation

/// The tag vocabulary `context_event.tags` draws on.
///
/// A closed set in Swift rather than ten free-text strings, for the same reason
/// `NutritionMealType` is one: these are the confounders readiness and
/// correlation get *asked about*, and a query like "does an `illness` tag
/// precede a readiness drop" needs the value to be the same value every time.
/// Migration018's comment lists the ten; a tag outside the list is still
/// storable (`tags` is a JSON array, not a CHECKed column) but nothing will
/// ever read it, so the picker offers exactly these.
enum ContextTag: String, CaseIterable, Identifiable, Hashable {
    case illness
    case medicationChange = "medication_change"
    case travelJetLag = "travel_jet_lag"
    case unusualStress = "unusual_stress"
    case heatExposure = "heat_exposure"
    case sauna
    case poorWatchWear = "poor_watch_wear"
    case lateNightEvent = "late_night_event"
    case sleepInterruption = "sleep_interruption"
    case competitionDay = "competition_day"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .illness: return "Illness"
        case .medicationChange: return "Medication change"
        case .travelJetLag: return "Travel or jet lag"
        case .unusualStress: return "Unusual stress"
        case .heatExposure: return "Heat exposure"
        case .sauna: return "Sauna"
        case .poorWatchWear: return "Poor watch wear"
        case .lateNightEvent: return "Late night event"
        case .sleepInterruption: return "Sleep interruption"
        case .competitionDay: return "Competition day"
        }
    }
}

/// Supplement plan vocabularies, from `supplement_plan`'s column comments.
///
/// Also closed sets: `doseUnit` and `frequency` are read by
/// `NotificationTriggerAssembler` and by the adherence maths, neither of which
/// can do anything sensible with a unit it has never heard of.
enum SupplementDoseUnit: String, CaseIterable, Identifiable, Hashable {
    case milligram = "mg"
    case gram = "g"
    case millilitre = "ml"
    case tablet
    case capsule
    case scoop

    var id: String { rawValue }
    var title: String { rawValue }
}

enum SupplementFrequency: String, CaseIterable, Identifiable, Hashable {
    case daily
    case twiceDaily = "twice_daily"
    case preWorkout = "pre_workout"
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: return "Daily"
        case .twiceDaily: return "Twice daily"
        case .preWorkout: return "Pre-workout"
        case .custom: return "Custom"
        }
    }
}

/// How often a plan is *expected*, which is what adherence is measured against.
///
/// Derived from `frequency` rather than stored, because the only question the
/// adherence row asks is "was this due today and not taken" — and a plan whose
/// frequency nothing in the UI can set has no due count to divide by.
enum SupplementSchedule {
    /// How many times a day this frequency expects, when the frequency states a
    /// count at all. Nil for `.custom`, where the plan's own `timingNotes` is
    /// the only statement of the schedule and parsing prose would be a guess.
    static func expectedPerDay(_ frequency: String) -> Int? {
        switch frequency {
        case SupplementFrequency.daily.rawValue: return 1
        case SupplementFrequency.twiceDaily.rawValue: return 2
        case SupplementFrequency.preWorkout.rawValue: return 1
        default: return nil
        }
    }

    static func title(_ frequency: String) -> String {
        SupplementFrequency(rawValue: frequency)?.title ?? readable(frequency)
    }
}
