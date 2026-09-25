import Foundation

/// A workout session not yet written to storage.
public struct WorkoutSessionDraft: Sendable {
    public var date: String  // logical day, YYYY-MM-DD
    public var startTimestamp: Date?
    public var endTimestamp: Date?
    public var durationMinutes: Int?
    public var rpe: Int?  // 1-10, session-level
    public var notes: String?
    public var prescribedWorkoutId: Int64?
    /// The user-selected sport/activity ("CrossFit", "football", "running", ...).
    public var sessionType: String?

    public init(date: String, startTimestamp: Date? = nil, endTimestamp: Date? = nil,
                durationMinutes: Int? = nil, rpe: Int? = nil, notes: String? = nil,
                prescribedWorkoutId: Int64? = nil, sessionType: String? = nil) {
        self.date = date
        self.startTimestamp = startTimestamp
        self.endTimestamp = endTimestamp
        self.durationMinutes = durationMinutes
        self.rpe = rpe
        self.notes = notes
        self.prescribedWorkoutId = prescribedWorkoutId
        self.sessionType = sessionType
    }
}

/// A workout session read from storage.
public struct WorkoutSessionEntry: Sendable, Hashable, Identifiable {
    public let id: Int64
    public let date: String
    public let startTimestamp: String?
    public let endTimestamp: String?
    public let durationMinutes: Int?
    public let rpe: Int?
    public let notes: String?
    public let prescribedWorkoutId: Int64?
    public let sessionType: String?
    /// Set when a HealthKit workout has been linked to this session. Null on
    /// every session the user logged themselves — including one a workout was
    /// later linked to and then unlinked from.
    public let healthKitUUID: String?
    /// Who *created* the row: `"healthkit"` for a session auto-logged from a
    /// watch workout, null for the user's own. Distinct from `healthKitUUID`,
    /// which records only that a link exists.
    public let source: String?
    public let deletedAt: String?
    public let createdAt: String
    public let updatedAt: String

    public var isDeleted: Bool { deletedAt != nil }

    /// True when the user logged this session themselves, so a manually logged
    /// bout belongs here rather than on a watch-derived one.
    public var isOwnLog: Bool { healthKitUUID == nil }
}

/// Completed-session storage over `workoutSession`.
public struct WorkoutSessionStore: @unchecked Sendable {
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

    @discardableResult
    public func log(_ draft: WorkoutSessionDraft) throws -> Int64 {
        let now = nowText
        try db.run("""
        INSERT INTO workoutSession
            (date, startTimestamp, endTimestamp, durationMinutes, rpe, notes,
             prescribedWorkoutId, sessionType, createdAt, updatedAt)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, [
            .text(draft.date),
            draft.startTimestamp.map { SQLValue.text(iso($0)) } ?? .null,
            draft.endTimestamp.map { SQLValue.text(iso($0)) } ?? .null,
            draft.durationMinutes.map { SQLValue.integer(Int64($0)) } ?? .null,
            draft.rpe.map { SQLValue.integer(Int64($0)) } ?? .null,
            draft.notes.map { SQLValue.text($0) } ?? .null,
            draft.prescribedWorkoutId.map { SQLValue.integer($0) } ?? .null,
            draft.sessionType.map { SQLValue.text($0) } ?? .null,
            .text(now), .text(now)
        ])
        var id: Int64 = 0
        if let row = try db.query("SELECT last_insert_rowid() as id;").first,
           let fetchedID = row.int("id") {
            id = fetchedID
        }
        return id
    }

    @discardableResult
    public func delete(id: Int64) throws -> Bool {
        let changes = try db.run("""
        UPDATE workoutSession SET deletedAt = ?, updatedAt = ? WHERE id = ? AND deletedAt IS NULL;
        """, [.text(nowText), .text(nowText), .integer(id)])
        return changes > 0
    }

    public func updateDate(id: Int64, to date: String) throws -> Bool {
        try db.run("""
            UPDATE workoutSession SET date = ?, updatedAt = ?
            WHERE id = ? AND deletedAt IS NULL;
            """, [.text(date), .text(nowText), .integer(id)]) > 0
    }

    // MARK: - Read

    public func session(id: Int64) throws -> WorkoutSessionEntry? {
        try db.query("SELECT * FROM workoutSession WHERE id = ?;", [.integer(id)])
            .first.flatMap(Self.entry(from:))
    }

    /// Live sessions on a given logical day, most recent first.
    public func sessions(date: String) throws -> [WorkoutSessionEntry] {
        try db.query("""
        SELECT * FROM workoutSession WHERE date = ? AND deletedAt IS NULL ORDER BY id;
        """, [.text(date)]).compactMap(Self.entry(from:))
    }

    // MARK: - Private

    private static func entry(from row: Row) -> WorkoutSessionEntry? {
        guard let id = row.int("id"),
              let date = row.string("date"),
              let createdAt = row.string("createdAt"),
              let updatedAt = row.string("updatedAt") else { return nil }
        return WorkoutSessionEntry(
            id: id, date: date,
            startTimestamp: row.string("startTimestamp"), endTimestamp: row.string("endTimestamp"),
            durationMinutes: row.int("durationMinutes").map(Int.init), rpe: row.int("rpe").map(Int.init),
            notes: row.string("notes"), prescribedWorkoutId: row.int("prescribedWorkoutId"),
            sessionType: row.string("sessionType"),
            healthKitUUID: row.string("healthKitUUID"), source: row.string("source"),
            deletedAt: row.string("deletedAt"), createdAt: createdAt, updatedAt: updatedAt
        )
    }
}
