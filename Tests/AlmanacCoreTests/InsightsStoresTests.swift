import Testing
import Foundation
@testable import AlmanacCore

@Suite("TrendSnapshotStore Tests")
struct TrendSnapshotStoreTests {
    let db = try! TestDatabase()
    var store: TrendSnapshotStore { TrendSnapshotStore(db: db) }

    @Test("Save and load a trend snapshot for a metric/period")
    func saveAndLoad() throws {
        let snapshot = TrendSnapshot(average: 7.2, minimum: 5.0, maximum: 9.0, direction: .up)
        try store.save(metric: "sleep_hours", period: "7day", snapshot: snapshot)

        let loaded = try store.snapshot(metric: "sleep_hours", period: "7day")
        #expect(loaded?.average == 7.2)
        #expect(loaded?.direction == .up)
    }

    @Test("Saving again for the same metric/period overwrites, not duplicates")
    func saveOverwrites() throws {
        try store.save(metric: "steps", period: "7day",
                        snapshot: TrendSnapshot(average: 1, minimum: 1, maximum: 1, direction: .flat))
        try store.save(metric: "steps", period: "7day",
                        snapshot: TrendSnapshot(average: 2, minimum: 2, maximum: 2, direction: .up))

        #expect(try store.snapshot(metric: "steps", period: "7day")?.average == 2)
        let count = try db.query("SELECT COUNT(*) AS n FROM trend_snapshot;").first?.int("n")
        #expect(count == 1)
    }
}

@Suite("CorrelationPairStore Tests")
struct CorrelationPairStoreTests {
    let db = try! TestDatabase()
    var store: CorrelationPairStore { CorrelationPairStore(db: db) }

    @Test("Save and load a computed correlation result")
    func saveAndLoadComputed() throws {
        try store.save(metricA: "sleep_hours", metricB: "readiness_score",
                        result: .computed(r: 0.42, sampleSize: 21))

        let loaded = try store.pair(metricA: "sleep_hours", metricB: "readiness_score")
        #expect(loaded?.rValue == 0.42)
        #expect(loaded?.sampleSize == 21)
        #expect(loaded?.confidenceLevel == "confident")
    }

    @Test("Insufficient-data results are stored without a fabricated r-value")
    func saveAndLoadInsufficient() throws {
        try store.save(metricA: "caffeine_mg", metricB: "sleep_onset",
                        result: .insufficientData(sampleSize: 4, minimumRequired: 14))

        let loaded = try store.pair(metricA: "caffeine_mg", metricB: "sleep_onset")
        #expect(loaded?.rValue == nil)
        #expect(loaded?.sampleSize == 4)
        #expect(loaded?.confidenceLevel == "insufficient")
    }
}

@Suite("AchievementRecordStore Tests")
struct AchievementRecordStoreTests {
    let db = try! TestDatabase()
    var store: AchievementRecordStore { AchievementRecordStore(db: db) }

    @Test("Recompute writes one row per badge, marking which were earned")
    func recomputeWritesAllBadges() throws {
        try store.recompute(logicalDay: "2026-09-19", earned: [.stepsTargetMet, .fastedDay])

        let met = try store.metBadges(for: "2026-09-19")
        #expect(met == [.stepsTargetMet, .fastedDay])

        let total = try db.query("SELECT COUNT(*) AS n FROM achievement_record WHERE logicalDay = '2026-09-19';").first?.int("n")
        #expect(total == Int64(AchievementBadge.allCases.count), "every badge gets a row, met or not, so an edit can flip met_threshold in place")
    }

    @Test("Recomputing the same day replaces the prior result rather than accumulating rows")
    func recomputeReplacesPriorResult() throws {
        try store.recompute(logicalDay: "2026-09-19", earned: [.perfectLog])
        try store.recompute(logicalDay: "2026-09-19", earned: [.stepsTargetMet])

        #expect(try store.metBadges(for: "2026-09-19") == [.stepsTargetMet])
        let total = try db.query("SELECT COUNT(*) AS n FROM achievement_record WHERE logicalDay = '2026-09-19';").first?.int("n")
        #expect(total == Int64(AchievementBadge.allCases.count))
    }
}
