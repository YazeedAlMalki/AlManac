import Foundation

/// A `readiness_record` row read from storage — the persisted form of a
/// `ReadinessOutcome`, plus the feedback fields `ReadinessEngine` never
/// touches.
public struct StoredReadinessRecord: Sendable, Hashable, Identifiable {
    public let id: Int64
    public let readinessCycleId: Int64
    public let anchorDate: String
    public let state: ReadinessState
    public let score: Int?
    public let colorGrade: ReadinessColor
    public let textDescription: String?
    public let confidence: ReadinessConfidence
    public let missingInputs: [ReadinessInputKind]
    public let formulaVersion: String
    public let inputSnapshot: String
    public let calculationTimestamp: Date
    public let recommendation: String?
    public let precedenceApplied: [ReadinessPrecedence]
    /// `"thumbs_up" | "thumbs_down"`, or nil if not yet rated. Not a `Bool` —
    /// see `readiness_record.feedbackValue` (§5.23) and §9.10 on timing.
    public let feedbackValue: String?
    public let feedbackTimestamp: Date?
    public let baselineContext: ReadinessBaselineContext
    public let createdAt: Date
    public let updatedAt: Date
}

/// Persists `ReadinessOutcome` (the pure `ReadinessEngine` result) into
/// `readiness_record`, and separately records the §9.10 feedback that
/// arrives later, on its own schedule, from a different screen.
///
/// One row per cycle: `record(_:cycleId:anchorDate:)` is an upsert keyed on
/// `readinessCycleId` (Migration023's unique index) — a cycle's provisional
/// score, and every recomputation of it, replaces the same row rather than
/// accumulating a history. §9.9's "historical records are never silently
/// rewritten" is about the *formula* changing under an old cycle, not about
/// the same cycle being re-evaluated as its own day's inputs arrive; that
/// distinction is why this upserts instead of appending.
public struct ReadinessRecordStore: @unchecked Sendable {
    let db: Database
    private let clock: any Clock

    public init(db: Database, clock: any Clock = SystemClock()) {
        self.db = db
        self.clock = clock
    }

    private var nowText: String { iso(clock.now) }
    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    // MARK: - Write

    public func record(_ outcome: ReadinessOutcome, cycleId: Int64, anchorDate: String) throws {
        let now = nowText
        try db.run("""
        INSERT INTO readiness_record
            (readinessCycleId, anchorDate, state, score, colorGrade, textDescription, confidence,
             missingInputs, formulaVersion, inputSnapshot, calculationTimestamp, recommendation,
             precedenceApplied, baselineContext, createdAt, updatedAt)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(readinessCycleId) DO UPDATE SET
            anchorDate = excluded.anchorDate,
            state = excluded.state,
            score = excluded.score,
            colorGrade = excluded.colorGrade,
            textDescription = excluded.textDescription,
            confidence = excluded.confidence,
            missingInputs = excluded.missingInputs,
            formulaVersion = excluded.formulaVersion,
            inputSnapshot = excluded.inputSnapshot,
            calculationTimestamp = excluded.calculationTimestamp,
            recommendation = excluded.recommendation,
            precedenceApplied = excluded.precedenceApplied,
            baselineContext = excluded.baselineContext,
            updatedAt = excluded.updatedAt;
        """, [
            .integer(cycleId),
            .text(anchorDate),
            .text(outcome.state.rawValue),
            outcome.score.map { SQLValue.integer(Int64($0)) } ?? .null,
            .text(outcome.color.rawValue),
            outcome.textDescription.map { SQLValue.text($0) } ?? .null,
            .text(outcome.confidence.rawValue),
            .text(jsonArray(outcome.missingInputs.map(\.rawValue))),
            .text(outcome.formulaVersion),
            .text(outcome.inputSnapshot),
            .text(now),
            outcome.recommendation.map { SQLValue.text($0) } ?? .null,
            .text(jsonArray(outcome.precedenceApplied.map(\.rawValue))),
            .text(outcome.baselineContext.rawValue),
            .text(now),
            .text(now)
        ])
    }

    /// `"thumbs_up"` or `"thumbs_down"` (§5.23). Stamps `feedbackTimestamp`
    /// to now.
    public func setFeedback(cycleId: Int64, value: String) throws {
        try db.run("""
        UPDATE readiness_record SET feedbackValue = ?, feedbackTimestamp = ?, updatedAt = ?
        WHERE readinessCycleId = ?;
        """, [.text(value), .text(nowText), .text(nowText), .integer(cycleId)])
    }

    // MARK: - Read

    public func record(cycleId: Int64) throws -> StoredReadinessRecord? {
        try db.query("""
        \(Self.columns) FROM readiness_record WHERE readinessCycleId = ?;
        """, [.integer(cycleId)]).first.flatMap(rowToRecord)
    }

    /// The most recent scored record strictly before `anchorDate` that has no
    /// feedback yet — what a feedback prompt shown "at the start of the next
    /// cycle" (§9.10) should ask about. A record with no score (insufficient
    /// data) is never offered: there is no outcome to react to.
    public func latestUnratedRecord(before anchorDate: String) throws -> StoredReadinessRecord? {
        try db.query("""
        \(Self.columns) FROM readiness_record
        WHERE anchorDate < ? AND score IS NOT NULL AND feedbackValue IS NULL
        ORDER BY anchorDate DESC LIMIT 1;
        """, [.text(anchorDate)]).first.flatMap(rowToRecord)
    }

    // MARK: - Private

    private static let columns = """
        SELECT id, readinessCycleId, anchorDate, state, score, colorGrade, textDescription, confidence,
               missingInputs, formulaVersion, inputSnapshot, calculationTimestamp, recommendation,
               precedenceApplied, feedbackValue, feedbackTimestamp, baselineContext, createdAt, updatedAt
        """

    private func jsonArray(_ values: [String]) -> String {
        let data = try? JSONEncoder().encode(values)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    private func decodeJSONArray(_ text: String?) -> [String] {
        guard let text, let data = text.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return values
    }

    private func rowToRecord(_ row: Row) -> StoredReadinessRecord? {
        guard let id = row.int("id"),
              let readinessCycleId = row.int("readinessCycleId"),
              let anchorDate = row.string("anchorDate"),
              let stateText = row.string("state"), let state = ReadinessState(rawValue: stateText),
              let confidenceText = row.string("confidence"),
              let confidence = ReadinessConfidence(rawValue: confidenceText),
              let formulaVersion = row.string("formulaVersion"),
              let inputSnapshot = row.string("inputSnapshot"),
              let calculationTimestamp = row.string("calculationTimestamp").flatMap(iso8601ToDate),
              let baselineContextText = row.string("baselineContext"),
              let baselineContext = ReadinessBaselineContext(rawValue: baselineContextText),
              let createdAt = row.string("createdAt").flatMap(iso8601ToDate),
              let updatedAt = row.string("updatedAt").flatMap(iso8601ToDate) else { return nil }

        let colorGrade = row.string("colorGrade").flatMap(ReadinessColor.init(rawValue:)) ?? .none

        return StoredReadinessRecord(
            id: id,
            readinessCycleId: readinessCycleId,
            anchorDate: anchorDate,
            state: state,
            score: row.int("score").map(Int.init),
            colorGrade: colorGrade,
            textDescription: row.string("textDescription"),
            confidence: confidence,
            missingInputs: decodeJSONArray(row.string("missingInputs")).compactMap(ReadinessInputKind.init(rawValue:)),
            formulaVersion: formulaVersion,
            inputSnapshot: inputSnapshot,
            calculationTimestamp: calculationTimestamp,
            recommendation: row.string("recommendation"),
            precedenceApplied: decodeJSONArray(row.string("precedenceApplied")).compactMap(ReadinessPrecedence.init(rawValue:)),
            feedbackValue: row.string("feedbackValue"),
            feedbackTimestamp: row.string("feedbackTimestamp").flatMap(iso8601ToDate),
            baselineContext: baselineContext,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func iso8601ToDate(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }
}
