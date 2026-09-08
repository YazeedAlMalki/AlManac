import XCTest
@testable import AlmanacCore

final class RequestedFixTests: XCTestCase {
    func fixture() throws -> (Database, LabStore) {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        return (db, LabStore(db: db))
    }
    func report(_ name: String, _ order: SourceOrdering = .unavailable) -> LabReportDraft {
        var r = LabReportDraft(); r.sourceSystem = "lab"; r.sourceReportID = "R"
        r.laboratoryNameText = name; r.sourceOrdering = order
        return r
    }
    func testDefaultConflictsCanBeAcceptedAndRejectedWithAudit() throws {
        let (db, lab) = try fixture()
        let id = try lab.saveReport(report("A"))
        guard case .conflict(_, let conflict) = try lab.upsertReport(report("B")) else { return XCTFail("default must hold") }
        XCTAssertEqual(try lab.report(id: id)?.laboratoryNameText, "A")
        XCTAssertThrowsError(try lab.resolveReportConflict(id: conflict, accept: true, actor: "user", reason: ""))
        try lab.resolveReportConflict(id: conflict, accept: true, actor: "user", reason: "Checked source")
        XCTAssertEqual(try lab.report(id: id)?.laboratoryNameText, "B")
        XCTAssertEqual(try lab.report(id: id)?.hasUnresolvedConflict, false)
        XCTAssertEqual(try db.query("SELECT resolved_by, resolution_reason FROM lab_report_revision WHERE id = ?", [.text(conflict)]).first?.string("resolved_by"), "user")
        XCTAssertThrowsError(try lab.resolveReportConflict(id: conflict, accept: false, actor: "user", reason: "Already handled"))
        guard case .conflict(_, let rejected) = try lab.upsertReport(report("C")) else { return XCTFail("hold C") }
        try lab.resolveReportConflict(id: rejected, accept: false, actor: "user", reason: "Old document")
        XCTAssertEqual(try lab.report(id: id)?.laboratoryNameText, "B")
        XCTAssertEqual(try lab.report(id: id)?.hasUnresolvedConflict, false)
        _ = try lab.upsertReport(report("C"))
        XCTAssertEqual(try lab.report(id: id)?.hasUnresolvedConflict, false)
    }
    func testManualRevertCreatesThirdRevisionAndImportRemainsIdempotent() throws {
        let (_, lab) = try fixture()
        var c = LabRevisionContent(); c.valueType = .quantitative; c.numericValue = 42; c.sourceValueText = "42"
        var d = LabObservationDraft(); d.sourceSystem = "lab"; d.sourceObservationID = "O"
        let id = try lab.record(d, content: c).observationID
        var b = c; b.numericValue = 48; b.sourceValueText = "48"
        _ = try lab.reviseObservation(id: id, content: b)
        c.actor = "reviewer"; c.reasonText = "Deliberate revert"; c.contentOrigin = .userCorrection
        _ = try lab.reviseObservation(id: id, content: c)
        XCTAssertEqual(try lab.currentRevision(of: id)?.content.actor, "reviewer")
        XCTAssertEqual(try lab.currentRevision(of: id)?.content.reasonText, "Deliberate revert")
        XCTAssertEqual(try lab.revisions(of: id).map { $0.content.numericValue }, [42, 48, 42])
        XCTAssertEqual(try lab.revisions(of: id).map(\.isCurrent), [false, false, true])
        _ = try lab.record(d, content: b)
        XCTAssertEqual(try lab.currentRevision(of: id)?.content.numericValue, 42)
        XCTAssertEqual(try lab.revisions(of: id).count, 3)
    }
    func testManualEditorSaveRollsBackBothPartsOnFailure() throws {
        let (_, lab) = try fixture()
        var c = LabRevisionContent(); c.valueType = .quantitative; c.numericValue = 42
        let id = try lab.record(LabObservationDraft(), content: c).observationID
        c.numericValue = 48
        var edit = LabObservationMetadataEdit(); edit.reportID = .set("nonexistent")
        XCTAssertThrowsError(try lab.saveManualEdit(id: id, content: c, metadata: edit))
        XCTAssertEqual(try lab.currentRevision(of: id)?.content.numericValue, 42)
        XCTAssertEqual(try lab.revisions(of: id).count, 1)
        XCTAssertEqual(try lab.metadataRevisions(of: id).count, 0)
        edit.reportID = .leaveUnchanged; edit.specimenKind = .set(.serum)
        try lab.saveManualEdit(id: id, content: c, metadata: edit)
        XCTAssertEqual(try lab.currentRevision(of: id)?.content.numericValue, 48)
        XCTAssertEqual(try lab.metadataRevisions(of: id).count, 1)
    }
    func testUnchangedContentAdvancesOrderingAndEqualVersionConflicts() throws {
        let (_, lab) = try fixture()
        let id = try lab.saveReport(report("A", .sequence(1)))
        _ = try lab.upsertReport(report("A", .sequence(3)))
        XCTAssertEqual(try lab.upsertReport(report("B", .sequence(2))), .staleIgnored(reportID: id))
        guard case .conflict(_, let conflict) = try lab.upsertReport(report("B", .sequence(3))) else { return XCTFail("equal conflicting version") }
        XCTAssertEqual(try lab.report(id: id)?.laboratoryNameText, "A")
        try lab.resolveReportConflict(id: conflict, accept: false, actor: "reviewer", reason: "Duplicate version")
        _ = try lab.upsertReport(report("B", .sequence(3)))
        XCTAssertEqual(try lab.report(id: id)?.hasUnresolvedConflict, false)
        let resolution = try XCTUnwrap(lab.reportRevisions(of: id).first { $0.id == conflict })
        XCTAssertNotNil(resolution.resolvedAt)
        XCTAssertEqual(resolution.resolutionReason, "Duplicate version")
    }
    func testPartialIssueDatesCannotRankBySpanStart() {
        XCTAssertNil(SourceOrdering.issuedAt("2026-02").compare(to: .issuedAt("2026-02-20")))
        XCTAssertNil(SourceOrdering.issuedAt("2026-02-20").compare(to: .issuedAt("2026-02-20")))
        XCTAssertEqual(SourceOrdering.issuedAt("2026-03").compare(to: .issuedAt("2026-01")), .orderedDescending)
    }
    func testOffsetParsingRequiresTimeAndValidOffset() throws {
        for text in ["2026-02-25", "2026-02-25T08:10", "2026-02-25T08:10:00"] {
            let date = try XCTUnwrap(PartialDateTime(inferringPrecisionFrom: text))
            XCTAssertFalse(date.hasKnownOffset, text)
            XCTAssertNotNil(date.span)
        }
        for text in ["2026-02-25T08:10:00Z", "2026-02-25T08:10:00+03:00", "2026-02-25T08:10+03:00"] {
            XCTAssertTrue(try XCTUnwrap(PartialDateTime(inferringPrecisionFrom: text)).hasKnownOffset)
        }
        for text in ["2026-02-25T08:10:00+25:00", "2026-02-25T08:10:00+03:99", "2026-02-30", "2026-02-25Z"] {
            XCTAssertNil(PartialDateTime(inferringPrecisionFrom: text), text)
        }
    }
}
