import XCTest
@testable import AlmanacCore

/// Fails on write, so the transaction rolls back after the change set was read.
private struct ThrowingWriter: HealthSampleWriting {
    struct Boom: Error {}
    func apply(_ changeSet: HealthChangeSet, in db: Database) throws -> HealthApplyCounts {
        throw Boom()
    }
}

final class HealthSyncTests: XCTestCase {

    private func fixture() throws -> (Database, HealthSampleStore, FakeHealthProvider, FixedClock) {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let clock = FixedClock(Date(timeIntervalSince1970: 1_772_000_000))
        let store = HealthSampleStore(db: db, healthDomain: .bodyMass, clock: clock)
        let provider = FakeHealthProvider()
        return (db, store, provider, clock)
    }

    private func sample(_ id: String, _ kg: Double, _ epoch: TimeInterval) -> HealthSample {
        HealthSample(externalID: id, domain: .bodyMass,
                     start: Date(timeIntervalSince1970: epoch),
                     end: Date(timeIntervalSince1970: epoch),
                     value: kg, unit: "kg", sourceName: "Withings")
    }

    func testSamplesArePersistedAndCursorAdvances() async throws {
        let (db, store, provider, clock) = try fixture()
        try await provider.requestAuthorisation(for: [.bodyMass])
        provider.enqueue(HealthChangeSet(
            added: [sample("s1", 81.2, 1_772_000_100), sample("s2", 80.9, 1_772_086_500)],
            deletedExternalIDs: [], nextAnchor: [1, 2, 3]), for: .bodyMass)

        let service = HealthSyncService(db: db, provider: provider, writer: store,
                                        healthDomain: .bodyMass, clock: clock)
        XCTAssertNil(try service.currentAnchor())
        let outcome = try await service.syncOnce()
        XCTAssertEqual(outcome.counts.inserted, 2)
        XCTAssertEqual(try store.liveSampleCount(), 2)
        XCTAssertEqual(try service.currentAnchor(), [1, 2, 3])
    }

    func testDeletionIsSoftAndScopedToItsSource() async throws {
        let (db, store, provider, clock) = try fixture()
        try await provider.requestAuthorisation(for: [.bodyMass])
        provider.enqueue(HealthChangeSet(added: [sample("s1", 81.2, 1_772_000_100)],
                                         deletedExternalIDs: [], nextAnchor: [1]), for: .bodyMass)
        provider.enqueue(HealthChangeSet(added: [], deletedExternalIDs: ["s1"], nextAnchor: [2]),
                         for: .bodyMass)
        let service = HealthSyncService(db: db, provider: provider, writer: store,
                                        healthDomain: .bodyMass, clock: clock)
        try await service.syncOnce()

        // A different source using the same external id must be untouched.
        let other = HealthSampleStore(db: db, healthDomain: .bodyMass,
                                      sourceSystem: "manual", clock: clock)
        _ = try other.apply(HealthChangeSet(added: [sample("s1", 79.0, 1_772_000_200)],
                                            deletedExternalIDs: [], nextAnchor: nil), in: db)

        try await service.syncOnce()
        XCTAssertTrue(try store.isDeleted(externalID: "s1"))
        XCTAssertFalse(try other.isDeleted(externalID: "s1"),
                       "deletion must not cross source boundaries")
        XCTAssertEqual(try store.liveSampleCount(), 0)
        XCTAssertEqual(try other.liveSampleCount(), 1)
        // Soft: the row survives so history is not rewritten.
        XCTAssertEqual(Int(try db.query("SELECT COUNT(*) AS n FROM health_sample;")
                            .first?.int("n") ?? 0), 2)
    }

    // The demonstration that matters: a write failure must not advance the cursor.
    func testFailedSyncLeavesTheCursorUnchanged() async throws {
        let (db, store, provider, clock) = try fixture()
        try await provider.requestAuthorisation(for: [.bodyMass])
        provider.enqueue(HealthChangeSet(added: [sample("s1", 81.2, 1_772_000_100)],
                                         deletedExternalIDs: [], nextAnchor: [7]), for: .bodyMass)
        let good = HealthSyncService(db: db, provider: provider, writer: store,
                                     healthDomain: .bodyMass, clock: clock)
        try await good.syncOnce()
        XCTAssertEqual(try good.currentAnchor(), [7])

        provider.enqueue(HealthChangeSet(added: [sample("s2", 80.4, 1_772_086_500)],
                                         deletedExternalIDs: [], nextAnchor: [9]), for: .bodyMass)
        let failing = HealthSyncService(db: db, provider: provider, writer: ThrowingWriter(),
                                        healthDomain: .bodyMass, clock: clock)
        do {
            _ = try await failing.syncOnce()
            XCTFail("expected the write to throw")
        } catch is ThrowingWriter.Boom {
            // expected
        }
        XCTAssertEqual(try failing.currentAnchor(), [7],
                       "the cursor must not advance past rows that were never persisted")
        XCTAssertEqual(try store.liveSampleCount(), 1, "the failed batch left nothing behind")

        let anchor = try XCTUnwrap(SyncAnchorStore(db: db, clock: clock).load("bodyMass"))
        XCTAssertNotNil(anchor.lastError, "the failure is recorded")
        XCTAssertEqual(anchor.token, [7], "recording a failure never clears the last good anchor")
    }

    // Range bounds and stored instants must be compared on one axis. Stored
    // samples are UTC `...Z`; a caller asking in +03:00 was previously compared
    // lexically, which is wrong by exactly the offset.
    func testSampleQueryNormalisesOffsetsBeforeComparing() async throws {
        let (db, store, provider, clock) = try fixture()
        try await provider.requestAuthorisation(for: [.bodyMass])
        // 2026-02-25T06:00:00Z
        let instant = Date(timeIntervalSince1970: 1_771_999_200)
        provider.enqueue(HealthChangeSet(added: [sample("w1", 81.2, instant.timeIntervalSince1970)],
                                         deletedExternalIDs: [], nextAnchor: [1]), for: .bodyMass)
        try await HealthSyncService(db: db, provider: provider, writer: store,
                                    healthDomain: .bodyMass, clock: clock).syncOnce()

        let stored = try XCTUnwrap(db.query("SELECT start_at FROM health_sample;")
            .first?.string("start_at"))
        XCTAssertEqual(stored, "2026-02-25T06:00:00Z")

        // 08:00–10:00 in +03:00 is 05:00–07:00 UTC, so the sample is inside it.
        let entries = try store.entries(from: "2026-02-25T08:00:00+03:00",
                                        to: "2026-02-25T10:00:00+03:00")
        XCTAssertEqual(entries.count, 1,
                       "a +03:00 window must be compared in UTC, not lexically")
        XCTAssertEqual(entries[0].rangeFit, .definite)

        // And a window that genuinely excludes it still excludes it.
        XCTAssertTrue(try store.entries(from: "2026-02-25T10:00:00+03:00",
                                        to: "2026-02-25T12:00:00+03:00").isEmpty)
        // The same window expressed in UTC gives the same answer.
        XCTAssertEqual(try store.entries(from: "2026-02-25T05:00:00Z",
                                         to: "2026-02-25T07:00:00Z").count, 1)
    }

    func testResyncAfterFailureReplaysTheSameRange() async throws {
        let (db, store, provider, clock) = try fixture()
        try await provider.requestAuthorisation(for: [.bodyMass])
        provider.enqueue(HealthChangeSet(added: [sample("s1", 81.2, 1_772_000_100)],
                                         deletedExternalIDs: [], nextAnchor: [7]), for: .bodyMass)
        let failing = HealthSyncService(db: db, provider: provider, writer: ThrowingWriter(),
                                        healthDomain: .bodyMass, clock: clock)
        _ = try? await failing.syncOnce()
        XCTAssertNil(try failing.currentAnchor())

        provider.enqueue(HealthChangeSet(added: [sample("s1", 81.2, 1_772_000_100)],
                                         deletedExternalIDs: [], nextAnchor: [7]), for: .bodyMass)
        let service = HealthSyncService(db: db, provider: provider, writer: store,
                                        healthDomain: .bodyMass, clock: clock)
        try await service.syncOnce()
        XCTAssertEqual(try store.liveSampleCount(), 1)
        XCTAssertEqual(try service.currentAnchor(), [7])
    }
}
