import Foundation

/// A context event not yet written to storage.
public struct ContextEventDraft: Sendable {
    public var date: String  // YYYY-MM-DD
    public var tags: [String]
    // illness | medication_change | travel_jet_lag | unusual_stress |
    // heat_exposure | sauna | poor_watch_wear | late_night_event |
    // sleep_interruption | competition_day
    public var notes: String?

    public init(date: String, tags: [String] = [], notes: String? = nil) {
        self.date = date
        self.tags = tags
        self.notes = notes
    }
}

/// A context event read from storage.
public struct ContextEvent: Sendable, Hashable, Identifiable {
    public let id: Int64
    public let date: String
    public let tags: [String]
    public let notes: String?
    public let createdAt: Date
    public let updatedAt: Date

    public init(id: Int64, date: String, tags: [String] = [], notes: String? = nil,
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.date = date
        self.tags = tags
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Context tag logging over `context_event` — available as confounders for
/// correlations (illness, travel, stress, etc.), same JSON-array-tags shape
/// `SorenessLogStore` already uses for `bodyAreas`.
public struct ContextEventStore: @unchecked Sendable {
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
    public func log(_ draft: ContextEventDraft) throws -> Int64 {
        let createdAt = nowText
        try db.run("""
        INSERT INTO context_event (date, tags, notes, createdAt, updatedAt)
        VALUES (?, ?, ?, ?, ?);
        """, [
            .text(draft.date),
            .text(tagsJSON(draft.tags)),
            draft.notes.map { SQLValue.text($0) } ?? .null,
            .text(createdAt),
            .text(createdAt)
        ])

        guard let row = try db.query("SELECT last_insert_rowid() as id;").first,
              let id = row.int("id") else {
            throw ContextEventStoreError.insertFailed
        }
        return id
    }

    public func updateTags(id: Int64, to tags: [String]) throws {
        try db.run("""
        UPDATE context_event SET tags = ?, updatedAt = ? WHERE id = ?;
        """, [.text(tagsJSON(tags)), .text(nowText), .integer(id)])
    }

    // MARK: - Read

    public func event(id: Int64) throws -> ContextEvent? {
        try db.query("""
        SELECT id, date, tags, notes, createdAt, updatedAt FROM context_event WHERE id = ?;
        """, [.integer(id)]).first.flatMap(rowToEvent)
    }

    public func event(for date: String) throws -> ContextEvent? {
        try db.query("""
        SELECT id, date, tags, notes, createdAt, updatedAt FROM context_event WHERE date = ?;
        """, [.text(date)]).first.flatMap(rowToEvent)
    }

    // MARK: - Private

    private func tagsJSON(_ tags: [String]) -> String {
        let data = try? JSONEncoder().encode(tags)
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    private func rowToEvent(_ row: Row) -> ContextEvent? {
        guard let id = row.int("id"),
              let date = row.string("date") else { return nil }
        let tags: [String] = (row.string("tags") ?? "[]").decodeJSON() ?? []
        return ContextEvent(
            id: id, date: date, tags: tags, notes: row.string("notes"),
            createdAt: row.string("createdAt").flatMap(iso8601ToDate) ?? Date(),
            updatedAt: row.string("updatedAt").flatMap(iso8601ToDate) ?? Date())
    }

    private func iso8601ToDate(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }
}

public enum ContextEventStoreError: Error, Sendable {
    case insertFailed
}

private extension String {
    func decodeJSON<T: Decodable>() -> T? {
        guard let data = self.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
