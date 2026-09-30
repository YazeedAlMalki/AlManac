import Foundation

/// What happened to one laboratory import.
///
/// A job is not a sync cursor: it has a start, an outcome and a count of rows.
/// A cursor has a position and nothing else. The distinction is load-bearing —
/// "how far" cannot answer "did I lose data", and that is the only question the
/// import screen is for.
///
/// The cases are a closed set. `rawValue` is what `import_job.status` stores,
/// and `resolve` is the one place that decides which case a set of counts
/// belongs to, so a status is never a judgement call made at a call site.
public enum LabImportStatus: String, Sendable, Hashable, CaseIterable {
    /// Every usable row resolved to exactly one catalog analyte.
    case matched
    /// Some rows resolved and some did not. The common, expected outcome: the
    /// catalog refuses to guess, so an unfamiliar test name is normal.
    case partial
    /// Rows were usable and none of them resolved. Usually a laboratory whose
    /// printing this repo has no aliases for.
    case unmatched
    /// No usable row at all. The file was not shaped like laboratory lines.
    case invalid
    /// Report-level metadata disagreed with what is already stored, and was
    /// held for a person rather than applied — arrival order is not authority.
    case conflicted
    /// The attempt did not complete. Carries a reason, because a count of zero
    /// does not say why.
    case failed

    /// The job ran; its outcome has not been worked out yet. Written by the
    /// import, closed by `LabImportJobReconciler`. Never shown to a person as a
    /// problem: it is the reconciler's queue, not a defect.
    case unresolved

    /// Whether a person has to do something about this job. `.unresolved` is
    /// excluded on purpose — it is this app's own pending work.
    public var needsAttention: Bool {
        switch self {
        case .partial, .unmatched, .invalid, .conflicted, .failed: return true
        case .matched, .unresolved: return false
        }
    }

    /// The reconciliation queue is exactly this case. `reconcile()` looks for
    /// it and nothing else.
    public static let pendingReconciliation: LabImportStatus = .unresolved

    /// Classifies a job from its counts.
    ///
    /// Precedence, and why each rule outranks the one below it:
    /// 1. `.failed` — nothing else is knowable about an attempt that did not finish.
    /// 2. `.invalid` — no usable row means no matching question to answer.
    /// 3. `.conflicted` — a person has to resolve report metadata, and that
    ///    outranks a row count they would otherwise be reading past. It does not
    ///    erase the row counts; both are stored.
    /// 4. the three match outcomes, from how many usable rows resolved.
    ///
    /// `invalidRows` deliberately does **not** feed into the classification. Two
    /// rows skipped and four resolved cleanly is a `matched` job with two skipped
    /// rows, not a `partial` one — calling it partial would report a matching
    /// problem where the rows were simply not laboratory lines.
    public static func resolve(_ counts: LabImportMatchCounts,
                               invalidRows: Int = 0,
                               reportConflicts: Int = 0,
                               failed: Bool = false) -> LabImportStatus {
        if failed { return .failed }
        if counts.rowsUsable == 0 { return .invalid }
        if reportConflicts > 0 { return .conflicted }
        if counts.matched == counts.rowsUsable { return .matched }
        if counts.matched == 0 { return .unmatched }
        return .partial
    }
}

/// The three numbers a job's outcome is read from: how many rows were usable,
/// and how each resolved against the catalog.
///
/// `ambiguous` and `unmatched` are separate counts rather than one "not matched"
/// number because they are different problems with different fixes. Ambiguous
/// means the catalog has candidates and only lacks a decision. Unmatched means
/// it has neither, and the fix is a new alias.
public struct LabImportMatchCounts: Sendable, Hashable {
    public let rowsUsable: Int
    public let matched: Int
    public let ambiguous: Int
    public let unmatched: Int

    public init(rowsUsable: Int, matched: Int = 0, ambiguous: Int = 0, unmatched: Int = 0) {
        self.rowsUsable = rowsUsable
        self.matched = matched
        self.ambiguous = ambiguous
        self.unmatched = unmatched
    }

    /// No rows asked a question — an empty file, or an attempt that threw.
    public init() {
        self.init(rowsUsable: 0)
    }

    /// Nothing to reconcile — no rows asked a question.
    public var isEmpty: Bool { rowsUsable == 0 }
}

/// One recorded attempt to import a laboratory file.
public struct LabImportJob: Sendable, Hashable, Identifiable {
    public let id: Int64
    /// What the person pasted, if anything was pasted. Not a filename: the
    /// import is a paste, and inventing a path would be a claim the app cannot
    /// support.
    public let sourceName: String?
    public let sourceSystem: String
    public let status: LabImportStatus
    public let startedAt: Date
    public let finishedAt: Date?
    /// The `source_report_id`s this attempt touched, as the source named them.
    /// Enough to find the observations again without freezing a copy of them.
    public let sourceReportIDs: [String]

    public let groups: Int
    public let reportsCreated: Int
    public let reportsUnchanged: Int
    public let reportConflicts: Int
    public let observationsCreated: Int
    public let observationsUnchanged: Int
    public let observationsRevised: Int
    public let invalidRows: Int

    /// Reconciled from the observations, not frozen at import time.
    public let rowsUsable: Int
    public let rowsMatched: Int
    public let rowsAmbiguous: Int
    public let rowsUnmatched: Int

    public let failureReason: String?

    public init(id: Int64, sourceName: String?, sourceSystem: String, status: LabImportStatus,
                startedAt: Date, finishedAt: Date?, sourceReportIDs: [String],
                groups: Int, reportsCreated: Int, reportsUnchanged: Int, reportConflicts: Int,
                observationsCreated: Int, observationsUnchanged: Int, observationsRevised: Int,
                invalidRows: Int, rowsUsable: Int, rowsMatched: Int, rowsAmbiguous: Int,
                rowsUnmatched: Int, failureReason: String?) {
        self.id = id
        self.sourceName = sourceName
        self.sourceSystem = sourceSystem
        self.status = status
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.sourceReportIDs = sourceReportIDs
        self.groups = groups
        self.reportsCreated = reportsCreated
        self.reportsUnchanged = reportsUnchanged
        self.reportConflicts = reportConflicts
        self.observationsCreated = observationsCreated
        self.observationsUnchanged = observationsUnchanged
        self.observationsRevised = observationsRevised
        self.invalidRows = invalidRows
        self.rowsUsable = rowsUsable
        self.rowsMatched = rowsMatched
        self.rowsAmbiguous = rowsAmbiguous
        self.rowsUnmatched = rowsUnmatched
        self.failureReason = failureReason
    }
}

/// A job not yet written.
public struct LabImportJobDraft: Sendable {
    public var sourceName: String?
    public var sourceSystem: String
    /// `.unresolved` unless the caller already knows why the attempt failed.
    public var status: LabImportStatus
    public var outcome: LabCSVImportResult
    public var failureReason: String?

    public init(sourceName: String? = nil,
                sourceReportIDs: [String],
                sourceSystem: String = LabReportCSVImport.importSourceSystem,
                outcome: LabCSVImportResult,
                status: LabImportStatus = .unresolved,
                failureReason: String? = nil) {
        self.sourceName = sourceName
        self.sourceSystem = sourceSystem
        // `.unresolved` is not a fallback for a missing status. It is the
        // honest answer: the import wrote rows and deliberately did not decide
        // whether they matched, so the job waits for the reconciler.
        self.status = status == .unresolved ? .unresolved : status
        self.outcome = outcome
        self.failureReason = failureReason
        self.sourceReportIDs = sourceReportIDs
    }

    /// The draft's own report keys. Set by `init`; declared here so the stored
    /// form and the draft cannot drift into two different lists.
    public var sourceReportIDs: [String]
}

/// Read and write for `import_job`. A seam over SQL, like every other store.
///
/// Deliberately has no "update the counts" method beyond the reconciler's one:
/// the counts are a derived view, and a store that let a caller set them
/// freely would let a caller write a job that disagrees with the rows behind it.
public struct LabImportJobStore: @unchecked Sendable {
    private let db: Database
    private let clock: any Clock

    public init(db: Database,
                clock: any Clock = SystemClock(),
                sourceSystem: String = LabReportCSVImport.importSourceSystem) {
        self.db = db
        self.clock = clock
        self.sourceSystem = sourceSystem
    }

    private var nowText: String { LabImportJobStore.iso(clock.now) }

    /// Every read of this table selects the same columns. Written out once here
    /// because a fourth hand-copied list is how a column silently stops being
    /// read — the shape of the row and the shape of the queries must move
    /// together.
    static let columns = """
    id, source_name, source_system, status, started_at, finished_at, source_report_ids, \
    groups, reports_created, reports_unchanged, report_conflicts, \
    observations_created, observations_unchanged, observations_revised, \
    invalid_rows, rows_usable, rows_matched, rows_ambiguous, rows_unmatched, failure_reason
    """

    /// Stamped on every job this store writes. The app's importer uses it so a
    /// job and the rows it names are found by the same key; a different
    /// automation can pass its own.
    public let sourceSystem: String

    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    // MARK: - Write

    /// Records that an attempt happened. **This is the one write the import
    /// path must make**, and the reconciler deliberately does not make it: a
    /// reconciler sees laboratory rows and cannot tell an imported one from a
    /// hand-entered one, so a job it reconstructed would be a guess about which
    /// rows came from a file.
    @discardableResult
    public func record(draft: LabImportJobDraft) throws -> Int64 {
        let outcome = draft.outcome
        let now = nowText
        try db.run("""
        INSERT INTO import_job
            (source_name, source_system, status, started_at, finished_at, source_report_ids,
             groups, reports_created, reports_unchanged, report_conflicts,
             observations_created, observations_unchanged, observations_revised,
             invalid_rows, failure_reason)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, [
            draft.sourceName.map { SQLValue.text($0) } ?? .null,
            .text(draft.sourceSystem),
            .text(draft.status.rawValue),
            .text(now),
            // A job written as `.unresolved` has not been reconciled, but the
            // attempt itself did finish — the import returned. Only `.failed`
            // has no finish, and the row counts say why.
            draft.status == .failed ? SQLValue.null : SQLValue.text(now),
            .text(LabImportJobStore.encode(draft.sourceReportIDs)),
            .integer(Int64(outcome.groups)),
            .integer(Int64(outcome.reportsCreated)),
            .integer(Int64(outcome.reportsUnchanged)),
            .integer(Int64(outcome.reportConflicts)),
            .integer(Int64(outcome.observationsCreated)),
            .integer(Int64(outcome.observationsUnchanged)),
            .integer(Int64(outcome.observationsRevised)),
            .integer(Int64(outcome.invalidRowCount)),
            draft.failureReason.map { SQLValue.text($0) } ?? .null
        ])
        guard let row = try db.query("SELECT last_insert_rowid() as id;").first,
              let id = row.int("id") else {
            throw LabImportJobStoreError.insertFailed
        }
        return id
    }

    /// Closes a reconciled job. The only writer of the derived counts, and the
    /// only writer of a status other than the initial one — which is what keeps
    /// "the counts came from the rows" a property of the schema and not a habit.
    ///
    /// `catalogGeneration` is recorded so the job can be recognised as stale
    /// later. Pass the value `LabImportJobReconciler.currentGeneration` returned
    /// at the time; a stale one leaves the job in the queue, a wrong one takes
    /// it out of it.
    public func resolve(id: Int64, counts: LabImportMatchCounts,
                        reportConflicts: Int, invalidRows: Int,
                        catalogGeneration: Int,
                        failureReason: String? = nil) throws {
        let status = LabImportStatus.resolve(counts, invalidRows: invalidRows,
                                             reportConflicts: reportConflicts,
                                             failed: failureReason != nil)
        try db.run("""
        UPDATE import_job
        SET status = ?, rows_usable = ?, rows_matched = ?, rows_ambiguous = ?,
            rows_unmatched = ?, report_conflicts = ?, catalog_generation = ?,
            failure_reason = COALESCE(?, failure_reason)
        WHERE id = ?;
        """, [
            .text(status.rawValue),
            .integer(Int64(counts.rowsUsable)),
            .integer(Int64(counts.matched)),
            .integer(Int64(counts.ambiguous)),
            .integer(Int64(counts.unmatched)),
            .integer(Int64(reportConflicts)),
            .integer(Int64(catalogGeneration)),
            failureReason.map { SQLValue.text($0) } ?? .null,
            .integer(id)
        ])
    }

    /// Writes the reconciled counts of a job that did not run to completion.
    /// Separate from `resolve` so the "counts describe the rows" invariant does
    /// not have to be weakened to allow a zero-row failure.
    public func markFailed(id: Int64, reason: String) throws {
        try db.run("""
        UPDATE import_job SET status = ?, failure_reason = ?, finished_at = ? WHERE id = ?;
        """, [.text(LabImportStatus.failed.rawValue), .text(reason),
              .text(""), .integer(id)])
    }

    // MARK: - Read

    public func job(id: Int64) throws -> LabImportJob? {
        try db.query("""
        SELECT \(LabImportJobStore.columns)
        FROM import_job WHERE id = ?;
        """, [.integer(id)]).first.flatMap(rowToJob)
    }

    /// Newest first. Bounded so an unbounded history cannot become a screen
    /// that costs a full-table read every time it appears.
    public func jobs(limit: Int = 50) throws -> [LabImportJob] {
        guard limit > 0 else { return [] }
        return try db.query("""
        SELECT \(LabImportJobStore.columns)
        FROM import_job ORDER BY started_at DESC, id DESC LIMIT ?;
        """, [.integer(Int64(limit))]).compactMap(rowToJob)
    }

    /// The jobs a person has to do something about, newest first. `.unresolved`
    /// is not one of them: it is this app's own queue, not the person's problem.
    public func jobsNeedingAttention(limit: Int = 50) throws -> [LabImportJob] {
        let statuses = LabImportStatus.allCases.filter(\.needsAttention).map(\.rawValue)
        guard !statuses.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: statuses.count).joined(separator: ", ")
        return try db.query("""
        SELECT \(LabImportJobStore.columns)
        FROM import_job WHERE status IN (\(placeholders))
        ORDER BY started_at DESC, id DESC LIMIT ?;
        """, statuses.map { SQLValue.text($0) } + [.integer(Int64(limit))]).compactMap(rowToJob)
    }

    /// The queue: jobs that have never been reconciled, and jobs whose outcome
    /// was worked out against a catalog older than the one that exists now.
    /// Exposed so a test can assert a job is waiting rather than inferring it
    /// from `job(id:)`'s status.
    ///
    /// The generation comparison is done in SQL against the alias table rather
    /// than in Swift against `currentGeneration`, so the queue is a single
    /// indexed query and the reconciler does not need to count rows itself.
    public func pendingReconciliation() throws -> [LabImportJob] {
        try db.query("""
        SELECT \(LabImportJobStore.columns)
        FROM import_job
        WHERE status = ? OR catalog_generation < (SELECT COUNT(*) FROM lab_catalog_alias)
        ORDER BY id ASC;
        """, [.text(LabImportStatus.pendingReconciliation.rawValue)]).compactMap(rowToJob)
    }

    // MARK: - Private

    private func rowToJob(_ row: Row) -> LabImportJob? {
        guard let id = row.int("id"),
              let statusText = row.string("status"),
              let status = LabImportStatus(rawValue: statusText),
              let startedAt = date(row.string("started_at")) else { return nil }
        return LabImportJob(
            id: id,
            sourceName: row.string("source_name"),
            sourceSystem: row.string("source_system") ?? LabReportCSVImport.importSourceSystem,
            status: status,
            startedAt: startedAt,
            finishedAt: date(row.string("finished_at")),
            sourceReportIDs: decode(row.string("source_report_ids") ?? "[]"),
            groups: Int(row.int("groups") ?? 0),
            reportsCreated: Int(row.int("reports_created") ?? 0),
            reportsUnchanged: Int(row.int("reports_unchanged") ?? 0),
            reportConflicts: Int(row.int("report_conflicts") ?? 0),
            observationsCreated: Int(row.int("observations_created") ?? 0),
            observationsUnchanged: Int(row.int("observations_unchanged") ?? 0),
            observationsRevised: Int(row.int("observations_revised") ?? 0),
            invalidRows: Int(row.int("invalid_rows") ?? 0),
            rowsUsable: Int(row.int("rows_usable") ?? 0),
            rowsMatched: Int(row.int("rows_matched") ?? 0),
            rowsAmbiguous: Int(row.int("rows_ambiguous") ?? 0),
            rowsUnmatched: Int(row.int("rows_unmatched") ?? 0),
            failureReason: row.string("failure_reason")
        )
    }

    private static func encode(_ ids: [String]) -> String {
        guard let data = try? JSONEncoder().encode(ids) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private func decode(_ text: String) -> [String] {
        guard let data = text.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}

public enum LabImportJobStoreError: Error, Sendable {
    case insertFailed
}
