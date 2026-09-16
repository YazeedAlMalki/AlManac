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

    @discardableResult
    public func create(name: String, containerType: String, notes: String? = nil) throws -> Int64 {
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
