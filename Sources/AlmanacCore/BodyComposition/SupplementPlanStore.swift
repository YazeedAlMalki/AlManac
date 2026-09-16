import Foundation

/// A supplement plan not yet written to storage.
public struct SupplementPlanDraft: Sendable {
    public var name: String
    public var doseAmount: Double
    public var doseUnit: String  // g | mg | ml | tablet | capsule | scoop
    public var frequency: String  // daily | twice_daily | pre_workout | custom
    public var timingNotes: String?

    public init(name: String, doseAmount: Double, doseUnit: String, frequency: String,
                timingNotes: String? = nil) {
        self.name = name
        self.doseAmount = doseAmount
        self.doseUnit = doseUnit
        self.frequency = frequency
        self.timingNotes = timingNotes
    }
}

/// A supplement plan read from storage.
public struct SupplementPlan: Sendable, Hashable, Identifiable {
    public let id: Int64
    public let name: String
    public let doseAmount: Double
    public let doseUnit: String
    public let frequency: String
    public let timingNotes: String?
    public let isActive: Bool
    public let createdAt: Date
    public let updatedAt: Date

    public init(id: Int64, name: String, doseAmount: Double, doseUnit: String, frequency: String,
                timingNotes: String? = nil, isActive: Bool = true,
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.doseAmount = doseAmount
        self.doseUnit = doseUnit
        self.frequency = frequency
        self.timingNotes = timingNotes
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Supplement plan CRUD over `supplement_plan`. Plans are deactivated
/// (`isActive = 0`), never deleted — matching `InjuryNoteStore`'s soft-state
/// convention, since adherence history (`supplement_log`) must keep pointing
/// at a real plan.
public struct SupplementPlanStore: @unchecked Sendable {
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
    public func create(_ draft: SupplementPlanDraft) throws -> Int64 {
        let createdAt = nowText
        try db.run("""
        INSERT INTO supplement_plan (name, doseAmount, doseUnit, frequency, timingNotes, createdAt, updatedAt)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """, [
            .text(draft.name),
            .real(draft.doseAmount),
            .text(draft.doseUnit),
            .text(draft.frequency),
            draft.timingNotes.map { SQLValue.text($0) } ?? .null,
            .text(createdAt),
            .text(createdAt)
        ])

        guard let row = try db.query("SELECT last_insert_rowid() as id;").first,
              let id = row.int("id") else {
            throw SupplementPlanStoreError.insertFailed
        }
        return id
    }

    public func deactivate(id: Int64) throws {
        try db.run("""
        UPDATE supplement_plan SET isActive = 0, updatedAt = ? WHERE id = ?;
        """, [.text(nowText), .integer(id)])
    }

    public func plan(id: Int64) throws -> SupplementPlan? {
        try db.query("""
        SELECT id, name, doseAmount, doseUnit, frequency, timingNotes, isActive, createdAt, updatedAt
        FROM supplement_plan WHERE id = ?;
        """, [.integer(id)]).first.flatMap(rowToPlan)
    }

    public func activePlans() throws -> [SupplementPlan] {
        try db.query("""
        SELECT id, name, doseAmount, doseUnit, frequency, timingNotes, isActive, createdAt, updatedAt
        FROM supplement_plan WHERE isActive = 1 ORDER BY name;
        """).compactMap(rowToPlan)
    }

    private func rowToPlan(_ row: Row) -> SupplementPlan? {
        guard let id = row.int("id"),
              let name = row.string("name"),
              let doseAmount = row.double("doseAmount"),
              let doseUnit = row.string("doseUnit"),
              let frequency = row.string("frequency") else { return nil }
        return SupplementPlan(
            id: id, name: name, doseAmount: doseAmount, doseUnit: doseUnit, frequency: frequency,
            timingNotes: row.string("timingNotes"),
            isActive: (row.int("isActive") ?? 1) != 0,
            createdAt: row.string("createdAt").flatMap(iso8601ToDate) ?? Date(),
            updatedAt: row.string("updatedAt").flatMap(iso8601ToDate) ?? Date())
    }

    private func iso8601ToDate(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }
}

public enum SupplementPlanStoreError: Error, Sendable {
    case insertFailed
}
