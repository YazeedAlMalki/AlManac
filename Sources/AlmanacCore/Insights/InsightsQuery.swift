import Foundation

/// Runs the three insights engines over real data.
///
/// The engines (`TrendEngine`, `CorrelationEngine`, `AchievementEngine`) have
/// been complete and tested since Slice 10 and had nothing in the app able to
/// hand them a number. This is that hand-off: read the tables, build the
/// series, run the engines, persist what they say.
///
/// **Association, not causation, and the wording is load-bearing.** The BRD's
/// guardrail is a rule about what a screen may say, so `CorrelationSummary` can
/// only produce the two halves of a sentence that cannot be misread as
/// cause: the number and the count of days behind it. The direction word is
/// derived from `r`'s sign, and the screen below adds the caveat in words.
public struct InsightsQuery: @unchecked Sendable {
    private let db: Database
    private let timeModel: TimeModel
    private let builder: InsightSeriesBuilder
    private let clock: any Clock

    /// The clock is injected like everywhere else in this package, and for the
    /// same reason: `recentRange` used to reach for `Date()` directly, which
    /// meant the only way to test a *window* was to write fixtures relative to
    /// whenever the test happened to run. Every other store here takes a
    /// `Clock`, and this one type was the outlier.
    public init(db: Database, timeModel: TimeModel = TimeModel(timeZone: .current),
                clock: any Clock = SystemClock()) {
        self.db = db
        self.timeModel = timeModel
        self.builder = InsightSeriesBuilder(db: db, timeModel: timeModel)
        self.clock = clock
    }

    // MARK: - Range

    /// `[fromDay, toDay)` covering the last `dayCount` logical days, ending
    /// today.
    public func recentRange(dayCount: Int) -> (from: String, to: String, days: [String]) {
        let end = timeModel.logicalDay(clock.now)
        let count = max(1, dayCount)
        var cursor = end
        for _ in 0..<(count - 1) {
            guard let previous = timeModel.day(before: cursor) else { break }
            cursor = previous
        }
        var days: [String] = [cursor.value]
        for _ in 0..<(count - 1) {
            guard let next = timeModel.day(after: LogicalDay(days[days.count - 1])) else { break }
            days.append(next.value)
        }
        return (cursor.value, end.value, days)
    }

    // MARK: - Trends

    /// One metric's trend over the range, and its persisted snapshot.
    ///
    /// The snapshot is saved so `trend_snapshot` stops being permanently empty,
    /// and it is saved on every call rather than behind a "recompute nightly"
    /// policy — the horizon is a caller concern the engine's own header already
    /// states, and a stored number nobody refreshes is worse than none.
    public func trend(for metric: InsightMetric, dayCount: Int) throws -> TrendSummary? {
        let range = recentRange(dayCount: dayCount)
        let series = try builder.series(for: metric, fromDay: range.from, toDay: range.to)
        let values = series.ordered(by: range.days)
        guard let snapshot = TrendEngine.snapshot(of: values) else { return nil }

        let period = "\(dayCount)d"
        try TrendSnapshotStore(db: db).save(metric: metric.rawValue, period: period, snapshot: snapshot)

        return TrendSummary(
            metric: metric,
            snapshot: snapshot,
            dayCount: series.dayCount,
            windowCount: dayCount,
            period: period
        )
    }

    // MARK: - Correlations

    /// The paired days two metrics share, and the correlation over them.
    ///
    /// **Only days where both metrics have a reading are paired.** Interpolating
    /// a missing hydration figure from its neighbours would reach
    /// `CorrelationEngine`'s 14-day gate on days where one side was never
    /// measured, and the resulting `r` would be a statement about the
    /// interpolation as much as about sleep.
    ///
    /// **Days in a circadian transition are left out.** BRD §6.15 names
    /// "comparable-day filtering (Day Type + Circadian Context)" and §13.2 says
    /// insights use `circadian_context.contextType` as a filter. A week spent
    /// moving from nights to days is not a week whose sleep and readiness sit on
    /// the same footing as a settled one, and pooling the two is how a
    /// correlation picks up a schedule change and reports it as a relationship
    /// between two measurements.
    ///
    /// **The filter is dropped when it would cost more than half the window.**
    /// A filter that empties the sample is not a stricter answer, it is a missing
    /// one, and the summary carries which of the two happened so the screen can
    /// say so rather than showing a number of unexplained provenance.
    public func correlation(between a: InsightMetric, and b: InsightMetric,
                            dayCount: Int) throws -> CorrelationSummary {
        let range = recentRange(dayCount: dayCount)
        let left = try builder.series(for: a, fromDay: range.from, toDay: range.to)
        let right = try builder.series(for: b, fromDay: range.from, toDay: range.to)
        let transitions = try transitionDays(in: range.days)

        var allPairs: [(Double, Double)] = []
        var comparablePairs: [(Double, Double)] = []
        var excluded = 0
        for day in range.days {
            guard let x = left.value(for: day), let y = right.value(for: day) else { continue }
            allPairs.append((x, y))
            if transitions.contains(day) {
                excluded += 1
            } else {
                comparablePairs.append((x, y))
            }
        }

        let filtered = !comparablePairs.isEmpty && comparablePairs.count * 2 >= allPairs.count
        let result = CorrelationEngine.pearson(filtered ? comparablePairs : allPairs)
        try CorrelationPairStore(db: db).save(
            metricA: a.rawValue, metricB: b.rawValue, result: result)

        return CorrelationSummary(metricA: a, metricB: b, result: result, windowCount: dayCount,
                                 excludedTransitionDays: filtered ? excluded : 0)
    }

    /// The dates in `days` whose stored circadian context is a transition.
    ///
    /// One ranged read rather than a lookup per day, because the row is keyed on
    /// `date` and the window is a bounded handful of days. A date with no row is
    /// **not** a transition: the table is only written for dates the readiness
    /// cycle linking service has processed, and an unprocessed date makes no
    /// claim in either direction. Treating absence as a transition would delete
    /// every unlinked day from every correlation, which is the opposite of what
    /// the filter is for.
    private func transitionDays(in days: [String]) throws -> Set<String> {
        guard let first = days.first, let last = days.last, first <= last else { return [] }
        var result: Set<String> = []
        for row in try db.query("""
            SELECT date, contextType FROM circadian_context WHERE date >= ? AND date <= ?;
            """, [.text(first), .text(last)]) {
            guard let date = row.string("date"),
                  let raw = row.string("contextType"),
                  let type = CircadianContextType(rawValue: raw),
                  type == .transitionEarlier || type == .transitionLater else { continue }
            result.insert(date)
        }
        return result
    }

    /// The default pairs, each computed and persisted.
    public func allDefaultCorrelations(dayCount: Int) throws -> [CorrelationSummary] {
        try InsightMetric.defaultPairs.map { try correlation(between: $0.0, and: $0.1, dayCount: dayCount) }
    }

    // MARK: - Achievements

    /// Recomputes a day's badges and persists all five rows.
    ///
    /// `isPerfectLog` is **false for every day**, and that is a recorded gap
    /// rather than a computed one. `AchievementEngine`'s own header says the
    /// handoff leaves "all Wellness data filled in, or all recommended entries
    /// logged?" undecided — and a badge that claims a perfect log on a day the
    /// definition of which nobody has signed off is exactly the kind of invented
    /// precision this app refuses elsewhere. `.perfectLog` therefore never
    /// appears, and `docs/features/insights.md` records that the other four do.
    public func recomputeAchievements(for day: String) throws -> Set<AchievementBadge> {
        let earned = AchievementEngine.badges(for: try achievementInputs(for: day))
        try AchievementRecordStore(db: db).recompute(logicalDay: day, earned: earned)
        return earned
    }

    /// The engine's inputs, assembled from the real tables.
    ///
    /// Three of the nine inputs are **not** derived, and each says why in place
    /// rather than being quietly defaulted. They are the ones a badge would
    /// otherwise claim a fact about: the two nutrition targets need a Diet
    /// Profile that does not exist, `isPerfectLog` needs a definition nobody
    /// has signed off, and the two thresholds need target values that are not
    /// specified anywhere in this codebase. Inventing them would make
    /// `achievement_record` non-empty and wrong, which is worse than empty.
    public func achievementInputs(for day: String) throws -> DailyAchievementInputs {
        let hydration = try HydrationStore(db: db)
            .total(from: day, to: boundsEnd(after: day))
            .value
        let goal = try HydrationSettingsStore(db: db).getOrCreate().dailyGoalMilliliters
        let summary = WorkloadComputer.summary(
            for: try WorkoutBoutStore(db: db).bouts(sessionId: sessionId(for: day) ?? -1))
        let steps = try VitalsRecordStore(db: db).records(metric: "steps", logicalDays: [day])
            .reduce(0.0) { $0 + $1.value }

        return DailyAchievementInputs(
            steps: Int(steps.rounded()),
            stepsTarget: 0,
            trainingLoad: summary.totalTonnageKg ?? 0,
            highLoadThreshold: 0,
            isFastedDay: try isFasted(day),
            calorieTargetMet: false,
            macroTargetMet: false,
            hydrationTargetMet: goal.map { hydration >= $0 } ?? false,
            isPerfectLog: false
        )
    }

    private func sessionId(for day: String) -> Int64? {
        (try? WorkoutSessionStore(db: db).sessions(date: day).first?.id) ?? nil
    }

    private func isFasted(_ day: String) throws -> Bool {
        try FastingSessionStore(db: db).sessions(for: day).contains { $0.isDryFast }
    }

    private func boundsEnd(after day: String) -> String {
        timeModel.day(after: LogicalDay(day))?.value ?? day
    }
}

// MARK: - Results

/// A metric's trend, with enough context to state it honestly.
public struct TrendSummary: Sendable, Hashable, Identifiable {
    public let metric: InsightMetric
    public let snapshot: TrendSnapshot
    /// Days that actually had a reading — not the window length. The difference
    /// is the difference between "sleep fell 40 minutes" and "sleep fell 40
    /// minutes across six recorded days of a fortnight", and only one of those
    /// is a statement about the user.
    public let dayCount: Int
    public let windowCount: Int
    public let period: String

    public var id: String { "\(metric.rawValue)-\(period)" }
}

/// A pair's correlation, carrying the count it was computed from.
public struct CorrelationSummary: Sendable, Hashable, Identifiable {
    public let metricA: InsightMetric
    public let metricB: InsightMetric
    public let result: CorrelationResult
    public let windowCount: Int
    /// Paired days dropped because they were inside a circadian transition
    /// (BRD §6.15 comparable-day filtering). Zero both when the filter was
    /// dropped for want of data and when there was nothing to filter — the
    /// screen only needs to mention it when it actually happened.
    public let excludedTransitionDays: Int

    public init(metricA: InsightMetric, metricB: InsightMetric, result: CorrelationResult,
                windowCount: Int, excludedTransitionDays: Int = 0) {
        self.metricA = metricA
        self.metricB = metricB
        self.result = result
        self.windowCount = windowCount
        self.excludedTransitionDays = excludedTransitionDays
    }

    public var id: String { "\(metricA.rawValue)-\(metricB.rawValue)" }

    public var isConfident: Bool {
        if case .computed = result { return true }
        return false
    }

    public var sampleSize: Int {
        switch result {
        case .computed(_, let n), .insufficientData(let n, _): return n
        }
    }

    public var minimumRequired: Int { CorrelationEngine.minimumSampleSize }

    /// `r`, or nil when the pair is short of data.
    ///
    /// Nil rather than zero. A pair with two days is not "no relationship"; it
    /// is an unknown, and the app's rule is that an unknown value slot stays
    /// empty.
    public var rValue: Double? {
        if case .computed(let r, _) = result { return r }
        return nil
    }

    /// The direction word, from the sign of `r`.
    ///
    /// Named for the *association*, not a cause: `.movesTogether` would be a
    /// claim about the world, and `r` cannot make one.
    public var direction: AssociationDirection? {
        guard let r = rValue else { return nil }
        if r > 0 { return .higherTogether }
        if r < 0 { return .lowerTogether }
        return .noAssociation
    }
}

/// How two measurements move relative to each other.
public enum AssociationDirection: String, Sendable, Hashable {
    case higherTogether
    case lowerTogether
    case noAssociation

    /// Deliberately says "moves", not "causes" or "affects".
    public var displayName: String {
        switch self {
        case .higherTogether: return "Higher together"
        case .lowerTogether: return "Lower together"
        case .noAssociation: return "No clear pattern"
        }
    }

    public var symbol: String {
        switch self {
        case .higherTogether: return "arrow.up.right"
        case .lowerTogether: return "arrow.down.right"
        case .noAssociation: return "minus"
        }
    }
}
