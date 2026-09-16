import Foundation

/// Fasting session tracking over `fasting_session` — spec §11.1's
/// fast-breaking and backdating rules.
///
/// Backdating scope: a correction looks at the active session first, then
/// (if none) the single most recently *started* ended, non-invalidated
/// session. Reconciling an arbitrary backdated entry against the full
/// session history is not attempted — nothing in the spec's examples needs
/// more than "the session this entry is obviously about."
public struct FastingSessionStore: @unchecked Sendable {
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
    private func iso8601ToDate(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }
    private func minutesBetween(_ a: Date, _ b: Date) -> Int {
        Int((b.timeIntervalSince(a) / 60).rounded())
    }

    // MARK: - Write

    @discardableResult
    public func start(_ draft: FastingSessionDraft, logicalDay: String) throws -> Int64 {
        let createdAt = nowText
        try db.run("""
        INSERT INTO fasting_session
            (startTimestamp, timezoneOffset, logicalDay, sessionType, isDryFast,
             protocol, windowHours, isActive, isInvalidated, correctionHistory, createdAt, updatedAt)
        VALUES (?, ?, ?, ?, ?, ?, ?, 1, 0, '[]', ?, ?);
        """, [
            .text(iso(draft.startTimestamp)),
            draft.timezoneOffset.map { SQLValue.integer(Int64($0)) } ?? .null,
            .text(logicalDay),
            .text(draft.sessionType.rawValue),
            .integer(draft.isDryFast ? 1 : 0),
            draft.protocolName.map { SQLValue.text($0) } ?? .null,
            draft.windowHours.map { SQLValue.real($0) } ?? .null,
            .text(createdAt),
            .text(createdAt)
        ])
        guard let row = try db.query("SELECT last_insert_rowid() as id;").first,
              let id = row.int("id") else {
            throw FastingSessionStoreError.insertFailed
        }
        return id
    }

    /// Applies spec §11.1's fast-breaking / backdating decision tree for one
    /// calorie-bearing nutrition entry. Water and black coffee/tea are
    /// `calories == 0` by definition and never reach the break logic.
    @discardableResult
    public func recordNutritionEntry(calories: Double, at timestamp: Date) throws -> FastingBreakOutcome {
        guard calories > 0 else { return .noOp }

        if let active = try activeSession() {
            if timestamp < active.startTimestamp {
                try invalidate(active, entryTimestamp: timestamp)
                return .invalidated(sessionId: active.id)
            }
            let minutes = try end(active, at: timestamp)
            return .ended(sessionId: active.id, durationMinutes: minutes)
        }

        if let recent = try mostRecentEndedSession() {
            if timestamp < recent.startTimestamp {
                try invalidate(recent, entryTimestamp: timestamp)
                return .invalidated(sessionId: recent.id)
            }
            if let end = recent.endTimestamp, timestamp < end {
                let minutes = try shorten(recent, to: timestamp)
                return .shortened(sessionId: recent.id, durationMinutes: minutes)
            }
        }

        return .noOp
    }

    // MARK: - Read

    public func session(id: Int64) throws -> FastingSession? {
        try db.query("\(selectColumns) FROM fasting_session WHERE id = ?;",
                      [.integer(id)]).first.flatMap(rowToSession)
    }

    public func activeSession() throws -> FastingSession? {
        try db.query("\(selectColumns) FROM fasting_session WHERE isActive = 1 LIMIT 1;")
            .first.flatMap(rowToSession)
    }

    public func sessions(for logicalDay: String) throws -> [FastingSession] {
        try db.query("\(selectColumns) FROM fasting_session WHERE logicalDay = ? ORDER BY startTimestamp;",
                      [.text(logicalDay)]).compactMap(rowToSession)
    }

    // MARK: - Private mutation

    private func end(_ session: FastingSession, at timestamp: Date) throws -> Int {
        let minutes = minutesBetween(session.startTimestamp, timestamp)
        try db.run("""
        UPDATE fasting_session
        SET endTimestamp = ?, isActive = 0, finalDurationMinutes = ?, updatedAt = ?
        WHERE id = ?;
        """, [.text(iso(timestamp)), .integer(Int64(minutes)), .text(nowText), .integer(session.id)])
        return minutes
    }

    private func shorten(_ session: FastingSession, to timestamp: Date) throws -> Int {
        let minutes = minutesBetween(session.startTimestamp, timestamp)
        let history = appendCorrection(to: session, action: .shortened, entryTimestamp: timestamp)
        try db.run("""
        UPDATE fasting_session
        SET endTimestamp = ?, finalDurationMinutes = ?, correctionHistory = ?, updatedAt = ?
        WHERE id = ?;
        """, [.text(iso(timestamp)), .integer(Int64(minutes)), .text(history), .text(nowText), .integer(session.id)])
        return minutes
    }

    /// An invalidated session also stops being "active" — the record it
    /// describes never happened as recorded, so it must not block a new
    /// session from starting (`idx_fasting_session_one_active`) or appear
    /// as an in-progress fast anywhere else.
    private func invalidate(_ session: FastingSession, entryTimestamp: Date) throws {
        let history = appendCorrection(to: session, action: .invalidated, entryTimestamp: entryTimestamp)
        try db.run("""
        UPDATE fasting_session SET isActive = 0, isInvalidated = 1, correctionHistory = ?, updatedAt = ?
        WHERE id = ?;
        """, [.text(history), .text(nowText), .integer(session.id)])
    }

    private func mostRecentEndedSession() throws -> FastingSession? {
        try db.query("""
        \(selectColumns) FROM fasting_session
        WHERE isActive = 0 AND isInvalidated = 0 AND endTimestamp IS NOT NULL
        ORDER BY startTimestamp DESC LIMIT 1;
        """).first.flatMap(rowToSession)
    }

    private func appendCorrection(to session: FastingSession, action: FastingCorrection.Action,
                                   entryTimestamp: Date) -> String {
        let correction = FastingCorrection(action: action, entryTimestamp: entryTimestamp,
                                            previousEndTimestamp: session.endTimestamp, recordedAt: clock.now)
        let history = session.correctionHistory + [correction]
        guard let data = try? JSONEncoder().encode(history),
              let json = String(data: data, encoding: .utf8) else { return "[]" }
        return json
    }

    // MARK: - Private read

    private let selectColumns = """
    SELECT id, startTimestamp, endTimestamp, logicalDay, sessionType, isDryFast, protocol,
           windowHours, isActive, isInvalidated, finalDurationMinutes, correctionHistory,
           createdAt, updatedAt
    """

    private func rowToSession(_ row: Row) -> FastingSession? {
        guard let id = row.int("id"),
              let startText = row.string("startTimestamp"),
              let start = iso8601ToDate(startText),
              let logicalDay = row.string("logicalDay"),
              let sessionTypeText = row.string("sessionType"),
              let sessionType = FastingSessionType(rawValue: sessionTypeText) else { return nil }

        let history: [FastingCorrection] = (row.string("correctionHistory") ?? "[]").data(using: .utf8)
            .flatMap { try? JSONDecoder().decode([FastingCorrection].self, from: $0) } ?? []

        return FastingSession(
            id: id, startTimestamp: start,
            endTimestamp: row.string("endTimestamp").flatMap(iso8601ToDate),
            logicalDay: logicalDay, sessionType: sessionType,
            isDryFast: (row.int("isDryFast") ?? 0) != 0,
            protocolName: row.string("protocol"),
            windowHours: row.double("windowHours"),
            isActive: (row.int("isActive") ?? 0) != 0,
            isInvalidated: (row.int("isInvalidated") ?? 0) != 0,
            finalDurationMinutes: row.int("finalDurationMinutes").map(Int.init),
            correctionHistory: history,
            createdAt: row.string("createdAt").flatMap(iso8601ToDate) ?? Date(),
            updatedAt: row.string("updatedAt").flatMap(iso8601ToDate) ?? Date())
    }
}

public enum FastingSessionStoreError: Error, Sendable {
    case insertFailed
}
