import Foundation

/// Plants the last `days` days of readiness history — a night's sleep, the
/// morning's resting heart rate and HRV, and the score those would have earned
/// — by relaunching the app with `-AlmanacSeedReadinessHistory <days>`.
///
/// ## Why history has to be planted as scores, not only as inputs
///
/// The app scores readiness for **today**, when the dashboard computes it
/// (`ReadinessModel.refresh`), and `readiness_record` keeps one row per cycle.
/// Nothing ever goes back and scores a past day. So sleep and vitals planted on
/// earlier days give the Trends chart nothing to draw: they only move today's
/// baseline. A chart with history needs a record for each of those days, and
/// this writes one, with the score the same engine gives the same inputs.
///
/// It is for the UI tests that need a readiness chart with a direction — the
/// Arabic pass reads which way the chart runs in a right-to-left layout. It is
/// gated exactly as `VitalsSeedPlan` is, by a launch argument that no ordinary
/// launch carries and by the app's `#if DEBUG` around its only call site; see
/// there for why reachability rather than absence is the claim.
///
/// ## What a day gets
///
/// Oldest day first, so each day's baseline is built from the days before it,
/// as it would have been. Day `k` of `n` (0 = oldest):
///
/// - a primary night ending 07:00, asleep 6 h + 8 min × k;
/// - resting heart rate 62 − 0.5 × k and HRV 45 + 1.5 × k, at 09:00;
/// - a provisional score from `ReadinessEngine.evaluate` against
///   `ReadinessBaselineService`'s baseline for that day, recorded on that day's
///   cycle.
///
/// Sleep lengthens, the resting rate falls and HRV rises, so the scores climb
/// and the chart has a direction to read.
///
/// **Authoritative, not additive.** A UI test relaunches the app many times and
/// the simulator's database is never reset, so applying the same plan twice must
/// leave the same rows. The sleep episode carries a fixed seed id in
/// `healthKitUUID`, which `SleepEpisodeStore.upsert` resolves to the same row;
/// the vitals go through `VitalsSeedPlan`, which replaces a day's manual
/// readings; the cycle is `ensureCycle`'d; and `ReadinessRecordStore.record`
/// upserts on the cycle.
public struct ReadinessHistorySeedPlan: Sendable, Hashable {
    public static let launchArgument = "-AlmanacSeedReadinessHistory"

    /// How far back a plan may reach. Ninety is the Trends chart's default
    /// window; anything longer is not a test's business.
    public static let maximumDays = 90

    /// The hour a seeded night ends. Before `VitalsSeedPlan.morningHour`, so the
    /// morning readings fall inside the cycle the night starts.
    public static let wakeHour = 7

    public let days: Int

    public init?(days: Int) {
        guard (1...Self.maximumDays).contains(days) else { return nil }
        self.days = days
    }

    /// `"14"` → fourteen days. Anything else is refused whole.
    public init?(spec: String) {
        guard let days = Int(spec.trimmingCharacters(in: .whitespaces)) else { return nil }
        self.init(days: days)
    }

    /// The plan the launch arguments asked for, or nil when they did not ask —
    /// which is every ordinary launch.
    public static func fromLaunchArguments(_ arguments: [String]) -> ReadinessHistorySeedPlan? {
        guard let index = arguments.firstIndex(of: launchArgument),
              arguments.indices.contains(index + 1) else { return nil }
        return ReadinessHistorySeedPlan(spec: arguments[index + 1])
    }

    /// What day `k` (0 = oldest) is given.
    public struct Day: Sendable, Hashable {
        public let asleepMinutes: Int
        public let restingHeartRate: Double
        public let hrv: Double
    }

    public static func inputs(forDay k: Int) -> Day {
        Day(asleepMinutes: 360 + 8 * k,
            restingHeartRate: 62 - 0.5 * Double(k),
            hrv: 45 + 1.5 * Double(k))
    }

    /// Plants and scores every day. Returns the days scored, oldest first.
    @discardableResult
    public func apply(into db: Database,
                      now: Date = Date(),
                      timeModel: TimeModel = TimeModel(timeZone: .current)) throws -> [LogicalDay] {
        let zone = timeModel.timeZone
        let vitals = VitalsRecordStore(db: db, zone: ZoneContext(zone), timeModel: timeModel)
        let sleep = SleepEpisodeStore(db: db)
        let cycles = ReadinessCycleStore(db: db)
        let records = ReadinessRecordStore(db: db)
        let baselines = ReadinessBaselineService(db: db, timeModel: timeModel)

        var scored: [LogicalDay] = []
        for (k, offset) in stride(from: days, through: 1, by: -1).enumerated() {
            let day = Self.inputs(forDay: k)
            let readings = [
                VitalsSeedReading(metric: .restingHeartRate, value: day.restingHeartRate, dayOffset: -offset),
                VitalsSeedReading(metric: .heartRateVariability, value: day.hrv, dayOffset: -offset),
            ]
            let vitalsPlan = VitalsSeedPlan(readings: readings)
            guard let logicalDay = vitalsPlan.logicalDay(for: -offset, now: now, timeModel: timeModel),
                  let dayStart = timeModel.start(of: logicalDay) else { continue }

            // The night: asleep the whole span, ending at the wake hour. The
            // seed id makes a second application update this row, not add one.
            let wake = Calendar.gregorianIn(zone).date(
                bySettingHour: Self.wakeHour, minute: 0, second: 0, of: dayStart) ?? dayStart
            let bed = wake.addingTimeInterval(-Double(day.asleepMinutes) * 60)
            try sleep.upsert(
                SleepEpisode(start: bed, end: wake, type: .primary, source: .manual,
                             asleepMinutes: day.asleepMinutes,
                             healthKitUUIDs: ["almanac-seed-sleep-\(logicalDay.value)"]),
                timezoneOffset: zone.secondsFromGMT(for: wake) / 60,
                logicalDay: logicalDay.value)
            try vitalsPlan.apply(into: vitals, now: now, timeModel: timeModel)

            // The score the dashboard would have shown that morning: the same
            // engine, the same baseline service, the day's own inputs.
            let resolution = try baselines.resolve(for: logicalDay)
            let outcome = ReadinessEngine.evaluate(
                state: .provisional,
                inputs: ReadinessInputs(sleepDurationMinutes: day.asleepMinutes,
                                        restingHeartRate: day.restingHeartRate,
                                        hrv: day.hrv,
                                        totalSleepAcrossEpisodesMinutes: day.asleepMinutes),
                baseline: resolution.baseline,
                context: ReadinessContext(calibrationDay: resolution.calibrationDay))
            let cycle = try cycles.ensureCycle(anchorDate: logicalDay.value, at: wake)
            try records.record(outcome, cycleId: cycle, anchorDate: logicalDay.value)
            scored.append(logicalDay)
        }
        return scored
    }
}

private extension Calendar {
    static func gregorianIn(_ zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }
}
