import Foundation

extension PrayerCalculationMethod {
    /// Maps `prayer_settings.calculationMethod`'s stored vocabulary onto the
    /// calculator's own type. Falls back to `.ummAlQura` for an unrecognized
    /// or not-yet-set value — the schema's own column default (Migration024).
    init(settings: PrayerSettings) {
        switch settings.calculationMethod {
        case "mwl": self = .muslimWorldLeague
        case "isna": self = .isna
        case "egypt": self = .egyptian
        case "karachi": self = .karachi
        case "custom":
            self = .custom(fajrAngleDeg: settings.customFajrAngleDeg ?? 18.5,
                            ishaAngleDeg: settings.customIshaAngleDeg ?? 18.5)
        default: self = .ummAlQura
        }
    }
}

/// §12.3 (caching) and §12.4 (travel handling) — the orchestration that
/// composes `AdhanCalculator`, `PrayerSettingsStore`, and
/// `PrayerTimeCacheStore`. None of those three know about each other; this
/// is where they meet.
///
/// **Deliberately not built here:** reacting automatically to a
/// `PrayerSettingsStore` write (§12.3's "prayer settings change" trigger).
/// There is no settings-change observer anywhere in this repo — every store
/// is a plain read/write surface a caller drives explicitly (see
/// `ReadinessModel.refresh()` for the same pattern). A UI that changes the
/// calculation method or offsets is expected to call `recalculateCache`
/// itself right after, the same way it would call `refresh()` after a write
/// elsewhere.
public enum PrayerTimeEngine {
    /// Writes `days` consecutive calendar days of prayer times starting at
    /// `startDate`, in `timeZone`, using `settings`. A day already flagged
    /// `isManualOverride` in the cache is left untouched — that flag exists
    /// precisely so a user's correction to one future day survives an
    /// automatic recalculation (`PrayerTimeCacheStore.deleteFuture` makes
    /// the same exception).
    ///
    /// Does nothing and returns 0 if `settings` has no location yet — there
    /// is nothing to calculate against, which is the normal state before a
    /// user has granted location or picked a city (§12.2), not an error.
    @discardableResult
    public static func recalculateCache(_ cacheStore: PrayerTimeCacheStore, settings: PrayerSettings,
                                         timeZone: TimeZone, startDate: Date, days: Int = 30) throws -> Int {
        guard let latitude = settings.latitude, let longitude = settings.longitude else { return 0 }
        let method = PrayerCalculationMethod(settings: settings)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        var written = 0
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDate) else { continue }
            let dateString = Self.dateString(day, timeZone: timeZone)

            if let existing = try cacheStore.cachedDay(dateString), existing.isManualOverride { continue }
            guard var times = AdhanCalculator.prayerTimes(latitude: latitude, longitude: longitude,
                                                           date: day, timeZone: timeZone, method: method) else { continue }
            times = applyOffsets(times, settings: settings)

            try cacheStore.upsert(date: dateString, times: times, latitude: latitude, longitude: longitude,
                                   calculationMethod: settings.calculationMethod)
            written += 1
        }
        return written
    }

    /// §12.3's "app launches and fewer than 7 days are cached" trigger.
    /// Returns whether it actually recalculated, so a caller (or a test)
    /// can tell a warm cache from a cold one.
    @discardableResult
    public static func ensureCache(_ cacheStore: PrayerTimeCacheStore, settings: PrayerSettings,
                                    timeZone: TimeZone, at now: Date, minimumDaysCached: Int = 7) throws -> Bool {
        guard settings.latitude != nil, settings.longitude != nil else { return false }
        let today = Self.dateString(now, timeZone: timeZone)
        guard try cacheStore.cachedDayCount(from: today) < minimumDaysCached else { return false }
        try recalculateCache(cacheStore, settings: settings, timeZone: timeZone, startDate: now)
        return true
    }

    /// §12.4, the full travel flow: only a genuine move (> `thresholdKm`,
    /// default 50) does anything. A real move updates `prayer_settings` to
    /// the new coordinates (clearing `manualCityOverride`, since this is a
    /// detected location, not a picked city), deletes future cache rows,
    /// and recalculates 30 days from `now`. Past cached dates are untouched
    /// — `deleteFuture` only ever removes rows strictly after today.
    @discardableResult
    public static func applyLocationUpdate(latitude: Double, longitude: Double, at now: Date, timeZone: TimeZone,
                                            settingsStore: PrayerSettingsStore, cacheStore: PrayerTimeCacheStore,
                                            thresholdKm: Double = 50) throws -> Bool {
        let current = try settingsStore.settings()
        if let currentLat = current.latitude, let currentLon = current.longitude {
            let distance = haversineKm(lat1: currentLat, lon1: currentLon, lat2: latitude, lon2: longitude)
            guard distance > thresholdKm else { return false }
        }

        try settingsStore.updateLocation(latitude: latitude, longitude: longitude,
                                          city: current.city, country: current.country, manualCityOverride: false)
        let today = Self.dateString(now, timeZone: timeZone)
        try cacheStore.deleteFuture(after: today)
        try recalculateCache(cacheStore, settings: try settingsStore.settings(), timeZone: timeZone, startDate: now)
        return true
    }

    // MARK: - Private

    private static func applyOffsets(_ times: [PrayerTime], settings: PrayerSettings) -> [PrayerTime] {
        let offsets: [String: Int] = [
            "fajr": settings.fajrOffsetMin, "dhuhr": settings.dhuhrOffsetMin,
            "asr": settings.asrOffsetMin, "maghrib": settings.maghribOffsetMin,
            "isha": settings.ishaOffsetMin
        ]
        return times.map { time in
            guard let minutes = offsets[time.name], minutes != 0 else { return time }
            return PrayerTime(name: time.name, timestamp: time.timestamp.addingTimeInterval(Double(minutes) * 60))
        }
    }

    private static func dateString(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func haversineKm(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let earthRadiusKm = 6371.0088
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return earthRadiusKm * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}
