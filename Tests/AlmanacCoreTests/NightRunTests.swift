import Testing
import Foundation
@testable import AlmanacCore

/// Runs of night shifts (shifts-profile spec, sections 3 and 4): how many nights
/// in a row a day is, when a run passes its run length, and the readiness effect
/// the run carries, up to one cap for every saved pattern.
@Suite("Night-shift runs")
struct NightRunTests {
    let db: Database
    let timeModel = TimeModel(timeZone: TimeZone(identifier: "Asia/Riyadh")!)

    init() throws {
        db = try TestDatabase()
    }

    private var runs: NightRunStore { NightRunStore(db: db, timeModel: timeModel) }
    private var patterns: SavedShiftPatternStore { SavedShiftPatternStore(db: db, timeModel: timeModel) }
    private var shifts: ShiftScheduleStore { ShiftScheduleStore(db: db) }

    /// One-day entries, from `start`, one shift per day.
    private func enter(_ sequence: [ShiftType], from start: String) throws {
        let scheduleId = try shifts.defaultScheduleId()
        var day = LogicalDay(start)
        for shift in sequence {
            try shifts.logOneDay(scheduleId: scheduleId, date: day.value, shift: shift)
            day = timeModel.day(after: day)!
        }
    }

    private func nights(_ count: Int, rest: Int = 2, runLength: Int? = nil,
                        start: String = "2026-11-02") throws -> Int64 {
        let id = try patterns.save(SavedShiftPatternDraft(
            name: "\(count) nights", blocks: [ShiftBlock(.night, days: count), ShiftBlock(.rest, days: rest)],
            startDate: LogicalDay(start), cadence: .monthly, runLengthNights: runLength))
        try patterns.use(id, today: LogicalDay(start))
        return id
    }

    // MARK: - Counting

    @Test("Each night in a row counts from the first night of the run; a day off ends the run")
    func nightsCountFromTheFirstNight() throws {
        try enter([.day, .night, .night, .night, .rest, .night], from: "2026-11-02")

        let counted = try ["2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06", "2026-11-07"]
            .map { try runs.night(on: LogicalDay($0)) }
        #expect(counted == [0, 1, 2, 3, 0, 1])
    }

    // MARK: - Run length

    @Test("A pattern with no run length uses 3 nights")
    func defaultRunLengthIsThree() throws {
        #expect(NightRunStore.defaultRunLengthNights == 3)
        try nights(5)
        #expect(try runs.runLength(on: LogicalDay("2026-11-03")) == 3)
        // Nights not written by any pattern use it too.
        try enter([.night], from: "2026-12-20")
        #expect(try runs.runLength(on: LogicalDay("2026-12-20")) == 3)
    }

    @Test("A pattern's own run length replaces the default")
    func patternRunLengthIsUsed() throws {
        try nights(6, runLength: 4)
        #expect(try runs.runLength(on: LogicalDay("2026-11-04")) == 4)
    }

    @Test("The warning is on every night past the run length, and the night that passes it is marked")
    func warningOnNightsPastTheRunLength() throws {
        try nights(5)   // run length 3: nights 4 and 5 pass it
        let window = try runs.nights(from: LogicalDay("2026-11-02"), through: LogicalDay("2026-11-08"))

        #expect(window.map(\.day.value) == ["2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06"])
        #expect(window.map(\.night) == [1, 2, 3, 4, 5])
        #expect(window.map(\.isPastRunLength) == [false, false, false, true, true])
        #expect(window.filter(\.passesRunLength).map(\.day.value) == ["2026-11-05"])
    }

    @Test("A pattern's run length can be set later, and cleared back to the default")
    func runLengthCanBeChanged() throws {
        let id = try nights(5)
        try patterns.setRunLength(4, for: id)
        #expect(try runs.runLength(on: LogicalDay("2026-11-03")) == 4)
        try patterns.setRunLength(nil, for: id)
        #expect(try runs.runLength(on: LogicalDay("2026-11-03")) == 3)
        #expect(throws: SavedShiftPatternError.runLengthNotPositive) { try patterns.setRunLength(0, for: id) }
    }

    @Test("A run as long as its run length gets no warning")
    func runAtItsLengthIsNotWarned() throws {
        try nights(4, runLength: 4)
        let window = try runs.nights(from: LogicalDay("2026-11-02"), through: LogicalDay("2026-11-07"))
        #expect(window.count == 4)
        #expect(window.allSatisfy { !$0.isPastRunLength })
    }

    // MARK: - Readiness effect

    @Test("The run effect starts on the first night and grows by 3% a night")
    func effectGrowsFromTheFirstNight() throws {
        try nights(4)
        let effects = try ["2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06"]
            .map { try runs.readinessEffectPercent(on: LogicalDay($0)) }
        #expect(effects == [3, 6, 9, 12, nil])
        #expect(NightRunStore.perNightPercent == 3)
    }

    @Test("The extra effect stops at the cap, 15% until the person sets one")
    func effectStopsAtTheCap() throws {
        #expect(try runs.capPercent() == 15)
        try nights(8)
        let effects = try ["2026-11-05", "2026-11-06", "2026-11-07", "2026-11-09"]
            .map { try runs.readinessEffectPercent(on: LogicalDay($0)) }
        #expect(effects == [12, 15, 15, 15])
    }

    @Test("One cap applies across patterns, whatever their run lengths")
    func oneCapAcrossPatterns() throws {
        try runs.setCapPercent(10)
        try nights(6, runLength: 2, start: "2026-11-02")
        let other = try patterns.save(SavedShiftPatternDraft(
            name: "Long", blocks: [ShiftBlock(.night, days: 7), ShiftBlock(.rest, days: 7)],
            startDate: LogicalDay("2026-12-01"), cadence: .weekly, runLengthNights: 6))
        try patterns.use(other, today: LogicalDay("2026-12-01"))

        #expect(try runs.readinessEffectPercent(on: LogicalDay("2026-11-05")) == 10)
        #expect(try runs.readinessEffectPercent(on: LogicalDay("2026-12-06")) == 10)
        #expect(try runs.readinessEffectPercent(on: LogicalDay("2026-12-03")) == 9)

        try runs.setCapPercent(nil)
        #expect(try runs.capPercent() == 15, "clearing the cap goes back to the default")
    }

    @Test("A cap must be a positive percentage")
    func capMustBePositive() throws {
        #expect(throws: NightRunError.capOutOfRange) { try runs.setCapPercent(0) }
        #expect(throws: NightRunError.capOutOfRange) { try runs.setCapPercent(101) }
    }

    // MARK: - Calibration

    @Test("Using and switching saved patterns never resets the 21-day calibration")
    func patternChangesDoNotResetCalibration() throws {
        // Twenty valid days by the vitals clause.
        var day = LogicalDay("2026-10-12")
        for _ in 0..<20 {
            let noon = timeModel.start(of: day)!.addingTimeInterval(8 * 3600)
            try VitalsRecordStore(db: db).record(VitalsRecordDraft(metric: "rhr", value: 58, unit: "bpm",
                                                                   timestamp: noon, source: "manual"),
                                                 logicalDay: day.value)
            try VitalsRecordStore(db: db).record(VitalsRecordDraft(metric: "hrv", value: 62, unit: "ms",
                                                                   timestamp: noon, source: "manual"),
                                                 logicalDay: day.value)
            day = timeModel.day(after: day)!
        }
        let today = LogicalDay("2026-11-01")
        let service = ReadinessBaselineService(db: db, timeModel: timeModel)
        #expect(try service.resolve(for: today).calibrationDay == 20)

        let a = try nights(3, start: "2026-10-20")
        let b = try patterns.save(SavedShiftPatternDraft(name: "Days", blocks: [ShiftBlock(.day, days: 1)],
                                                         startDate: today, cadence: .weekly))
        try patterns.setNext(b, today: today)
        try patterns.use(b, today: today)
        try patterns.use(a, today: today)

        #expect(try service.resolve(for: today).calibrationDay == 20)
        #expect(try service.resolve(for: today).validDayCount == 20)
    }

    // MARK: - The notification

    private func riyadh(_ day: String, _ hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeModel.timeZone
        let p = day.split(separator: "-").map { Int($0)! }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: hour))!
    }

    private func warnings(at now: Date) throws -> [PlannedNotification] {
        try NotificationPlanner(db: db, timeModel: timeModel, clock: FixedClock(now)).plan()
            .notifications.filter { $0.type == .nightRun }
    }

    @Test("The notification fires the evening before the run passes its run length, and on the night it passes")
    func notificationFiresTheEveningBeforeAndOnTheNight() throws {
        try nights(5)   // run length 3: the run passes it on night 4, 5 Nov

        let planned = try warnings(at: riyadh("2026-11-04", 12))
        #expect(planned.map(\.identifier) == ["almanac.night_run.eve.2026-11-05",
                                              "almanac.night_run.night.2026-11-05"])
        #expect(planned.map(\.fireAt) == [riyadh("2026-11-04", 18), riyadh("2026-11-05", 18)])
        #expect(planned.first?.body == "Tomorrow is night 4 in a row, past your run length of 3.")
        #expect(planned.last?.body == "Tonight is night 4 in a row, past your run length of 3.")
        // Night 5 is past the run length too, but the run passed it once.
        #expect(try warnings(at: riyadh("2026-11-05", 19)).isEmpty)
    }

    @Test("A pattern's own run length moves the notification to the night that passes it")
    func notificationFollowsThePatternsRunLength() throws {
        try nights(6, runLength: 4)
        let planned = try warnings(at: riyadh("2026-11-05", 12))
        #expect(planned.map(\.identifier) == ["almanac.night_run.eve.2026-11-06",
                                              "almanac.night_run.night.2026-11-06"])
    }

    @Test("No notification for a run that stays within its run length, or with the switch off")
    func noNotificationWithinTheRunLengthOrWhenOff() throws {
        try nights(3)
        #expect(try warnings(at: riyadh("2026-11-03", 12)).isEmpty)

        try nights(5, start: "2026-12-07")
        try NotificationRuleStore(db: db).setEnabled(false, for: .nightRun)
        #expect(try warnings(at: riyadh("2026-12-09", 12)).isEmpty)
    }
}
