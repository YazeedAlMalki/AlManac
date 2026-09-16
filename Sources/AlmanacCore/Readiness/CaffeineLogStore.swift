import Foundation

/// A caffeine log entry not yet written to storage.
public struct CaffeineLogDraft: Sendable {
    public var timestamp: Date
    public var drinkType: String
    public var caffeineMg: Double
    public var drinkEntryId: Int64?
    public var intendedSleepTimestamp: Date?
    public var timezoneOffset: Int?

    public init(timestamp: Date, drinkType: String, caffeineMg: Double,
                drinkEntryId: Int64? = nil, intendedSleepTimestamp: Date? = nil,
                timezoneOffset: Int? = nil) {
        self.timestamp = timestamp
        self.drinkType = drinkType
        self.caffeineMg = caffeineMg
        self.drinkEntryId = drinkEntryId
        self.intendedSleepTimestamp = intendedSleepTimestamp
        self.timezoneOffset = timezoneOffset
    }
}

/// A caffeine log entry read from storage.
public struct CaffeineLogEntry: Sendable, Hashable, Identifiable {
    public let id: Int64
    public let timestamp: Date
    public let logicalDay: String
    public let drinkType: String
    public let caffeineMg: Double
    public let drinkEntryId: Int64?
    public let intendedSleepTimestamp: Date?
    public let hoursBeforeIntendedSleep: Double?
    public let caffeineContext: String?  // early | normal | late | very_late
    public let createdAt: Date

    public init(id: Int64, timestamp: Date, logicalDay: String, drinkType: String,
                caffeineMg: Double, drinkEntryId: Int64? = nil,
                intendedSleepTimestamp: Date? = nil, hoursBeforeIntendedSleep: Double? = nil,
                caffeineContext: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.timestamp = timestamp
        self.logicalDay = logicalDay
        self.drinkType = drinkType
        self.caffeineMg = caffeineMg
        self.drinkEntryId = drinkEntryId
        self.intendedSleepTimestamp = intendedSleepTimestamp
        self.hoursBeforeIntendedSleep = hoursBeforeIntendedSleep
        self.caffeineContext = caffeineContext
        self.createdAt = createdAt
    }
}

/// Caffeine logging and querying over `caffeine_log` table.
///
/// Tracks caffeine intake with context relative to intended sleep time.
/// Context is derived from shift schedule (spec §11): intendedSleepTimestamp
/// is looked up from shift_schedule, and hoursBeforeIntendedSleep and
/// caffeineContext are computed at log time (or sync time for HealthKit imports).
public struct CaffeineLogStore: @unchecked Sendable {
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
    public func log(_ draft: CaffeineLogDraft, logicalDay: String) throws -> Int64 {
        let timestamp = iso(draft.timestamp)
        let createdAt = nowText
        let intendedSleepText = draft.intendedSleepTimestamp.map(iso)
        
        // Compute caffeineContext and hoursBeforeIntendedSleep if we have intended sleep time
        let (hoursBefore, context) = computeContext(from: draft.timestamp,
                                                     to: draft.intendedSleepTimestamp)
        
        var id: Int64 = 0
        try db.run("""
        INSERT INTO caffeine_log
            (timestamp, logicalDay, drinkType, caffeineMg, drinkEntryId,
             intendedSleepTimestamp, hoursBeforeIntendedSleep, caffeineContext, createdAt)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, [
            .text(timestamp),
            .text(logicalDay),
            .text(draft.drinkType),
            .real(draft.caffeineMg),
            draft.drinkEntryId.map { SQLValue.integer($0) } ?? .null,
            intendedSleepText.map { SQLValue.text($0) } ?? .null,
            hoursBefore.map { SQLValue.real($0) } ?? .null,
            context.map { SQLValue.text($0) } ?? .null,
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

    public func entry(id: Int64) throws -> CaffeineLogEntry? {
        try db.query("""
        SELECT id, timestamp, logicalDay, drinkType, caffeineMg, drinkEntryId,
               intendedSleepTimestamp, hoursBeforeIntendedSleep, caffeineContext, createdAt
        FROM caffeine_log WHERE id = ?;
        """, [.integer(id)]).first.flatMap(rowToEntry)
    }

    /// Fetch all caffeine logs for a logical day.
    public func entries(for logicalDay: String) throws -> [CaffeineLogEntry] {
        return try db.query("""
        SELECT id, timestamp, logicalDay, drinkType, caffeineMg, drinkEntryId,
               intendedSleepTimestamp, hoursBeforeIntendedSleep, caffeineContext, createdAt
        FROM caffeine_log WHERE logicalDay = ?
        ORDER BY timestamp;
        """, [.text(logicalDay)]).compactMap(rowToEntry)
    }

    /// Sum caffeine mg for a logical day.
    public func totalCaffeine(for logicalDay: String) throws -> Double {
        let result = try db.query("""
        SELECT COALESCE(SUM(caffeineMg), 0) as total FROM caffeine_log
        WHERE logicalDay = ?;
        """, [.text(logicalDay)]).first?.double("total") ?? 0
        return result
    }

    /// Fetch entries by context (early, normal, late, very_late).
    public func entries(context: String, for logicalDay: String) throws -> [CaffeineLogEntry] {
        return try db.query("""
        SELECT id, timestamp, logicalDay, drinkType, caffeineMg, drinkEntryId,
               intendedSleepTimestamp, hoursBeforeIntendedSleep, caffeineContext, createdAt
        FROM caffeine_log WHERE logicalDay = ? AND caffeineContext = ?
        ORDER BY timestamp;
        """, [.text(logicalDay), .text(context)]).compactMap(rowToEntry)
    }

    // MARK: - Private

    private func rowToEntry(_ row: Row) -> CaffeineLogEntry? {
        guard let id = row.int("id"),
              let timestamp = row.string("timestamp").flatMap(iso8601ToDate),
              let logicalDay = row.string("logicalDay"),
              let drinkType = row.string("drinkType"),
              let caffeineMg = row.double("caffeineMg") else { return nil }
        
        return CaffeineLogEntry(
            id: id,
            timestamp: timestamp,
            logicalDay: logicalDay,
            drinkType: drinkType,
            caffeineMg: caffeineMg,
            drinkEntryId: row.int("drinkEntryId"),
            intendedSleepTimestamp: row.string("intendedSleepTimestamp").flatMap(iso8601ToDate),
            hoursBeforeIntendedSleep: row.double("hoursBeforeIntendedSleep"),
            caffeineContext: row.string("caffeineContext"),
            createdAt: row.string("createdAt").flatMap(iso8601ToDate) ?? Date()
        )
    }

    private func iso8601ToDate(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }

    /// Compute hoursBeforeIntendedSleep and caffeineContext.
    /// Per BRD §6.2: early (<6h before), normal (6-3h), late (3-1h), very_late (<1h).
    private func computeContext(from drinkTime: Date, to sleepTime: Date?) -> (hours: Double?, context: String?) {
        guard let sleepTime = sleepTime else { return (nil, nil) }
        
        let hoursBefore = sleepTime.timeIntervalSince(drinkTime) / 3600
        guard hoursBefore >= 0 else { return (nil, nil) }  // Drink after intended sleep doesn't make sense
        
        let context: String
        if hoursBefore >= 6 {
            context = "early"
        } else if hoursBefore >= 3 {
            context = "normal"
        } else if hoursBefore >= 1 {
            context = "late"
        } else {
            context = "very_late"
        }
        
        return (hours: hoursBefore, context: context)
    }
}
