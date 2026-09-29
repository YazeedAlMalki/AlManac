import Testing
import Foundation
@testable import AlmanacCore

/// §9.7's calibration counting and §9.8's three baselines, against real stores.
///
/// The interesting assertions here are the *thresholds*: each one is a number
/// the spec states, and a baseline pipeline is exactly the kind of thing that
/// looks right while being off by one day, by one metric, or by one side of an
/// inequality.
@Suite("ReadinessBaselineService Tests")
struct ReadinessBaselineServiceTests {
    let db: Database
    let timeModel = TimeModel(timeZone: TimeZone(identifier: "Asia/Riyadh")!)
    let today = LogicalDay("2025-09-30")

    init() throws {
        db = try TestDatabase()
    }

    private var service: ReadinessBaselineService {
        ReadinessBaselineService(db: db, timeModel: timeModel, clock: FixedClock(riyadh(12, day: today.value)))
    }

    // MARK: - Helpers

    private func riyadh(_ hour: Int = 8, _ minute: Int = 0, day dateString: String) -> Date {
        let bits = dateString.split(separator: "-").compactMap { Int($0) }
        var comps = DateComponents()
        comps.year = bits[0]; comps.month = bits[1]; comps.day = bits[2]
        comps.hour = hour; comps.minute = minute
        comps.timeZone = timeModel.timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeModel.timeZone
        return calendar.date(from: comps)!
    }

    /// A valid day by §9.7's sleep clause, or by its vitals clause.
    @discardableResult
    private func logDay(_ day: LogicalDay, sleep: Bool = true, rhr: Double? = 58, hrv: Double? = 62) throws {
        if sleep {
            let end = riyadh(7, day: day.value)
            try SleepEpisodeStore(db: db).upsert(
                SleepEpisode(start: end.addingTimeInterval(-8 * 3600), end: end, type: .primary,
                             source: .healthkit, asleepMinutes: 480),
                timezoneOffset: 180, logicalDay: day.value)
        }
        let store = VitalsRecordStore(db: db)
        if let rhr {
            try store.record(VitalsRecordDraft(metric: "rhr", value: rhr, unit: "bpm",
                                               timestamp: riyadh(8, day: day.value), source: "healthkit"),
                             logicalDay: day.value)
        }
        if let hrv {
            try store.record(VitalsRecordDraft(metric: "hrv", value: hrv, unit: "ms",
                                               timestamp: riyadh(8, day: day.value), source: "healthkit"),
                             logicalDay: day.value)
        }
    }

    /// `count` consecutive valid days ending the day before `today`, so today's
    /// own data is never part of what today's score is measured against.
    @discardableResult
    private func logDays(_ count: Int, from startIndex: Int = 1,
                         rhr: (Int) -> Double = { _ in 58 }, hrv: (Int) -> Double = { _ in 62 }) throws {
        for offset in 0..<count {
            let day = LogicalDay(formatted("2025-09-%02d", 30 - startIndex - offset))
            try logDay(day, rhr: rhr(startIndex + offset), hrv: hrv(startIndex + offset))
        }
    }

    private func formatted(_ format: String, _ day: Int) -> String {
        String(format: format, day)
    }

    private func shiftOn(_ days: [LogicalDay], type: ShiftType) throws {
        let id = try ShiftScheduleStore(db: db).createSchedule(ShiftScheduleDraft(name: "S"))
        for day in days {
            try ShiftScheduleStore(db: db).logOccurrence(ShiftOccurrenceDraft(
                scheduleId: id, date: day.value, shiftType: type,
                expectedSleepWindowStart: riyadh(23, day: day.value),
                expectedWakeTime: riyadh(7, day: day.value)))
        }
    }

    // MARK: - §9.7 valid days

    @Test("A day with sleep is valid")
    func sleepMakesAValidDay() throws {
        try logDay(LogicalDay("2025-09-29"), sleep: true, rhr: nil, hrv: nil)
        #expect(try service.resolve(for: today).validDayCount == 1)
    }

    @Test("A day with both RHR and HRV is valid")
    func bothVitalsMakeAValidDay() throws {
        try logDay(LogicalDay("2025-09-29"), sleep: false, rhr: 58, hrv: 62)
        #expect(try service.resolve(for: today).validDayCount == 1)
    }

    @Test("RHR without HRV is not a valid day, and HRV without RHR is not either")
    func oneVitalAloneIsNotValid() throws {
        try logDay(LogicalDay("2025-09-29"), sleep: false, rhr: 58, hrv: nil)
        #expect(try service.resolve(for: today).validDayCount == 0)
        try logDay(LogicalDay("2025-09-28"), sleep: false, rhr: nil, hrv: 62)
        #expect(try service.resolve(for: today).validDayCount == 0)
    }

    @Test("A day with nothing at all does not count")
    func emptyDayIsNotValid() throws {
        #expect(try service.resolve(for: today).validDayCount == 0)
    }

    // MARK: - §9.7 calibration

    @Test("Calibration reports its day until the 21st valid day, and stops exactly there")
    func calibrationStopsAtTwentyOne() throws {
        try logDays(20)
        let twentieth = try service.resolve(for: today)
        #expect(twentieth.calibrationDay == 20)
        #expect(twentieth.calibrationDay != nil)

        try logDays(1, from: 21)
        let twentyFirst = try service.resolve(for: today)
        #expect(twentyFirst.calibrationDay == 21, "the 21st valid day is the last day of calibration")
        #expect(twentyFirst.validDayCount == 21)

        try logDays(1, from: 22)
        let twentySecond = try service.resolve(for: today)
        #expect(twentySecond.calibrationDay == nil, "past 21 valid days the label stops")
        #expect(twentySecond.validDayCount == 22)
    }

    @Test("Calibration counts from the first valid day, not from a rolling window")
    func calibrationIsNotAWindow() throws {
        // 40 days spread over two months, all in the past relative to `today`.
        for offset in 1...40 {
            let day = LogicalDay(formatted("2025-08-%02d", offset))
            try logDay(day)
        }
        #expect(try service.resolve(for: today).validDayCount == 40)
    }

    // MARK: - §9.8 general

    @Test("The general baseline averages the last 28 valid days, not all of them")
    func generalBaselineIsWindowed() throws {
        // 40 days: 20 at RHR 50, then 20 at RHR 70. Only the last 28 count, so
        // the answer is pulled towards 70 rather than sitting on the midpoint.
        for offset in 1...20 { try logDay(LogicalDay(formatted("2025-08-%02d", offset)), rhr: 50, hrv: 60) }
        for offset in 1...20 { try logDay(LogicalDay(formatted("2025-09-%02d", offset)), rhr: 70, hrv: 80) }

        let resolution = try service.resolve(for: today)
        let average = try #require(resolution.baseline.restingHeartRate)
        #expect(average > 60, "the older 50s should have fallen out of a 28-day window: \(average)")
        #expect(resolution.baseline.context == .general)
        // 40 valid days, so the 28-day window starts partway through August.
        #expect(resolution.windowStartDate == "2025-08-13")
        #expect(resolution.windowEndDate == "2025-09-20")
        #expect(resolution.baseline.validDayCount == 28)
    }

    @Test("The baseline averages days, not readings, so a day with six samples is not six votes")
    func baselineAveragesDaysNotReadings() throws {
        let day = LogicalDay("2025-09-29")
        try SleepEpisodeStore(db: db).upsert(
            SleepEpisode(start: riyadh(23, day: day.value).addingTimeInterval(-8 * 3600),
                         end: riyadh(7, day: day.value), type: .primary, source: .healthkit,
                         asleepMinutes: 480), timezoneOffset: 180, logicalDay: day.value)
        let store = VitalsRecordStore(db: db)
        for index in 0..<6 {
            try store.record(VitalsRecordDraft(metric: "rhr", value: 90, unit: "bpm",
                                               timestamp: riyadh(7 + index, day: day.value),
                                               source: "healthkit"), logicalDay: day.value)
        }
        // A second valid day with a single low reading.
        try logDay(LogicalDay("2025-09-28"), rhr: 50, hrv: 60)

        let average = try #require(try service.resolve(for: today).baseline.restingHeartRate)
        #expect(abs(average - 70) < 0.001, "expected the mean of 70 and 50, got \(average)")
    }

    @Test("Nothing logged gives an empty baseline rather than a zero")
    func emptyBaselineIsNotZero() throws {
        let resolution = try service.resolve(for: today)
        #expect(resolution.baseline.restingHeartRate == nil)
        #expect(resolution.baseline.hrv == nil)
        #expect(resolution.windowStartDate == nil)
    }

    // MARK: - §9.8 shift-specific

    @Test("A shift baseline activates at exactly 14 valid days on that shift type")
    func shiftBaselineActivatesAtFourteen() throws {
        let days = (0..<14).map { LogicalDay(formatted("2025-09-%02d", 16 + $0)) }
        try shiftOn(days + [today], type: .night)
        for day in days { try logDay(day, rhr: 70, hrv: 80) }

        let resolution = try service.resolve(for: today)
        #expect(resolution.baseline.context == .shiftSpecific)
        #expect(resolution.notice == nil)
        #expect(resolution.baseline.restingHeartRate == 70)
    }

    @Test("Thirteen valid days on a shift is not enough, and the user is told why")
    func thirteenShiftDaysIsNotEnough() throws {
        let days = (0..<13).map { LogicalDay(formatted("2025-09-%02d", 17 + $0)) }
        try shiftOn(days + [today], type: .night)
        for day in days { try logDay(day, rhr: 70, hrv: 80) }
        // A non-shift valid day at a different RHR, so the general baseline
        // and the shift baseline are genuinely different numbers.
        try logDay(LogicalDay("2025-09-10"), rhr: 50, hrv: 60)

        let resolution = try service.resolve(for: today)
        #expect(resolution.baseline.context == .general)
        #expect(resolution.notice == .limitedComparableShiftData)
        // The general baseline is dominated by the 13 night days, so it is
        // *near* the shift average rather than equal to it. The distinction
        // being tested is which set of days was used, and 14 ≠ 13.
        let average = try #require(resolution.baseline.restingHeartRate)
        #expect(abs(average - (13 * 70.0 + 50.0) / 14.0) < 0.001, "expected the 14-day general mean")
        #expect(resolution.baseline.validDayCount == 14)
    }

    @Test("A shift baseline is built only from days on that shift")
    func shiftBaselineIgnoresOtherShifts() throws {
        let nights = (0..<14).map { LogicalDay(formatted("2025-09-%02d", 16 + $0)) }
        try shiftOn(nights + [today], type: .night)
        for day in nights { try logDay(day, rhr: 70, hrv: 80) }
        // Valid days on a different shift, which must not pollute the night
        // baseline even though they are inside the 28-day window.
        let days = (0..<5).map { LogicalDay(formatted("2025-09-%02d", 4 + $0)) }
        try shiftOn(days, type: .day)
        for day in days { try logDay(day, rhr: 40, hrv: 30) }

        let resolution = try service.resolve(for: today)
        #expect(resolution.baseline.context == .shiftSpecific)
        #expect(resolution.baseline.restingHeartRate == 70)
    }

    @Test("No shift schedule at all means the general baseline, and no notice")
    func noScheduleMeansGeneralWithoutNotice() throws {
        try logDays(20)
        let resolution = try service.resolve(for: today)
        #expect(resolution.baseline.context == .general)
        #expect(resolution.notice == nil, "there is no shift to have too little data on")
    }

    // MARK: - §9.8 shift change

    @Test("Changing the shift schedule never resets the 21-day calibration")
    func shiftChangeDoesNotResetCalibration() throws {
        try logDays(20)
        let before = try service.resolve(for: today)
        #expect(before.calibrationDay == 20)

        // A brand-new schedule, on a different shift type, with no history.
        try shiftOn([today], type: .evening)
        let after = try service.resolve(for: today)
        #expect(after.validDayCount == 20, "the app-wide count is untouched by a schedule change")
        #expect(after.calibrationDay == 20, "§9.8: the new schedule accumulates independently")
        #expect(after.notice == .limitedComparableShiftData,
                "the new schedule is the one with too little data, not the app")
    }

    // MARK: - §9.8 Ramadan

    private func ramadanSchedule(_ type: String, from: String, to: String) throws {
        try ReligiousFastScheduleStore(db: db).createSchedule(
            scheduleType: type, startGregorianDate: from, endGregorianDate: to)
    }

    @Test("A Ramadan day with too few prior Ramadan days falls back to general, and says so")
    func ramadanCalibrating() throws {
        try ramadanSchedule("ramadan", from: "2025-09-20", to: "2025-09-30")
        // Six prior Ramadan days — real valid days, but inside a Ramadan that
        // has no schedule row, so they are not "Ramadan days" as far as the
        // count is concerned. That is the point of the test: the threshold is
        // about Ramadan days, not valid days.
        for offset in 1...6 { try logDay(LogicalDay(formatted("2025-09-%02d", 20 - offset)), rhr: 50, hrv: 60) }
        // Plus a general baseline of 14 non-Ramadan valid days to fall back to.
        for offset in 1...5 { try logDay(LogicalDay(formatted("2025-08-%02d", offset)), rhr: 50, hrv: 60) }

        let resolution = try service.resolve(for: today)
        #expect(resolution.notice == .ramadanContextCalibrating)
        #expect(resolution.baseline.context == .general)
        #expect(resolution.baseline.restingHeartRate == 50)
    }

    @Test("A Ramadan day with 14 prior Ramadan days uses the Ramadan baseline")
    func ramadanBaselineActivates() throws {
        // A completed prior Ramadan, 14 valid days long.
        try ramadanSchedule("ramadan", from: "2025-08-01", to: "2025-08-14")
        for offset in 1...14 { try logDay(LogicalDay(formatted("2025-08-%02d", offset)), rhr: 65, hrv: 75) }
        // This year's Ramadan, with a different RHR everywhere.
        try ramadanSchedule("ramadan", from: "2025-09-20", to: "2025-09-30")
        for offset in 1...9 { try logDay(LogicalDay(formatted("2025-09-%02d", 20 - offset)), rhr: 75, hrv: 85) }

        let resolution = try service.resolve(for: today)
        #expect(resolution.baseline.context == .ramadan)
        #expect(resolution.notice == nil)
        #expect(resolution.baseline.restingHeartRate == 65, "prior Ramadan, not this year's")
    }

    @Test("A Ramadan baseline never counts the days it is scoring")
    func ramadanBaselineIsNotCircular() throws {
        try ramadanSchedule("ramadan", from: "2025-08-01", to: "2025-08-14")
        for offset in 1...14 { try logDay(LogicalDay(formatted("2025-08-%02d", offset)), rhr: 65, hrv: 75) }
        try ramadanSchedule("ramadan", from: "2025-09-20", to: "2025-09-30")
        // Nineteen valid days inside the current Ramadan at a wildly different
        // RHR. If any of them leaked into the baseline, the answer would move.
        for offset in 1...19 { try logDay(LogicalDay(formatted("2025-09-%02d", 20 - offset)), rhr: 120, hrv: 20) }

        let resolution = try service.resolve(for: today)
        #expect(resolution.baseline.restingHeartRate == 65)
    }

    @Test("A non-Ramadan religious fast day is not Ramadan")
    func monThuIsNotRamadan() throws {
        try ReligiousFastScheduleStore(db: db).createSchedule(scheduleType: "mon_thu")
        try logDays(20)
        let resolution = try service.resolve(for: today)
        #expect(resolution.baseline.context == .general)
        #expect(resolution.notice == nil)
    }

    // MARK: - Notice text

    @Test("Both notices say something a user can act on rather than naming a state")
    func noticeTextIsPlain() throws {
        for notice in [ReadinessBaselineNotice.limitedComparableShiftData,
                       .ramadanContextCalibrating] {
            #expect(notice.text.contains("average") || notice.text.contains("calibrating"))
            #expect(notice.text.count > 20)
        }
        #expect(ReadinessBaselineNotice.ramadanContextCalibrating.text
                .contains("Ramadan context — calibrating"))
    }
}
