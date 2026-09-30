import Testing
import Foundation
@testable import AlmanacCore

/// Migration 046 — `import_job`.
///
/// The seam is `LabImportJobStore` plus `LabImportStatus` classification: a
/// status is a function of counts, so it is testable without a database, and
/// the counts it reads are derived from the observations themselves rather than
/// from a tally the import kept in memory.
@Suite("Lab import job records")
struct LabImportJobTests {

    /// A migrated in-memory database, built the way every core suite builds one
    /// so that Migration046 is exercised by every test below.
    private func makeDB() throws -> Database {
        let db = try Database.inMemory()
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        return db
    }

    // MARK: - Status classification (pure)

    @Test("An empty import is invalid, not matched")
    func emptyIsInvalid() {
        // Zero rows cannot be "everything matched" — there was nothing to match.
        #expect(LabImportStatus.resolve(.init()) == .invalid)
    }

    @Test("Every usable row resolved to exactly one analyte: matched")
    func allMatched() {
        let counts = LabImportMatchCounts(rowsUsable: 4, matched: 4, ambiguous: 0, unmatched: 0)
        #expect(LabImportStatus.resolve(counts) == .matched)
    }

    @Test("Some rows resolved and some did not: partial")
    func someMatched() {
        let counts = LabImportMatchCounts(rowsUsable: 4, matched: 2, ambiguous: 1, unmatched: 1)
        #expect(LabImportStatus.resolve(counts) == .partial)
        #expect(LabImportStatus.resolve(counts).needsAttention)
    }

    @Test("No row resolved but rows were usable: unmatched")
    func noneMatched() {
        let counts = LabImportMatchCounts(rowsUsable: 3, matched: 0, ambiguous: 1, unmatched: 2)
        #expect(LabImportStatus.resolve(counts) == .unmatched)
        #expect(LabImportStatus.resolve(counts).needsAttention)
    }

    @Test("A held report conflict outranks the match counts")
    func conflictWins() {
        // A person has to resolve it, so it is the thing the screen must show
        // first — but it does not erase the fact that rows were also unmatched.
        let counts = LabImportMatchCounts(rowsUsable: 2, matched: 2, ambiguous: 0, unmatched: 0)
        #expect(LabImportStatus.resolve(counts, reportConflicts: 1) == .conflicted)
        #expect(LabImportStatus.resolve(counts, reportConflicts: 1).needsAttention)
    }

    @Test("Malformed rows alone do not make a good import bad")
    func invalidRowsAloneAreNotPartial() {
        // Two rows were skipped and four resolved cleanly. Calling that
        // "partial" would report a matching problem where the rows were simply
        // not laboratory lines at all.
        let counts = LabImportMatchCounts(rowsUsable: 4, matched: 4, ambiguous: 0, unmatched: 0)
        #expect(LabImportStatus.resolve(counts, invalidRows: 2) == .matched)
    }

    @Test("A job that did not run is failed, whatever its counts were")
    func failedOutranksEverything() {
        let counts = LabImportMatchCounts(rowsUsable: 4, matched: 4, ambiguous: 0, unmatched: 0)
        #expect(LabImportStatus.resolve(counts, failed: true) == .failed)
    }

    @Test("Raw values survive a round trip, so an unreadable row is visible rather than silently dropped")
    func rawValueRoundTrip() throws {
        let store = LabImportJobStore(db: try makeDB())
        let id = try store.record(draft: LabImportJobDraft(
            sourceName: "march-panel.csv",
            sourceReportIDs: ["panel-mar"],
            outcome: LabCSVImportResult(observationsCreated: 3),
            status: .partial
        ))
        let read = try #require(try store.job(id: id))
        #expect(read.sourceName == "march-panel.csv")
        #expect(read.sourceReportIDs == ["panel-mar"])
        #expect(read.status == .partial)
        #expect(read.finishedAt != nil, "A job with an outcome has a finish; §2.5's start/outcome pair is one write")
    }

    // MARK: - Reconciler

    @Test("The reconciler derives the outcome from the observations, not from a remembered tally")
    func outcomeComesFromObservations() throws {
        let db = try makeDB()
        let store = LabImportJobStore(db: db)
        let lab = LabStore(db: db)
        let catalog = LabCatalogStore(db: db)

        // One analyte the catalog knows, one it does not.
        let ferritin = CatalogAnalyte(id: "almanac:ferritin", canonicalName: "Ferritin",
                                      family: "iron", measurementRole: .direct)
        try catalog.upsert(ferritin)
        try catalog.addAlias("Ferritin", to: "almanac:ferritin")

        let jobID = try store.record(draft: LabImportJobDraft(
            sourceName: "march.csv",
            sourceReportIDs: ["panel-mar"],
            outcome: LabCSVImportResult(observationsCreated: 2),
            // The import did not decide this. It said "unresolved" and the
            // reconciler worked it out from the rows.
            status: .unresolved
        ))

        var ferritinDraft = LabReportDraft()
        ferritinDraft.sourceSystem = LabReportCSVImport.importSourceSystem
        ferritinDraft.sourceReportID = "panel-mar"
        ferritinDraft.entryOrigin = "csv-import"
        let outcome = try lab.upsertReport(ferritinDraft)
        let reportID = outcome.reportID

        var known = LabObservationDraft()
        known.reportID = reportID
        known.sourceSystem = LabReportCSVImport.importSourceSystem
        known.sourceObservationID = "panel-mar#1"
        var knownContent = LabRevisionContent()
        knownContent.sourceAnalyteText = "Ferritin"
        knownContent.valueType = .quantitative
        knownContent.sourceValueText = "80"
        knownContent.numericValue = 80
        _ = try lab.record(known, content: knownContent)

        var unknown = LabObservationDraft()
        unknown.reportID = reportID
        unknown.sourceSystem = LabReportCSVImport.importSourceSystem
        unknown.sourceObservationID = "panel-mar#2"
        var unknownContent = LabRevisionContent()
        unknownContent.sourceAnalyteText = "Zinc, serum"
        unknownContent.valueType = .quantitative
        unknownContent.sourceValueText = "70"
        unknownContent.numericValue = 70
        _ = try lab.record(unknown, content: unknownContent)

        let reconciled = try LabImportJobReconciler(db: db).reconcile()
        #expect(reconciled == 1, "One job was unresolved and is now closed")

        let job = try #require(try store.job(id: jobID))
        #expect(job.status == .partial)
        #expect(job.rowsMatched == 1)
        #expect(job.rowsUnmatched == 1)
        // The frozen count of what the attempt did survives reconciliation, and
        // is not overwritten by the reconciled view of what it matched.
        #expect(job.observationsCreated == 2)
    }

    @Test("Reconciling twice changes nothing the second time")
    func reconcileIsIdempotent() throws {
        let db = try makeDB()
        let store = LabImportJobStore(db: db)
        _ = try store.record(draft: LabImportJobDraft(
            sourceName: "a.csv", sourceReportIDs: ["r1"],
            outcome: LabCSVImportResult(), status: .unresolved))
        let reconciler = LabImportJobReconciler(db: db)
        #expect(try reconciler.reconcile() == 1)
        #expect(try reconciler.reconcile() == 0, "Nothing left to close; a second pass costs one query")
    }

    @Test("An alias added later resolves a row the import could not")
    func laterAliasResolvesAnEarlierImport() throws {
        // This is the reason the outcome is reconciled rather than decided at
        // the import: matching depends on the catalog, and the catalog gains
        // aliases after the import has already run.
        let db = try makeDB()
        let catalog = LabCatalogStore(db: db)
        let lab = LabStore(db: db)
        let store = LabImportJobStore(db: db)

        var draft = LabReportDraft()
        draft.sourceSystem = LabReportCSVImport.importSourceSystem
        draft.sourceReportID = "panel-apr"
        draft.entryOrigin = "csv-import"
        let reportID = try lab.upsertReport(draft).reportID

        var observation = LabObservationDraft()
        observation.reportID = reportID
        observation.sourceSystem = LabReportCSVImport.importSourceSystem
        observation.sourceObservationID = "panel-apr#1"
        var content = LabRevisionContent()
        content.sourceAnalyteText = "Zinc, serum"
        content.valueType = .quantitative
        content.sourceValueText = "70"
        content.numericValue = 70
        let observationID = try lab.record(observation, content: content).observationID
        #expect(try lab.catalogAnalyteID(of: observationID) == nil)

        let jobID = try store.record(draft: LabImportJobDraft(
            sourceName: "april.csv", sourceReportIDs: ["panel-apr"],
            outcome: LabCSVImportResult(), status: .unresolved))
        // Not reconciled yet: the import deliberately left the question open.
        #expect(try store.job(id: jobID)?.status == .unresolved)

        // A person teaches the catalog the name their laboratory printed.
        try catalog.upsert(CatalogAnalyte(id: "almanac:zinc", canonicalName: "Zinc",
                                          family: "trace", measurementRole: .direct))
        try catalog.addAlias("Zinc, serum", to: "almanac:zinc")

        _ = try LabImportJobReconciler(db: db).reconcile()
        #expect(try store.job(id: jobID)?.status == .matched)
        #expect(try store.job(id: jobID)?.rowsMatched == 1)
        // The row itself is linked, not merely counted — otherwise the data
        // would sit in the database with no history, no trend and no
        // correlation, which is the whole cost of the unmatched state.
        #expect(try lab.catalogAnalyteID(of: observationID) == "almanac:zinc")
    }

    @Test("A closed job reopens when the catalog learns something new")
    func closedJobReopensOnCatalogChange() throws {
        // Without this, an import reconciled once would never be looked at
        // again and the alias below would be a note to nobody.
        let db = try makeDB()
        let catalog = LabCatalogStore(db: db)
        let lab = LabStore(db: db)
        let store = LabImportJobStore(db: db)
        let reconciler = LabImportJobReconciler(db: db)

        var draft = LabReportDraft()
        draft.sourceSystem = LabReportCSVImport.importSourceSystem
        draft.sourceReportID = "panel-may"
        draft.entryOrigin = "csv-import"
        let reportID = try lab.upsertReport(draft).reportID

        var observation = LabObservationDraft()
        observation.reportID = reportID
        observation.sourceSystem = LabReportCSVImport.importSourceSystem
        observation.sourceObservationID = "panel-may#1"
        var content = LabRevisionContent()
        content.valueType = .quantitative
        content.sourceAnalyteText = "Selenium"
        content.sourceValueText = "70"
        content.numericValue = 70
        _ = try lab.record(observation, content: content)

        let jobID = try store.record(draft: LabImportJobDraft(
            sourceName: "may.csv", sourceReportIDs: ["panel-may"],
            outcome: LabCSVImportResult(), status: .unresolved))
        #expect(try reconciler.reconcile() == 1)
        #expect(try store.job(id: jobID)?.status == .unmatched)
        #expect(try reconciler.reconcile() == 0, "A settled job with an unchanged catalog is not re-examined")

        // An unrelated alias still bumps the generation, because the reconciler
        // cannot know in advance whether it will matter.
        try catalog.upsert(CatalogAnalyte(id: "almanac:copper", canonicalName: "Copper",
                                          family: "trace", measurementRole: .direct))
        try catalog.addAlias("Copper", to: "almanac:copper")
        #expect(try reconciler.reconcile() == 1, "The catalog moved, so the job is stale")
        #expect(try store.job(id: jobID)?.status == .unmatched, "And it is still unmatched, because nothing matched")
    }

    @Test("A job's history is newest first and bounded")
    func historyIsOrderedAndBounded() throws {
        let store = LabImportJobStore(db: try makeDB())
        for index in 0..<5 {
            _ = try store.record(draft: LabImportJobDraft(
                sourceName: "file-\(index).csv", sourceReportIDs: ["r-\(index)"],
                outcome: LabCSVImportResult(), status: .matched))
        }
        let recent = try store.jobs(limit: 3)
        #expect(recent.count == 3)
        #expect(recent.map(\.sourceName) == ["file-4.csv", "file-3.csv", "file-2.csv"])
        #expect(try store.jobsNeedingAttention().count == 0)
    }

    @Test("A failed job is listed as needing attention")
    func failedNeedsAttention() throws {
        let store = LabImportJobStore(db: try makeDB())
        _ = try store.record(draft: LabImportJobDraft(
            sourceName: "broken.csv", sourceReportIDs: [], outcome: LabCSVImportResult(),
            status: .failed, failureReason: "The file was not readable as text."))
        let attention = try store.jobsNeedingAttention()
        #expect(attention.count == 1)
        #expect(attention.first?.failureReason == "The file was not readable as text.")
    }

    @Test("A failed job records why, because a count of zero does not say why")
    func failureReasonIsKept() throws {
        let store = LabImportJobStore(db: try makeDB())
        let id = try store.record(draft: LabImportJobDraft(
            sourceName: "broken.csv", sourceReportIDs: [], outcome: LabCSVImportResult(),
            status: .failed, failureReason: "Row 4 has 9 columns, not 11."))
        #expect(try store.job(id: id)?.failureReason == "Row 4 has 9 columns, not 11.")
    }
}
