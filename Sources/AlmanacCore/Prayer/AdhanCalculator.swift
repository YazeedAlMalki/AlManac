import Foundation
import Adhan

/// One computed prayer time. `name` matches `prayer_times_cache`'s own
/// column names (§5.22) so a caller can write a row without translating
/// vocabulary — `"fajr" | "sunrise" | "dhuhr" | "asr" | "maghrib" | "isha"`.
/// Sunrise is included because the underlying calculation produces it as a
/// byproduct (it bounds the Fajr-to-Dhuhr interval) and the cache table
/// stores it too, even though it isn't itself a prayer.
public struct PrayerTime: Sendable, Hashable {
    public let name: String
    public let timestamp: Date

    public init(name: String, timestamp: Date) {
        self.name = name
        self.timestamp = timestamp
    }

    /// The five obligatory prayers, in the order they fall in a day. Sunrise
    /// is deliberately absent: it bounds Fajr but is not itself a prayer, so
    /// nothing that alerts or counts down "to the next prayer" may treat it as
    /// one.
    public static let obligatoryNames = ["fajr", "dhuhr", "asr", "maghrib", "isha"]

    /// The English name a screen shows. One table, so the prayer screen, the
    /// fasting screen and the notification copy cannot spell a prayer three
    /// different ways.
    public static func displayName(_ name: String) -> String {
        switch name {
        case "fajr": return "Fajr"
        case "sunrise": return "Sunrise"
        case "dhuhr": return "Dhuhr"
        case "asr": return "Asr"
        case "maghrib": return "Maghrib"
        case "isha": return "Isha"
        default: return name.capitalized
        }
    }
}

/// `prayer_settings.calculationMethod`'s vocabulary (§5.22), mapped to the
/// vendored `Adhan` module's own `CalculationMethod`. `.custom` carries its
/// own angles rather than deferring to Adhan's `.other` (which has no angle
/// set at all) — `customFajrAngleDeg`/`customIshaAngleDeg` exist precisely
/// for this case.
///
/// §12.1 names five methods. The seven after `.karachi` are the other
/// authorities the vendored library already implements, added because a user
/// in Kuwait, Qatar, the Emirates, Turkey, Iran, Singapore or following the
/// Moonsighting Committee otherwise has no correct choice at all — and a wrong
/// Fajr is a wrong fast. The column is free text, so this widens the
/// vocabulary without a schema change; §12.1's five keep their spelling.
public enum PrayerCalculationMethod: Sendable, Hashable {
    case ummAlQura
    case muslimWorldLeague
    /// ISNA — Adhan's own `.northAmerica` case is this method under a
    /// different name.
    case isna
    case egyptian
    case karachi
    case dubai
    case kuwait
    case qatar
    case singapore
    case turkey
    case tehran
    case moonsightingCommittee
    case custom(fajrAngleDeg: Double, ishaAngleDeg: Double)

    /// Every stored value the settings screen offers, with its label, in the
    /// order it offers them. `custom` is last because it is the one that needs
    /// further input.
    public static let storedVocabulary: [(value: String, label: String)] = [
        ("umm_al_qura", "Umm al-Qura, Makkah"),
        ("mwl", "Muslim World League"),
        ("egypt", "Egyptian General Authority"),
        ("karachi", "University of Islamic Sciences, Karachi"),
        ("isna", "ISNA (North America)"),
        ("dubai", "Dubai"),
        ("kuwait", "Kuwait"),
        ("qatar", "Qatar"),
        ("singapore", "Singapore"),
        ("turkey", "Diyanet, Turkey"),
        ("tehran", "Institute of Geophysics, Tehran"),
        ("moonsighting_committee", "Moonsighting Committee"),
        ("custom", "Custom angles")
    ]

    var adhanParameters: Adhan.CalculationParameters {
        switch self {
        case .ummAlQura: return Adhan.CalculationMethod.ummAlQura.params
        case .muslimWorldLeague: return Adhan.CalculationMethod.muslimWorldLeague.params
        case .isna: return Adhan.CalculationMethod.northAmerica.params
        case .egyptian: return Adhan.CalculationMethod.egyptian.params
        case .karachi: return Adhan.CalculationMethod.karachi.params
        case .dubai: return Adhan.CalculationMethod.dubai.params
        case .kuwait: return Adhan.CalculationMethod.kuwait.params
        case .qatar: return Adhan.CalculationMethod.qatar.params
        case .singapore: return Adhan.CalculationMethod.singapore.params
        case .turkey: return Adhan.CalculationMethod.turkey.params
        case .tehran: return Adhan.CalculationMethod.tehran.params
        case .moonsightingCommittee: return Adhan.CalculationMethod.moonsightingCommittee.params
        case .custom(let fajrAngle, let ishaAngle):
            var params = Adhan.CalculationMethod.other.params
            params.fajrAngle = fajrAngle
            params.ishaAngle = ishaAngle
            return params
        }
    }
}

/// Which shadow length starts Asr. `prayer_settings.asrMethod` (Migration050).
///
/// Standard (Shafi'i, Maliki, Hanbali — and Umm al-Qura's own convention) is
/// one shadow-length; Hanafi is two, which puts Asr roughly an hour later. A
/// Hanafi user given the standard time prays Asr before it is due by their
/// school, so this is a correctness setting, not a preference.
public enum AsrMethod: String, Sendable, Hashable, CaseIterable {
    case standard
    case hanafi

    public var label: String {
        switch self {
        case .standard: return "Standard"
        case .hanafi: return "Hanafi"
        }
    }

    var madhab: Adhan.Madhab {
        switch self {
        case .standard: return .shafi
        case .hanafi: return .hanafi
        }
    }
}

/// Thin wrapper over the vendored `Adhan` module (`Sources/Adhan/`,
/// `batoulapps/adhan-swift`) — see `docs/features/fasting.md` §3 for why
/// this library rather than hand-written solar-position formulas.
/// `AlmanacCore`'s own callers never need to `import Adhan` themselves;
/// everything Adhan-specific stays inside this file.
public enum AdhanCalculator {
    /// Umm al-Qura's Isha during Ramadan: two hours after Maghrib instead of
    /// ninety minutes. The method is defined that way — the vendored library's
    /// own documentation of `.ummAlQura` says to add 30 minutes to Isha in
    /// Ramadan, and Saudi Arabia's published timetables do — and the library
    /// leaves it to the caller, so before this every Ramadan Isha in the app's
    /// default method was half an hour early.
    public static let ummAlQuraRamadanIshaMinutes = 120

    /// The day's five prayer times (plus sunrise) for a location.
    ///
    /// `date` names the *local calendar day* to compute for: its
    /// year/month/day in `timeZone` is what goes into the astronomical
    /// calculation, not the instant `date` itself — noon UTC and 11pm UTC
    /// on the same local calendar day produce identical results. Returned
    /// timestamps are absolute instants; format them in `timeZone` (or any
    /// zone) for display.
    ///
    /// High latitudes need no parameter here: with no rule set, the library
    /// applies its own recommendation for the coordinates (middle of the night
    /// below 48°, a seventh of the night above), which is what keeps Fajr and
    /// Isha defined through a northern summer.
    ///
    /// Returns nil only when Adhan's own calculation cannot determine
    /// sunrise/sunset for the given coordinates and date — its documented
    /// failure mode at extreme latitudes during parts of the year with no
    /// proper sunrise or sunset.
    public static func prayerTimes(latitude: Double, longitude: Double,
                                    date: Date = Date(), timeZone: TimeZone,
                                    method: PrayerCalculationMethod = .ummAlQura,
                                    asrMethod: AsrMethod = .standard) -> [PrayerTime]? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)

        var parameters = method.adhanParameters
        parameters.madhab = asrMethod.madhab
        if method == .ummAlQura, isRamadan(date, timeZone: timeZone) {
            parameters.ishaInterval = ummAlQuraRamadanIshaMinutes
        }

        guard let times = Adhan.PrayerTimes(
            coordinates: Adhan.Coordinates(latitude: latitude, longitude: longitude),
            date: components,
            calculationParameters: parameters
        ) else { return nil }

        return [
            PrayerTime(name: "fajr", timestamp: times.fajr),
            PrayerTime(name: "sunrise", timestamp: times.sunrise),
            PrayerTime(name: "dhuhr", timestamp: times.dhuhr),
            PrayerTime(name: "asr", timestamp: times.asr),
            PrayerTime(name: "maghrib", timestamp: times.maghrib),
            PrayerTime(name: "isha", timestamp: times.isha)
        ]
    }

    /// The Qibla's bearing from `latitude`/`longitude`, in degrees clockwise
    /// from true north (0..<360). Great-circle, from the vendored library.
    public static func qiblaBearing(latitude: Double, longitude: Double) -> Double {
        Adhan.Qibla(coordinates: Adhan.Coordinates(latitude: latitude, longitude: longitude)).direction
    }

    /// Whether the local calendar day containing `date` falls in Hijri month 9
    /// by the Umm al-Qura calendar — the same calendar
    /// `ReligiousFastScheduleStore` takes Ramadan from, so the Isha rule and the
    /// fast days cannot disagree about which days are Ramadan.
    static func isRamadan(_ date: Date, timeZone: TimeZone) -> Bool {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZone
        let day = gregorian.dateComponents([.year, .month, .day], from: date)
        // Re-anchor the local calendar day at UTC noon, so the Hijri lookup
        // asks about the day the user is in rather than whichever day the
        // instant happens to fall on in UTC.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        var noon = day
        noon.hour = 12
        guard let anchor = utc.date(from: noon) else { return false }
        var islamic = Calendar(identifier: .islamicUmmAlQura)
        islamic.timeZone = TimeZone(identifier: "UTC")!
        return islamic.component(.month, from: anchor) == 9
    }
}
