import Testing
import Foundation
@testable import AlmanacCore

@Suite("BodyCompositionMeasurementStore Tests")
struct BodyCompositionMeasurementStoreTests {
    let db = try! TestDatabase()
    var store: BodyCompositionMeasurementStore { BodyCompositionMeasurementStore(db: db) }

    @Test("Log a manual weight entry and read it back")
    func logWeight() throws {
        let draft = BodyCompositionMeasurementDraft(
            metric: "weight", value: 82.4, unit: "kg",
            timestamp: Date(timeIntervalSince1970: 1_000_000),
            source: "manual", conditions: "fasted",
            timezoneOffset: 180, timezoneIdentifier: "Asia/Riyadh")

        let id = try store.log(draft, logicalDay: "2026-09-16")
        let measurement = try store.measurement(id: id)

        #expect(measurement?.metric == "weight")
        #expect(measurement?.value == 82.4)
        #expect(measurement?.unit == "kg")
        #expect(measurement?.source == "manual")
        #expect(measurement?.conditions == "fasted")
        #expect(measurement?.logicalDay == "2026-09-16")
        #expect(measurement?.timezoneOffset == 180)
        #expect(measurement?.timezoneIdentifier == "Asia/Riyadh")
    }

    @Test("Conditions defaults to unknown when not given")
    func defaultsToUnknownConditions() throws {
        let draft = BodyCompositionMeasurementDraft(
            metric: "body_fat_pct", value: 18.0, unit: "pct",
            timestamp: Date(timeIntervalSince1970: 1_000_000), source: "manual")

        let id = try store.log(draft, logicalDay: "2026-09-16")
        let measurement = try store.measurement(id: id)

        #expect(measurement?.conditions == "unknown")
    }

    @Test("Latest value for a metric returns the most recent entry, not the most recently inserted")
    func latestValueByTimestamp() throws {
        let older = BodyCompositionMeasurementDraft(
            metric: "weight", value: 83.0, unit: "kg",
            timestamp: Date(timeIntervalSince1970: 2_000_000), source: "manual")
        let newer = BodyCompositionMeasurementDraft(
            metric: "weight", value: 82.4, unit: "kg",
            timestamp: Date(timeIntervalSince1970: 3_000_000), source: "apple_health")

        // Insert the newer-timestamped one first to prove ordering is by
        // timestamp, not insertion order.
        _ = try store.log(newer, logicalDay: "2026-09-16")
        _ = try store.log(older, logicalDay: "2026-09-15")

        let latest = try store.latestValue(for: "weight")

        #expect(latest?.value == 82.4)
        #expect(latest?.source == "apple_health")
    }

    @Test("History for a metric is ordered by timestamp within a logical-day range")
    func historyForMetric() throws {
        _ = try store.log(BodyCompositionMeasurementDraft(
            metric: "weight", value: 84.0, unit: "kg",
            timestamp: Date(timeIntervalSince1970: 1_000_000), source: "manual"), logicalDay: "2026-09-01")
        _ = try store.log(BodyCompositionMeasurementDraft(
            metric: "weight", value: 83.0, unit: "kg",
            timestamp: Date(timeIntervalSince1970: 2_000_000), source: "manual"), logicalDay: "2026-09-08")
        _ = try store.log(BodyCompositionMeasurementDraft(
            metric: "weight", value: 82.0, unit: "kg",
            timestamp: Date(timeIntervalSince1970: 3_000_000), source: "manual"), logicalDay: "2026-09-20")

        let history = try store.records(metric: "weight", from: "2026-09-01", to: "2026-09-09")

        #expect(history.count == 2)
        #expect(history.map { $0.value } == [84.0, 83.0])
    }

    // MARK: - Correction and deletion (Slice 7, 2026-10-15)

    private func manualWeight(_ value: Double, day: String = "2026-10-14",
                              at seconds: TimeInterval = 5_000_000) throws -> Int64 {
        try store.log(BodyCompositionMeasurementDraft(
            metric: "weight", value: value, unit: "kg",
            timestamp: Date(timeIntervalSince1970: seconds), source: "manual"), logicalDay: day)
    }

    @Test("A manual reading can be corrected: value and conditions change, metric and time do not")
    func correctManual() throws {
        let id = try manualWeight(82.4)
        try store.correct(id: id, value: 81.9, conditions: "fasted")
        let row = try #require(try store.measurement(id: id))
        #expect(row.value == 81.9)
        #expect(row.conditions == "fasted")
        #expect(row.metric == "weight")
        #expect(row.timestamp == Date(timeIntervalSince1970: 5_000_000))
    }

    @Test("An imported reading cannot be corrected or deleted here; Health owns it")
    func importedIsReadOnly() throws {
        let id = try store.log(BodyCompositionMeasurementDraft(
            metric: "weight", value: 80, unit: "kg", timestamp: Date(timeIntervalSince1970: 5_000_000),
            source: "apple_health", healthKitUUID: "hk-1"), logicalDay: "2026-10-14")
        #expect(throws: BodyCompositionMeasurementStoreError.notManual) {
            try store.correct(id: id, value: 79, conditions: "unknown")
        }
        #expect(throws: BodyCompositionMeasurementStoreError.notManual) {
            try store.delete(id: id)
        }
        #expect(try store.measurement(id: id)?.value == 80)
    }

    @Test("A correction must be a finite positive number")
    func correctionValidated() throws {
        let id = try manualWeight(82.4)
        #expect(throws: BodyCompositionMeasurementStoreError.invalidValue) {
            try store.correct(id: id, value: 0, conditions: "unknown")
        }
        #expect(throws: BodyCompositionMeasurementStoreError.invalidValue) {
            try store.correct(id: id, value: .nan, conditions: "unknown")
        }
    }

    @Test("Deleting a manual reading removes it from every read, including latest")
    func deleteManual() throws {
        let older = try manualWeight(83.0, day: "2026-10-13", at: 4_000_000)
        let newer = try manualWeight(82.0, day: "2026-10-14", at: 5_000_000)
        try store.delete(id: newer)
        #expect(try store.latestValue(for: "weight")?.id == older)
        #expect(try store.records(metric: "weight", from: "2026-10-01", to: "2026-10-31").map(\.id) == [older])
        #expect(try store.latestPerMetric()["weight"]?.id == older)
    }

    @Test("A deleted reading that was waiting to go to Health is no longer queued")
    func deleteDequeues() throws {
        let id = try manualWeight(82.0)
        try store.delete(id: id)
        let pending = try db.query("""
        SELECT COUNT(*) AS n FROM body_composition_measurement
        WHERE pendingHealthKitWrite = 1 AND deletedAt IS NULL;
        """).first?.int("n")
        #expect(pending == 0)
    }

    @Test("History for one metric is oldest first, for a chart")
    func historyOldestFirst() throws {
        let a = try manualWeight(83.0, day: "2026-10-12", at: 3_000_000)
        let b = try manualWeight(82.0, day: "2026-10-14", at: 5_000_000)
        let c = try manualWeight(82.5, day: "2026-10-13", at: 4_000_000)
        #expect(try store.records(metric: "weight", from: "2026-10-01", to: "2026-10-31").map(\.id) == [a, c, b])
    }
}
