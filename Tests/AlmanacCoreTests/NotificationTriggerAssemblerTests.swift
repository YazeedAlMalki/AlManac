import Testing
import Foundation
@testable import AlmanacCore

/// `NotificationTriggerAssembler` against real stores — each per-type
/// method exercised for both the ordinary case and the "nothing logged"
/// case, which must come back nil/empty rather than throwing.
@Suite("NotificationTriggerAssembler Tests")
struct NotificationTriggerAssemblerTests {
    let db: Database
    let timeModel = TimeModel(timeZone: TimeZone(identifier: "Asia/Riyadh")!)
    let day = LogicalDay("2025-09-18")

    init() throws {
        db = try TestDatabase()
    }

    private var assembler: NotificationTriggerAssembler {
        NotificationTriggerAssembler(db: db, timeModel: timeModel)
    }

    private func riyadh(_ hour: Int, _ minute: Int = 0, day dateString: String = "2025-09-18") -> Date {
        var comps = DateComponents()
        let bits = dateString.split(separator: "-").compactMap { Int($0) }
        comps.year = bits[0]; comps.month = bits[1]; comps.day = bits[2]
        comps.hour = hour; comps.minute = minute
        comps.timeZone = timeModel.timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeModel.timeZone
        return calendar.date(from: comps)!
    }

    /// Fixed inside the contextual-hydration tests' 14-day query window
    /// (2025-09-04..<2025-09-18), so an entry recorded with `eatenAt: .unknown`
    /// falls back to a `recordedAt` that the range would actually keep —
    /// making the "recordedAt fallback is not counted" test below exercise
    /// the `basis == .occurrence` filter itself, not just a date-range miss.
    private var nutritionLog: NutritionLogStore {
        NutritionLogStore(db: db, clock: FixedClock(riyadh(10, day: "2025-09-12")),
                          zone: ZoneContext(timeModel.timeZone))
    }

    private let testFood = SourceIdentifier(namespace: .almanac, localID: "test-food")

    @discardableResult
    private func logMeal(_ mealType: NutritionMealType, eatenAt: PartialDateTime) throws -> NutritionLogOutcome {
        try nutritionLog.record(NutritionLogDraft(foodRef: testFood, eatenAt: eatenAt, mealType: mealType))
    }

    /// `PrayerTimeCacheStore.upsert` requires all six named prayer times or
    /// it throws `incompleteTimes` — these tests only care about fajr and
    /// maghrib, so the other four are filled with plausible placeholders
    /// between them.
    private func allSixTimes(fajr: Date, maghrib: Date) -> [PrayerTime] {
        [
            PrayerTime(name: "fajr", timestamp: fajr),
            PrayerTime(name: "sunrise", timestamp: fajr.addingTimeInterval(3600)),
            PrayerTime(name: "dhuhr", timestamp: fajr.addingTimeInterval(7 * 3600)),
            PrayerTime(name: "asr", timestamp: fajr.addingTimeInterval(10 * 3600)),
            PrayerTime(name: "maghrib", timestamp: maghrib),
            PrayerTime(name: "isha", timestamp: maghrib.addingTimeInterval(3600))
        ]
    }

    // MARK: - Suhoor / Iftar

    @Test("Suhoor fires 20 minutes before Fajr on a scheduled fast day")
    func suhoorOnFastDay() throws {
        let fajr = riyadh(4, 30)
        try PrayerTimeCacheStore(db: db).upsert(
            date: day.value,
            times: allSixTimes(fajr: fajr, maghrib: riyadh(18)),
            latitude: 24.7136, longitude: 46.6753, calculationMethod: "umm_al_qura")
        try ReligiousFastScheduleStore(db: db).createSchedule(
            scheduleType: "ramadan", startGregorianDate: day.value, endGregorianDate: day.value)

        #expect(try assembler.suhoorTrigger(for: day) == fajr.addingTimeInterval(-20 * 60))
    }

    @Test("Suhoor is nil on a day with cached prayer times but no scheduled fast")
    func suhoorWithoutFastDay() throws {
        try PrayerTimeCacheStore(db: db).upsert(
            date: day.value,
            times: allSixTimes(fajr: riyadh(4, 30), maghrib: riyadh(18)),
            latitude: 24.7136, longitude: 46.6753, calculationMethod: "umm_al_qura")

        #expect(try assembler.suhoorTrigger(for: day) == nil)
    }

    @Test("Suhoor and iftar are both nil when the day has no cached prayer times at all")
    func suhoorAndIftarWithoutCachedTimes() throws {
        #expect(try assembler.suhoorTrigger(for: day) == nil)
        #expect(try assembler.iftarTrigger(for: day) == nil)
    }

    @Test("Iftar fires exactly at Maghrib on a scheduled fast day")
    func iftarOnFastDay() throws {
        let maghrib = riyadh(18, 5)
        try PrayerTimeCacheStore(db: db).upsert(
            date: day.value,
            times: allSixTimes(fajr: riyadh(4, 30), maghrib: maghrib),
            latitude: 24.7136, longitude: 46.6753, calculationMethod: "umm_al_qura")
        try ReligiousFastScheduleStore(db: db).createSchedule(
            scheduleType: "ramadan", startGregorianDate: day.value, endGregorianDate: day.value)

        #expect(try assembler.iftarTrigger(for: day) == maghrib)
    }

    // MARK: - Water

    @Test("Water reminders delegate to the pure computer once wake/sleep are resolved from the shift occurrence")
    func waterFromShiftOccurrence() throws {
        let scheduleId = try ShiftScheduleStore(db: db).createSchedule(ShiftScheduleDraft(name: "Days"))
        let wake = riyadh(7)
        let sleepStart = riyadh(23)
        try ShiftScheduleStore(db: db).logOccurrence(ShiftOccurrenceDraft(
            scheduleId: scheduleId, date: day.value, shiftType: .day,
            expectedSleepWindowStart: sleepStart, expectedWakeTime: wake))

        let times = try assembler.waterReminderTimes(for: day)
        #expect(times == NotificationTriggerTimeComputer.waterReminderTimes(
            expectedWakeTime: wake, expectedSleepWindowStart: sleepStart))
    }

    @Test("Water reminders are empty with no shift occurrence logged at all")
    func waterWithoutShiftOccurrence() throws {
        #expect(try assembler.waterReminderTimes(for: day).isEmpty)
    }

    @Test("Water reminders are empty when the occurrence has a shift type but no wake/sleep instants")
    func waterWithIncompleteOccurrence() throws {
        let scheduleId = try ShiftScheduleStore(db: db).createSchedule(ShiftScheduleDraft(name: "Days"))
        try ShiftScheduleStore(db: db).logOccurrence(ShiftOccurrenceDraft(
            scheduleId: scheduleId, date: day.value, shiftType: .day))

        #expect(try assembler.waterReminderTimes(for: day).isEmpty)
    }

    // MARK: - Bedtime

    @Test("Bedtime fires 30 minutes before the shift's expected sleep window")
    func bedtimeFromShiftOccurrence() throws {
        let scheduleId = try ShiftScheduleStore(db: db).createSchedule(ShiftScheduleDraft(name: "Days"))
        let sleepStart = riyadh(23)
        try ShiftScheduleStore(db: db).logOccurrence(ShiftOccurrenceDraft(
            scheduleId: scheduleId, date: day.value, shiftType: .day, expectedSleepWindowStart: sleepStart))

        #expect(try assembler.bedtimeTrigger(for: day) == sleepStart.addingTimeInterval(-30 * 60))
    }

    @Test("Bedtime is nil with no shift occurrence logged at all")
    func bedtimeWithoutShiftOccurrence() throws {
        #expect(try assembler.bedtimeTrigger(for: day) == nil)
    }

    // MARK: - Readiness

    @Test("Readiness uses the day's own primary sleep episode end when one has been classified")
    func readinessFromPrimaryEpisode() throws {
        let episodeEnd = riyadh(7)
        let episode = SleepEpisode(start: riyadh(23, 0, day: "2025-09-17"), end: episodeEnd,
                                    type: .primary, source: .healthkit, asleepMinutes: 480)
        try SleepEpisodeStore(db: db).upsert(episode, timezoneOffset: 180, logicalDay: day.value)

        // A shift-derived wake time is present too, but the primary episode wins.
        let scheduleId = try ShiftScheduleStore(db: db).createSchedule(ShiftScheduleDraft(name: "Days"))
        try ShiftScheduleStore(db: db).logOccurrence(ShiftOccurrenceDraft(
            scheduleId: scheduleId, date: day.value, shiftType: .day, expectedWakeTime: riyadh(6)))

        #expect(try assembler.readinessTrigger(for: day) == episodeEnd)
    }

    @Test("Readiness falls back to the shift's expected wake time with no primary episode")
    func readinessFromShiftWakeTime() throws {
        let scheduleId = try ShiftScheduleStore(db: db).createSchedule(ShiftScheduleDraft(name: "Days"))
        let wake = riyadh(6, 30)
        try ShiftScheduleStore(db: db).logOccurrence(ShiftOccurrenceDraft(
            scheduleId: scheduleId, date: day.value, shiftType: .day, expectedWakeTime: wake))

        #expect(try assembler.readinessTrigger(for: day) == wake)
    }

    @Test("Readiness falls back to a 7-day average wake time with no episode and no shift")
    func readinessFromSevenDayAverage() throws {
        let store = SleepEpisodeStore(db: db)
        // Three prior days, each waking at a different time of day, plus one
        // day with no primary episode at all (skipped, not averaged as zero).
        let priorWakeHours: [(dateString: String, hour: Int, minute: Int)] = [
            ("2025-09-15", 6, 0), ("2025-09-16", 6, 30), ("2025-09-17", 6, 30)
        ]
        for prior in priorWakeHours {
            let end = riyadh(prior.hour, prior.minute, day: prior.dateString)
            let episode = SleepEpisode(start: end.addingTimeInterval(-8 * 3600), end: end,
                                        type: .primary, source: .healthkit, asleepMinutes: 480)
            try store.upsert(episode, timezoneOffset: 180, logicalDay: prior.dateString)
        }

        // Average of 06:00, 06:30, 06:30 is 06:20.
        let expected = riyadh(6, 20)
        #expect(try assembler.readinessTrigger(for: day) == expected)
    }

    @Test("Readiness is nil with no primary episode, no shift, and no history to average")
    func readinessNilWithNothingKnown() throws {
        #expect(try assembler.readinessTrigger(for: day) == nil)
    }

    // MARK: - Contextual hydration

    @Test("Contextual hydration fires 60 minutes before the 14-day average time for that meal type")
    func contextualHydrationFromAverage() throws {
        try logMeal(.breakfast, eatenAt: PartialDateTime(
            text: "2025-09-11T07:00:00+03:00", precision: .instant, zone: ZoneContext(offsetMinutes: 180)))
        try logMeal(.breakfast, eatenAt: PartialDateTime(
            text: "2025-09-12T07:30:00+03:00", precision: .instant, zone: ZoneContext(offsetMinutes: 180)))
        try logMeal(.breakfast, eatenAt: PartialDateTime(
            text: "2025-09-13T07:00:00+03:00", precision: .instant, zone: ZoneContext(offsetMinutes: 180)))

        // Average of 07:00, 07:30, 07:00 is 07:10; 60 minutes before is 06:10.
        #expect(try assembler.contextualHydrationTrigger(for: .breakfast, before: day) == riyadh(6, 10))
    }

    @Test("Entries with coarser-than-minute precision carry no time-of-day and are excluded from the average")
    func contextualHydrationExcludesCoarsePrecision() throws {
        try logMeal(.breakfast, eatenAt: PartialDateTime(text: "2025-09-12", precision: .day))
        try logMeal(.breakfast, eatenAt: PartialDateTime(
            text: "2025-09-13T07:00:00+03:00", precision: .instant, zone: ZoneContext(offsetMinutes: 180)))

        // Only the instant-precision entry counts.
        #expect(try assembler.contextualHydrationTrigger(for: .breakfast, before: day) == riyadh(6, 0))
    }

    @Test("An entry with no stated eaten time is placed by when it was recorded, and does not count toward the average")
    func contextualHydrationExcludesRecordedFallback() throws {
        try logMeal(.breakfast, eatenAt: .unknown)

        #expect(try assembler.contextualHydrationTrigger(for: .breakfast, before: day) == nil)
    }

    @Test("Entries logged under a different meal type do not count toward this one's average")
    func contextualHydrationExcludesOtherMealTypes() throws {
        try logMeal(.dinner, eatenAt: PartialDateTime(
            text: "2025-09-12T19:00:00+03:00", precision: .instant, zone: ZoneContext(offsetMinutes: 180)))

        #expect(try assembler.contextualHydrationTrigger(for: .breakfast, before: day) == nil)
    }

    @Test("An entry eaten on day itself does not count toward that same day's prediction")
    func contextualHydrationExcludesTheDayItself() throws {
        try logMeal(.breakfast, eatenAt: PartialDateTime(
            text: "2025-09-18T07:00:00+03:00", precision: .instant, zone: ZoneContext(offsetMinutes: 180)))

        #expect(try assembler.contextualHydrationTrigger(for: .breakfast, before: day) == nil)
    }

    @Test("Contextual hydration is nil with no meals logged at all")
    func contextualHydrationNilWithNothingLogged() throws {
        #expect(try assembler.contextualHydrationTrigger(for: .breakfast, before: day) == nil)
    }
}
