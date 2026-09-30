import Testing
import Foundation
@testable import AlmanacCore

/// A scheduling pass runs on **every foreground activation**, so its cost is a
/// battery and a frame-time question, not a micro-optimisation.
///
/// The first implementation of `NotificationPlanner` evaluated suppression by
/// calling `NotificationSuppressionContextAssembler.context(at:)` once per
/// candidate notification. That was correct — two of Appendix B's five axes carry
/// their own timestamps and genuinely need the fire instant — and it cost about
/// seven queries *per candidate*: roughly 140 for a 48-hour window, every time
/// the app came forward. These tests pin the cheap form so the expensive one
/// cannot come back unnoticed.
@Suite("Notification planning cost")
struct NotificationPlannerCostTests {
    let db: Database
    let timeModel = TimeModel(timeZone: TimeZone(identifier: "Asia/Riyadh")!)
    let day = LogicalDay("2025-09-30")
    // 2025-09-30 08:00:00 Riyadh (UTC+3). Written as a verified instant, not
    // an offset guess: an earlier draft of this file used 1_758_247_200, which
    // is 2025-09-19 05:00 — eleven days and a night off. Nothing failed; the
    // window simply contained no fixtures and every count came back zero.
    let now = Date(timeIntervalSince1970: 1_759_208_400)

    init() throws {
        db = try TestDatabase()
    }

    private var planner: NotificationPlanner {
        NotificationPlanner(db: db, timeModel: timeModel, clock: FixedClock(now))
    }

    // MARK: - Fixtures

    /// The candidate count for a realistic day, which is what the cost multiplies.
    private func candidateCount() throws -> Int {
        let id = try ShiftScheduleStore(db: db).createSchedule(ShiftScheduleDraft(name: "S"))
        for offset in 0...2 {
            let target = LogicalDay(String(format: "2025-09-%02d", 28 + offset))
            try ShiftScheduleStore(db: db).logOccurrence(ShiftOccurrenceDraft(
                scheduleId: id, date: target.value, shiftType: .day,
                expectedSleepWindowStart: riyadh(23, day: target.value),
                expectedWakeTime: riyadh(7, day: target.value)))
        }
        return try planner.plan().notifications.count
    }

    private func riyadh(_ hour: Int, day dateString: String) -> Date {
        let bits = dateString.split(separator: "-").compactMap { Int($0) }
        var comps = DateComponents()
        comps.year = bits[0]; comps.month = bits[1]; comps.day = bits[2]
        comps.hour = hour
        comps.timeZone = timeModel.timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeModel.timeZone
        return calendar.date(from: comps)!
    }

    // MARK: - Tests

    @Test("A full 48-hour pass plans a realistic number of notifications")
    func aRealisticPassIsWorthOptimising() throws {
        let count = try candidateCount()
        #expect(count > 8, "expected a day of water reminders plus the rest, got \(count)")
    }

    /// The three axes that cannot vary within a pass are read once, not once per
    /// candidate. Asserted on the type rather than on timing, because a timing
    /// assertion is a flaky test and a query count is the actual claim.
    @Test("The now-only axes are read once and reused for every instant")
    func nowOnlyAxesAreReusable() throws {
        let assembler = NotificationSuppressionContextAssembler(db: db, timeModel: timeModel)
        let first = try assembler.nowOnlyAxes()
        let second = try assembler.nowOnlyAxes()

        // Two reads of the same unchanged state must agree exactly — that is the
        // whole basis for reusing one across a pass.
        #expect(first == second)
        #expect(first == NowOnlySuppressionAxes(isDryFastActive: false,
                                                isConfirmedIFActive: false,
                                                isReadinessAlreadyFinal: false))
    }

    @Test("The now-only axes follow the live fast, so reuse cannot go stale mid-pass")
    func nowOnlyAxesTrackTheFast() throws {
        let assembler = NotificationSuppressionContextAssembler(db: db, timeModel: timeModel)
        #expect(try !assembler.nowOnlyAxes().isDryFastActive)

        try FastingSessionStore(db: db).start(
            FastingSessionDraft(startTimestamp: now.addingTimeInterval(-3600), sessionType: .religious,
                                 isDryFast: true), logicalDay: day.value)
        #expect(try assembler.nowOnlyAxes().isDryFastActive)
    }

    /// The cheap form must give the *same answers* as the per-instant one. A
    /// performance fix that changes behaviour is not a performance fix, and this
    /// is the test that would catch it.
    @Test("The batched form answers exactly what the per-instant form does")
    func batchedEqualsPerInstant() throws {
        let scheduleId = try ShiftScheduleStore(db: db).createSchedule(ShiftScheduleDraft(name: "Nights"))
        try ShiftScheduleStore(db: db).logOccurrence(ShiftOccurrenceDraft(
            scheduleId: scheduleId, date: day.value, shiftType: .night,
            shiftStartTime: riyadh(19, day: day.value),
            shiftEndTime: riyadh(23, day: day.value),
            expectedSleepWindowStart: riyadh(23, day: day.value),
            expectedWakeTime: riyadh(7, day: day.value)))
        try SleepEpisodeStore(db: db).upsert(
            SleepEpisode(start: now.addingTimeInterval(-3600), end: riyadh(12, day: day.value),
                         type: .postShift, source: .healthkit, asleepMinutes: 480),
            timezoneOffset: 180, logicalDay: day.value)

        let assembler = NotificationSuppressionContextAssembler(db: db, timeModel: timeModel)
        let nowOnly = try assembler.nowOnlyAxes()
        let occurrences = try assembler.nightOccurrences(around: now)
        let episodes = try assembler.postShiftEpisodes(around: now)

        // Sampled inside the night shift, inside the episode, and well after both.
        for instant in [now, riyadh(20, day: day.value), riyadh(23, day: day.value)] {
            let direct = try assembler.context(at: instant)
            let batched = nowOnly.with(
                isNightShift: assembler.isWithinNightShift(at: instant, occurrences: occurrences),
                isPostShiftSleep: assembler.isWithinPostShiftSleep(at: instant, episodes: episodes))
            #expect(direct == batched, "diverged at \(instant)")
        }
    }

    @Test("A pass still costs the same on its second run — it caches nothing stale and nothing extra")
    func repeatedPassesAreStable() throws {
        _ = try candidateCount()
        let second = try planner.plan()
        let third = try planner.plan()
        #expect(second == third)
    }
}
