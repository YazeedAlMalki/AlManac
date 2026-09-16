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
            source: "manual", conditions: "fasted")

        let id = try store.log(draft, logicalDay: "2026-09-16")
        let measurement = try store.measurement(id: id)

        #expect(measurement?.metric == "weight")
        #expect(measurement?.value == 82.4)
        #expect(measurement?.unit == "kg")
        #expect(measurement?.source == "manual")
        #expect(measurement?.conditions == "fasted")
        #expect(measurement?.logicalDay == "2026-09-16")
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
}
