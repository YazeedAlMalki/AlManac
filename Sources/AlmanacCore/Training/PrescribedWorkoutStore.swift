import Foundation

/// A workout template read from storage.
public struct PrescribedWorkoutEntry: Sendable, Hashable, Identifiable {
    public let id: Int64
    public let name: String
    public let containerType: String
    public let notes: String?
    public let deletedAt: String?
    public let createdAt: String
    public let updatedAt: String

    public var isDeleted: Bool { deletedAt != nil }
}

/// Reusable workout templates over `prescribedWorkout`.
///
/// Deliberately thin: a template is a name plus a container shape (§3).
/// The bouts a template prescribes are `workoutBout` rows a session logs
/// against it — there is no separate "template bout" table, so editing a
/// template never rewrites history the way it would if sessions pointed at
/// mutable template rows for their prescribed values.
public struct PrescribedWorkoutStore: @unchecked Sendable {
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

    /// Creates a template.
    ///
    /// `containerType` is validated against `TrainingContainer` rather than left
    /// free, because the column has a CHECK constraint: a value outside the
    /// model's ten would otherwise be a runtime SQL error at the insert instead
    /// of a typed mistake at the call site. The error names the offending value
    /// so the caller can say which one it was.
    @discardableResult
    public func create(name: String, containerType: String, notes: String? = nil) throws -> Int64 {
        guard TrainingContainer(rawValue: containerType) != nil else {
            throw PrescribedWorkoutStoreError.unknownContainerType(containerType)
        }
        let now = nowText
        try db.run("""
        INSERT INTO prescribedWorkout (name, containerType, notes, createdAt, updatedAt)
        VALUES (?, ?, ?, ?, ?);
        """, [.text(name), .text(containerType), notes.map { SQLValue.text($0) } ?? .null, .text(now), .text(now)])

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
        UPDATE prescribedWorkout SET deletedAt = ?, updatedAt = ? WHERE id = ? AND deletedAt IS NULL;
        """, [.text(nowText), .text(nowText), .integer(id)])
        return changes > 0
    }

    /// Live templates, by name.
    ///
    /// Excludes soft-deleted ones. `workout(id:)` deliberately does **not** — a
    /// past session can still name a template that has since been discontinued,
    /// and the review screen needs to be able to say which one that was. Listing
    /// deleted templates as if they were current is the trap; reading one
    /// because a history row points at it is not.
    public func templates() throws -> [PrescribedWorkoutEntry] {
        try db.query("""
        SELECT * FROM prescribedWorkout WHERE deletedAt IS NULL ORDER BY name COLLATE NOCASE;
        """).compactMap(Self.entry(from:))
    }

    public func update(id: Int64, name: String, containerType: String, notes: String?) throws -> Bool {
        try db.run("""
        UPDATE prescribedWorkout SET name = ?, containerType = ?, notes = ?, updatedAt = ?
        WHERE id = ? AND deletedAt IS NULL;
        """, [
            .text(name), .text(containerType),
            notes.map { SQLValue.text($0) } ?? .null,
            .text(nowText), .integer(id)
        ]) > 0
    }

    public func workout(id: Int64) throws -> PrescribedWorkoutEntry? {
        try db.query("SELECT * FROM prescribedWorkout WHERE id = ?;", [.integer(id)])
            .first.flatMap(Self.entry(from:))
    }

    private static func entry(from row: Row) -> PrescribedWorkoutEntry? {
        guard let id = row.int("id"),
              let name = row.string("name"),
              let containerType = row.string("containerType"),
              let createdAt = row.string("createdAt"),
              let updatedAt = row.string("updatedAt") else { return nil }
        return PrescribedWorkoutEntry(id: id, name: name, containerType: containerType,
                                       notes: row.string("notes"), deletedAt: row.string("deletedAt"),
                                       createdAt: createdAt, updatedAt: updatedAt)
    }
}

public enum PrescribedWorkoutStoreError: Error, Sendable, Equatable {
    case unknownContainerType(String)
}
