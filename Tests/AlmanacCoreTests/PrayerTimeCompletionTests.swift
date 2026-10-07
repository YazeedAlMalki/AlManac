import Testing
import Foundation
@testable import AlmanacCore

/// The prayer-time half of §12 that existed in the spec and not in the app:
/// the manual city, the Asr rule, Umm al-Qura's Ramadan Isha, a name for a
/// detected fix, and the alerts.
@Suite("Prayer times, completed")
struct PrayerTimeCompletionTests {
    let db: Database
    let riyadh = TimeZone(identifier: "Asia/Riyadh")!

    init() throws {
        db = try TestDatabase()
    }

    private func noon(_ date: String, in tz: TimeZone? = nil) -> Date {
        let bits = date.split(separator: "-").compactMap { Int($0) }
        var comps = DateComponents()
        comps.year = bits[0]; comps.month = bits[1]; comps.day = bits[2]; comps.hour = 12
        comps.timeZone = tz ?? riyadh
        return Calendar(identifier: .gregorian).date(from: comps)!
    }

    private func time(_ name: String, in times: [PrayerTime]) -> Date {
        times.first { $0.name == name }!.timestamp
    }

    // MARK: - Calculation

    @Test("Umm al-Qura's Isha is two hours after Maghrib in Ramadan")
    func ummAlQuraRamadanIsha() throws {
        let ramadan = try #require(ReligiousFastScheduleStore.ramadanRange(hijriYear: 1448))
        let inRamadan = try #require(AdhanCalculator.prayerTimes(
            latitude: 24.7136, longitude: 46.6753, date: noon(ramadan.start), timeZone: riyadh))
        #expect(abs(time("isha", in: inRamadan).timeIntervalSince(time("maghrib", in: inRamadan)) - 120 * 60) < 5)

        // Other methods are untouched by it.
        let mwl = try #require(AdhanCalculator.prayerTimes(
            latitude: 24.7136, longitude: 46.6753, date: noon(ramadan.start), timeZone: riyadh,
            method: .muslimWorldLeague))
        #expect(abs(time("isha", in: mwl).timeIntervalSince(time("maghrib", in: mwl)) - 120 * 60) > 5)
    }

    @Test("Hanafi Asr comes well after the standard Asr")
    func hanafiAsrIsLater() throws {
        let standard = try #require(AdhanCalculator.prayerTimes(
            latitude: 24.7136, longitude: 46.6753, date: noon("2026-09-17"), timeZone: riyadh))
        let hanafi = try #require(AdhanCalculator.prayerTimes(
            latitude: 24.7136, longitude: 46.6753, date: noon("2026-09-17"), timeZone: riyadh, asrMethod: .hanafi))
        let difference = time("asr", in: hanafi).timeIntervalSince(time("asr", in: standard))
        #expect(difference > 30 * 60 && difference < 90 * 60)
        #expect(time("fajr", in: hanafi) == time("fajr", in: standard), "the Asr rule moves only Asr")
    }

    @Test("Every offered method maps from its stored value and calculates")
    func everyOfferedMethodCalculates() throws {
        for (value, _) in PrayerCalculationMethod.storedVocabulary {
            let settings = PrayerSettings(calculationMethod: value, customFajrAngleDeg: 17, customIshaAngleDeg: 17,
                                          latitude: 24.7136, longitude: 46.6753, city: nil, country: nil,
                                          manualCityOverride: false, fajrOffsetMin: 0, dhuhrOffsetMin: 0,
                                          asrOffsetMin: 0, maghribOffsetMin: 0, ishaOffsetMin: 0,
                                          timezone: "Asia/Riyadh", updatedAt: Date())
            let method = PrayerCalculationMethod(settings: settings)
            if value != "umm_al_qura" { #expect(method != .ummAlQura, "\(value) fell back to the default") }
            #expect(AdhanCalculator.prayerTimes(latitude: 24.7136, longitude: 46.6753, date: noon("2026-09-17"),
                                                timeZone: riyadh, method: method) != nil, "\(value)")
        }
    }

    @Test("The Qibla from Riyadh is west-south-west, and from London east-south-east")
    func qibla() {
        let riyadhBearing = AdhanCalculator.qiblaBearing(latitude: 24.7136, longitude: 46.6753)
        #expect(abs(riyadhBearing - 244.5) < 1.5)
        let londonBearing = AdhanCalculator.qiblaBearing(latitude: 51.5072, longitude: -0.1276)
        #expect(abs(londonBearing - 119) < 1.5)
    }

    // MARK: - Location

    @Test("A detected fix is named after the bundled city it is in, and only one close by")
    func nearestCityNamesAFix() {
        #expect(PrayerTimeEngine.nearestCity(latitude: 24.75, longitude: 46.70)?.name == "Riyadh")
        #expect(PrayerTimeEngine.nearestCity(latitude: 20.0, longitude: 60.0) == nil, "the Arabian Sea is nowhere")
    }

    @Test("Choosing a city stores it as a manual override with its zone, and recalculates")
    func manualCity() throws {
        let settingsStore = PrayerSettingsStore(db: db)
        let cacheStore = PrayerTimeCacheStore(db: db)
        let makkah = try #require(ManualCityCatalog.city(named: "Makkah") ?? ManualCityCatalog.city(named: "Mecca"))

        try PrayerTimeEngine.applyManualCity(makkah, at: noon("2026-09-17"), timeZone: riyadh,
                                             settingsStore: settingsStore, cacheStore: cacheStore)

        let settings = try settingsStore.settings()
        #expect(settings.manualCityOverride)
        #expect(settings.city == makkah.name)
        #expect(settings.timezone == makkah.timezone)
        #expect(try cacheStore.cachedDay("2026-09-17")?.latitude == makkah.lat)
        #expect(try cacheStore.cachedDayCount(from: "2026-09-17") == 30)
    }

    @Test("Asking for the current location applies it however close, and ends the manual city")
    func requestedLocationAlwaysApplies() throws {
        let settingsStore = PrayerSettingsStore(db: db)
        let cacheStore = PrayerTimeCacheStore(db: db)
        try settingsStore.updateLocation(latitude: 24.7136, longitude: 46.6753, city: "Riyadh",
                                         country: "Saudi Arabia", manualCityOverride: true)

        // 10 km away — under the passive-update threshold.
        try PrayerTimeEngine.applyRequestedLocation(latitude: 24.80, longitude: 46.70, at: noon("2026-09-17"),
                                                    timeZone: riyadh, settingsStore: settingsStore,
                                                    cacheStore: cacheStore)

        let settings = try settingsStore.settings()
        #expect(settings.latitude == 24.80)
        #expect(!settings.manualCityOverride)
        #expect(settings.city == "Riyadh")
        #expect(try cacheStore.cachedDay("2026-09-17")?.latitude == 24.80)
    }

    @Test("Travel renames the location instead of keeping the old city's name")
    func travelRenames() throws {
        let settingsStore = PrayerSettingsStore(db: db)
        let cacheStore = PrayerTimeCacheStore(db: db)
        try settingsStore.updateLocation(latitude: 24.7136, longitude: 46.6753, city: "Riyadh",
                                         country: "Saudi Arabia", manualCityOverride: false)
        let jeddah = try #require(ManualCityCatalog.city(named: "Jeddah"))

        _ = try PrayerTimeEngine.applyLocationUpdate(latitude: jeddah.lat, longitude: jeddah.lon,
                                                     at: noon("2026-09-17"), timeZone: riyadh,
                                                     settingsStore: settingsStore, cacheStore: cacheStore)

        #expect(try settingsStore.settings().city == "Jeddah")
    }

    @Test("A cache built for another place is rebuilt even when it holds enough days")
    func staleCacheIsRebuilt() throws {
        let settingsStore = PrayerSettingsStore(db: db)
        let cacheStore = PrayerTimeCacheStore(db: db)
        try settingsStore.updateLocation(latitude: 24.7136, longitude: 46.6753, city: "Riyadh",
                                         country: "Saudi Arabia", manualCityOverride: false)
        try PrayerTimeEngine.recalculateCache(cacheStore, settings: try settingsStore.settings(),
                                              timeZone: riyadh, startDate: noon("2026-09-17"))
        // The location changed and its recalculation never ran.
        try settingsStore.updateLocation(latitude: 21.5, longitude: 39.2, city: "Jeddah",
                                         country: "Saudi Arabia", manualCityOverride: true)

        let rebuilt = try PrayerTimeEngine.ensureCache(cacheStore, settings: try settingsStore.settings(),
                                                       timeZone: riyadh, at: noon("2026-09-17"))

        #expect(rebuilt)
        #expect(try cacheStore.cachedDay("2026-09-17")?.latitude == 21.5)
    }

    @Test("A settings change recalculates today too, with the Asr rule applied")
    func settingsChangeRecalculatesToday() throws {
        let settingsStore = PrayerSettingsStore(db: db)
        let cacheStore = PrayerTimeCacheStore(db: db)
        try settingsStore.updateLocation(latitude: 24.7136, longitude: 46.6753, city: "Riyadh",
                                         country: "Saudi Arabia", manualCityOverride: false)
        try PrayerTimeEngine.recalculateCache(cacheStore, settings: try settingsStore.settings(),
                                              timeZone: riyadh, startDate: noon("2026-09-17"))
        let before = time("asr", in: try #require(try cacheStore.cachedDay("2026-09-17")).times)

        try settingsStore.updateAsrMethod(.hanafi)
        try settingsStore.updateOffsets(maghrib: 2)
        try PrayerTimeEngine.applySettingsChange(settingsStore: settingsStore, cacheStore: cacheStore,
                                                 timeZone: riyadh, at: noon("2026-09-17"))

        let after = try #require(try cacheStore.cachedDay("2026-09-17")).times
        #expect(time("asr", in: after) > before.addingTimeInterval(30 * 60))
        let unadjusted = try #require(AdhanCalculator.prayerTimes(
            latitude: 24.7136, longitude: 46.6753, date: noon("2026-09-17"), timeZone: riyadh))
        #expect(time("maghrib", in: after) == time("maghrib", in: unadjusted).addingTimeInterval(120))
    }

    @Test("The Asr rule and the alert list round-trip; sunrise is never an alert")
    func settingsRoundTrip() throws {
        let store = PrayerSettingsStore(db: db)
        #expect(try store.settings().asrMethod == "standard")
        #expect(try store.settings().alertPrayers == Set(PrayerTime.obligatoryNames))

        try store.updateAsrMethod(.hanafi)
        try store.updateAlertPrayers(["fajr", "maghrib", "sunrise"])
        #expect(try store.settings().asrMethod == "hanafi")
        #expect(try store.settings().alertPrayers == ["fajr", "maghrib"])

        try store.updateAlertPrayers([])
        #expect(try store.settings().alertPrayers.isEmpty, "none chosen stays none")
    }

    // MARK: - Alerts and the schedule around a fast

    private func cacheDay(_ date: String) throws {
        let times = try #require(AdhanCalculator.prayerTimes(latitude: 24.7136, longitude: 46.6753,
                                                             date: noon(date), timeZone: riyadh))
        try PrayerTimeCacheStore(db: db).upsert(date: date, times: times, latitude: 24.7136, longitude: 46.6753,
                                                calculationMethod: "umm_al_qura")
    }

    private func plan(at now: Date) throws -> NotificationPlan {
        try NotificationPlanner(db: db, timeModel: TimeModel(timeZone: riyadh), clock: FixedClock(now)).plan()
    }

    @Test("Prayer alerts are off until turned on, then one per chosen prayer still to come")
    func prayerAlerts() throws {
        for date in ["2026-09-17", "2026-09-18", "2026-09-19"] { try cacheDay(date) }
        let now = noon("2026-09-17")
        #expect(try plan(at: now).notifications.filter { $0.type == .prayer }.isEmpty)

        try NotificationRuleStore(db: db).setEnabled(true, for: .prayer)
        let alerts = try plan(at: now).notifications.filter { $0.type == .prayer }
        #expect(alerts.allSatisfy { $0.fireAt > now && $0.fireAt <= now.addingTimeInterval(48 * 3600) })
        #expect(alerts.contains { $0.identifier == "almanac.prayer.asr.2026-09-17" })
        #expect(!alerts.contains { $0.identifier == "almanac.prayer.fajr.2026-09-17" }, "Fajr has passed")
        #expect(alerts.first { $0.identifier == "almanac.prayer.asr.2026-09-17" }?.title == "Asr")

        try PrayerSettingsStore(db: db).updateAlertPrayers(["fajr"])
        #expect(try plan(at: now).notifications.filter { $0.type == .prayer }
            .allSatisfy { $0.identifier.hasPrefix("almanac.prayer.fajr.") })
    }

    @Test("On a fast day Maghrib's alert is iftar's, not a second notification at the same instant")
    func maghribDefersToIftar() throws {
        for date in ["2026-09-17", "2026-09-18", "2026-09-19"] { try cacheDay(date) }
        try NotificationRuleStore(db: db).setEnabled(true, for: .prayer)
        try ReligiousFastScheduleStore(db: db).setRecurringEnabled(ReligiousFastScheduleStore.monThu, enabled: true)

        let notifications = try plan(at: noon("2026-09-17")).notifications
        #expect(notifications.contains { $0.identifier == "almanac.iftar.2026-09-17" })
        #expect(!notifications.contains { $0.identifier == "almanac.prayer.maghrib.2026-09-17" })
        #expect(notifications.contains { $0.identifier == "almanac.prayer.maghrib.2026-09-18" },
                "Friday is not a fast day")
    }

    @Test("During a fast, tomorrow's suhoor is still planned and tonight's water is not muted")
    func dryFastSuppressionIsPerInstant() throws {
        for date in ["2026-09-16", "2026-09-17", "2026-09-18", "2026-09-19"] { try cacheDay(date) }
        let schedules = ReligiousFastScheduleStore(db: db)
        try schedules.setRecurringEnabled(ReligiousFastScheduleStore.monThu, enabled: true)
        try schedules.setManualFastDay("2026-09-18", isFast: true)
        let now = noon("2026-09-17")
        try FastingCoordinator(db: db, clock: FixedClock(now), timeZone: riyadh).refresh()
        #expect(try FastingSessionStore(db: db).activeSession()?.isDryFast == true)

        let notifications = try plan(at: now).notifications
        #expect(notifications.contains { $0.identifier == "almanac.suhoor.2026-09-18" },
                "a fast running now must not mute the suhoor that ends tomorrow's night")

        let spans = try NotificationSuppressionContextAssembler(db: db, timeModel: TimeModel(timeZone: riyadh))
            .dryFastSpans(around: now, horizon: 48 * 3600,
                          nowOnly: NowOnlySuppressionAxes(isDryFastActive: true, isConfirmedIFActive: false,
                                                          isReadinessAlreadyFinal: false))
        #expect(spans.contains(now))
        #expect(!spans.contains(noon("2026-09-17").addingTimeInterval(9 * 3600)), "21:00 is after Maghrib")
        #expect(spans.contains(noon("2026-09-18")), "tomorrow's daytime is a fast too")
    }

    @Test("A reminder whose time has passed is not planned")
    func pastRemindersAreNotPlanned() throws {
        for date in ["2026-09-17", "2026-09-18", "2026-09-19"] { try cacheDay(date) }
        try ReligiousFastScheduleStore(db: db).setRecurringEnabled(ReligiousFastScheduleStore.monThu, enabled: true)
        let evening = noon("2026-09-17").addingTimeInterval(8 * 3600)
        let notifications = try plan(at: evening).notifications
        #expect(!notifications.contains { $0.identifier == "almanac.iftar.2026-09-17" })
        #expect(notifications.allSatisfy { $0.fireAt > evening })
    }
}
