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
}

/// `prayer_settings.calculationMethod`'s vocabulary (§5.22), mapped to the
/// vendored `Adhan` module's own `CalculationMethod`. `.custom` carries its
/// own angles rather than deferring to Adhan's `.other` (which has no angle
/// set at all) — `customFajrAngleDeg`/`customIshaAngleDeg` exist precisely
/// for this case.
public enum PrayerCalculationMethod: Sendable, Hashable {
    case ummAlQura
    case muslimWorldLeague
    /// ISNA — Adhan's own `.northAmerica` case is this method under a
    /// different name.
    case isna
    case egyptian
    case karachi
    case custom(fajrAngleDeg: Double, ishaAngleDeg: Double)

    var adhanParameters: Adhan.CalculationParameters {
        switch self {
        case .ummAlQura: return Adhan.CalculationMethod.ummAlQura.params
        case .muslimWorldLeague: return Adhan.CalculationMethod.muslimWorldLeague.params
        case .isna: return Adhan.CalculationMethod.northAmerica.params
        case .egyptian: return Adhan.CalculationMethod.egyptian.params
        case .karachi: return Adhan.CalculationMethod.karachi.params
        case .custom(let fajrAngle, let ishaAngle):
            var params = Adhan.CalculationMethod.other.params
            params.fajrAngle = fajrAngle
            params.ishaAngle = ishaAngle
            return params
        }
    }
}

/// Thin wrapper over the vendored `Adhan` module (`Sources/Adhan/`,
/// `batoulapps/adhan-swift`) — see `docs/features/fasting.md` §3 for why
/// this library rather than hand-written solar-position formulas.
/// `AlmanacCore`'s own callers never need to `import Adhan` themselves;
/// everything Adhan-specific stays inside this file.
public enum AdhanCalculator {
    /// The day's five prayer times (plus sunrise) for a location.
    ///
    /// `date` names the *local calendar day* to compute for: its
    /// year/month/day in `timeZone` is what goes into the astronomical
    /// calculation, not the instant `date` itself — noon UTC and 11pm UTC
    /// on the same local calendar day produce identical results. Returned
    /// timestamps are absolute instants; format them in `timeZone` (or any
    /// zone) for display.
    ///
    /// Returns nil only when Adhan's own calculation cannot determine
    /// sunrise/sunset for the given coordinates and date — its documented
    /// failure mode at extreme latitudes during parts of the year with no
    /// proper sunrise or sunset.
    public static func prayerTimes(latitude: Double, longitude: Double,
                                    date: Date = Date(), timeZone: TimeZone,
                                    method: PrayerCalculationMethod = .ummAlQura) -> [PrayerTime]? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)

        guard let times = Adhan.PrayerTimes(
            coordinates: Adhan.Coordinates(latitude: latitude, longitude: longitude),
            date: components,
            calculationParameters: method.adhanParameters
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
}
