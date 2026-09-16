import Testing
import Foundation
@testable import AlmanacCore

@Suite("ReligiousFastScheduleStore Tests")
struct ReligiousFastScheduleStoreTests {
    let db: Database

    init() throws {
        db = try TestDatabase()
    }

    @Test("A created schedule can be read back")
    func createAndRead() throws {
        let store = ReligiousFastScheduleStore(db: db)
        let id = try store.createSchedule(scheduleType: "mon_thu")

        let schedule = try store.schedule(id: id)
        #expect(schedule?.scheduleType == "mon_thu")
        #expect(schedule?.isActive == true)
        #expect(schedule?.manualCorrections.isEmpty == true)
    }

    @Test("A Ramadan schedule matches only dates within its stored range")
    func ramadanRangeMatch() throws {
        let store = ReligiousFastScheduleStore(db: db)
        try store.createSchedule(scheduleType: "ramadan", hijriYear: 1447,
                                  startGregorianDate: "2026-02-18", endGregorianDate: "2026-03-19")

        #expect(try store.isFastDay("2026-02-17") == false)
        #expect(try store.isFastDay("2026-02-18") == true)
        #expect(try store.isFastDay("2026-03-01") == true)
        #expect(try store.isFastDay("2026-03-19") == true)
        #expect(try store.isFastDay("2026-03-20") == false)
    }

    @Test("A mon_thu schedule matches every Monday and Thursday, nothing else")
    func monThuMatch() throws {
        let store = ReligiousFastScheduleStore(db: db)
        try store.createSchedule(scheduleType: "mon_thu")

        // 2026-09-14 is a Monday, 2026-09-17 a Thursday, 2026-09-15 a Tuesday.
        #expect(try store.isFastDay("2026-09-14") == true)
        #expect(try store.isFastDay("2026-09-17") == true)
        #expect(try store.isFastDay("2026-09-15") == false)
    }

    @Test("A white_days schedule matches Hijri 13th-15th only")
    func whiteDaysMatch() throws {
        let store = ReligiousFastScheduleStore(db: db)
        try store.createSchedule(scheduleType: "white_days")

        var islamic = Calendar(identifier: .islamicUmmAlQura)
        islamic.timeZone = TimeZone(identifier: "UTC")!
        // Find a Hijri 14th within the next 40 days to test against, rather
        // than hard-coding a Gregorian date that drifts every Hijri year.
        let today = Date()
        var candidate: String?
        for offset in 0..<40 {
            guard let date = Calendar(identifier: .gregorian).date(byAdding: .day, value: offset, to: today) else { continue }
            if islamic.component(.day, from: date) == 14 {
                let df = DateFormatter()
                df.calendar = Calendar(identifier: .gregorian)
                df.timeZone = TimeZone(identifier: "UTC")
                df.dateFormat = "yyyy-MM-dd"
                candidate = df.string(from: date)
                break
            }
        }
        let whiteDay = try #require(candidate, "expected a Hijri 14th within 40 days")
        #expect(try store.isFastDay(whiteDay) == true)
    }

    @Test("A deactivated schedule no longer matches")
    func deactivatedScheduleDoesNotMatch() throws {
        let store = ReligiousFastScheduleStore(db: db)
        let id = try store.createSchedule(scheduleType: "mon_thu")
        try store.deactivate(id: id)

        #expect(try store.isFastDay("2026-09-14") == false)
    }

    @Test("A manual remove_fast correction overrides a calculated match")
    func manualRemoveOverrides() throws {
        let store = ReligiousFastScheduleStore(db: db)
        let id = try store.createSchedule(scheduleType: "mon_thu")
        try store.addManualCorrection(id: id, date: "2026-09-14", action: "remove_fast", reason: "traveling")

        #expect(try store.isFastDay("2026-09-14") == false)
        // Other Mondays are unaffected.
        #expect(try store.isFastDay("2026-09-21") == true)
    }

    @Test("A manual add_fast correction overrides a calculated non-match")
    func manualAddOverrides() throws {
        let store = ReligiousFastScheduleStore(db: db)
        let id = try store.createSchedule(scheduleType: "mon_thu")
        try store.addManualCorrection(id: id, date: "2026-09-15", action: "add_fast", reason: nil)

        #expect(try store.isFastDay("2026-09-15") == true)
    }

    @Test("Manual corrections are recorded in order and readable back")
    func manualCorrectionsRecorded() throws {
        let store = ReligiousFastScheduleStore(db: db)
        let id = try store.createSchedule(scheduleType: "mon_thu")
        try store.addManualCorrection(id: id, date: "2026-09-14", action: "remove_fast", reason: "traveling")

        let schedule = try store.schedule(id: id)
        #expect(schedule?.manualCorrections.count == 1)
        #expect(schedule?.manualCorrections.first?.date == "2026-09-14")
        #expect(schedule?.manualCorrections.first?.action == "remove_fast")
        #expect(schedule?.manualCorrections.first?.reason == "traveling")
    }

    @Test("ramadanRange returns a span whose every day is Hijri month 9, and no day outside it is")
    func ramadanRangeInvariant() throws {
        let currentHijriYear = Calendar(identifier: .islamicUmmAlQura).component(.year, from: Date())
        guard let range = ReligiousFastScheduleStore.ramadanRange(hijriYear: currentHijriYear) else {
            Issue.record("expected a Ramadan range for the current Hijri year")
            return
        }

        var islamic = Calendar(identifier: .islamicUmmAlQura)
        islamic.timeZone = TimeZone(identifier: "UTC")!
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.timeZone = TimeZone(identifier: "UTC")
        df.dateFormat = "yyyy-MM-dd"

        let start = try #require(df.date(from: range.start))
        let end = try #require(df.date(from: range.end))
        #expect(islamic.component(.month, from: start) == 9)
        #expect(islamic.component(.month, from: end) == 9)

        let dayBefore = Calendar(identifier: .gregorian).date(byAdding: .day, value: -1, to: start)!
        let dayAfter = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: end)!
        #expect(islamic.component(.month, from: dayBefore) != 9)
        #expect(islamic.component(.month, from: dayAfter) != 9)
    }
}
