import Foundation

/// Fasting session tracking over `fasting_session` — spec §11.1's
/// fast-breaking and backdating rules.
///
/// Backdating scope: a correction looks at the active session first, then
/// (if none) the single most recently *started* ended, non-invalidated
/// session. Reconciling an arbitrary backdated entry against the full
/// session history is not attempted — nothing in the spec's examples needs
/// more than "the session this entry is obviously about."
///
/// **§11.1's decision tree is intermittent fasting's, and religious sessions
/// are outside it.** A religious fast is Fajr→Maghrib by definition, so a meal
/// before its start is suhoor, not a backdated entry that proves the fast never
/// happened. Applying the IF tree to one invalidated the day's fast every time
/// suhoor was logged after the session existed. Religious sessions are kept
/// right by `ReligiousFastingService.ensureDay`, which derives them from the
/// prayer times and the intake log; `recordIntake` is the one rule here that
/// touches them, for the moment between a drink and the next derivation.
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

    /// Any intake at all — water included — against an active *religious dry
    /// fast*, which the owner's call (2026-09-29) treats differently from an
    /// intermittent fast: a dry fast that was drunk from is not a fast that was
    /// kept, so the session ends and records the real duration rather than
    /// claiming a completed fast. §11.1's rules were written for IF and do not
    /// cover this, which is why this is a separate method rather than a flag on
    /// `recordNutritionEntry`.
    ///
    /// Non-dry and IF sessions are `.noOp` here: water never breaks those, and
    /// `recordNutritionEntry` already owns the calorie-bearing case for them.
    ///
    /// An intake before the session's start is suhoor and changes nothing — the
    /// old version ended the fast "at" a time before it began, with a negative
    /// duration.
    @discardableResult
    public func recordIntake(at timestamp: Date) throws -> FastingBreakOutcome {
        guard let active = try activeSession(),
              active.sessionType == .religious, active.isDryFast,
              timestamp >= active.startTimestamp else { return .noOp }
        let minutes = try end(active, at: timestamp)
        return .ended(sessionId: active.id, durationMinutes: minutes)
    }

    /// Applies spec §11.1's fast-breaking / backdating decision tree for one
    /// calorie-bearing nutrition entry. Water and black coffee/tea are
    /// `calories == 0` by definition and never reach the break logic.
    @discardableResult
    public func recordNutritionEntry(calories: Double, at timestamp: Date) throws -> FastingBreakOutcome {
        guard calories > 0 else { return .noOp }

        if let active = try activeIntermittentSession() {
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

    /// Reconciles an edit to the meal that previously ended the most recent
    /// session. The normal edit case is reversible: if that meal is no longer
    /// calorie-bearing, reopen the session; if it still is, reopen first and
    /// apply the new occurrence through the ordinary decision tree.
    ///
    /// This deliberately follows the existing active/recent-session scope. A
    /// full historical rebuild would need a durable link from every correction
    /// to its nutrition-log id, which this store does not yet have.
    @discardableResult
    public func reconcileNutritionEdit(
        previousCalories: Double,
        previousTimestamp: Date,
        currentCalories: Double,
        currentTimestamp: Date
    ) throws -> FastingBreakOutcome {
        if let ended = try mostRecentEndedSession() {
            let correction = ended.correctionHistory.last(where: {
                ($0.action == .shortened || $0.action == .extended)
                    && $0.entryTimestamp == previousTimestamp
            })
            let normallyEnded = previousCalories > 0 && ended.endTimestamp == previousTimestamp
            if normallyEnded || correction != nil {
                guard try activeSession() == nil else { return .noOp }
                let restoredEnd = correction?.previousEndTimestamp
                if let restoredEnd {
                    try restore(ended, to: restoredEnd)
                } else {
                    try reopen(ended)
                }
                guard currentCalories > 0 else { return .restored(sessionId: ended.id) }
                if let restoredEnd, currentTimestamp > restoredEnd {
                    let minutes = try extend(ended, from: restoredEnd, at: currentTimestamp)
                    return .ended(sessionId: ended.id, durationMinutes: minutes)
                }
                return try recordNutritionEntry(calories: currentCalories, at: currentTimestamp)
            }
        }

        if previousCalories > 0,
           let invalidated = try invalidatedSession(affectedBy: previousTimestamp) {
            guard try activeSession() == nil else { return .noOp }
            let restoredEnd = try restore(invalidated, previousTimestamp: previousTimestamp)
            guard currentCalories > 0 else { return .restored(sessionId: invalidated.id) }
            if let restoredEnd, currentTimestamp > restoredEnd {
                // The old session had already ended before this meal was
                // backdated. Moving the meal later does not extend that fast.
                return .noOp
            }
            return try recordNutritionEntry(calories: currentCalories, at: currentTimestamp)
        }

        return try recordNutritionEntry(calories: currentCalories, at: currentTimestamp)
    }

    /// A scheduled, non-break end for a fast — §11.2's "at Maghrib(D), set
    /// `endTimestamp = Maghrib(D)`, `isActive = 0`." Unlike
    /// `recordNutritionEntry`'s break/invalidate/shorten decision tree, this
    /// isn't a correction: no calorie entry is involved, so nothing is
    /// appended to `correctionHistory`. Used by `ReligiousFastingService`.
    @discardableResult
    public func endScheduled(id: Int64, at timestamp: Date) throws -> Int {
        guard let session = try session(id: id) else { throw FastingSessionStoreError.notFound }
        return try end(session, at: timestamp)
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

    /// The active session when it is an intermittent one — what §11.1's
    /// break/backdate rules and the IF controls act on.
    public func activeIntermittentSession() throws -> FastingSession? {
        try activeSession().flatMap { $0.sessionType == .religious ? nil : $0 }
    }

    public func sessions(for logicalDay: String) throws -> [FastingSession] {
        try db.query("\(selectColumns) FROM fasting_session WHERE logicalDay = ? ORDER BY startTimestamp;",
                      [.text(logicalDay)]).compactMap(rowToSession)
    }

    /// The newest sessions first, invalidated ones included so a history can
    /// say so rather than hide them.
    public func recentSessions(limit: Int = 10) throws -> [FastingSession] {
        try db.query("\(selectColumns) FROM fasting_session ORDER BY startTimestamp DESC LIMIT ?;",
                     [.integer(Int64(limit))]).compactMap(rowToSession)
    }

    /// The intermittent session a screen should be about: the active one, or
    /// else the most recently started one — whatever logical day it began on.
    /// Looking an IF fast up by today's logical day was the bug: a fast started
    /// at 20:00 belongs to yesterday, so it vanished from the screen at 04:00
    /// while it was still running, and "Start" was offered over it.
    public func latestIntermittentSession() throws -> FastingSession? {
        try db.query("""
        \(selectColumns) FROM fasting_session
        WHERE sessionType != 'religious'
        ORDER BY isActive DESC, startTimestamp DESC LIMIT 1;
        """).first.flatMap(rowToSession)
    }

    /// The most recent calorie-free stretch's start for a confirmed suggestion
    /// (§11.1: "startTimestamp set to the timestamp of the last nutrition log").
    @discardableResult
    public func startConfirmedSuggestion(lastNutritionLogAt: Date, logicalDay: String,
                                         timezoneOffset: Int?) throws -> Int64 {
        try start(FastingSessionDraft(startTimestamp: lastNutritionLogAt, sessionType: .ifConfirmedSuggestion,
                                      timezoneOffset: timezoneOffset),
                  logicalDay: logicalDay)
    }

    // MARK: - Religious maintenance (ReligiousFastingService only)

    /// Moves a religious session's start, when the day's Fajr was recalculated
    /// (a new location, method or offset). Duration follows if it has ended.
    func moveStart(id: Int64, to start: Date) throws {
        guard let session = try session(id: id) else { throw FastingSessionStoreError.notFound }
        let duration: SQLValue = session.endTimestamp
            .map { .integer(Int64(minutesBetween(start, $0))) } ?? .null
        try db.run("""
        UPDATE fasting_session SET startTimestamp = ?, finalDurationMinutes = ?, updatedAt = ? WHERE id = ?;
        """, [.text(iso(start)), duration, .text(nowText), .integer(id)])
    }

    /// Sets a religious session to exactly the derived state: ended at `end`,
    /// or open when `end` is nil. Clears any invalidation an older build's IF
    /// rules wrongly applied to it.
    func setDerivedEnd(id: Int64, end: Date?) throws {
        guard let session = try session(id: id) else { throw FastingSessionStoreError.notFound }
        let endValue: SQLValue = end.map { .text(iso($0)) } ?? .null
        let duration: SQLValue = end.map { .integer(Int64(minutesBetween(session.startTimestamp, $0))) } ?? .null
        try db.run("""
        UPDATE fasting_session
        SET endTimestamp = ?, isActive = ?, isInvalidated = 0, finalDurationMinutes = ?, updatedAt = ?
        WHERE id = ?;
        """, [endValue, .integer(end == nil ? 1 : 0), duration, .text(nowText), .integer(id)])
    }

    /// Removes a session the calendar created for a day that is no longer a
    /// fast day — the user said so. It was derived state, and every input it
    /// was derived from (schedule, correction, prayer times, intake) is kept.
    func delete(id: Int64) throws {
        try db.run("DELETE FROM fasting_session WHERE id = ?;", [.integer(id)])
    }

    // MARK: - Private mutation

    private func reopen(_ session: FastingSession) throws {
        try db.run("""
        UPDATE fasting_session
        SET endTimestamp = NULL, isActive = 1, finalDurationMinutes = NULL, updatedAt = ?
        WHERE id = ?;
        """, [.text(nowText), .integer(session.id)])
    }

    private func restore(_ session: FastingSession, previousTimestamp: Date) throws -> Date? {
        let correction = session.correctionHistory.last {
            $0.action == .invalidated && $0.entryTimestamp == previousTimestamp
        }
        let previousEnd = correction?.previousEndTimestamp
        try restore(session, to: previousEnd)
        return previousEnd
    }

    private func restore(_ session: FastingSession, to previousEnd: Date?) throws {
        let endValue: SQLValue = previousEnd.map { .text(iso($0)) } ?? .null
        let duration: SQLValue = previousEnd.map { .integer(Int64(minutesBetween(session.startTimestamp, $0))) } ?? .null
        try db.run("""
        UPDATE fasting_session
        SET endTimestamp = ?, isActive = ?, isInvalidated = 0,
            finalDurationMinutes = ?, updatedAt = ?
        WHERE id = ?;
        """, [endValue, .integer(previousEnd == nil ? 1 : 0), duration,
              .text(nowText), .integer(session.id)])
    }

    private func extend(_ session: FastingSession, from previousEnd: Date, at timestamp: Date) throws -> Int {
        let minutes = minutesBetween(session.startTimestamp, timestamp)
        let history = appendCorrection(to: session, action: .extended, entryTimestamp: timestamp,
                                       previousEndTimestamp: previousEnd)
        try db.run("""
        UPDATE fasting_session
        SET endTimestamp = ?, finalDurationMinutes = ?, correctionHistory = ?, updatedAt = ?
        WHERE id = ?;
        """, [.text(iso(timestamp)), .integer(Int64(minutes)), .text(history),
              .text(nowText), .integer(session.id)])
        return minutes
    }

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
          AND sessionType != 'religious'
        ORDER BY startTimestamp DESC LIMIT 1;
        """).first.flatMap(rowToSession)
    }

    private func invalidatedSession(affectedBy timestamp: Date) throws -> FastingSession? {
        try db.query("""
        \(selectColumns) FROM fasting_session
        WHERE isInvalidated = 1 AND sessionType != 'religious'
        ORDER BY startTimestamp DESC;
        """).compactMap(rowToSession).first {
            $0.correctionHistory.contains {
                $0.action == .invalidated && $0.entryTimestamp == timestamp
            }
        }
    }

    private func appendCorrection(to session: FastingSession, action: FastingCorrection.Action,
                                   entryTimestamp: Date,
                                   previousEndTimestamp: Date? = nil) -> String {
        let correction = FastingCorrection(action: action, entryTimestamp: entryTimestamp,
                                            previousEndTimestamp: previousEndTimestamp ?? session.endTimestamp,
                                            recordedAt: clock.now)
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
    case notFound
}
