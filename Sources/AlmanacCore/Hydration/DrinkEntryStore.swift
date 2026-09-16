import Foundation

/// A drink entry not yet written to storage.
public struct DrinkEntryDraft: Sendable {
    public var timestamp: Date
    public var drinkType: String  // water, coffee_black, coffee_latte, etc.
    public var drinkName: String?  // custom name if drinkType == "custom"
    public var fluidVolumeMl: Double
    public var caffeineMg: Double
    public var calories: Double
    public var proteinG: Double
    public var carbsG: Double
    public var fatG: Double
    public var notes: String?
    public var timezoneOffset: Int?

    public init(timestamp: Date, drinkType: String, drinkName: String? = nil,
                fluidVolumeMl: Double = 0, caffeineMg: Double = 0, calories: Double = 0,
                proteinG: Double = 0, carbsG: Double = 0, fatG: Double = 0,
                notes: String? = nil, timezoneOffset: Int? = nil) {
        self.timestamp = timestamp
        self.drinkType = drinkType
        self.drinkName = drinkName
        self.fluidVolumeMl = fluidVolumeMl
        self.caffeineMg = caffeineMg
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.notes = notes
        self.timezoneOffset = timezoneOffset
    }
}

/// A drink entry read from storage.
public struct DrinkEntry: Sendable, Hashable, Identifiable {
    public let id: Int64
    public let timestamp: Date
    public let logicalDay: String
    public let drinkType: String
    public let drinkName: String?
    public let fluidVolumeMl: Double
    public let caffeineMg: Double
    public let calories: Double
    public let proteinG: Double
    public let carbsG: Double
    public let fatG: Double
    public let notes: String?
    public let createdAt: Date

    public init(id: Int64, timestamp: Date, logicalDay: String, drinkType: String,
                drinkName: String? = nil, fluidVolumeMl: Double = 0, caffeineMg: Double = 0,
                calories: Double = 0, proteinG: Double = 0, carbsG: Double = 0, fatG: Double = 0,
                notes: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.timestamp = timestamp
        self.logicalDay = logicalDay
        self.drinkType = drinkType
        self.drinkName = drinkName
        self.fluidVolumeMl = fluidVolumeMl
        self.caffeineMg = caffeineMg
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.notes = notes
        self.createdAt = createdAt
    }
}

/// Drink entry logging and querying over `drink_entry` table.
public struct DrinkEntryStore: @unchecked Sendable {
    let db: Database
    private let clock: any Clock
    private let zone: ZoneContext

    public init(db: Database, clock: any Clock = SystemClock(),
                zone: ZoneContext = ZoneContext(TimeZone.current)) {
        self.db = db
        self.clock = clock
        self.zone = zone
    }

    private var nowText: String { iso(clock.now) }
    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    // MARK: - Write

    @discardableResult
    public func log(_ draft: DrinkEntryDraft, logicalDay: String) throws -> Int64 {
        let timestamp = iso(draft.timestamp)
        let createdAt = nowText
        
        var id: Int64 = 0
        try db.run("""
        INSERT INTO drink_entry
            (timestamp, timezoneOffset, logicalDay, drinkType, drinkName, fluidVolumeMl,
             caffeineMg, calories, proteinG, carbsG, fatG, notes, createdAt)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, [
            .text(timestamp),
            draft.timezoneOffset.map { SQLValue.integer(Int64($0)) } ?? .null,
            .text(logicalDay),
            .text(draft.drinkType),
            draft.drinkName.map { SQLValue.text($0) } ?? .null,
            .real(draft.fluidVolumeMl),
            .real(draft.caffeineMg),
            .real(draft.calories),
            .real(draft.proteinG),
            .real(draft.carbsG),
            .real(draft.fatG),
            draft.notes.map { SQLValue.text($0) } ?? .null,
            .text(createdAt)
        ])
        
        // Fetch the last inserted rowid
        if let row = try db.query("SELECT last_insert_rowid() as id;").first,
           let fetchedID = row.int("id") {
            id = fetchedID
        }
        return id
    }

    // MARK: - Read

    public func entry(id: Int64) throws -> DrinkEntry? {
        try db.query("""
        SELECT id, timestamp, logicalDay, drinkType, drinkName, fluidVolumeMl,
               caffeineMg, calories, proteinG, carbsG, fatG, notes, createdAt
        FROM drink_entry WHERE id = ?;
        """, [.integer(id)]).first.flatMap(rowToEntry)
    }

    /// Fetch all drink entries for a logical day.
    public func entries(for logicalDay: String) throws -> [DrinkEntry] {
        return try db.query("""
        SELECT id, timestamp, logicalDay, drinkType, drinkName, fluidVolumeMl,
               caffeineMg, calories, proteinG, carbsG, fatG, notes, createdAt
        FROM drink_entry WHERE logicalDay = ?
        ORDER BY timestamp;
        """, [.text(logicalDay)]).compactMap(rowToEntry)
    }

    /// Sum caffeine for a logical day.
    public func totalCaffeine(for logicalDay: String) throws -> Double {
        let result = try db.query("""
        SELECT COALESCE(SUM(caffeineMg), 0) as total FROM drink_entry
        WHERE logicalDay = ?;
        """, [.text(logicalDay)]).first?.double("total") ?? 0
        return result
    }

    // MARK: - Private

    private func rowToEntry(_ row: Row) -> DrinkEntry? {
        guard let id = row.int("id"),
              let timestamp = row.string("timestamp").flatMap(iso8601ToDate),
              let logicalDay = row.string("logicalDay"),
              let drinkType = row.string("drinkType") else { return nil }
        
        return DrinkEntry(
            id: id,
            timestamp: timestamp,
            logicalDay: logicalDay,
            drinkType: drinkType,
            drinkName: row.string("drinkName"),
            fluidVolumeMl: row.double("fluidVolumeMl") ?? 0,
            caffeineMg: row.double("caffeineMg") ?? 0,
            calories: row.double("calories") ?? 0,
            proteinG: row.double("proteinG") ?? 0,
            carbsG: row.double("carbsG") ?? 0,
            fatG: row.double("fatG") ?? 0,
            notes: row.string("notes"),
            createdAt: row.string("createdAt").flatMap(iso8601ToDate) ?? Date()
        )
    }

    private func iso8601ToDate(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }
}
