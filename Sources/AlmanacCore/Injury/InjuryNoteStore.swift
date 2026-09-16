import Foundation

/// An injury note not yet written to storage.
public struct InjuryNoteDraft: Sendable {
    public var startDate: String  // YYYY-MM-DD
    public var endDate: String?
    public var bodyArea: String
    public var description: String
    public var isActive: Bool
    public var affectsTraining: Bool

    public init(startDate: String, endDate: String? = nil, bodyArea: String,
                description: String, isActive: Bool = true, affectsTraining: Bool = true) {
        self.startDate = startDate
        self.endDate = endDate
        self.bodyArea = bodyArea
        self.description = description
        self.isActive = isActive
        self.affectsTraining = affectsTraining
    }
}

/// An injury note read from storage.
public struct InjuryNote: Sendable, Hashable, Identifiable {
    public let id: Int64
    public let startDate: String  // YYYY-MM-DD
    public let endDate: String?
    public let bodyArea: String
    public let description: String
    public let isActive: Bool
    public let affectsTraining: Bool
    public let createdAt: Date
    public let updatedAt: Date

    public init(id: Int64, startDate: String, endDate: String? = nil, bodyArea: String,
                description: String, isActive: Bool = true, affectsTraining: Bool = true,
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.bodyArea = bodyArea
        self.description = description
        self.isActive = isActive
        self.affectsTraining = affectsTraining
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Injury note logging and querying over `injury_note`.
public struct InjuryNoteStore: @unchecked Sendable {
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
    public func log(_ draft: InjuryNoteDraft) throws -> Int64 {
        let createdAt = nowText
        
        var id: Int64 = 0
        try db.run("""
        INSERT INTO injury_note
            (startDate, endDate, bodyArea, description, isActive, affectsTraining, createdAt, updatedAt)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """, [
            .text(draft.startDate),
            draft.endDate.map { SQLValue.text($0) } ?? .null,
            .text(draft.bodyArea),
            .text(draft.description),
            .integer(draft.isActive ? 1 : 0),
            .integer(draft.affectsTraining ? 1 : 0),
            .text(createdAt),
            .text(createdAt)
        ])
        
        // Fetch the last inserted rowid
        if let row = try db.query("SELECT last_insert_rowid() as id;").first,
           let fetchedID = row.int("id") {
            id = fetchedID
        }
        return id
    }

    /// Update the end date of an injury (marks it as resolved).
    public func markResolved(id: Int64, endDate: String) throws {
        try db.run("""
        UPDATE injury_note SET endDate = ?, isActive = 0, updatedAt = ? WHERE id = ?;
        """, [.text(endDate), .text(nowText), .integer(id)])
    }

    /// Update whether the injury affects training.
    public func updateAffectsTraining(id: Int64, to affectsTraining: Bool) throws {
        try db.run("""
        UPDATE injury_note SET affectsTraining = ?, updatedAt = ? WHERE id = ?;
        """, [.integer(affectsTraining ? 1 : 0), .text(nowText), .integer(id)])
    }

    /// Update the description of an injury.
    public func updateDescription(id: Int64, to description: String) throws {
        try db.run("""
        UPDATE injury_note SET description = ?, updatedAt = ? WHERE id = ?;
        """, [.text(description), .text(nowText), .integer(id)])
    }

    // MARK: - Read

    public func note(id: Int64) throws -> InjuryNote? {
        try db.query("""
        SELECT id, startDate, endDate, bodyArea, description, isActive, affectsTraining, createdAt, updatedAt
        FROM injury_note WHERE id = ?;
        """, [.integer(id)]).first.flatMap(rowToNote)
    }

    /// Fetch all active injuries.
    public func activeInjuries() throws -> [InjuryNote] {
        return try db.query("""
        SELECT id, startDate, endDate, bodyArea, description, isActive, affectsTraining, createdAt, updatedAt
        FROM injury_note WHERE isActive = 1
        ORDER BY startDate DESC;
        """).compactMap(rowToNote)
    }

    /// Fetch all injuries that affect training.
    public func injuriesAffectingTraining() throws -> [InjuryNote] {
        return try db.query("""
        SELECT id, startDate, endDate, bodyArea, description, isActive, affectsTraining, createdAt, updatedAt
        FROM injury_note WHERE affectsTraining = 1
        ORDER BY startDate DESC;
        """).compactMap(rowToNote)
    }

    /// Fetch all injuries for a specific body area.
    public func injuries(for bodyArea: String) throws -> [InjuryNote] {
        return try db.query("""
        SELECT id, startDate, endDate, bodyArea, description, isActive, affectsTraining, createdAt, updatedAt
        FROM injury_note WHERE bodyArea = ?
        ORDER BY startDate DESC;
        """, [.text(bodyArea)]).compactMap(rowToNote)
    }

    // MARK: - Private

    private func rowToNote(_ row: Row) -> InjuryNote? {
        guard let id = row.int("id"),
              let startDate = row.string("startDate"),
              let bodyArea = row.string("bodyArea"),
              let description = row.string("description") else { return nil }
        
        let isActive = row.int("isActive") != 0
        let affectsTraining = row.int("affectsTraining") != 0
        let createdAt = row.string("createdAt").flatMap(iso8601ToDate) ?? Date()
        let updatedAt = row.string("updatedAt").flatMap(iso8601ToDate) ?? Date()
        
        return InjuryNote(
            id: id,
            startDate: startDate,
            endDate: row.string("endDate"),
            bodyArea: bodyArea,
            description: description,
            isActive: isActive,
            affectsTraining: affectsTraining,
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
