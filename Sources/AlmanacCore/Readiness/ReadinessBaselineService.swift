import Foundation

/// A `readiness_baseline` row (§5.23), and the vocabulary for which of the
/// three baseline types a row is.
///
/// §9.8 names exactly three: general, shift-specific and Ramadan. Those are the
/// cases, spelled the spec's way rather than as booleans, because "is this a
/// Ramadan day" is a question with a real answer and a flag would only record
/// that somebody asked it.
public enum ReadinessBaselineType: String, Sendable, Hashable, Codable, CaseIterable {
    case general
    case shiftSpecific = "shift_specific"
    case ramadan

    /// `ReadinessBaselineContext` is §5.23's `baselineContext` column, which
    /// carries the same three plus `.calibration`. The conversion is one-way on
    /// purpose: a stored baseline row never *is* a calibration state, it is a
    /// measurement that happens to be taken while calibration is incomplete.
    public var context: ReadinessBaselineContext {
        switch self {
        case .general: return .general
        case .shiftSpecific: return .shiftSpecific
        case .ramadan: return .ramadan
        }
    }
}

/// §9.8's "limited comparable shift data" and "Ramadan context — calibrating",
/// as data. The engine's own text suffixes cover shift *transitions* (§13) and
/// say nothing about a baseline that has not activated yet, so these are
/// carried here and shown alongside the score rather than smuggled into
/// `ReadinessContext.shiftTransition`, which is a different fact with an
/// overlapping name.
public enum ReadinessBaselineNotice: String, Sendable, Hashable, Codable {
    case limitedComparableShiftData = "limited_comparable_shift_data"
    case ramadanContextCalibrating = "ramadan_context_calibrating"

    public var text: String {
        switch self {
        case .limitedComparableShiftData:
            return "Not enough comparable days on this shift yet — compared against your general average."
        case .ramadanContextCalibrating:
            return "Ramadan context — calibrating. Compared against your general average until enough Ramadan days are logged."
        }
    }
}

/// What a single day's score should be measured against, and what the user
/// should be told about how solid it is.
public struct ReadinessBaselineResolution: Sendable, Hashable {
    public let baseline: ReadinessBaseline
    /// §9.7's "Day X of 21 valid days", or nil once calibration is complete.
    /// Counts the app-wide valid days up to and including `day`.
    public let calibrationDay: Int?
    public let notice: ReadinessBaselineNotice?
    /// App-wide valid days up to and including the day in question. §9.8's
    /// "shift schedule change never resets the 21-day calibration" is a
    /// statement about this number, so it is carried rather than inferred.
    public let validDayCount: Int
    /// The window the numbers came from, for the record and for §9.9's
    /// "explain the score later" requirement. Nil when nothing qualified.
    public let windowStartDate: String?
    public let windowEndDate: String?

    public init(baseline: ReadinessBaseline, calibrationDay: Int?, notice: ReadinessBaselineNotice?,
                validDayCount: Int, windowStartDate: String? = nil, windowEndDate: String? = nil) {
        self.baseline = baseline
        self.calibrationDay = calibrationDay
        self.notice = notice
        self.validDayCount = validDayCount
        self.windowStartDate = windowStartDate
        self.windowEndDate = windowEndDate
    }
}

/// §9.7's calibration counting and §9.8's three baselines, as one pull-based
/// call over the stores that hold the underlying facts.
///
/// **This replaces an approximation that was standing in for it.**
/// `ReadinessModel.recentBaseline` averaged every RHR and HRV reading in the
/// last 28 *days* — counting days, not §9.7's valid days, and including days
/// with a single stray reading. It never counted calibration at all, so
/// `calibrationDay` stayed nil and the "Preliminary estimate" label §9.7
/// requires never appeared.
///
/// The three rules, and the data each one actually needs:
///
/// - **Valid day** (§9.7): sleep data, or *both* RHR and HRV. Computed over
///   whole history rather than a window, because "the first 21 valid days from
///   first use" is a statement about the beginning of the record and a 28-day
///   window would silently re-count a user who has been logging for a year.
/// - **General baseline** (§9.8): the last 28 valid days, any schedule.
/// - **Shift-specific** (§9.8): activated at 14 valid days on the same
///   `shiftType`; the window is the last 28 valid days *with that shift type*.
///   Below that, the general baseline plus
///   `limitedComparableShiftData`.
/// - **Ramadan** (§9.8): "prior years' Ramadan data may contribute if ≥ 14
///   usable Ramadan days exist in history", "activated at start of Ramadan if
///   prior data meets threshold". So the count is of usable Ramadan days
///   **before** this Ramadan's own start — a baseline built from the days being
///   scored would be circular, the same non-circularity
///   `NotificationTriggerAssembler.averageWakeTime` keeps for wake times.
///   Below the threshold: general baseline plus `ramadanContextCalibrating`.
///
/// **`day_record.dayType` is not read, and does not need to be.** §9.8 writes
/// "dayType = 'religious', scheduleType = 'ramadan'", but nothing in this repo
/// ever types a day — `dayType` is a column Migration014 creates and no code
/// writes. What exists and does carry the fact is
/// `ReligiousFastScheduleStore`: a `ramadan` schedule is a dated span, so
/// "is this a Ramadan day" is answerable directly, and it is answerable
/// *better* than through `dayType`, because the schedule is what the user can
/// correct (§11.2's calendar honesty). The substitution is recorded in
/// `docs/features/readiness.md` rather than made silently.
public struct ReadinessBaselineService: @unchecked Sendable {
    /// §9.8 — "Activated when: ≥ 14 valid days on the same shiftType".
    public static let shiftBaselineActivationDays = ReadinessFormula.shiftBaselineActivationDays
    /// §9.8 — "if ≥ 14 usable Ramadan days exist in history".
    public static let ramadanBaselineActivationDays = 14
    /// §9.8 — the rolling window for the general and shift-specific baselines.
    public static let windowDays = ReadinessFormula.baselineWindowDays

    private let db: Database
    private let timeModel: TimeModel
    private let sleepEpisodes: SleepEpisodeStore
    private let vitals: VitalsRecordStore
    private let shifts: ShiftScheduleStore
    private let fastSchedules: ReligiousFastScheduleStore

    public init(db: Database, timeModel: TimeModel, clock: any Clock = SystemClock()) {
        self.db = db
        self.timeModel = timeModel
        self.sleepEpisodes = SleepEpisodeStore(db: db, clock: clock)
        self.vitals = VitalsRecordStore(db: db, clock: clock)
        self.shifts = ShiftScheduleStore(db: db)
        self.fastSchedules = ReligiousFastScheduleStore(db: db, clock: clock)
    }

    /// The baseline `day` should be scored against, plus the calibration and
    /// comparability facts that go with it.
    public func resolve(for day: LogicalDay) throws -> ReadinessBaselineResolution {
        let facts = ValidDayFacts(db: db, timeModel: timeModel)
        let allValid = try facts.validDays()
        let validDayCount = allValid.filter { $0 <= day.value }.count

        // §9.7 — "First 21 valid days from first use", and "After calibration:
        // full personalised scoring active". So the 21st valid day is still the
        // last day *of* calibration, and the count stops after it: `<=`, not
        // `<`. Past the threshold the number is nil rather than a count, because
        // "Day 400 of 21" is not a sentence anyone should read.
        let calibrationDay: Int? = validDayCount <= ReadinessFormula.calibrationValidDays
            ? validDayCount
            : nil

        if let ramadan = try ramadanResolution(for: day, facts: facts) {
            return ReadinessBaselineResolution(
                baseline: ramadan.baseline,
                calibrationDay: calibrationDay,
                notice: ramadan.notice,
                validDayCount: validDayCount,
                windowStartDate: ramadan.windowStart,
                windowEndDate: ramadan.windowEnd)
        }

        if let shiftType = try shifts.occurrence(for: day.value)?.shiftType {
            let shiftDays = recent(try validDays(on: shiftType, facts: facts), through: day.value)
            if shiftDays.count >= Self.shiftBaselineActivationDays {
                return ReadinessBaselineResolution(
                    baseline: try averages(over: shiftDays, context: .shiftSpecific),
                    calibrationDay: calibrationDay, notice: nil, validDayCount: validDayCount,
                    windowStartDate: shiftDays.first, windowEndDate: shiftDays.last)
            }
            // Below the threshold the general baseline answers, and the user is
            // told why it is not a shift-specific one.
            let general = try generalResolution(for: day, facts: facts, calibrationDay: calibrationDay,
                                                validDayCount: validDayCount)
            return ReadinessBaselineResolution(
                baseline: general.baseline, calibrationDay: calibrationDay,
                notice: .limitedComparableShiftData, validDayCount: validDayCount,
                windowStartDate: general.windowStartDate, windowEndDate: general.windowEndDate)
        }

        return try generalResolution(for: day, facts: facts, calibrationDay: calibrationDay,
                                    validDayCount: validDayCount)
    }

    // MARK: - Private

    private func generalResolution(for day: LogicalDay, facts: ValidDayFacts,
                                   calibrationDay: Int?, validDayCount: Int) throws -> ReadinessBaselineResolution {
        let days = recent(try facts.validDays(), through: day.value)
        return ReadinessBaselineResolution(
            baseline: try averages(over: days, context: .general),
            calibrationDay: calibrationDay, notice: nil, validDayCount: validDayCount,
            windowStartDate: days.first, windowEndDate: days.last)
    }

    /// The Ramadan answer, or nil when `day` is not in a Ramadan at all.
    private func ramadanResolution(for day: LogicalDay, facts: ValidDayFacts) throws -> (
        baseline: ReadinessBaseline, notice: ReadinessBaselineNotice?,
        windowStart: String?, windowEnd: String?)? {
        guard let schedule = try fastSchedules.schedules(activeOnly: true)
            .first(where: { $0.scheduleType == "ramadan" && $0.covers(day.value) }) else { return nil }

        // Prior Ramadan days only. A baseline built from the days currently
        // being scored would be the score compared against itself.
        //
        // With no recorded start the schedule is an open-ended span, and
        // "before this Ramadan" has no answer. The conservative reading is used
        // instead: no prior days, which lands on the general baseline and the
        // calibrating notice rather than on a number built from this year's
        // own days.
        guard let scheduleStart = schedule.startGregorianDate else {
            let general = try generalWindow(for: day, facts: facts)
            return (try averages(over: general, context: .general),
                    .ramadanContextCalibrating, general.first, general.last)
        }
        let prior = try facts.validDays().filter { $0 < scheduleStart }
        let ramadanDays = try prior.filter { candidate in
            try fastSchedules.schedules(activeOnly: true)
                .contains { $0.scheduleType == "ramadan" && $0.covers(candidate) }
        }
        let start = max(0, ramadanDays.count - Self.windowDays)
        let usable = Array(ramadanDays[start...])

        guard usable.count >= Self.ramadanBaselineActivationDays else {
            // §9.8 — "otherwise general baseline + 'Ramadan context —
            // calibrating' notice". The general baseline is the fall-back *and*
            // the notice is what makes it honest, so neither is optional.
            let general = try generalWindow(for: day, facts: facts)
            return (try averages(over: general, context: .general),
                    .ramadanContextCalibrating, general.first, general.last)
        }
        return (try averages(over: usable, context: .ramadan), nil, usable.first, usable.last)
    }

    private func generalWindow(for day: LogicalDay, facts: ValidDayFacts) throws -> [String] {
        return recent(try facts.validDays(), through: day.value)
    }

    /// The last `windowDays` valid days on or before `date`, oldest first.
    /// `days` is already ascending, so this is a tail rather than a sort.
    private func recent(_ days: [String], through date: String) -> [String] {
        let eligible = days.filter { $0 <= date }
        let start = max(0, eligible.count - Self.windowDays)
        return Array(eligible[start...])
    }

    /// Valid days on one shift type, newest last, for the shift-specific window.
    private func validDays(on shiftType: ShiftType, facts: ValidDayFacts) throws -> [String] {
        try facts.validDays().filter { candidate in
            try shifts.occurrence(for: candidate)?.shiftType == shiftType
        }
    }

    /// The averages themselves. Averages over days rather than over readings,
    /// so a day with six RHR samples does not outvote a day with one.
    private func averages(over days: [String], context: ReadinessBaselineContext) throws -> ReadinessBaseline {
        guard !days.isEmpty else {
            return ReadinessBaseline(context: context, validDayCount: 0)
        }
        return ReadinessBaseline(
            context: context,
            restingHeartRate: try meanPerDay(days, metric: "rhr"),
            hrv: try meanPerDay(days, metric: "hrv"),
            validDayCount: days.count)
    }

    private func meanPerDay(_ days: [String], metric: String) throws -> Double? {
        let records = try vitals.records(metric: metric, logicalDays: days)
        var byDay: [String: [Double]] = [:]
        for record in records { byDay[record.logicalDay, default: []].append(record.value) }

        var dailyMeans: [Double] = []
        for day in days {
            guard let readings = byDay[day], !readings.isEmpty else { continue }
            dailyMeans.append(readings.reduce(0, +) / Double(readings.count))
        }
        guard !dailyMeans.isEmpty else { return nil }
        return dailyMeans.reduce(0, +) / Double(dailyMeans.count)
    }
}

/// §9.7's valid-day predicate, over whole history, computed once per
/// `ReadinessBaselineService.resolve` and shared by all three baselines.
///
/// One small type rather than three queries in the service because the three
/// baselines all need the same answer and the answer is a set intersection; a
/// per-baseline implementation would recompute it three times and could
/// disagree with itself if the data changed between calls.
struct ValidDayFacts: @unchecked Sendable {
    private let db: Database
    private let timeModel: TimeModel

    init(db: Database, timeModel: TimeModel) {
        self.db = db
        self.timeModel = timeModel
    }

    /// Every logical day in the record that §9.7 calls valid, ascending.
    func validDays() throws -> [String] {
        let sleep = try Set(db.query("SELECT DISTINCT logicalDay AS d FROM sleep_episode;")
            .compactMap { $0.string("d") })
        let rhr = try Set(db.query("SELECT DISTINCT logicalDay AS d FROM vitals_record WHERE metric = 'rhr';")
            .compactMap { $0.string("d") })
        let hrv = try Set(db.query("SELECT DISTINCT logicalDay AS d FROM vitals_record WHERE metric = 'hrv';")
            .compactMap { $0.string("d") })
        // §9.7 — "Sleep data … OR both RHR and HRV". An RHR without an HRV is
        // not a valid day, which is the whole reason the rule says "both".
        let both = rhr.intersection(hrv)
        return Array(sleep.union(both)).sorted()
    }
}

extension ReligiousFastSchedule {
    /// Whether `date` falls inside this schedule's stored span. Nil bounds are
    /// unbounded on that side, because a schedule row can legitimately carry
    /// only a start (a Ramadan the user entered late) or only an end.
    func covers(_ date: String) -> Bool {
        if let start = startGregorianDate, date < start { return false }
        if let end = endGregorianDate, date > end { return false }
        return startGregorianDate != nil || endGregorianDate != nil
    }
}
