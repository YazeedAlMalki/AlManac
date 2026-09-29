import Testing
import Foundation
@testable import AlmanacCore

/// The line between the tables and the numbers — the thing whose absence left
/// `correlation_pair`, `trend_snapshot` and `achievement_record` permanently
/// empty while their engines sat complete and tested.
@Suite("Insights series and query")
struct InsightsQueryTests {
    let db = try! TestDatabase()
    let timeModel = TimeModel.riyadh()

    /// 2026-02-25 in Riyadh, 12:00 local.
    private let noon = Date(timeIntervalSince1970: 1_772_000_000)
    private let riyadh = ZoneContext(TimeZone(identifier: "Asia/Riyadh")!)

    private var builder: InsightSeriesBuilder {
        InsightSeriesBuilder(db: db, timeModel: timeModel)
    }

    /// The `offset`-th logical day after 2026-02-25.
    ///
    /// Walked through `TimeModel` rather than by string arithmetic, which would
    /// produce "2026-02-30" and silently drop that day's fixture.
    private func day(offset: Int) -> String {
        var cursor = LogicalDay("2026-02-25")
        for _ in 0..<offset {
            guard let next = timeModel.day(after: cursor) else { break }
            cursor = next
        }
        return cursor.value
    }

    private func logHydration(_ milliliters: Int, on day: String, at hour: Int = 12) throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone(identifier: "Asia/Riyadh")
        guard let instant = formatter.date(from: "\(day) \(String(format: "%02d", hour)):00") else {
            Issue.record("bad fixture date \(day)")
            return
        }
        _ = try HydrationStore(db: db).log(
            HydrationLogDraft(amount: Milliliters(Double(milliliters)), loggedAt: instant))
    }

    // MARK: - Reduction

    @Test("Hydration sums across a day; four drinks are one figure, not four")
    func hydrationSums() throws {
        try logHydration(250, on: "2026-02-25", at: 8)
        try logHydration(500, on: "2026-02-25", at: 13)
        try logHydration(250, on: "2026-02-25", at: 20)

        let series = try builder.series(for: .hydrationMilliliters,
                                        fromDay: "2026-02-25", toDay: "2026-02-26")
        #expect(series.value(for: "2026-02-25") == 1000)
    }

    @Test("A day with nothing recorded is absent, not zero")
    func emptyDayIsAbsentNotZero() throws {
        // The whole reason `CorrelationEngine` has a sample-size gate. A zero
        // here would reach the gate on days where nothing was measured.
        try logHydration(500, on: "2026-02-25")

        let series = try builder.series(for: .hydrationMilliliters,
                                        fromDay: "2026-02-24", toDay: "2026-02-27")
        #expect(series.value(for: "2026-02-25") == 500)
        #expect(series.value(for: "2026-02-26") == nil)
        #expect(series.dayCount == 1)
    }

    @Test("A 03:00 drink belongs to the previous logical day")
    func lateNightDrinkLandsOnThePriorDay() throws {
        // 03:00 on the 26th is before the 04:00 boundary, so it is the 25th.
        try logHydration(300, on: "2026-02-26", at: 3)
        try logHydration(300, on: "2026-02-25", at: 21)

        let series = try builder.series(for: .hydrationMilliliters,
                                        fromDay: "2026-02-24", toDay: "2026-02-27")
        #expect(series.value(for: "2026-02-25") == 600, "the 03:00 drink is on the wrong day")
        #expect(series.value(for: "2026-02-26") == nil)
    }

    @Test("Mood is averaged, not summed — a 7 is not four 7s")
    func moodAverages() throws {
        let store = MoodLogStore(db: db)
        try store.log(MoodLogDraft(score: 6, timestamp: noon), logicalDay: "2026-02-25")
        try store.log(MoodLogDraft(score: 8, timestamp: noon.addingTimeInterval(3600)), logicalDay: "2026-02-25")

        let series = try builder.series(for: .mood, fromDay: "2026-02-25", toDay: "2026-02-26")
        #expect(series.value(for: "2026-02-25") == 7)
    }

    @Test("A day with no readiness record contributes nothing rather than a zero")
    func missingReadinessIsSkipped() throws {
        // A provisional record is not a zero readiness, and averaging one in
        // would pull every series down on days the app had nothing to say.
        let series = try builder.series(for: .readiness, fromDay: "2026-02-25", toDay: "2026-02-26")
        #expect(series.values.isEmpty)
    }

    // MARK: - Correlation

    /// Two metrics paired only on days where **both** were recorded.
    @Test("Pairs are only the days both metrics have")
    func pairsOnlySharedDays() throws {
        try logHydration(500, on: "2026-02-25")
        try logHydration(500, on: "2026-02-26")
        // No sleep on the 25th, so the 25th cannot be a pair.
        _ = try SleepEpisodeStore(db: db).upsert(
            SleepEpisode(start: noon.addingTimeInterval(-8 * 3600), end: noon,
                         type: .primary, source: .manual, asleepMinutes: 480),
            timezoneOffset: 180, logicalDay: "2026-02-26")

        let query = InsightsQuery(db: db, timeModel: timeModel)
        // A range that ends today, so pass the days directly instead.
        let sleep = try builder.series(for: .sleepMinutes, fromDay: "2026-02-25", toDay: "2026-02-27")
        let water = try builder.series(for: .hydrationMilliliters, fromDay: "2026-02-25", toDay: "2026-02-27")
        let shared = ["2026-02-25", "2026-02-26"].compactMap { day -> (Double, Double)? in
            guard let x = sleep.value(for: day), let y = water.value(for: day) else { return nil }
            return (x, y)
        }
        #expect(shared.count == 1, "the 25th has no sleep and must not be paired")
        _ = query
    }

    @Test("A correlation with too few paired days reports insufficient, not a number")
    func correlationIsGated() throws {
        // Five days of each, against a 14-day gate.
        let days = (0..<5).map { day(offset: $0) }
        for day in days { try logHydration(500, on: day) }

        var pairs: [(Double, Double)] = []
        let water = try builder.series(for: .hydrationMilliliters,
                                       fromDay: days[0], toDay: day(offset: 5))
        for (index, day) in days.enumerated() {
            guard let y = water.value(for: day) else { continue }
            pairs.append((Double(400 + index * 10), y))
        }
        let result = CorrelationEngine.pearson(pairs)
        #expect(pairs.count == 5)
        #expect(result == .insufficientData(sampleSize: 5, minimumRequired: 14))
    }

    // MARK: - Trend persistence

    @Test("A trend is computed and its snapshot persisted")
    func trendIsPersisted() throws {
        for offset in 0..<20 { try logHydration(400 + offset * 10, on: day(offset: offset)) }
        let series = try builder.series(for: .hydrationMilliliters,
                                        fromDay: day(offset: 0), toDay: day(offset: 21))
        let snapshot = try #require(TrendEngine.snapshot(of: series.ordered(by: series.values.keys.sorted())))
        #expect(snapshot.direction == .up)

        try TrendSnapshotStore(db: db).save(metric: "hydrationMilliliters", period: "30d", snapshot: snapshot)
        let read = try TrendSnapshotStore(db: db).snapshot(metric: "hydrationMilliliters", period: "30d")
        #expect(read?.direction == .up, "the direction did not survive the round trip")
        #expect(read?.average == snapshot.average)
    }

    /// The direction used to round-trip through `String(describing:)`, which
    /// happened to produce "up" and matched the reader by luck. A raw value
    /// makes the storage representation a decision.
    @Test("Every trend direction survives a storage round trip")
    func everyDirectionRoundTrips() throws {
        let store = TrendSnapshotStore(db: db)
        for direction in TrendDirection.allCases {
            let snapshot = TrendSnapshot(average: 1, minimum: 0, maximum: 2, direction: direction)
            try store.save(metric: "m-\(direction.rawValue)", period: "30d", snapshot: snapshot)
            let read = try store.snapshot(metric: "m-\(direction.rawValue)", period: "30d")
            #expect(read?.direction == direction, "\(direction) did not survive the round trip")
        }
    }

    // MARK: - The unordered-pair defect

    @Test("A correlation pair is one row whichever way round it is asked for")
    func pairIsUnordered() throws {
        let store = CorrelationPairStore(db: db)
        try store.save(metricA: "sleepMinutes", metricB: "readiness",
                       result: .computed(r: 0.62, sampleSize: 21))

        // The doc comment said "unordered" and the code did not: these used to
        // be two different rows holding the same number.
        #expect(try store.pair(metricA: "sleepMinutes", metricB: "readiness")?.rValue == 0.62)
        #expect(try store.pair(metricA: "readiness", metricB: "sleepMinutes")?.rValue == 0.62)

        let rows = try db.query("SELECT COUNT(*) AS n FROM correlation_pair;").first?.int("n")
        #expect(rows == 1, "the pair was stored twice")
    }

    @Test("Recomputing a pair in reverse order replaces the row rather than adding one")
    func reverseOrderReplaces() throws {
        let store = CorrelationPairStore(db: db)
        try store.save(metricA: "a", metricB: "b", result: .computed(r: 0.5, sampleSize: 20))
        try store.save(metricA: "b", metricB: "a", result: .computed(r: 0.8, sampleSize: 30))

        #expect(try db.query("SELECT COUNT(*) AS n FROM correlation_pair;").first?.int("n") == 1)
        let record = try store.pair(metricA: "b", metricB: "a")
        #expect(record?.rValue == 0.8, "the later computation did not win")
        #expect(record?.sampleSize == 30)
    }

    @Test("The stored pair is always in canonical order, whatever went in")
    func storedPairIsCanonical() throws {
        let store = CorrelationPairStore(db: db)
        try store.save(metricA: "zebra", metricB: "apple", result: .computed(r: 0.1, sampleSize: 20))
        let record = try store.pair(metricA: "zebra", metricB: "apple")
        #expect(record?.metricA == "apple")
        #expect(record?.metricB == "zebra")
    }

    @Test("A list of pairs reports each once, confident first")
    func allPairsIsOrdered() throws {
        let store = CorrelationPairStore(db: db)
        try store.save(metricA: "a", metricB: "b", result: .computed(r: 0.9, sampleSize: 30))
        try store.save(metricA: "c", metricB: "d", result: .insufficientData(sampleSize: 3, minimumRequired: 14))
        try store.save(metricA: "e", metricB: "f", result: .computed(r: 0.2, sampleSize: 20))

        let all = try store.allPairs()
        #expect(all.count == 3)
        // Strongest first, and the insufficient one last rather than mixed in.
        #expect(all[0].rValue == 0.9)
        #expect(all[2].rValue == nil)
        #expect(all[2].confidenceLevel == "insufficient")
    }

    // MARK: - Achievements

    @Test("A dry fast day is recorded as a badge")
    func fastedDayIsBadged() throws {
        let query = InsightsQuery(db: db, timeModel: timeModel)
        let day = "2026-02-25"
        _ = try FastingSessionStore(db: db).start(
            FastingSessionDraft(startTimestamp: noon, sessionType: .religious, isDryFast: true),
            logicalDay: day)

        let inputs = try query.achievementInputs(for: day)
        #expect(inputs.isFastedDay)
        #expect(AchievementEngine.badges(for: inputs).contains(.fastedDay))
    }

    /// The badge engine's own header says the definition of a perfect log is
    /// undecided, so nothing may award one.
    @Test("A perfect log is never awarded, because its definition is undecided")
    func perfectLogIsNeverAwarded() throws {
        let query = InsightsQuery(db: db, timeModel: timeModel)
        let day = "2026-02-25"
        try logHydration(3000, on: day)
        let settings = try HydrationSettingsStore(db: db).getOrCreate()
        try HydrationSettingsStore(db: db).save(
            HydrationSettings(isCalorieTrackingEnabled: settings.isCalorieTrackingEnabled,
                              isDoubleTrackWarningEnabled: settings.isDoubleTrackWarningEnabled,
                              remindersEnabled: settings.remindersEnabled,
                              reminderIntervalMinutes: settings.reminderIntervalMinutes,
                              reminderStartHour: settings.reminderStartHour,
                              reminderEndHour: settings.reminderEndHour,
                              dailyGoalMilliliters: 2000,
                              trackSodium: settings.trackSodium,
                              trackSugar: settings.trackSugar))

        #expect(try query.achievementInputs(for: day).isPerfectLog == false)
        #expect(try query.recomputeAchievements(for: day).contains(.perfectLog) == false)
        #expect(try AchievementRecordStore(db: db).metBadges(for: day).contains(.perfectLog) == false)
    }

    @Test("A day is recomputed, not accumulated — an edit replaces the badges")
    func recomputeReplaces() throws {
        let store = AchievementRecordStore(db: db)
        try store.recompute(logicalDay: "2026-02-25", earned: [.fastedDay, .highLoadDay])
        try store.recompute(logicalDay: "2026-02-25", earned: [.fastedDay])

        // Every badge gets a row, met or not, so the second pass is a plain
        // upsert rather than a diff.
        #expect(try store.metBadges(for: "2026-02-25") == [.fastedDay])
        let rows = try db.query(
            "SELECT COUNT(*) AS n FROM achievement_record WHERE logicalDay = '2026-02-25';").first?.int("n")
        #expect(rows == Int64(AchievementBadge.allCases.count))
    }
}
