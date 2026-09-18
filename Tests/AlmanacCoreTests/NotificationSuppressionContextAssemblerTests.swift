import Testing
import Foundation
@testable import AlmanacCore

/// `NotificationSuppressionContextAssembler` against real stores — each axis
/// exercised the way its own doc-comment footnote in
/// `NotificationSuppressionContext` defines it.
@Suite("NotificationSuppressionContextAssembler Tests")
struct NotificationSuppressionContextAssemblerTests {
    let db: Database
    let timeModel = TimeModel(timeZone: TimeZone(identifier: "Asia/Riyadh")!)
    let now = Date(timeIntervalSince1970: 1_758_164_400)  // 2025-09-18 06:00:00 Riyadh (UTC+3)

    init() throws {
        db = try TestDatabase()
    }

    private var assembler: NotificationSuppressionContextAssembler {
        NotificationSuppressionContextAssembler(db: db, timeModel: timeModel)
    }

    @Test("Nothing logged at all is an all-clear context")
    func allClear() throws {
        let context = try assembler.context(at: now)
        #expect(context == NotificationSuppressionContext())
    }

    // MARK: - Fasting axes

    @Test("An active dry fast sets isDryFastActive but not isConfirmedIFActive")
    func activeDryFast() throws {
        let logicalDay = timeModel.logicalDay(now).value
        try FastingSessionStore(db: db).start(
            FastingSessionDraft(startTimestamp: now.addingTimeInterval(-3600), sessionType: .religious,
                                 isDryFast: true), logicalDay: logicalDay)

        let context = try assembler.context(at: now)
        #expect(context.isDryFastActive)
        #expect(!context.isConfirmedIFActive)
    }

    @Test("An active if_planned session sets isConfirmedIFActive but not isDryFastActive")
    func activeIFPlanned() throws {
        try assertConfirmedIFSetsAxis(.ifPlanned)
    }

    @Test("An active if_confirmed_suggestion session sets isConfirmedIFActive but not isDryFastActive")
    func activeIFConfirmedSuggestion() throws {
        try assertConfirmedIFSetsAxis(.ifConfirmedSuggestion)
    }

    private func assertConfirmedIFSetsAxis(_ sessionType: FastingSessionType) throws {
        let logicalDay = timeModel.logicalDay(now).value
        try FastingSessionStore(db: db).start(
            FastingSessionDraft(startTimestamp: now.addingTimeInterval(-3600), sessionType: sessionType,
                                 isDryFast: false), logicalDay: logicalDay)

        let context = try assembler.context(at: now)
        #expect(context.isConfirmedIFActive)
        #expect(!context.isDryFastActive)
    }

    @Test("A religious fast that isn't dry sets neither fasting axis")
    func religiousNonDryFastSetsNeitherAxis() throws {
        let logicalDay = timeModel.logicalDay(now).value
        try FastingSessionStore(db: db).start(
            FastingSessionDraft(startTimestamp: now.addingTimeInterval(-3600), sessionType: .religious,
                                 isDryFast: false), logicalDay: logicalDay)

        let context = try assembler.context(at: now)
        #expect(!context.isDryFastActive)
        #expect(!context.isConfirmedIFActive)
    }

    // MARK: - isNightShift

    @Test("Now inside a logged night shift's hours sets isNightShift")
    func withinNightShift() throws {
        let scheduleId = try ShiftScheduleStore(db: db).createSchedule(ShiftScheduleDraft(name: "Nights"))
        try ShiftScheduleStore(db: db).logOccurrence(ShiftOccurrenceDraft(
            scheduleId: scheduleId, date: "2025-09-18", shiftType: .night,
            shiftStartTime: now.addingTimeInterval(-3600), shiftEndTime: now.addingTimeInterval(3600)))

        #expect(try assembler.context(at: now).isNightShift)
    }

    @Test("An overnight night shift logged under yesterday's date still counts now")
    func overnightNightShiftFromYesterday() throws {
        let scheduleId = try ShiftScheduleStore(db: db).createSchedule(ShiftScheduleDraft(name: "Nights"))
        // Shift started the evening before `now` and is still running.
        try ShiftScheduleStore(db: db).logOccurrence(ShiftOccurrenceDraft(
            scheduleId: scheduleId, date: "2025-09-17", shiftType: .night,
            shiftStartTime: now.addingTimeInterval(-8 * 3600), shiftEndTime: now.addingTimeInterval(2 * 3600)))

        #expect(try assembler.context(at: now).isNightShift)
    }

    @Test("A day shift covering the same hours never sets isNightShift")
    func dayShiftNeverCounts() throws {
        let scheduleId = try ShiftScheduleStore(db: db).createSchedule(ShiftScheduleDraft(name: "Days"))
        try ShiftScheduleStore(db: db).logOccurrence(ShiftOccurrenceDraft(
            scheduleId: scheduleId, date: "2025-09-18", shiftType: .day,
            shiftStartTime: now.addingTimeInterval(-3600), shiftEndTime: now.addingTimeInterval(3600)))

        #expect(!(try assembler.context(at: now).isNightShift))
    }

    @Test("Outside a night shift's logged hours does not set isNightShift")
    func outsideNightShiftHours() throws {
        let scheduleId = try ShiftScheduleStore(db: db).createSchedule(ShiftScheduleDraft(name: "Nights"))
        try ShiftScheduleStore(db: db).logOccurrence(ShiftOccurrenceDraft(
            scheduleId: scheduleId, date: "2025-09-18", shiftType: .night,
            shiftStartTime: now.addingTimeInterval(3600), shiftEndTime: now.addingTimeInterval(2 * 3600)))

        #expect(!(try assembler.context(at: now).isNightShift))
    }

    // MARK: - isPostShiftSleep

    @Test("Now inside a post_shift-typed episode sets isPostShiftSleep")
    func withinPostShiftSleep() throws {
        let logicalDay = timeModel.logicalDay(now).value
        let episode = SleepEpisode(start: now.addingTimeInterval(-1800), end: now.addingTimeInterval(1800),
                                    type: .postShift, source: .healthkit, asleepMinutes: 60)
        try SleepEpisodeStore(db: db).upsert(episode, timezoneOffset: 180, logicalDay: logicalDay)

        #expect(try assembler.context(at: now).isPostShiftSleep)
    }

    @Test("Now inside an ordinary primary episode does not set isPostShiftSleep")
    func withinPrimarySleepIsNotPostShift() throws {
        let logicalDay = timeModel.logicalDay(now).value
        let episode = SleepEpisode(start: now.addingTimeInterval(-1800), end: now.addingTimeInterval(1800),
                                    type: .primary, source: .healthkit, asleepMinutes: 60)
        try SleepEpisodeStore(db: db).upsert(episode, timezoneOffset: 180, logicalDay: logicalDay)

        #expect(!(try assembler.context(at: now).isPostShiftSleep))
    }

    @Test("A post_shift episode filed under yesterday's logical day still counts if it spans now")
    func postShiftSleepFromYesterdaysLogicalDay() throws {
        let yesterday = timeModel.day(before: timeModel.logicalDay(now))!.value
        let episode = SleepEpisode(start: now.addingTimeInterval(-1800), end: now.addingTimeInterval(1800),
                                    type: .postShift, source: .healthkit, asleepMinutes: 60)
        try SleepEpisodeStore(db: db).upsert(episode, timezoneOffset: 180, logicalDay: yesterday)

        #expect(try assembler.context(at: now).isPostShiftSleep)
    }

    // MARK: - isReadinessAlreadyFinal

    private func outcome(state: ReadinessState) -> ReadinessOutcome {
        ReadinessOutcome(state: state, score: 72, color: .green, textDescription: nil, confidence: .high,
                         missingInputs: [], formulaVersion: "1.0", inputSnapshot: "{}", recommendation: nil,
                         precedenceApplied: [], baselineContext: .general)
    }

    @Test("A final record on the open cycle sets isReadinessAlreadyFinal")
    func finalRecordSuppresses() throws {
        let anchorDate = timeModel.logicalDay(now).value
        let cycleId = try ReadinessCycleStore(db: db).createCycle(anchorDate: anchorDate)
        try ReadinessRecordStore(db: db).record(outcome(state: .final), cycleId: cycleId, anchorDate: anchorDate)

        #expect(try assembler.context(at: now).isReadinessAlreadyFinal)
    }

    @Test("A provisional record on the open cycle does not set isReadinessAlreadyFinal")
    func provisionalRecordDoesNotSuppress() throws {
        let anchorDate = timeModel.logicalDay(now).value
        let cycleId = try ReadinessCycleStore(db: db).createCycle(anchorDate: anchorDate)
        try ReadinessRecordStore(db: db).record(outcome(state: .provisional), cycleId: cycleId, anchorDate: anchorDate)

        #expect(!(try assembler.context(at: now).isReadinessAlreadyFinal))
    }

    @Test("No open cycle at all does not set isReadinessAlreadyFinal")
    func noOpenCycleDoesNotSuppress() throws {
        #expect(!(try assembler.context(at: now).isReadinessAlreadyFinal))
    }
}
