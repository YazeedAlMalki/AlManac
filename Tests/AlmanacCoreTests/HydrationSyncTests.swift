import XCTest
@testable import AlmanacCore

/// Inbound (HealthKit → Almanac) and outbound (Almanac → HealthKit) hydration
/// sync. Inbound reuses `HealthSyncService` unmodified — `HydrationStore`
/// just needs to conform to `HealthSampleWriting`, exercised here the same
/// way `HealthSyncTests` exercises `.bodyMass`. Outbound is `HydrationWriteback`,
/// which has no counterpart to mirror but follows the same "never mark
/// success until it happened" discipline.
final class HydrationSyncTests: XCTestCase {

    private func fixture() throws -> (Database, HydrationStore, FakeHealthProvider, FixedClock) {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let clock = FixedClock(Date(timeIntervalSince1970: 1_772_000_000))
        let store = HydrationStore(db: db, clock: clock)
        return (db, store, FakeHealthProvider(), clock)
    }

    private func sample(_ id: String, _ ml: Double, _ epoch: TimeInterval) -> HealthSample {
        HealthSample(externalID: id, domain: .water,
                     start: Date(timeIntervalSince1970: epoch),
                     end: Date(timeIntervalSince1970: epoch),
                     value: ml, unit: "ml", sourceName: "Apple Watch")
    }

    // MARK: - Inbound

    func testInboundSamplesArePersistedAndAnchorAdvances() async throws {
        let (db, store, provider, clock) = try fixture()
        try await provider.requestAuthorisation(for: [.water])
        provider.enqueue(HealthChangeSet(
            added: [sample("w1", 250, 1_772_000_100), sample("w2", 500, 1_772_010_000)],
            deletedExternalIDs: [], nextAnchor: [1, 2, 3]), for: .water)

        let service = HealthSyncService(db: db, provider: provider, writer: store,
                                        healthDomain: .water, clock: clock)
        XCTAssertNil(try service.currentAnchor())
        let outcome = try await service.syncOnce()
        XCTAssertEqual(outcome.counts.inserted, 2)
        XCTAssertEqual(try service.currentAnchor(), [1, 2, 3])

        let logs = try store.logs(from: "2026-02-25", to: "2026-02-26")
        XCTAssertEqual(logs.count, 2)
        XCTAssertTrue(logs.allSatisfy { $0.sourceSystem == "healthkit" && $0.healthKitSynced == false })
    }

    func testFailedInboundSyncLeavesTheAnchorUnchanged() async throws {
        struct Boom: Error {}
        struct ThrowingWriter: HealthSampleWriting {
            func apply(_ changeSet: HealthChangeSet, in db: Database) throws -> HealthApplyCounts { throw Boom() }
        }
        let (db, store, provider, clock) = try fixture()
        try await provider.requestAuthorisation(for: [.water])
        provider.enqueue(HealthChangeSet(added: [sample("w1", 250, 1_772_000_100)],
                                         deletedExternalIDs: [], nextAnchor: [7]), for: .water)
        let good = HealthSyncService(db: db, provider: provider, writer: store,
                                     healthDomain: .water, clock: clock)
        try await good.syncOnce()
        XCTAssertEqual(try good.currentAnchor(), [7])

        provider.enqueue(HealthChangeSet(added: [sample("w2", 300, 1_772_010_000)],
                                         deletedExternalIDs: [], nextAnchor: [9]), for: .water)
        let failing = HealthSyncService(db: db, provider: provider, writer: ThrowingWriter(),
                                        healthDomain: .water, clock: clock)
        do {
            _ = try await failing.syncOnce()
            XCTFail("expected the write to throw")
        } catch is Boom {
            // expected
        }
        XCTAssertEqual(try failing.currentAnchor(), [7],
                       "the cursor must not advance past a row that was never persisted")
        XCTAssertEqual(try store.logs(from: "2026-02-25", to: "2026-02-26").count, 1)
    }

    func testInboundDeletionIsSoftAndDoesNotResurrectOnResync() async throws {
        let (db, store, provider, clock) = try fixture()
        try await provider.requestAuthorisation(for: [.water])
        provider.enqueue(HealthChangeSet(added: [sample("w1", 250, 1_772_000_100)],
                                         deletedExternalIDs: [], nextAnchor: [1]), for: .water)
        let service = HealthSyncService(db: db, provider: provider, writer: store,
                                        healthDomain: .water, clock: clock)
        try await service.syncOnce()
        let id = try XCTUnwrap(store.logs(from: "2026-02-25", to: "2026-02-26").first?.id)

        // The user deletes it in-app.
        try store.delete(id: id)
        XCTAssertNil(try store.entry(id: id))

        // A resync that re-reads the same sample must not bring it back.
        provider.enqueue(HealthChangeSet(added: [sample("w1", 250, 1_772_000_100)],
                                         deletedExternalIDs: [], nextAnchor: [2]), for: .water)
        try await service.syncOnce()
        XCTAssertNil(try store.entry(id: id),
                     "a soft-deleted row must not be resurrected by re-reading the same anchor range")
    }

    // MARK: - Outbound

    func testWritebackPushesUnsyncedManualEntriesOnly() async throws {
        let (db, store, _, clock) = try fixture()
        let manual = try store.log(HydrationLogDraft(amount: Milliliters(250),
                                                      loggedAt: Date(timeIntervalSince1970: 1_772_000_100)))
        // A HealthKit-originated row must never be pushed back — nothing to push.
        let provider = FakeHealthProvider()
        try await provider.requestAuthorisation(for: [.water])
        provider.enqueue(HealthChangeSet(added: [sample("w1", 500, 1_772_010_000)],
                                         deletedExternalIDs: [], nextAnchor: [1]), for: .water)
        try await HealthSyncService(db: db, provider: provider, writer: store,
                                    healthDomain: .water, clock: clock).syncOnce()

        let writer = FakeHealthWriter()
        let pushed = try await HydrationWriteback(db: db, writer: writer, clock: clock).drainOnce()

        XCTAssertEqual(pushed, 1)
        XCTAssertEqual(writer.written.map(\.externalID), [manual])
        let entry = try XCTUnwrap(store.entry(id: manual))
        XCTAssertTrue(entry.healthKitSynced)
    }

    func testAFailedPushLeavesTheRowPendingAndItIsRetriedNext() async throws {
        let (db, store, _, clock) = try fixture()
        let id = try store.log(HydrationLogDraft(amount: Milliliters(250),
                                                  loggedAt: Date(timeIntervalSince1970: 1_772_000_100)))

        let failing = FakeHealthWriter()
        failing.shouldFail = true
        let firstAttempt = try await HydrationWriteback(db: db, writer: failing, clock: clock).drainOnce()
        XCTAssertEqual(firstAttempt, 0)
        XCTAssertFalse(try XCTUnwrap(store.entry(id: id)).healthKitSynced,
                       "a failed write must not stamp healthkit_synced_at")

        let succeeding = FakeHealthWriter()
        let secondAttempt = try await HydrationWriteback(db: db, writer: succeeding, clock: clock).drainOnce()
        XCTAssertEqual(secondAttempt, 1, "a previously-failed row must be retried with no separate bookkeeping")
        XCTAssertTrue(try XCTUnwrap(store.entry(id: id)).healthKitSynced)
    }
}
