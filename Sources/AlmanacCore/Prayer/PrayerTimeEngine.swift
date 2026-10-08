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
        case "dubai": self = .dubai
        case "kuwait": self = .kuwait
        case "qatar": self = .qatar
        case "singapore": self = .singapore
        case "turkey": self = .turkey
        case "tehran": self = .tehran
        case "moonsighting_committee": self = .moonsightingCommittee
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
        let asrMethod = AsrMethod(rawValue: settings.asrMethod) ?? .standard

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        var written = 0
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDate) else { continue }
            let dateString = Self.dateString(day, timeZone: timeZone)

            if let existing = try cacheStore.cachedDay(dateString), existing.isManualOverride { continue }
            guard var times = AdhanCalculator.prayerTimes(latitude: latitude, longitude: longitude,
                                                           date: day, timeZone: timeZone, method: method,
                                                           asrMethod: asrMethod) else { continue }
            times = applyOffsets(times, settings: settings)

            try cacheStore.upsert(date: dateString, times: times, latitude: latitude, longitude: longitude,
                                   calculationMethod: settings.calculationMethod)
            written += 1
        }
        return written
    }

    /// §12.3's "app launches and fewer than 7 days are cached" trigger —
    /// plus one the spec's list implies without naming: today's row was
    /// computed for somewhere or some method other than the current settings.
    /// That happens whenever a settings write and its recalculation did not both
    /// land (the app was killed between them, or an older build changed the
    /// location without recalculating), and without this check the stale times
    /// stay in force for up to a month while the count looks healthy.
    ///
    /// Returns whether it actually recalculated, so a caller (or a test)
    /// can tell a warm cache from a cold one.
    @discardableResult
    public static func ensureCache(_ cacheStore: PrayerTimeCacheStore, settings: PrayerSettings,
                                    timeZone: TimeZone, at now: Date, minimumDaysCached: Int = 7) throws -> Bool {
        guard let latitude = settings.latitude, let longitude = settings.longitude else { return false }
        let today = Self.dateString(now, timeZone: timeZone)
        let enoughDays = try cacheStore.cachedDayCount(from: today) >= minimumDaysCached
        var matchesSettings = true
        if let cached = try cacheStore.cachedDay(today), !cached.isManualOverride {
            matchesSettings = cached.calculationMethod == settings.calculationMethod
                && abs(cached.latitude - latitude) < 0.0001
                && abs(cached.longitude - longitude) < 0.0001
        }
        guard !enoughDays || !matchesSettings else { return false }
        try recalculateCache(cacheStore, settings: settings, timeZone: timeZone, startDate: now)
        return true
    }

    /// A settings change the user made (method, angles, Asr rule, offsets):
    /// §12.3's first trigger. Recalculates from today, so today's own times
    /// follow the change — a user who moves Maghrib by two minutes to match
    /// their mosque means today's Maghrib too. Past days are never touched.
    @discardableResult
    public static func applySettingsChange(settingsStore: PrayerSettingsStore, cacheStore: PrayerTimeCacheStore,
                                           timeZone: TimeZone, at now: Date) throws -> Int {
        try recalculateCache(cacheStore, settings: try settingsStore.settings(), timeZone: timeZone, startDate: now)
    }

    /// §12.2's second coordinate source: a city the user picked from the
    /// bundled list. Stored with `manualCityOverride = 1` and the city's own
    /// zone, future rows are invalidated (a city is a move like any other —
    /// §12.4's "historical prayer times never altered" holds), and 30 days are
    /// recalculated from today.
    ///
    /// The caller is responsible for not feeding Core Location fixes while a
    /// manual city is chosen: §12.4 says a detected move clears the override,
    /// which is right for a user travelling with location on and wrong for one
    /// who picked a city precisely because the detected location is not where
    /// they want times for. That choice is the user's, so it lives in the app.
    public static func applyManualCity(_ city: ManualCity, at now: Date, timeZone: TimeZone,
                                       settingsStore: PrayerSettingsStore,
                                       cacheStore: PrayerTimeCacheStore) throws {
        try settingsStore.updateLocation(latitude: city.lat, longitude: city.lon, city: city.name,
                                          country: city.country, manualCityOverride: true,
                                          timezone: city.timezone)
        try cacheStore.deleteFuture(after: Self.dateString(now, timeZone: timeZone))
        try recalculateCache(cacheStore, settings: try settingsStore.settings(), timeZone: timeZone, startDate: now)
    }

    /// A fix the user asked for by tapping "use my location": applied whatever
    /// the distance, and it clears a manual city. Distinct from
    /// `applyLocationUpdate`, whose 50 km threshold exists to ignore GPS jitter
    /// on passive updates — an explicit request is not jitter, and a user who
    /// switches from "Riyadh" to their real position 20 km away should get it.
    public static func applyRequestedLocation(latitude: Double, longitude: Double, at now: Date,
                                              timeZone: TimeZone, settingsStore: PrayerSettingsStore,
                                              cacheStore: PrayerTimeCacheStore) throws {
        let near = nearestCity(latitude: latitude, longitude: longitude)
        try settingsStore.updateLocation(latitude: latitude, longitude: longitude,
                                          city: near?.name, country: near?.country,
                                          manualCityOverride: false, timezone: timeZone.identifier)
        try cacheStore.deleteFuture(after: Self.dateString(now, timeZone: timeZone))
        try recalculateCache(cacheStore, settings: try settingsStore.settings(), timeZone: timeZone, startDate: now)
    }

    /// The bundled city nearest a coordinate, if one is within `withinKm` —
    /// how a detected fix gets a name without a network geocoder (§12: "no
    /// server"). Nil rather than a far-away name: "Riyadh" shown for a fix
    /// 300 km into the desert would be a claim about where the user is.
    public static func nearestCity(latitude: Double, longitude: Double, withinKm: Double = 50) -> ManualCity? {
        var best: (city: ManualCity, km: Double)?
        for city in ManualCityCatalog.allCities {
            let km = haversineKm(lat1: latitude, lon1: longitude, lat2: city.lat, lon2: city.lon)
            if km <= withinKm, km < (best?.km ?? .infinity) { best = (city, km) }
        }
        return best?.city
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

        // The name is re-derived from the new fix. Keeping `current.city` here
        // was a bug: travel from a chosen "Riyadh" to Jeddah kept saying Riyadh.
        let near = nearestCity(latitude: latitude, longitude: longitude)
        try settingsStore.updateLocation(latitude: latitude, longitude: longitude,
                                          city: near?.name, country: near?.country, manualCityOverride: false,
                                          timezone: timeZone.identifier)
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

    static func dateString(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    static func haversineKm(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let earthRadiusKm = 6371.0088
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return earthRadiusKm * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}
