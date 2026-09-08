import XCTest
@testable import AlmanacCore

/// The flow a person will actually perform, against a database that is closed
/// and reopened in the middle — because an in-memory database would pass this
/// even if nothing were ever written to disk.
final class ManualEntryTests: XCTestCase {

    private var path = ""
    private let clock = FixedClock(Date(timeIntervalSince1970: 1_772_000_000))  // 2026-02-25

    override func setUp() {
        super.setUp()
        path = NSTemporaryDirectory() + "almanac-manual-\(UUID().uuidString).sqlite"
    }

    override func tearDown() {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: path + suffix)
        }
        super.tearDown()
    }

    private func ferritin(_ value: Double, _ text: String) -> LabRevisionContent {
        var c = LabRevisionContent()
        c.lifecycle = .final
        c.valueType = .quantitative
        c.derivation = .reportedWithoutDerivationStated
        c.numericValue = value
        c.unitText = "ng/mL"
        c.sourceAnalyteText = "Ferritin"
        c.sourceValueText = text
        c.contentOrigin = .userTranscription
        c.actor = "user"
        return c
    }

    // Scoped so the Database is released and the file closed before phase two.
    private func createReportAndResult() throws -> (reportID: String, observationID: String) {
        let db = try Database(path: path)
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        try LabCatalogSeed.seed(into: LabCatalogStore(db: db, clock: clock))
        let lab = LabStore(db: db, clock: clock)

        // Create a report by hand: no source system, no source report id.
        var report = LabReportDraft()
        report.laboratoryNameText = "Al Borg"
        report.reportedAt = PartialDateTime(text: "2026-02-20", precision: .day)
        let reportID = try lab.saveReport(report)

        var draft = LabObservationDraft()
        draft.reportID = reportID
        draft.specimenKind = .serum
        draft.specimenText = "Serum"
        draft.collectedAt = PartialDateTime(text: "2026-02-20T07:45:00Z", precision: .instant)
        let created = try lab.record(draft, content: ferritin(42, "42"))
        return (reportID, created.observationID)
    }

    func testCreateReopenEditHistoryAndASecondMeasurement() throws {
        let (reportID, observationID) = try createReportAndResult()

        // Reopened from disk. Everything below reads what was actually written.
        let db = try Database(path: path)
        let lab = LabStore(db: db, clock: clock)

        let summary = try XCTUnwrap(try lab.report(id: reportID))
        XCTAssertEqual(summary.laboratoryNameText, "Al Borg")
        XCTAssertEqual(summary.resultCount, 1)
        XCTAssertFalse(summary.hasUnresolvedConflict)

        var results = try lab.currentResults(inReport: reportID)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].displayName, "Ferritin")
        XCTAssertEqual(results[0].specimenKind, .serum)
        XCTAssertEqual(results[0].value, .quantity(text: "42", unit: "ng/mL"))
        XCTAssertEqual(results[0].revisionNumber, 1)

        // Edit the result. No external observation id exists and none is needed.
        var corrected = results[0].content
        corrected.numericValue = 48
        corrected.sourceValueText = "48"
        corrected.contentOrigin = .userCorrection
        corrected.actor = "user"
        corrected.reasonText = "Misread the printed value"
        let revised = try lab.reviseObservation(id: observationID, content: corrected)
        guard case .revised(let sameObservation, _, let number) = revised else {
            return XCTFail("expected a revision, got \(revised)")
        }
        XCTAssertEqual(sameObservation, observationID, "one observation identity throughout")
        XCTAssertEqual(number, 2)

        // Revision history: corrections to this one measurement.
        let revisions = try lab.revisions(of: observationID)
        XCTAssertEqual(revisions.map(\.content.sourceValueText), ["42", "48"])
        XCTAssertEqual(revisions.map(\.isCurrent), [false, true])
        XCTAssertEqual(revisions[1].content.contentOrigin, .userCorrection)
        XCTAssertEqual(revisions[1].content.reasonText, "Misread the printed value")

        results = try lab.currentResults(inReport: reportID)
        XCTAssertEqual(results[0].value, .quantity(text: "48", unit: "ng/mL"))

        // A second measurement of the same test, six months later, in its own report.
        var later = LabReportDraft()
        later.laboratoryNameText = "Al Borg"
        later.reportedAt = PartialDateTime(text: "2026-08-01", precision: .day)
        let laterReportID = try lab.saveReport(later)
        var draft = LabObservationDraft()
        draft.reportID = laterReportID
        draft.specimenKind = .serum
        draft.collectedAt = PartialDateTime(text: "2026-08-01T08:00:00Z", precision: .instant)
        try lab.record(draft, content: ferritin(55, "55"))

        // Longitudinal history: both measurements, across both reports.
        let series = try lab.measurements(analyteID: "almanac:lab.iron.ferritin",
                                          specimenKind: .serum)
        XCTAssertEqual(series.count, 2)
        XCTAssertEqual(series.map(\.content.sourceValueText), ["48", "55"])
        XCTAssertEqual(Set(series.compactMap(\.reportID)), Set([reportID, laterReportID]))

        // And it is not revision history: two measurements, three revisions.
        XCTAssertEqual(try lab.revisions(of: series[0].observationID).count, 2)
        XCTAssertEqual(try lab.revisions(of: series[1].observationID).count, 1)
    }

    // A manual record is editable by Almanac id alone — no external identifier
    // has to be invented to make a correction stick.
    func testReportIsEditableByAlmanacIDWithNoSourceIdentifiers() throws {
        let (reportID, _) = try createReportAndResult()
        let db = try Database(path: path)
        let lab = LabStore(db: db, clock: clock)

        var edit = LabReportEdit()
        edit.laboratoryNameText = .set("Al Borg Laboratories")
        edit.reasonText = "Full name from the letterhead"
        let outcome = try lab.updateReport(id: reportID, edit)
        guard case .updated = outcome else { return XCTFail("expected an update") }

        XCTAssertEqual(try lab.report(id: reportID)?.laboratoryNameText, "Al Borg Laboratories")
        let history = try lab.reportRevisions(of: reportID)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].laboratoryNameText, "Al Borg")
        XCTAssertEqual(history[0].kind, "superseded")

        // An edit that touches nothing is a no-op, not an empty revision.
        XCTAssertEqual(try lab.updateReport(id: reportID, LabReportEdit()),
                       .unchanged(reportID: reportID))
        XCTAssertEqual(try lab.reportRevisions(of: reportID).count, 1)
    }

    // Metadata corrections must land even though the measured value is
    // untouched — `record` compares content, so this path was previously silent.
    func testMetadataCorrectionIsAuditedAndAppliesWithUnchangedValue() throws {
        let (reportID, observationID) = try createReportAndResult()
        let db = try Database(path: path)
        let lab = LabStore(db: db, clock: clock)

        var edit = LabObservationMetadataEdit()
        edit.specimenKind = .set(.plasma)
        edit.specimenText = .set("Plasma, EDTA")
        edit.collectedAt = .set(PartialDateTime(text: "2026-02-19T07:30:00Z", precision: .instant))
        edit.actor = "user"
        edit.reasonText = "Draw was the day before; tube was EDTA"

        let outcome = try lab.updateObservationMetadata(id: observationID, edit)
        XCTAssertEqual(Set(outcome.changedFields),
                       Set(["specimen_kind", "specimen_text", "collected_at"]))

        let now = try XCTUnwrap(try lab.currentResults(inReport: reportID).first)
        XCTAssertEqual(now.specimenKind, .plasma)
        XCTAssertEqual(now.specimenText, "Plasma, EDTA")
        XCTAssertEqual(now.collectedAt.text, "2026-02-19T07:30:00Z")
        XCTAssertEqual(now.value, .quantity(text: "42", unit: "ng/mL"),
                       "the measured value was not part of this correction")
        XCTAssertEqual(try lab.revisions(of: observationID).count, 1,
                       "a metadata correction is not a result revision")

        let audit = try lab.metadataRevisions(of: observationID)
        XCTAssertEqual(audit.count, 1)
        XCTAssertEqual(audit[0].specimenKind, .serum, "the previous value is preserved")
        XCTAssertEqual(audit[0].specimenText, "Serum")
        XCTAssertEqual(audit[0].collectedAtText, "2026-02-20T07:45:00Z")
        XCTAssertEqual(audit[0].actor, "user")
        XCTAssertEqual(audit[0].reasonText, "Draw was the day before; tube was EDTA")
    }

    // "Leave unchanged" and "clear this field" are different instructions.
    func testLeaveUnchangedIsNotTheSameAsClear() throws {
        let (reportID, observationID) = try createReportAndResult()
        let db = try Database(path: path)
        let lab = LabStore(db: db, clock: clock)

        // Touch only the specimen kind; the text and the report link survive.
        var narrow = LabObservationMetadataEdit()
        narrow.specimenKind = .set(.wholeBlood)
        try lab.updateObservationMetadata(id: observationID, narrow)
        var view = try XCTUnwrap(try lab.currentResults(inReport: reportID).first)
        XCTAssertEqual(view.specimenKind, .wholeBlood)
        XCTAssertEqual(view.specimenText, "Serum", "leaveUnchanged left it alone")
        XCTAssertEqual(view.reportID, reportID)

        // Now clear the text explicitly, and the mapping with it.
        var clearing = LabObservationMetadataEdit()
        clearing.specimenText = .clear
        clearing.catalogAnalyteID = .clear
        try lab.updateObservationMetadata(id: observationID, clearing)
        view = try XCTUnwrap(try lab.currentResults(inReport: reportID).first)
        XCTAssertNil(view.specimenText)
        XCTAssertNil(view.catalogAnalyteID)
        XCTAssertTrue(view.isUnmatched)
        XCTAssertEqual(view.displayName, "Ferritin", "falls back to the source's own words")

        // Clearing a field with its own not-stated member uses that member.
        var clearTime = LabObservationMetadataEdit()
        clearTime.collectedAt = .clear
        try lab.updateObservationMetadata(id: observationID, clearTime)
        view = try XCTUnwrap(try lab.currentResults(inReport: reportID).first)
        XCTAssertEqual(view.collectedAt.precision, .unknown)

        XCTAssertEqual(try lab.metadataRevisions(of: observationID).count, 3)
    }

    // Re-mapping an unmatched result to a catalog analyte is a person's
    // decision and is attributed to them.
    func testCatalogMappingCorrectionIsAttributedToTheUser() throws {
        let (reportID, observationID) = try createReportAndResult()
        let db = try Database(path: path)
        let lab = LabStore(db: db, clock: clock)

        var edit = LabObservationMetadataEdit()
        edit.catalogAnalyteID = .set("almanac:lab.vitamin-d.25oh-total")
        try lab.updateObservationMetadata(id: observationID, edit)

        let view = try XCTUnwrap(try lab.currentResults(inReport: reportID).first)
        XCTAssertEqual(view.catalogAnalyteID, "almanac:lab.vitamin-d.25oh-total")
        XCTAssertEqual(view.displayName, "25-hydroxyvitamin D, total")
        let origin = try db.query("SELECT match_origin, match_confidence FROM lab_observation WHERE id = ?;",
                                  [.text(observationID)]).first
        XCTAssertEqual(origin?.string("match_origin"), "user")
        XCTAssertEqual(origin?.string("match_confidence"), "user_assigned")

        let audit = try lab.metadataRevisions(of: observationID)
        XCTAssertEqual(audit[0].catalogAnalyteID, "almanac:lab.iron.ferritin",
                       "the previous mapping is preserved")
    }

    func testReportsPaginateDeterministically() throws {
        let db = try Database(path: path)
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let lab = LabStore(db: db, clock: clock)

        // Three reports sharing one date, so only the tie-break can order them.
        for _ in 0..<3 {
            var draft = LabReportDraft()
            draft.reportedAt = PartialDateTime(text: "2026-02-20", precision: .day)
            try lab.saveReport(draft)
        }
        var older = LabReportDraft()
        older.reportedAt = PartialDateTime(text: "2025-01-01", precision: .day)
        try lab.saveReport(older)

        let all = try lab.reports(limit: 10)
        XCTAssertEqual(all.count, 4)
        XCTAssertEqual(all.last?.reportedAt.text, "2025-01-01", "newest first")

        let page1 = try lab.reports(limit: 2, offset: 0)
        let page2 = try lab.reports(limit: 2, offset: 2)
        XCTAssertEqual(page1.map(\.id) + page2.map(\.id), all.map(\.id),
                       "paging must not repeat or skip a row")
        XCTAssertEqual(try lab.reports(limit: 10).map(\.id), all.map(\.id),
                       "and must be stable across calls")
    }

    func testSuggestSearchesCanonicalNamesAndAliases() throws {
        let db = try Database(path: path)
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let catalog = LabCatalogStore(db: db, clock: clock)
        try LabCatalogSeed.seed(into: catalog)

        let ferr = try catalog.suggest(prefix: "ferr")
        XCTAssertEqual(ferr.first?.analyteID, "almanac:lab.iron.ferritin")
        XCTAssertTrue(ferr.first?.matchedCanonicalName ?? false)

        // An abbreviation that is not the canonical name still finds it.
        let hgb = try catalog.suggest(prefix: "hgb")
        XCTAssertEqual(hgb.first?.analyteID, "almanac:lab.haematology.haemoglobin")
        XCTAssertEqual(hgb.first?.canonicalName, "Haemoglobin")
        XCTAssertEqual(hgb.first?.matchedText, "HGB")

        // Arabic, and a prefix that spans several analytes.
        XCTAssertEqual(try catalog.suggest(prefix: "هيمو").first?.analyteID,
                       "almanac:lab.haematology.haemoglobin")
        let vitamins = try catalog.suggest(prefix: "vitamin", limit: 50)
        XCTAssertGreaterThan(vitamins.count, 5)
        XCTAssertEqual(Set(vitamins.map(\.analyteID)).count, vitamins.count,
                       "one row per analyte")

        XCTAssertTrue(try catalog.suggest(prefix: "").isEmpty)
        XCTAssertTrue(try catalog.suggest(prefix: "zzzz").isEmpty)
    }
}
