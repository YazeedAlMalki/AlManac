import XCTest
@testable import AlmanacCore

/// Arrival order is not authority. These pin what happens when a source
/// re-sends, reverts, or says nothing about which version is newer.
final class ImportOrderingTests: XCTestCase {

    private let clock = FixedClock(Date(timeIntervalSince1970: 1_772_000_000))

    private func fixture(policy: UnrankedImportPolicy = .applyAndFlag) throws -> (Database, LabStore) {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        return (db, LabStore(db: db, clock: clock, unrankedImports: policy))
    }

    private func version(_ laboratory: String, _ date: String,
                         ordering: SourceOrdering = .unavailable) -> LabReportDraft {
        var draft = LabReportDraft()
        draft.sourceSystem = "lab-a"
        draft.sourceReportID = "R-1"
        draft.laboratoryNameText = laboratory
        draft.reportedAt = PartialDateTime(text: date, precision: .day)
        draft.entryOrigin = "import"
        draft.sourceOrdering = ordering
        return draft
    }

    /// The required case: A, then correction B, then A arrives again.
    func testStaleReimportDoesNotBecomeCurrent() throws {
        let (_, lab) = try fixture()
        let a = version("Al Borg", "2026-02-20")
        let b = version("Al Borg Laboratories", "2026-02-21")

        guard case .created(let reportID) = try lab.upsertReport(a) else {
            return XCTFail("expected a new report")
        }
        guard case .updated = try lab.upsertReport(b) else {
            return XCTFail("B is the first correction and becomes current")
        }
        XCTAssertEqual(try lab.report(id: reportID)?.reportedAt.text, "2026-02-21")

        // A comes back. It is already in this report's history, so it is a
        // re-send, not a correction back to it.
        let replay = try lab.upsertReport(a)
        guard case .replayIgnored(let sameID, _) = replay else {
            return XCTFail("expected the replay to be ignored, got \(replay)")
        }
        XCTAssertEqual(sameID, reportID)

        // B is still current, and both versions are still retrievable.
        let current = try XCTUnwrap(try lab.report(id: reportID))
        XCTAssertEqual(current.laboratoryNameText, "Al Borg Laboratories")
        XCTAssertEqual(current.reportedAt.text, "2026-02-21")
        let history = try lab.reportRevisions(of: reportID)
        XCTAssertEqual(history.map(\.laboratoryNameText), ["Al Borg"])
        XCTAssertEqual(history.map(\.reportedAtText), ["2026-02-20"])

        // Replaying it a third time still changes nothing and logs nothing new.
        XCTAssertEqual(try lab.reportRevisions(of: reportID).count, 1)
    }

    /// A source that explicitly ranks a version above the current one may set
    /// it back to an earlier value. That is a deliberate revert, and it is only
    /// distinguishable from a replay by the ordering marker.
    func testExplicitRevertWithNewerOrderingIsAppliedNotTreatedAsReplay() throws {
        let (_, lab) = try fixture()
        guard case .created(let reportID) =
                try lab.upsertReport(version("Al Borg", "2026-02-20", ordering: .sequence(1))) else {
            return XCTFail("expected a new report")
        }
        guard case .updated = try lab.upsertReport(
            version("Al Borg Laboratories", "2026-02-21", ordering: .sequence(2))) else {
            return XCTFail("expected B to supersede A")
        }

        // The same content as A, but stated as version 3: the laboratory is
        // undoing its own correction.
        let revert = try lab.upsertReport(version("Al Borg", "2026-02-20", ordering: .sequence(3)))
        guard case .updated = revert else {
            return XCTFail("a ranked revert must be applied, got \(revert)")
        }
        XCTAssertEqual(try lab.report(id: reportID)?.reportedAt.text, "2026-02-20")
        XCTAssertEqual(try lab.reportRevisions(of: reportID).count, 2,
                       "both earlier versions are still retrievable")
    }

    func testOlderOrderedVersionIsIgnored() throws {
        let (_, lab) = try fixture()
        guard case .created(let reportID) =
                try lab.upsertReport(version("Al Borg", "2026-02-20", ordering: .sequence(5))) else {
            return XCTFail("expected a new report")
        }
        let stale = try lab.upsertReport(version("Old Name", "2026-02-01", ordering: .sequence(4)))
        XCTAssertEqual(stale, .staleIgnored(reportID: reportID))
        XCTAssertEqual(try lab.report(id: reportID)?.laboratoryNameText, "Al Borg")
        XCTAssertTrue(try lab.reportRevisions(of: reportID).isEmpty)
    }

    /// Timestamps rank the same way, and two incomparable kinds do not rank at
    /// all — a sequence number cannot be compared with an issue date.
    func testOrderingKindsMustMatchToRank() throws {
        XCTAssertEqual(SourceOrdering.sequence(2).compare(to: .sequence(1)), .orderedDescending)
        XCTAssertEqual(SourceOrdering.issuedAt("2026-02-21").compare(to: .issuedAt("2026-02-20")),
                       .orderedDescending)
        XCTAssertNil(SourceOrdering.sequence(2).compare(to: .issuedAt("2026-02-20")))
        XCTAssertNil(SourceOrdering.unavailable.compare(to: .sequence(1)))
        XCTAssertNil(SourceOrdering.sequence(1).compare(to: .unavailable))
    }

    /// Under the strict policy, unranked new content never becomes current.
    func testUnrankedNewContentIsHeldAsAConflictUnderTheStrictPolicy() throws {
        let (_, lab) = try fixture(policy: .holdAsConflict)
        guard case .created(let reportID) = try lab.upsertReport(version("Al Borg", "2026-02-20")) else {
            return XCTFail("expected a new report")
        }
        let outcome = try lab.upsertReport(version("Al Borg Laboratories", "2026-02-21"))
        guard case .conflict(let sameID, let conflictID) = outcome else {
            return XCTFail("expected a conflict, got \(outcome)")
        }
        XCTAssertEqual(sameID, reportID)
        XCTAssertTrue(outcome.needsHumanResolution)

        // Current is untouched, and the incoming version is retrievable.
        XCTAssertEqual(try lab.report(id: reportID)?.laboratoryNameText, "Al Borg")
        XCTAssertTrue(try XCTUnwrap(try lab.report(id: reportID)).hasUnresolvedConflict)
        let history = try lab.reportRevisions(of: reportID)
        XCTAssertEqual(history.map(\.kind), ["conflict"])
        XCTAssertEqual(history[0].laboratoryNameText, "Al Borg Laboratories")
        XCTAssertEqual(history[0].id, conflictID)

        // Sending the same unrankable version again does not log it twice.
        _ = try lab.upsertReport(version("Al Borg Laboratories", "2026-02-21"))
        XCTAssertEqual(try lab.reportRevisions(of: reportID).count, 1)
    }

    /// Under the default policy the change is applied, but the revision records
    /// that nothing ranked it — the assumption is visible, not implied.
    func testUnrankedChangeUnderTheDefaultPolicyIsRecordedAsUnranked() throws {
        let (_, lab) = try fixture()
        guard case .created(let reportID) = try lab.upsertReport(version("Al Borg", "2026-02-20")) else {
            return XCTFail("expected a new report")
        }
        guard case .updated = try lab.upsertReport(version("Al Borg Laboratories", "2026-02-21")) else {
            return XCTFail("expected an update")
        }
        XCTAssertEqual(try lab.reportRevisions(of: reportID).map(\.kind), ["superseded_unranked"])
    }
}
