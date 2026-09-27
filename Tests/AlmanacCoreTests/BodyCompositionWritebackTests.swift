import Testing
import Foundation
@testable import AlmanacCore

/// `BodyCompositionWriteback` — the outbound half of the three body-composition
/// metrics that have a HealthKit type.
///
/// The inbound bridge had tests and the outbound half had a column, a store and
/// a `HealthKitProvider` guard that refused every body domain, so the flag the
/// schema was built around (`pendingHealthKitWrite`) was written by nothing and
/// read by nothing. What is worth pinning here is the queue's *edges*: which
/// rows are eligible, what happens to a row HealthKit cannot hold, and that the
/// export does not come back in as a second row.
@Suite("BodyCompositionWriteback")
struct BodyCompositionWritebackTests {
    let db = try! TestDatabase()

    private var store: BodyCompositionMeasurementStore {
        BodyCompositionMeasurementStore(db: db)
    }
    private var bridge: BodyCompositionMeasurementHealthBridge {
        BodyCompositionMeasurementHealthBridge(db: db)
    }

    private static let at = Date(timeIntervalSince1970: 1_789_000_000)

    private func log(_ metric: String, _ value: Double, unit: String = "kg",
                     source: String = "manual") throws -> Int64 {
        try store.log(.init(metric: metric, value: value, unit: unit,
                            timestamp: Self.at, source: source, conditions: "fasted"),
                      logicalDay: "2026-09-16")
    }

    private func isPending(_ id: Int64) throws -> Bool {
        try db.query("SELECT pendingHealthKitWrite FROM body_composition_measurement WHERE id = ?;",
                     [.integer(id)]).first?.int("pendingHealthKitWrite") == 1
    }

    // MARK: The two directions agree on the metric set

    @Test("The outbound table covers exactly the metrics the inbound bridge maps")
    func bothDirectionsCoverTheSameMetrics() {
        // The bridge's map is `private`, so it is read back the only honest way:
        // through the bridge itself. Three metrics with a HealthKit type, and no
        // fifth — skeletal muscle and visceral rating have none.
        let inbound = ["weight", "body_fat_pct", "lean_mass_kg"]
        #expect(Set(BodyCompositionMeasurementHealthBridge.outbound.keys) == Set(inbound))
        for metric in inbound {
            #expect(BodyCompositionMeasurementHealthBridge.healthKitDomain(forMetric: metric) != nil)
        }
        #expect(BodyCompositionMeasurementHealthBridge.healthKitDomain(forMetric: "skeletal_muscle_kg") == nil)
        #expect(BodyCompositionMeasurementHealthBridge.healthKitDomain(forMetric: "visceral_rating") == nil)
    }

    // MARK: What gets queued

    @Test("A manual weight is flagged for write-back, an imported one is not")
    func onlyManualRowsAreQueued() throws {
        let manual = try log("weight", 82.4)
        let imported = try log("weight", 81.0, source: "smart_scale")
        #expect(try isPending(manual))
        #expect(try !isPending(imported), "an imported row is already somewhere else")
    }

    @Test("A metric HealthKit cannot hold is never queued")
    func unpushableMetricIsNeverQueued() async throws {
        // No `skeletal_muscle_kg` type exists, so flagging this row would leave
        // it in the queue forever, failing every drain.
        let muscle = try log("skeletal_muscle_kg", 32.0)
        let visceral = try log("visceral_rating", 5.0, unit: "rating")
        #expect(try !isPending(muscle))
        #expect(try !isPending(visceral))

        let writer = FakeHealthWriter()
        #expect(try await BodyCompositionWriteback(db: db, writer: writer).drainOnce() == 0)
        #expect(writer.written.isEmpty)
    }

    // MARK: The drain

    @Test("All three metrics reach HealthKit, body fat under the label HealthKit accepts")
    func drainsEveryPushableMetric() async throws {
        let fat = try log("body_fat_pct", 18.0, unit: "pct")
        let lean = try log("lean_mass_kg", 65.0)
        let mass = try log("weight", 82.4)

        let writer = FakeHealthWriter()
        #expect(try await BodyCompositionWriteback(db: db, writer: writer).drainOnce() == 3)

        let byDomain = Dictionary(uniqueKeysWithValues: writer.written.map { ($0.domain, $0) })
        #expect(byDomain[.bodyMass]?.value == 82.4)
        #expect(byDomain[.bodyMass]?.unit == "kg")
        #expect(byDomain[.leanBodyMass]?.value == 65.0)
        // Stored as `pct`, sent as `%`: `HealthKitProvider.write` compares the
        // unit against its own table and refuses anything else.
        #expect(byDomain[.bodyFatPercentage]?.value == 18.0)
        #expect(byDomain[.bodyFatPercentage]?.unit == "%")
        #expect(writer.written.allSatisfy { $0.start == $0.end })

        // Each row keeps the identifier HealthKit gave its own sample — they
        // are distinct samples, so the identifiers must be too.
        let stored = try [fat, lean, mass].map { try store.measurement(id: $0)?.healthKitUUID }
        #expect(stored.allSatisfy { $0?.isEmpty == false })
        #expect(Set(stored.compactMap { $0 }).count == 3)

        for id in [fat, lean, mass] {
            #expect(try !isPending(id), "a pushed row is no longer queued")
        }
    }

    @Test("A second drain pushes nothing, and the HealthKit identifier is kept")
    func drainIsIdempotent() async throws {
        let id = try log("weight", 82.4)
        let writer = FakeHealthWriter()
        writer.nextID = { "exported-uuid" }

        #expect(try await BodyCompositionWriteback(db: db, writer: writer).drainOnce() == 1)
        #expect(try await BodyCompositionWriteback(db: db, writer: writer).drainOnce() == 0)
        #expect(writer.written.count == 1)
        #expect(try store.measurement(id: id)?.healthKitUUID == "exported-uuid")
    }

    @Test("A retry is the same write, not a second one")
    func retryReusesTheSyncIdentifier() async throws {
        _ = try log("weight", 82.4)
        let writer = FakeHealthWriter()
        writer.nextID = { "exported-uuid" }
        _ = try await BodyCompositionWriteback(db: db, writer: writer).drainOnce()

        // Re-flagged, as if the stamp were lost mid-flight.
        try db.run("UPDATE body_composition_measurement SET pendingHealthKitWrite = 1;")
        _ = try await BodyCompositionWriteback(db: db, writer: writer).drainOnce()

        #expect(writer.written.count == 2)
        #expect(writer.written[0].externalID == writer.written[1].externalID,
                "HealthKit ignores an equal-version retry only if the identifier matches")
    }

    @Test("A row in a unit its metric is not stored in is left queued, not mislabelled")
    func foreignUnitIsNotRelabelled() async throws {
        // A `weight` in pounds sent as HealthKit's `kg` would be a wrong number
        // under a right label, which is worse than not being sent.
        let pounds = try log("weight", 180.0, unit: "lb")
        let writer = FakeHealthWriter()
        #expect(try await BodyCompositionWriteback(db: db, writer: writer).drainOnce() == 0)
        #expect(writer.written.isEmpty)
        #expect(try isPending(pounds))
    }

    @Test("One failing row neither blocks the rows after it nor hides itself")
    func failureIsIsolatedAndStillReported() async throws {
        let first = try log("weight", 82.4)
        _ = try log("body_fat_pct", 18.0, unit: "pct")

        // Fails only the first write it is handed, so the row after it succeeds.
        let writer = FlakyHealthWriter(failingCall: 1)

        await #expect(throws: FlakyHealthWriter.Refused.self) {
            try await BodyCompositionWriteback(db: db, writer: writer).drainOnce()
        }
        #expect(writer.written.count == 1, "the second row was still attempted")
        #expect(writer.written.first?.domain == .bodyFatPercentage)
        #expect(try isPending(first), "the failed row stays queued, which is the retry")

        // The retry drains exactly the one that failed.
        #expect(try await BodyCompositionWriteback(db: db, writer: writer).drainOnce() == 1)
        #expect(try !isPending(first))
    }

    @Test("A soft-deleted row is not exported")
    func softDeletedRowsAreSkipped() async throws {
        let id = try log("weight", 82.4)
        try db.run("UPDATE body_composition_measurement SET deletedAt = ? WHERE id = ?;",
                   [.text("2026-09-17T00:00:00Z"), .integer(id)])

        let writer = FakeHealthWriter()
        #expect(try await BodyCompositionWriteback(db: db, writer: writer).drainOnce() == 0)
        #expect(writer.written.isEmpty)
    }

    @Test("A non-finite or non-positive value is not exported")
    func impossibleValuesAreNotExported() async throws {
        _ = try log("weight", 0.0)
        _ = try log("weight", -3.0)
        let writer = FakeHealthWriter()
        #expect(try await BodyCompositionWriteback(db: db, writer: writer).drainOnce() == 0)
        #expect(writer.written.isEmpty)
    }

    // MARK: The echo

    @Test("HealthKit echoing this app's own export does not become a second row")
    func ownExportIsNotReimported() async throws {
        let id = try log("weight", 82.4)
        let writer = FakeHealthWriter()
        writer.nextID = { "exported-uuid" }
        #expect(try await BodyCompositionWriteback(db: db, writer: writer).drainOnce() == 1)

        // What the sync layer would hand the bridge if it did not already drop
        // own exports by bundle identifier.
        let echo = HealthSample(externalID: "exported-uuid", domain: .bodyMass,
                                start: Self.at, end: Self.at, value: 82.4, unit: "kg")
        let counts = try bridge.apply(.init(added: [echo], deletedExternalIDs: [], nextAnchor: nil), in: db)

        #expect(counts.inserted == 0 && counts.updated == 0)
        #expect(try db.query("SELECT id FROM body_composition_measurement;").count == 1)
        #expect(try store.measurement(id: id)?.source == "manual",
                "the reading is still the person's own entry, not an imported copy")
    }

    @Test("A genuinely foreign sample with that identifier is not silently dropped")
    func foreignUUIDStillImports() throws {
        _ = try log("weight", 82.4)
        let sample = HealthSample(externalID: "someone-elses-uuid", domain: .bodyMass,
                                  start: Self.at, end: Self.at, value: 70.0, unit: "kg")
        let counts = try bridge.apply(.init(added: [sample], deletedExternalIDs: [], nextAnchor: nil), in: db)
        #expect(counts.inserted == 1)
    }
}

/// A writer that fails on one chosen call, so a single row can be made to fail
/// while the rows around it succeed — `FakeHealthWriter.shouldFail` is
/// all-or-nothing and cannot express that.
private final class FlakyHealthWriter: HealthWriter, @unchecked Sendable {
    struct Refused: Error, Sendable {}
    private let failingCall: Int
    private let lock = NSLock()
    private var _calls = 0
    private var _written: [HealthSample] = []

    var written: [HealthSample] { lock.lock(); defer { lock.unlock() }; return _written }

    /// `failingCall` is 1-based: 1 refuses the first write and nothing after.
    init(failingCall: Int) { self.failingCall = failingCall }

    func write(_ sample: HealthSample) async throws -> String {
        lock.lock()
        _calls += 1
        let call = _calls
        let refuse = call == failingCall
        if !refuse { _written.append(sample) }
        lock.unlock()
        if refuse { throw Refused() }
        return "hk-\(call)"
    }
}
