import Foundation

/// One day of a training program, read from storage.
public struct ProgramDayEntry: Sendable, Hashable, Identifiable {
    public let id: Int64
    public let programId: Int64
    /// "Push", "Pull", "Legs" — the user's own name for it, not an enum.
    public let label: String
    public let deletedAt: String?
    public let createdAt: String
    public let updatedAt: String

    public var isDeleted: Bool { deletedAt != nil }
}

/// Storage for `programDay`.
///
/// One part of a split. `label` is free text rather than a closed set, because
/// "Push / Pull / Legs" is one program's vocabulary and not the app's — a
/// mobility routine's days are called something else entirely, and the only
/// thing every program's days share is that a person names them.
public struct ProgramDayStore: @unchecked Sendable {
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
    public func create(programId: Int64, label: String) throws -> Int64 {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ProgramDayStoreError.emptyLabel }
        let now = nowText
        try db.run("""
        INSERT INTO programDay (programId, label, createdAt, updatedAt) VALUES (?, ?, ?, ?);
        """, [.integer(programId), .text(trimmed), .text(now), .text(now)])
        var id: Int64 = 0
        if let row = try db.query("SELECT last_insert_rowid() as id;").first,
           let fetchedID = row.int("id") {
            id = fetchedID
        }
        return id
    }

    @discardableResult
    public func update(id: Int64, label: String) throws -> Bool {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ProgramDayStoreError.emptyLabel }
        return try db.run("""
        UPDATE programDay SET label = ?, updatedAt = ? WHERE id = ? AND deletedAt IS NULL;
        """, [.text(trimmed), .text(nowText), .integer(id)]) > 0
    }

    /// Soft delete. The pool underneath is left in place for the same reason
    /// `ProgramStore.delete` leaves its days: the prescription a past session
    /// ran against must not disappear when the program is retired.
    @discardableResult
    public func delete(id: Int64) throws -> Bool {
        try db.run("""
        UPDATE programDay SET deletedAt = ?, updatedAt = ? WHERE id = ? AND deletedAt IS NULL;
        """, [.text(nowText), .text(nowText), .integer(id)]) > 0
    }

    /// A program's live days, in the order they were authored.
    ///
    /// Not alphabetical: Push before Pull before Legs is the order a person
    /// wrote them, and a picker that sorts them by name will eventually offer
    /// "Legs / Pull / Push" and call it a feature.
    public func days(programId: Int64) throws -> [ProgramDayEntry] {
        try db.query("""
        SELECT * FROM programDay WHERE programId = ? AND deletedAt IS NULL ORDER BY id;
        """, [.integer(programId)]).compactMap(ProgramDayEntry.init(from:))
    }

    /// Every live day across every program, each paired with its program's name.
    ///
    /// The read the session-start picker needs — "choose a program, then a day"
    /// is two pickers, but "which programs exist at all" is one question, and
    /// asking it per program is how a picker ends up showing fewer than it says.
    public func daysWithPrograms() throws -> [(program: TrainingProgramEntry, days: [ProgramDayEntry])] {
        let programs = try db.query("""
        SELECT * FROM trainingProgram WHERE deletedAt IS NULL ORDER BY name COLLATE NOCASE;
        """).compactMap(TrainingProgramEntry.init(from:))
        // Hoisted, not inside the loop: a query per program is fine at two
        // programs and linear at twenty (handoff §8, "ask what varies within the
        // pass, read the rest once").
        let daysByProgram = try db.query("""
        SELECT * FROM programDay WHERE deletedAt IS NULL ORDER BY id;
        """).compactMap(ProgramDayEntry.init(from:))
        var grouped: [Int64: [ProgramDayEntry]] = [:]
        for day in daysByProgram { grouped[day.programId, default: []].append(day) }
        return programs.compactMap { program in
            guard let days = grouped[program.id], !days.isEmpty else { return nil }
            return (program, days)
        }
    }

    public func day(id: Int64) throws -> ProgramDayEntry? {
        try db.query("SELECT * FROM programDay WHERE id = ?;", [.integer(id)])
            .first.flatMap(ProgramDayEntry.init(from:))
    }
}

/// The row projections both program stores read through.
///
/// Declared on the entries rather than as private statics on each store because
/// `ProgramDayStore.daysWithPrograms` needs to project a `programDay` row
/// without going through a store instance — it is one query across every
/// program, not a query per program. One guard chain, two callers, no way for
/// them to disagree about what a missing column means.
extension ProgramDayEntry {
    init?(from row: Row) {
        guard let id = row.int("id"),
              let programId = row.int("programId"),
              let label = row.string("label"),
              let createdAt = row.string("createdAt"),
              let updatedAt = row.string("updatedAt") else { return nil }
        self.init(id: id, programId: programId, label: label,
                  deletedAt: row.string("deletedAt"), createdAt: createdAt, updatedAt: updatedAt)
    }
}

extension TrainingProgramEntry {
    init?(from row: Row) {
        guard let id = row.int("id"),
              let name = row.string("name"),
              let createdAt = row.string("createdAt"),
              let updatedAt = row.string("updatedAt") else { return nil }
        self.init(id: id, name: name, notes: row.string("notes"),
                  deletedAt: row.string("deletedAt"), createdAt: createdAt, updatedAt: updatedAt)
    }
}

public enum ProgramDayStoreError: Error, Sendable, Equatable {
    case emptyLabel
}
