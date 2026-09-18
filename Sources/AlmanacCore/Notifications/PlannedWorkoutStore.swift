import Foundation

/// A planned workout not yet written to storage.
public struct PlannedWorkoutDraft: Sendable {
    public var scheduledAt: Date
    public var prescribedWorkoutId: Int64?
    public var notes: String?

    public init(scheduledAt: Date, prescribedWorkoutId: Int64? = nil, notes: String? = nil) {
        self.scheduledAt = scheduledAt
        self.prescribedWorkoutId = prescribedWorkoutId
        self.notes = notes
    }
}

/// A `planned_workout` row read from storage.
public struct PlannedWorkout: Sendable, Hashable, Identifiable {
    public let id: Int64
    public let scheduledAt: Date
    public let prescribedWorkoutId: Int64?
    public let notes: String?
    public let createdAt: Date
    public let updatedAt: Date
}

/// CRUD over `planned_workout` (Migration031). Deliberately thin — see the
/// migration's own doc comment for why this doesn't grow into a full
/// scheduling feature (no status, no recurrence, no cancellation state).
/// `nextUpcoming(after:)` is the one query
/// `NotificationTriggerAssembler.preWorkoutSnackTrigger` actually needs;
/// everything else is ordinary CRUD.
public struct PlannedWorkoutStore: @unchecked Sendable {
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

    @discardableResult
    public func create(_ draft: PlannedWorkoutDraft) throws -> Int64 {
        let createdAt = nowText
        try db.run("""
        INSERT INTO planned_workout (scheduledAt, prescribedWorkoutId, notes, createdAt, updatedAt)
        VALUES (?, ?, ?, ?, ?);
        """, [
            .text(iso(draft.scheduledAt)),
            draft.prescribedWorkoutId.map { SQLValue.integer($0) } ?? .null,
            draft.notes.map { SQLValue.text($0) } ?? .null,
            .text(createdAt),
            .text(createdAt)
        ])

        guard let row = try db.query("SELECT last_insert_rowid() as id;").first,
              let id = row.int("id") else {
            throw PlannedWorkoutStoreError.insertFailed
        }
        return id
    }

    public func delete(id: Int64) throws {
        try db.run("DELETE FROM planned_workout WHERE id = ?;", [.integer(id)])
    }

    public func planned(id: Int64) throws -> PlannedWorkout? {
        try db.query("""
        SELECT id, scheduledAt, prescribedWorkoutId, notes, createdAt, updatedAt
        FROM planned_workout WHERE id = ?;
        """, [.integer(id)]).first.flatMap(rowToPlanned)
    }

    /// The soonest planned workout with `scheduledAt > after` — the "next
    /// planned workout" the pre-workout snack trigger needs. A workout
    /// scheduled at or before `after` is treated as already underway or
    /// past, not upcoming.
    public func nextUpcoming(after: Date) throws -> PlannedWorkout? {
        try db.query("""
        SELECT id, scheduledAt, prescribedWorkoutId, notes, createdAt, updatedAt
        FROM planned_workout WHERE scheduledAt > ?
        ORDER BY scheduledAt ASC LIMIT 1;
        """, [.text(iso(after))]).first.flatMap(rowToPlanned)
    }

    private func rowToPlanned(_ row: Row) -> PlannedWorkout? {
        guard let id = row.int("id"),
              let scheduledAt = row.string("scheduledAt").flatMap(iso8601ToDate),
              let createdAt = row.string("createdAt").flatMap(iso8601ToDate),
              let updatedAt = row.string("updatedAt").flatMap(iso8601ToDate) else { return nil }
        return PlannedWorkout(
            id: id, scheduledAt: scheduledAt,
            prescribedWorkoutId: row.int("prescribedWorkoutId"),
            notes: row.string("notes"),
            createdAt: createdAt, updatedAt: updatedAt)
    }

    private func iso8601ToDate(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }
}

public enum PlannedWorkoutStoreError: Error, Sendable {
    case insertFailed
}
