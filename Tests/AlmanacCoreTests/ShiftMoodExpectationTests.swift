import Testing
import Foundation
@testable import AlmanacCore

/// Expected mood on shift days (shifts-profile spec, section 4): the person's
/// own average on past days of the same shift type, shown once there are 14 of
/// them, and compared with the mood they log. A logged mood is never changed.
@Suite("Expected mood on shift days")
struct ShiftMoodExpectationTests {
    let db: Database
    let timeModel = TimeModel(timeZone: TimeZone(identifier: "Asia/Riyadh")!)
    let today = LogicalDay("2026-11-20")

    init() throws {
        db = try TestDatabase()
    }

    private var expectation: ShiftMoodExpectation { ShiftMoodExpectation(db: db, timeModel: timeModel) }
    private var moods: MoodLogStore { MoodLogStore(db: db) }

    /// `count` days before `today`, newest first, each with `shift` and the
    /// moods given (cycled).
    private func pastDays(_ count: Int, shift: ShiftType, moods scores: [Int], skipping skip: Int = 0) throws {
        let shifts = ShiftScheduleStore(db: db)
        let scheduleId = try shifts.defaultScheduleId()
        var day = today
        for _ in 0..<skip { day = timeModel.day(before: day)! }
        for index in 0..<count {
            day = timeModel.day(before: day)!
            try shifts.logOneDay(scheduleId: scheduleId, date: day.value, shift: shift)
            let at = timeModel.start(of: day)!.addingTimeInterval(10 * 3600)
            try moods.log(MoodLogDraft(score: scores[index % scores.count], timestamp: at), logicalDay: day.value)
        }
    }

    private func tonight(_ shift: ShiftType) throws {
        let shifts = ShiftScheduleStore(db: db)
        try shifts.logOneDay(scheduleId: try shifts.defaultScheduleId(), date: today.value, shift: shift)
    }

    @Test("No expected mood until there are 14 past days on that shift with a mood logged")
    func needsFourteenDays() throws {
        #expect(ShiftMoodExpectation.activationDays == 14)
        try pastDays(13, shift: .night, moods: [6])
        try tonight(.night)
        #expect(try expectation.expected(on: today) == nil)

        try pastDays(1, shift: .night, moods: [6], skipping: 13)
        let expected = try #require(try expectation.expected(on: today))
        #expect(expected.shift == .night)
        #expect(expected.dayCount == 14)
        #expect(expected.average == 6)
    }

    @Test("The expected mood is the average over past days on the same shift type, one vote a day")
    func averageOfTheSameShiftType() throws {
        try pastDays(14, shift: .night, moods: [5, 7])
        // Day shifts in between do not count, however many there are.
        try pastDays(10, shift: .day, moods: [1], skipping: 14)
        // A second log on one night does not give that night two votes: that
        // day's average (5 and 9, so 7) is its one vote.
        let extra = timeModel.day(before: today)!
        try moods.log(MoodLogDraft(score: 9, timestamp: timeModel.start(of: extra)!.addingTimeInterval(14 * 3600)),
                      logicalDay: extra.value)
        try tonight(.night)

        let expected = try #require(try expectation.expected(on: today))
        // Seven nights at 5 and seven at 7 is 84; one of the fives is now 7: 86 / 14.
        #expect(expected.dayCount == 14)
        #expect(abs(expected.average - 86.0 / 14.0) < 0.0001)
    }

    @Test("A rest day, or a day with no shift, has no expected mood")
    func notOnRestOrUnshiftedDays() throws {
        try pastDays(20, shift: .rest, moods: [7])
        try tonight(.rest)
        #expect(try expectation.expected(on: today) == nil)
        #expect(try expectation.expected(on: timeModel.day(after: today)!) == nil)
    }

    @Test("The logged mood is compared with the expected one, as a whole number on the same scale")
    func comparison() {
        let expected = ExpectedMood(shift: .night, average: 6.4, dayCount: 14)
        #expect(ShiftMoodExpectation.compare(logged: 8, with: expected) == .higher)
        #expect(ShiftMoodExpectation.compare(logged: 6, with: expected) == .asExpected)
        #expect(ShiftMoodExpectation.compare(logged: 5, with: expected) == .lower)
    }

    @Test("Working out the expected mood never changes a logged mood")
    func loggedMoodIsNeverChanged() throws {
        try pastDays(14, shift: .night, moods: [8])
        try tonight(.night)
        let id = try moods.log(MoodLogDraft(score: 3, timestamp: timeModel.start(of: today)!.addingTimeInterval(3600)),
                               logicalDay: today.value)
        let before = try db.query("SELECT id, score, notes FROM mood_log ORDER BY id;").map {
            "\($0.int("id") ?? 0):\($0.int("score") ?? 0):\($0.string("notes") ?? "")"
        }

        let expected = try #require(try expectation.expected(on: today))
        #expect(ShiftMoodExpectation.compare(logged: 3, with: expected) == .lower)

        let after = try db.query("SELECT id, score, notes FROM mood_log ORDER BY id;").map {
            "\($0.int("id") ?? 0):\($0.int("score") ?? 0):\($0.string("notes") ?? "")"
        }
        #expect(after == before)
        #expect(try moods.entry(id: id)?.score == 3)
    }
}
