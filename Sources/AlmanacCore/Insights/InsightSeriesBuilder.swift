import Foundation

/// The metrics the Insights surface can read, and how to read one of them for
/// a logical day.
///
/// This is the query builder that was missing. `CorrelationEngine`,
/// `TrendEngine` and `AchievementEngine` all take plain numbers and had been
/// complete and tested since Slice 10, with **nothing in the app able to hand
/// them any** — so `correlation_pair`, `trend_snapshot` and
/// `achievement_record` stayed permanently empty. The engines were never the
/// gap; the line between the tables and the numbers was.
///
/// **One value per metric per day, and which value that is has to be a
/// decision.** A day can hold four hydration entries and two mood check-ins.
/// Summing hydration is right; averaging four moods is a claim nobody made. So
/// each case below states its reduction, and the ones that are genuinely
/// ambiguous about it (mood, soreness) average and say so — those are
/// check-ins a user rates more than once a day, and their mean is the least
/// invented summary available.
public enum InsightMetric: String, Sendable, Hashable, CaseIterable, Identifiable {
    case readiness
    case sleepMinutes
    case hydrationMilliliters
    case steps
    case restingHeartRate
    case bodyWeightKg
    case trainingLoadTonnageKg
    case mood
    case soreness

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .readiness: return "Readiness"
        case .sleepMinutes: return "Sleep"
        case .hydrationMilliliters: return "Hydration"
        case .steps: return "Steps"
        case .restingHeartRate: return "Resting heart rate"
        case .bodyWeightKg: return "Weight"
        case .trainingLoadTonnageKg: return "Training load"
        case .mood: return "Mood"
        case .soreness: return "Soreness"
        }
    }

    /// The unit shown beside a value, or nil for a score.
    public var unit: String? {
        switch self {
        case .readiness: return nil
        case .sleepMinutes: return "min"
        case .hydrationMilliliters: return "mL"
        case .steps: return "steps"
        case .restingHeartRate: return "bpm"
        case .bodyWeightKg: return "kg"
        case .trainingLoadTonnageKg: return "kg"
        case .mood: return "/10"
        case .soreness: return "/10"
        }
    }

    /// How several entries on one day become one value.
    ///
    /// Stated on the case because it is the part a reader has to trust: "sleep
    /// 7h30" is obviously a total and "mood 7" obviously is not, and a screen
    /// that silently picked the wrong one would produce a chart that looks fine
    /// and means something else.
    public var reduction: Reduction {
        switch self {
        case .sleepMinutes, .hydrationMilliliters, .steps, .trainingLoadTonnageKg:
            return .sum
        case .readiness, .restingHeartRate, .bodyWeightKg:
            return .mean
        case .mood, .soreness:
            return .mean
        }
    }

    public enum Reduction: String, Sendable {
        case sum, mean
    }

    /// A step count is a sum, but resting heart rate is a mean, and both are
    /// "more than one reading a day" in principle. The distinction is what the
    /// reading *is*, not how many there are — so the two lists above are not
    /// merged.

    /// The pairs the Insights surface offers by default.
    ///
    /// Chosen because both sides are things the app already records daily, so a
    /// user reaches the 14-day gate rather than being told nothing was measured.
    /// Not offered: anything pairable with a context tag, because those are
    /// sparse by nature and would sit at "insufficient" permanently.
    public static let defaultPairs: [(InsightMetric, InsightMetric)] = [
        (.sleepMinutes, .readiness),
        (.sleepMinutes, .trainingLoadTonnageKg),
        (.hydrationMilliliters, .readiness),
        (.trainingLoadTonnageKg, .mood),
        (.soreness, .trainingLoadTonnageKg)
    ]
}

/// One metric's values across a range of logical days.
///
/// A dictionary keyed by day rather than an array, because **a day with no
/// reading must be absent rather than zero** — the absence is the whole reason
/// `CorrelationEngine` has a sample-size gate, and filling the gap would let a
/// pair reach that gate on days where nothing was measured.
public struct InsightSeries: Sendable, Hashable {
    public let metric: InsightMetric
    public let values: [String: Double]

    public init(metric: InsightMetric, values: [String: Double]) {
        self.metric = metric
        self.values = values
    }

    public func value(for day: String) -> Double? { values[day] }

    /// The values in day order, for `TrendEngine`, which needs a series and not
    /// a set.
    public func ordered(by days: [String]) -> [Double] {
        days.compactMap { values[$0] }
    }

    public var dayCount: Int { values.count }
}

/// Extracts `InsightSeries` from the real tables.
///
/// Pull-based and composed from the existing module stores rather than from raw
/// SQL, for the same reason `TrackingTimeline` is: a direct query here would be
/// a second statement of each table's meaning, and the two would drift.
public struct InsightSeriesBuilder: @unchecked Sendable {
    private let db: Database
    private let timeModel: TimeModel

    public init(db: Database, timeModel: TimeModel = TimeModel(timeZone: .current)) {
        self.db = db
        self.timeModel = timeModel
    }

    /// One metric across `[fromDay, toDay)`, `toDay` exclusive.
    ///
    /// Walks the days and calls each store's own per-day read rather than adding
    /// a range query to five modules. That is the same trade
    /// `TrackingSupplementProvider` makes, and for the same reason: a range
    /// query added only so one screen can avoid a loop is a new statement of a
    /// table's meaning in a module that has no use for it. Ninety indexed
    /// single-day reads is not the thing worth optimising in a local logbook.
    public func series(for metric: InsightMetric, fromDay: String, toDay: String) throws -> InsightSeries {
        var perDay: [String: [Double]] = [:]
        let days = days(from: fromDay, to: toDay)

        switch metric {
        case .readiness:
            // Only scored records. A provisional record with no score is not a
            // zero readiness, and averaging one in would quietly pull every
            // series down on days the app had nothing to say.
            for record in try ReadinessRecordStore(db: db).records(limit: 400)
            where record.anchorDate >= fromDay && record.anchorDate < toDay {
                guard let score = record.score else { continue }
                perDay[record.anchorDate, default: []].append(Double(score))
            }

        case .sleepMinutes:
            // The span of the day's episodes, summed. `sleep_episode` stores the
            // episode's duration, not a separately measured asleep time, so this
            // is time in bed — the label says "Sleep" because that is the
            // user's word for it, and the value is not claimed to be anything
            // more precise than it is.
            for day in days {
                let total = try SleepEpisodeStore(db: db).episodes(for: day)
                    .reduce(0.0) { $0 + Double($1.durationMinutes) }
                if total > 0 { perDay[day] = [total] }
            }

        case .hydrationMilliliters:
            // `HydrationStore` has no per-day read, so each day is bounded by
            // its own 04:00-to-04:00 span and asked for as instants. The bounds
            // come from `TimeModel`, so a 03:30 drink lands on the night before
            // — the same rule every other module in this file is keyed by.
            let store = HydrationStore(db: db)
            for day in days {
                guard let bounds = timeModel.bounds(of: LogicalDay(day)) else { continue }
                let text = DateRange(start: bounds.start, end: bounds.end).utcTextBounds
                let total = try store.logs(from: text.start, to: text.end)
                    .reduce(0.0) { $0 + $1.amount.value }
                if total > 0 { perDay[day] = [total] }
            }

        case .steps, .restingHeartRate:
            // The one case with a range read already: `records(metric:logicalDays:)`.
            let wanted = metric == .steps ? "steps" : "rhr"
            for record in try VitalsRecordStore(db: db).records(metric: wanted, logicalDays: days) {
                perDay[record.logicalDay, default: []].append(record.value)
            }

        case .bodyWeightKg:
            for record in try BodyCompositionMeasurementStore(db: db)
                .records(metric: "weight", from: fromDay, to: toDay) {
                perDay[record.logicalDay, default: []].append(record.value)
            }

        case .trainingLoadTonnageKg:
            // Nil tonnage left as an absence: a rest day and a session whose
            // work is not tonnage are both "no tonnage recorded", and neither is
            // zero kilograms lifted.
            let boutStore = WorkoutBoutStore(db: db)
            for session in try WorkoutSessionStore(db: db).sessions(from: fromDay, to: toDay) {
                let summary = WorkloadComputer.summary(for: try boutStore.bouts(sessionId: session.id))
                guard let tonnage = summary.totalTonnageKg else { continue }
                perDay[session.date, default: []].append(tonnage)
            }

        case .mood:
            let store = MoodLogStore(db: db)
            for day in days {
                let scores = try store.logs(for: day).map { Double($0.score) }
                if !scores.isEmpty { perDay[day] = scores }
            }

        case .soreness:
            let store = SorenessLogStore(db: db)
            for day in days {
                let scores = try store.logs(for: day).map { Double($0.overallScore) }
                if !scores.isEmpty { perDay[day] = scores }
            }
        }

        return InsightSeries(metric: metric, values: perDay.mapValues { reduce(metric.reduction, $0) })
    }

    private func reduce(_ reduction: InsightMetric.Reduction, _ values: [Double]) -> Double {
        switch reduction {
        case .sum: return values.reduce(0, +)
        case .mean: return values.reduce(0, +) / Double(values.count)
        }
    }

    /// The logical days in `[from, to)`.
    private func days(from: String, to: String) -> [String] {
        var result: [String] = []
        var cursor = LogicalDay(from)
        for _ in 0..<370 {
            if cursor.value >= to { break }
            result.append(cursor.value)
            guard let next = timeModel.day(after: cursor) else { break }
            cursor = next
        }
        return result
    }
}
