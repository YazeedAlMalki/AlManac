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
    /// Which program's day generated this session. Null on every ad-hoc and
    /// HealthKit-derived session.
    public var programDayId: Int64?
    /// Which pass through the day's pool this session was. Advances only on a
    /// completed session, never on a calendar gap (Decision 2).
    public var rotationIndex: Int?
    /// Whether the user chose to factor their readiness score into the
    /// prescription when starting. Records the decision; `false` means "no", or
    /// "nobody was asked" — the same answer either way.
    public var readinessAdjusted: Bool

    public init(date: String, startTimestamp: Date? = nil, endTimestamp: Date? = nil,
                durationMinutes: Int? = nil, rpe: Int? = nil, notes: String? = nil,
                prescribedWorkoutId: Int64? = nil, sessionType: String? = nil,
                programDayId: Int64? = nil, rotationIndex: Int? = nil,
                readinessAdjusted: Bool = false) {
        self.date = date
        self.startTimestamp = startTimestamp
        self.endTimestamp = endTimestamp
        self.durationMinutes = durationMinutes
        self.rpe = rpe
        self.notes = notes
        self.prescribedWorkoutId = prescribedWorkoutId
        self.sessionType = sessionType
        self.programDayId = programDayId
        self.rotationIndex = rotationIndex
        self.readinessAdjusted = readinessAdjusted
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
    /// Which program's day generated this session, and which pass through its
    /// pool this was. Both null on an ad-hoc or HealthKit-derived session.
    public let programDayId: Int64?
    public let rotationIndex: Int?
    /// Whether the user said yes to "Factor in your readiness score?" when
    /// starting this session.
    public let readinessAdjusted: Bool
    public let deletedAt: String?
    public let createdAt: String
    public let updatedAt: String

    /// The three program columns default to "no program", so an ad-hoc session —
    /// and every session logged before Migration049 — is expressible without
    /// naming them. Absent is the overwhelmingly common case and should not cost
    /// every construction site three arguments.
    public init(id: Int64, date: String, startTimestamp: String? = nil,
                endTimestamp: String? = nil, durationMinutes: Int? = nil,
                rpe: Int? = nil, notes: String? = nil, prescribedWorkoutId: Int64? = nil,
                sessionType: String? = nil, healthKitUUID: String? = nil, source: String? = nil,
                programDayId: Int64? = nil, rotationIndex: Int? = nil,
                readinessAdjusted: Bool = false, deletedAt: String? = nil,
                createdAt: String = "", updatedAt: String = "") {
        self.id = id
        self.date = date
        self.startTimestamp = startTimestamp
        self.endTimestamp = endTimestamp
        self.durationMinutes = durationMinutes
        self.rpe = rpe
        self.notes = notes
        self.prescribedWorkoutId = prescribedWorkoutId
        self.sessionType = sessionType
        self.healthKitUUID = healthKitUUID
        self.source = source
        self.programDayId = programDayId
        self.rotationIndex = rotationIndex
        self.readinessAdjusted = readinessAdjusted
        self.deletedAt = deletedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var isDeleted: Bool { deletedAt != nil }

    /// True when the user logged this session themselves, so a manually logged
    /// bout belongs here rather than on a watch-derived one.
    public var isOwnLog: Bool { healthKitUUID == nil }

    /// True when this session was generated from a program's day pool, so its
    /// rotation index is a real position in a cycle rather than absent.
    public var isFromProgram: Bool { programDayId != nil && rotationIndex != nil }
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
             prescribedWorkoutId, sessionType, programDayId, rotationIndex, readinessAdjusted,
             createdAt, updatedAt)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, [
            .text(draft.date),
            draft.startTimestamp.map { SQLValue.text(iso($0)) } ?? .null,
            draft.endTimestamp.map { SQLValue.text(iso($0)) } ?? .null,
            draft.durationMinutes.map { SQLValue.integer(Int64($0)) } ?? .null,
            draft.rpe.map { SQLValue.integer(Int64($0)) } ?? .null,
            draft.notes.map { SQLValue.text($0) } ?? .null,
            draft.prescribedWorkoutId.map { SQLValue.integer($0) } ?? .null,
            draft.sessionType.map { SQLValue.text($0) } ?? .null,
            draft.programDayId.map { SQLValue.integer($0) } ?? .null,
            draft.rotationIndex.map { SQLValue.integer(Int64($0)) } ?? .null,
            .integer(draft.readinessAdjusted ? 1 : 0),
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

    /// Records which template a session was filled from. Only sets it where
    /// none is recorded, so the first template applied names the session.
    @discardableResult
    public func setTemplateIfUnset(id: Int64, prescribedWorkoutId: Int64) throws -> Bool {
        try db.run("""
            UPDATE workoutSession SET prescribedWorkoutId = ?, updatedAt = ?
            WHERE id = ? AND deletedAt IS NULL AND prescribedWorkoutId IS NULL;
            """, [.integer(prescribedWorkoutId), .text(nowText), .integer(id)]) > 0
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

    /// Live sessions across a logical-day range `[from, to)`, newest day first.
    ///
    /// The read a past-days review needs. Without it a screen has to ask once
    /// per day and stitch the results, which is how a review screen ends up
    /// silently showing fewer days than it says it does when one query throws.
    public func sessions(from: String, to: String) throws -> [WorkoutSessionEntry] {
        try db.query("""
        SELECT * FROM workoutSession
        WHERE date >= ? AND date < ? AND deletedAt IS NULL
        ORDER BY date DESC, id;
        """, [.text(from), .text(to)]).compactMap(Self.entry(from:))
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
            programDayId: row.int("programDayId"),
            rotationIndex: row.int("rotationIndex").map(Int.init),
            readinessAdjusted: row.int("readinessAdjusted") == 1,
            deletedAt: row.string("deletedAt"), createdAt: createdAt, updatedAt: updatedAt
        )
    }
}
