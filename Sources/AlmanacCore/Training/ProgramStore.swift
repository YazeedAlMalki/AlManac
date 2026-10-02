import Foundation

/// A training program read from storage: the split above a day.
public struct TrainingProgramEntry: Sendable, Hashable, Identifiable {
    public let id: Int64
    public let name: String
    public let notes: String?
    public let deletedAt: String?
    public let createdAt: String
    public let updatedAt: String

    public var isDeleted: Bool { deletedAt != nil }
}

/// Storage for `trainingProgram` — "My PPL", "Mobility".
///
/// Thin, like `PrescribedWorkoutStore` and for the same reason: a program is a
/// name and a set of days, and its substance lives in `programDay` and the pool
/// underneath. Putting anything about *what to train* here would be a second
/// home for a prescription that `programDayExercisePool` owns.
///
/// **There is no "active" flag.** Decision 6 is that several programs may be
/// active at once, so there is nothing to arbitrate and nothing to store; a
/// program is in use or it has been deleted.
public struct ProgramStore: @unchecked Sendable {
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
    public func create(name: String, notes: String? = nil) throws -> Int64 {
        // Validated here rather than left to the schema, so the refusal is a typed
        // error naming the problem — the same reasoning `ProgramDayStore.create`
        // gives for `label`, and the reason the column's `NOT NULL` is not enough:
        // it rejects a null, not a blank one.
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ProgramStoreError.emptyName }
        let now = nowText
        try db.run("""
        INSERT INTO trainingProgram (name, notes, createdAt, updatedAt) VALUES (?, ?, ?, ?);
        """, [.text(trimmed), notes.map { SQLValue.text($0) } ?? .null, .text(now), .text(now)])
        var id: Int64 = 0
        if let row = try db.query("SELECT last_insert_rowid() as id;").first,
           let fetchedID = row.int("id") {
            id = fetchedID
        }
        return id
    }

    @discardableResult
    public func update(id: Int64, name: String, notes: String?) throws -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ProgramStoreError.emptyName }
        return try db.run("""
        UPDATE trainingProgram SET name = ?, notes = ?, updatedAt = ?
        WHERE id = ? AND deletedAt IS NULL;
        """, [.text(trimmed), notes.map { SQLValue.text($0) } ?? .null, .text(nowText), .integer(id)]) > 0
    }

    /// Soft delete. Idempotent — returns whether a live row was changed.
    ///
    /// Days and pool items are left in place rather than cascaded. They carry no
    /// independent meaning once the program is gone, and deleting them would
    /// destroy the record of what a past session's prescription actually was,
    /// which is the one thing this schema exists to preserve.
    @discardableResult
    public func delete(id: Int64) throws -> Bool {
        try db.run("""
        UPDATE trainingProgram SET deletedAt = ?, updatedAt = ? WHERE id = ? AND deletedAt IS NULL;
        """, [.text(nowText), .text(nowText), .integer(id)]) > 0
    }

    /// Live programs, by name.
    ///
    /// Excludes soft-deleted ones. `program(id:)` deliberately does not: a past
    /// session can still name a program that has since been deleted, and the
    /// review screen has to be able to say which one that was — the same
    /// asymmetry `PrescribedWorkoutStore.templates()` states for templates.
    public func programs() throws -> [TrainingProgramEntry] {
        try db.query("""
        SELECT * FROM trainingProgram WHERE deletedAt IS NULL ORDER BY name COLLATE NOCASE;
        """).compactMap(TrainingProgramEntry.init(from:))
    }

    public func program(id: Int64) throws -> TrainingProgramEntry? {
        try db.query("SELECT * FROM trainingProgram WHERE id = ?;", [.integer(id)])
            .first.flatMap(TrainingProgramEntry.init(from:))
    }
}

public enum ProgramStoreError: Error, Sendable, Equatable {
    /// A name nobody can act on. A program with an empty label cannot be
    /// chosen at session start, and an unnamed row in a picker is worse than a
    /// refusal at the point it was typed.
    case emptyName
}
