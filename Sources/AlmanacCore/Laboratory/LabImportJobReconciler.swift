import Foundation

/// Works out how an import went, from the rows it left behind, and links the
/// rows it can now link.
///
/// **Why this is a reconciliation and not part of the import.** Whether a row
/// matched the catalog is not a property of the file — it is a property of the
/// file *and the catalog at the moment the question is asked*. A person who
/// teaches Almanac the name their laboratory printed has answered a question an
/// import could not have answered correctly at the time. Deciding the outcome
/// inside `importReports` would freeze the wrong answer into the record.
///
/// So the import writes a job as `.unresolved` and this closes it. The seam is
/// one call, `reconcile()`, idempotent and cheap when there is nothing to do —
/// the same shape as `ensureCache`, `ensureCycle` and
/// `NotificationPlanner.plan()`. A missed call site costs one stale count, not
/// a permanently wrong state.
///
/// **It links, it does not just count.** A row the import could not resolve is
/// stored with its source text intact and `catalog_analyte_id` null. That row
/// is real data with no history, no trend and no correlation, and the fix — an
/// alias — arrives after the import. Linking here is what makes the import
/// screen worth having: add the name your lab prints, and the four rows you
/// could not match become four rows you can.
///
/// **Only a unique match is linked.** `LabCatalog.matchCandidates` refuses to
/// choose between candidates and Laboratory's own rule is that ambiguity goes to
/// a person. This keeps that: an ambiguous row stays unlinked and is counted as
/// ambiguous, so the screen can offer the candidates rather than report an
/// unexplained gap. A link already made — especially one a person made — is
/// never overwritten.
///
/// The link is written through `LabStore.updateObservationMetadata`, so it lands
/// in `lab_observation_metadata_revision` with an actor and a reason, and the
/// measured value is untouched. It is metadata, not a correction of what the lab
/// said.
public struct LabImportJobReconciler: @unchecked Sendable {
    private let db: Database

    public init(db: Database) {
        self.db = db
    }

    /// Who the metadata revision says did the linking.
    static let actor = "catalog-reconciliation"

    /// How many aliases the catalog holds. Used as the job's generation stamp:
    /// a job reconciled at this number is up to date, one stamped lower has an
    /// outcome that was decided before the catalog learned something.
    ///
    /// One query, and the same count the queue query compares against in SQL —
    /// so the two cannot disagree, because there is only one definition.
    public static func currentGeneration(_ db: Database) throws -> Int {
        Int(try db.query("SELECT COUNT(*) AS n FROM lab_catalog_alias;").first?.int("n") ?? 0)
    }

    /// Closes every job whose outcome is stale or has never been worked out.
    /// Returns how many were closed, so a caller can tell "nothing to do" from
    /// "ran and found nothing".
    ///
    /// **A closed job reopens when the catalog changes.** That is the whole
    /// point of stamping a generation: without it, an import reconciled once
    /// would never be looked at again, and adding the alias that resolves the
    /// four rows you could not match would do nothing at all.
    @discardableResult
    public func reconcile() throws -> Int {
        let jobs = try LabImportJobStore(db: db).pendingReconciliation()
        guard !jobs.isEmpty else { return 0 }
        let generation = try Self.currentGeneration(db)
        for job in jobs {
            try close(job, generation: generation)
        }
        return jobs.count
    }

    private func close(_ job: LabImportJob, generation: Int) throws {
        // A job that produced no reports has no rows to ask about. Its own
        // frozen counts already say so, and `resolve` classifies an empty
        // window as `.invalid` without a second query.
        guard !job.sourceReportIDs.isEmpty else {
            try store.resolve(id: job.id, counts: LabImportMatchCounts(rowsUsable: 0),
                              reportConflicts: job.reportConflicts,
                              invalidRows: job.invalidRows, catalogGeneration: generation,
                              failureReason: job.failureReason)
            return
        }
        try linkUnmatchedRows(job)
        let counts = try counts(forReportKeys: job.sourceReportIDs, sourceSystem: job.sourceSystem)
        try store.resolve(id: job.id, counts: counts, reportConflicts: job.reportConflicts,
                          invalidRows: job.invalidRows, catalogGeneration: generation,
                          failureReason: job.failureReason)
    }

    /// One query for the whole job to find the candidates, and one write each
    /// for the rows a unique match resolves. The rows are fetched with their
    /// source text so the catalog is asked exactly what `LabStore.record` would
    /// have asked.
    ///
    /// Bounded by the job's own reports, so the cost is proportional to the
    /// file that was imported and not to the history.
    private func linkUnmatchedRows(_ job: LabImportJob) throws {
        let placeholders = Array(repeating: "?", count: job.sourceReportIDs.count).joined(separator: ", ")
        let rows = try db.query("""
        SELECT o.id AS observation_id, v.source_analyte_text
        FROM lab_observation o
        JOIN lab_report r ON r.id = o.report_id
        JOIN lab_observation_revision v
          ON v.observation_id = o.id AND v.is_current = 1
        WHERE r.source_system = ? AND r.source_report_id IN (\(placeholders))
          AND o.catalog_analyte_id IS NULL AND o.match_origin IS NOT 'ambiguous';
        """, [.text(job.sourceSystem)] + job.sourceReportIDs.map { SQLValue.text($0) })

        guard !rows.isEmpty else { return }
        let catalog = LabCatalogStore(db: db)
        let lab = LabStore(db: db)
        for row in rows {
            guard let observationID = row.string("observation_id"),
                  let sourceText = row.string("source_analyte_text"),
                  case .unique(let match) = try catalog.matchCandidates(sourceText: sourceText)
            else { continue }
            var edit = LabObservationMetadataEdit()
            edit.catalogAnalyteID = .set(match.analyteID)
            edit.actor = Self.actor
            edit.reasonText = "The catalog learned this test name after the import ran."
            _ = try? lab.updateObservationMetadata(id: observationID, edit)
        }
    }

    /// One query for the whole job, not one per report key and not one per row.
    ///
    /// The classification mirrors `LabStore.record`'s own matching rules, which
    /// are the rules that decided what `catalog_analyte_id` and `match_origin`
    /// hold:
    /// - `catalog_analyte_id IS NOT NULL` → matched.
    /// - `match_origin = 'ambiguous'` → candidates exist, only a decision is
    ///   missing.
    /// - anything else → the catalog has nothing for this text.
    private func counts(forReportKeys keys: [String], sourceSystem: String) throws -> LabImportMatchCounts {
        let placeholders = Array(repeating: "?", count: keys.count).joined(separator: ", ")
        let row = try db.query("""
        SELECT
            COUNT(*) AS usable,
            COALESCE(SUM(CASE WHEN o.catalog_analyte_id IS NOT NULL THEN 1 ELSE 0 END), 0) AS matched,
            COALESCE(SUM(CASE WHEN o.catalog_analyte_id IS NULL AND o.match_origin = 'ambiguous'
                              THEN 1 ELSE 0 END), 0) AS ambiguous,
            COALESCE(SUM(CASE WHEN o.catalog_analyte_id IS NULL
                               AND (o.match_origin IS NULL OR o.match_origin <> 'ambiguous')
                              THEN 1 ELSE 0 END), 0) AS unmatched
        FROM lab_observation o
        JOIN lab_report r ON r.id = o.report_id
        WHERE r.source_system = ? AND r.source_report_id IN (\(placeholders));
        """, [.text(sourceSystem)] + keys.map { SQLValue.text($0) }).first
        return LabImportMatchCounts(
            rowsUsable: Int(row?.int("usable") ?? 0),
            matched: Int(row?.int("matched") ?? 0),
            ambiguous: Int(row?.int("ambiguous") ?? 0),
            unmatched: Int(row?.int("unmatched") ?? 0)
        )
    }

    private var store: LabImportJobStore { LabImportJobStore(db: db) }
}
