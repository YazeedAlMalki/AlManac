import XCTest
@testable import AlmanacCore

/// HealthKit de-duplication after restore (Slice 12 handoff §6.18).
///
/// The one provable overlap shape in this schema: a manual hydration entry
/// pushed to HealthKit carries `healthkit_external_id`, and a later inbound
/// sync can re-read that same sample as a `healthkit`-sourced row keyed on
/// the same UUID in `external_id`. That is the same drink twice. The manual
/// row wins — it is user-authored and can carry a note/drink attachment.
final class RestoreHealthReconcileTests: XCTestCase {

    private func fixture() throws -> (Database, HydrationStore, FixedClock) {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let clock = FixedClock(Date(timeIntervalSince1970: 1_772_000_000)) // 2026-02-25T06:13:20Z
        return (db, HydrationStore(db: db, clock: clock), clock)
    }

    /// A manual writeback + its HealthKit echo: the manual row logged in-app,
    /// stamped `healthkit_external_id` exactly as `HydrationWriteback.drainOnce`
    /// does after a successful push, then the inbound sync reading that same
    /// sample back (exactly as `apply` does).
    private func manualWritebackAndEcho(
        in db: Database, store: HydrationStore, clock: FixedClock, externalID: String
    ) throws -> String {
        let manualID = try store.log(HydrationLogDraft(amount: Milliliters(250), loggedAt: Date(timeIntervalSince1970: 1_772_000_100)))
        try db.run("""
        UPDATE hydration_log SET healthkit_synced_at = ?, healthkit_external_id = ?
        WHERE id = ?;
        """, [.text(clock.nowText()), .text(externalID), .text(manualID)])
        _ = try store.apply(HealthChangeSet(
            added: [HealthSample(externalID: externalID, domain: .water,
                                 start: Date(timeIntervalSince1970: 1_772_000_100),
                                 end: Date(timeIntervalSince1970: 1_772_000_100),
                                 value: 250, unit: "ml")],
            deletedExternalIDs: [], nextAnchor: nil
        ), in: db)
        return manualID
    }

    private func row(_ db: Database, id: String) throws -> Row? {
        try db.query("SELECT id, source_system, deleted_at FROM hydration_log WHERE id = ?;", [.text(id)]).first
    }

    // MARK: - Direct reconcile

    func testReconcileCollapsesEchoOfLiveManualWriteback() throws {
        let (db, store, clock) = try fixture()
        let manualID = try manualWritebackAndEcho(in: db, store: store, clock: clock, externalID: "uuid-healthkit-sample-1")

        let dropped = try store.reconcileAfterRestore()
        XCTAssertEqual(dropped, 1, "exactly the one duplicated HealthKit row must be dropped")

        let manual = try XCTUnwrap(row(db, id: manualID))
        XCTAssertEqual(manual.string("source_system"), "manual")
        XCTAssertNil(manual.string("deleted_at"), "the manual row is the keeper and must survive untouched")

        let echo = try XCTUnwrap(db.query(
            "SELECT id, source_system, deleted_at FROM hydration_log WHERE source_system = 'healthkit' AND external_id = ?;",
            [.text("uuid-healthkit-sample-1")]
        ).first)
        XCTAssertNotNil(echo.string("deleted_at"), "the HealthKit echo must be soft-deleted, sticky against re-sync")
    }

    func testReconcileLeavesUnrelatedRowsAlone() throws {
        let (db, store, clock) = try fixture()
        _ = try manualWritebackAndEcho(in: db, store: store, clock: clock, externalID: "uuid-echo-1")
        // A HealthKit row with no matching manual writeback — a real HealthKit
        // entry the user logged from Health directly. There is no overlap to
        // collapse and it must survive.
        let unrelated = try store.log(HydrationLogDraft(amount: Milliliters(400), loggedAt: Date(timeIntervalSince1970: 1_772_000_200)))
        _ = try store.apply(HealthChangeSet(
            added: [HealthSample(externalID: "uuid-healthkit-only", domain: .water,
                                 start: Date(timeIntervalSince1970: 1_772_000_500),
                                 end: Date(timeIntervalSince1970: 1_772_000_500),
                                 value: 400, unit: "ml")],
            deletedExternalIDs: [], nextAnchor: nil
        ), in: db)

        let dropped = try store.reconcileAfterRestore()
        XCTAssertEqual(dropped, 1, "only the echo of the writeback is an overlap")
        XCTAssertNil(try row(db, id: unrelated)?.string("deleted_at"), "a HealthKit-only row is not a duplicate")
    }

    func testReconcileDoesNotCollapseEchoOfSoftDeletedManualRow() throws {
        let (db, store, clock) = try fixture()
        let manualID = try manualWritebackAndEcho(in: db, store: store, clock: clock, externalID: "uuid-echo-2")
        // The user deleted the manual entry before the restore; the HealthKit
        // echo is now the *only* remaining representation and must not be
        // collapsed onto a row that no longer exists.
        try store.delete(id: manualID)

        let dropped = try store.reconcileAfterRestore()
        XCTAssertEqual(dropped, 0, "a soft-deleted manual row must not collapse the only remaining copy")

        let echo = try XCTUnwrap(db.query(
            "SELECT id, source_system, deleted_at FROM hydration_log WHERE source_system = 'healthkit' AND external_id = ?;",
            [.text("uuid-echo-2")]
        ).first)
        XCTAssertNil(echo.string("deleted_at"),
                     "with the manual row gone the HealthKit row is the surviving representation")
    }

    // MARK: - End to end through the bundle restore seam

    func testRestoreBundleRunsReconcileAfterRestore() throws {
        let dir = NSTemporaryDirectory() + "almanac-reconcile-\(UUID().uuidString)"
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: dir), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let sourcePath = dir + "/src.sqlite"
        let bundlePath = dir + "/snapshot.almanac-backup"
        let targetPath = dir + "/tgt.sqlite"

        // Source: a manual writeback + its HealthKit echo, as shipped in the bundle.
        let source = try Database(path: sourcePath)
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(source)
        let clock = FixedClock(Date(timeIntervalSince1970: 1_772_000_000))
        let store = HydrationStore(db: source, clock: clock)
        let manualID = try manualWritebackAndEcho(in: source, store: store, clock: clock, externalID: "uuid-cross-device-1")
        try BackupService(db: source, clock: clock).writeBundle(to: bundlePath, documentsRoot: nil, note: "reconcile c2e")

        // Target: a fresh install whose own data must be replaced wholesale.
        let target = try Database(path: targetPath)
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(target)
        try SyncAnchorStore(db: target).save(domain: "steps", token: [9])
        try BackupService(db: target).restoreBundle(at: bundlePath)

        // The manual entry is back; the echo has been collapsed by the seam.
        let restoredManual = try XCTUnwrap(row(target, id: manualID))
        XCTAssertEqual(restoredManual.string("source_system"), "manual")
        XCTAssertNil(restoredManual.string("deleted_at"))
        let restoredEcho = try XCTUnwrap(target.query(
            "SELECT id, deleted_at FROM hydration_log WHERE source_system = 'healthkit' AND external_id = ?;",
            [.text("uuid-cross-device-1")]
        ).first)
        XCTAssertNotNil(restoredEcho.string("deleted_at"),
                        "the shared restore seam must de-duplicate, not just swap the database")
    }
}

private extension FixedClock {
    func nowText() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: now)
    }
}