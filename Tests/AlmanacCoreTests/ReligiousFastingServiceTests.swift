import Testing
import Foundation
@testable import AlmanacCore

@Suite("ReligiousFastingService Tests")
struct ReligiousFastingServiceTests {
    let db: Database
    let scheduleStore: ReligiousFastScheduleStore
    let sessionStore: FastingSessionStore
    let windowStore: NutritionWindowStore

    // Fajr(D) 2026-09-17 = 04:22 Riyadh = 01:22 UTC.
    // Maghrib(D) 2026-09-17 = 17:55 Riyadh = 14:55 UTC.
    // Fajr(D+1) 2026-09-18 = 04:22 Riyadh = 01:22 UTC next day.
    let fajrD = Date(timeIntervalSince1970: 1_789_608_120)
    let maghribD = Date(timeIntervalSince1970: 1_789_656_900)
    let fajrDPlus1 = Date(timeIntervalSince1970: 1_789_694_520)

    init() throws {
        db = try TestDatabase()
        scheduleStore = ReligiousFastScheduleStore(db: db)
        sessionStore = FastingSessionStore(db: db)
        windowStore = NutritionWindowStore(db: db)
    }

    private var todaysPrayerTimes: [PrayerTime] {
        [PrayerTime(name: "fajr", timestamp: fajrD), PrayerTime(name: "maghrib", timestamp: maghribD)]
    }

    @Test("A non-fast day does nothing")
    func nonFastDayNoOp() throws {
        try scheduleStore.createSchedule(scheduleType: "mon_thu")
        let outcome = try ReligiousFastingService.ensureDay(
            anchorDate: "2026-09-15", prayerTimes: todaysPrayerTimes, // Tuesday, not Mon/Thu
            scheduleStore: scheduleStore, sessionStore: sessionStore, windowStore: windowStore,
            nextDayFajr: fajrDPlus1, timezoneOffset: 180, at: fajrD)

        #expect(outcome == .notAFastDay)
        #expect(try sessionStore.sessions(for: "2026-09-15").isEmpty)
    }

    @Test("A fast day with no existing session creates one starting at Fajr, plus its night window")
    func createsSessionAndWindow() throws {
        try scheduleStore.createSchedule(scheduleType: "mon_thu") // 2026-09-17 is a Thursday
        let outcome = try ReligiousFastingService.ensureDay(
            anchorDate: "2026-09-17", prayerTimes: todaysPrayerTimes,
            scheduleStore: scheduleStore, sessionStore: sessionStore, windowStore: windowStore,
            nextDayFajr: fajrDPlus1, timezoneOffset: 180, at: fajrD)

        guard case .sessionCreated(let id) = outcome else {
            Issue.record("expected .sessionCreated, got \(outcome)")
            return
        }
        let session = try sessionStore.session(id: id)
        #expect(session?.sessionType == .religious)
        #expect(session?.isDryFast == true)
        #expect(session?.startTimestamp == fajrD)
        #expect(session?.isActive == true)

        let window = try windowStore.window(date: "2026-09-17", windowType: "night_nutrition_window")
        #expect(window?.startTimestamp == maghribD)
        #expect(window?.endTimestamp == fajrDPlus1)
    }

    @Test("Calling ensureDay again before Maghrib does not create a second session")
    func idempotentBeforeMaghrib() throws {
        try scheduleStore.createSchedule(scheduleType: "mon_thu")
        let first = try ReligiousFastingService.ensureDay(
            anchorDate: "2026-09-17", prayerTimes: todaysPrayerTimes,
            scheduleStore: scheduleStore, sessionStore: sessionStore, windowStore: windowStore,
            nextDayFajr: fajrDPlus1, timezoneOffset: 180, at: fajrD)
        guard case .sessionCreated(let id) = first else { Issue.record("expected creation"); return }

        let second = try ReligiousFastingService.ensureDay(
            anchorDate: "2026-09-17", prayerTimes: todaysPrayerTimes,
            scheduleStore: scheduleStore, sessionStore: sessionStore, windowStore: windowStore,
            nextDayFajr: fajrDPlus1, timezoneOffset: 180, at: maghribD.addingTimeInterval(-3600))

        #expect(second == .alreadyActive(sessionId: id))
        #expect(try sessionStore.sessions(for: "2026-09-17").count == 1)
    }

    @Test("Calling ensureDay at or after Maghrib ends the active session")
    func endsAtMaghrib() throws {
        try scheduleStore.createSchedule(scheduleType: "mon_thu")
        let first = try ReligiousFastingService.ensureDay(
            anchorDate: "2026-09-17", prayerTimes: todaysPrayerTimes,
            scheduleStore: scheduleStore, sessionStore: sessionStore, windowStore: windowStore,
            nextDayFajr: fajrDPlus1, timezoneOffset: 180, at: fajrD)
        guard case .sessionCreated(let id) = first else { Issue.record("expected creation"); return }

        let outcome = try ReligiousFastingService.ensureDay(
            anchorDate: "2026-09-17", prayerTimes: todaysPrayerTimes,
            scheduleStore: scheduleStore, sessionStore: sessionStore, windowStore: windowStore,
            nextDayFajr: fajrDPlus1, timezoneOffset: 180, at: maghribD.addingTimeInterval(60))

        #expect(outcome == .sessionEnded(sessionId: id))
        let session = try sessionStore.session(id: id)
        #expect(session?.isActive == false)
        #expect(session?.endTimestamp == maghribD)
        #expect(session?.correctionHistory.isEmpty == true)
    }

    @Test("Calling ensureDay again after the session has ended is a no-op, not a re-end")
    func idempotentAfterEnd() throws {
        try scheduleStore.createSchedule(scheduleType: "mon_thu")
        let first = try ReligiousFastingService.ensureDay(
            anchorDate: "2026-09-17", prayerTimes: todaysPrayerTimes,
            scheduleStore: scheduleStore, sessionStore: sessionStore, windowStore: windowStore,
            nextDayFajr: fajrDPlus1, timezoneOffset: 180, at: fajrD)
        guard case .sessionCreated(let id) = first else { Issue.record("expected creation"); return }
        _ = try ReligiousFastingService.ensureDay(
            anchorDate: "2026-09-17", prayerTimes: todaysPrayerTimes,
            scheduleStore: scheduleStore, sessionStore: sessionStore, windowStore: windowStore,
            nextDayFajr: fajrDPlus1, timezoneOffset: 180, at: maghribD)

        let outcome = try ReligiousFastingService.ensureDay(
            anchorDate: "2026-09-17", prayerTimes: todaysPrayerTimes,
            scheduleStore: scheduleStore, sessionStore: sessionStore, windowStore: windowStore,
            nextDayFajr: fajrDPlus1, timezoneOffset: 180, at: maghribD.addingTimeInterval(3600))

        #expect(outcome == .alreadyEnded(sessionId: id))
    }

    @Test("When the next day's Fajr isn't known yet, the session is still created but no window is")
    func sessionCreatedWithoutWindowWhenNextFajrUnknown() throws {
        try scheduleStore.createSchedule(scheduleType: "mon_thu")
        let outcome = try ReligiousFastingService.ensureDay(
            anchorDate: "2026-09-17", prayerTimes: todaysPrayerTimes,
            scheduleStore: scheduleStore, sessionStore: sessionStore, windowStore: windowStore,
            nextDayFajr: nil, timezoneOffset: 180, at: fajrD)

        guard case .sessionCreated = outcome else { Issue.record("expected creation"); return }
        #expect(try windowStore.window(date: "2026-09-17", windowType: "night_nutrition_window") == nil)
    }

    @Test("A manually removed fast day is respected — no session is created")
    func manuallyRemovedDayCreatesNothing() throws {
        let id = try scheduleStore.createSchedule(scheduleType: "mon_thu")
        try scheduleStore.addManualCorrection(id: id, date: "2026-09-17", action: "remove_fast", reason: "travel")

        let outcome = try ReligiousFastingService.ensureDay(
            anchorDate: "2026-09-17", prayerTimes: todaysPrayerTimes,
            scheduleStore: scheduleStore, sessionStore: sessionStore, windowStore: windowStore,
            nextDayFajr: fajrDPlus1, timezoneOffset: 180, at: fajrD)

        #expect(outcome == .notAFastDay)
    }
}
