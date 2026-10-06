import Foundation

/// A vitals record not yet written to storage.
public struct VitalsRecordDraft: Sendable {
    public var metric: String  // e.g., "rhr", "hrv", "spo2", "temp", "bp_systolic", "bp_diastolic"
    public var value: Double
    public var unit: String  // e.g., "bpm", "%", "mmHg"
    public var timestamp: Date
    public var source: String  // e.g., "healthkit", "manual", "device"
    public var healthKitUUID: String?  // if from HealthKit, the UUID
    public var timezoneOffset: Int?  // offset in minutes from UTC
    public var timezoneID: String?

    public init(metric: String, value: Double, unit: String, timestamp: Date,
                source: String, healthKitUUID: String? = nil, 
                timezoneOffset: Int? = nil, timezoneID: String? = nil) {
        self.metric = metric
        self.value = value
        self.unit = unit
        self.timestamp = timestamp
        self.source = source
        self.healthKitUUID = healthKitUUID
        self.timezoneOffset = timezoneOffset
        self.timezoneID = timezoneID
    }
}

/// A vitals record read from storage.
public struct VitalsRecord: Sendable, Hashable, Identifiable {
    public let id: Int64
    public let metric: String
    public let value: Double
    public let unit: String
    public let timestamp: Date
    public let logicalDay: String  // YYYY-MM-DD
    public let source: String
    public let healthKitUUID: String?
    public let createdAt: Date

    public init(id: Int64, metric: String, value: Double, unit: String, 
                timestamp: Date, logicalDay: String, source: String,
                healthKitUUID: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.metric = metric
        self.value = value
        self.unit = unit
        self.timestamp = timestamp
        self.logicalDay = logicalDay
        self.source = source
        self.healthKitUUID = healthKitUUID
        self.createdAt = createdAt
    }
}

/// Vitals record logging and querying over `vitals_record`.
public struct VitalsRecordStore: @unchecked Sendable {
    let db: Database
    private let clock: any Clock
    private let zone: ZoneContext
    private let timeModel: TimeModel

    public init(db: Database, clock: any Clock = SystemClock(),
                zone: ZoneContext = ZoneContext(TimeZone.current),
                timeModel: TimeModel = TimeModel(timeZone: .current)) {
        self.db = db
        self.clock = clock
        self.zone = zone
        self.timeModel = timeModel
    }

    private var nowText: String { iso(clock.now) }
    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    // MARK: - Write

    @discardableResult
    public func record(_ draft: VitalsRecordDraft, logicalDay: String) throws -> Int64 {
        let timestamp = iso(draft.timestamp)
        let createdAt = nowText
        
        var id: Int64 = 0
        try db.run("""
        INSERT INTO vitals_record
            (timestamp, timezoneOffset, logicalDay, metric, value, unit, source, healthKitUUID, createdAt)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, [
            .text(timestamp),
            draft.timezoneOffset.map { SQLValue.integer(Int64($0)) } ?? .null,
            .text(logicalDay),
            .text(draft.metric),
            .real(draft.value),
            .text(draft.unit),
            .text(draft.source),
            draft.healthKitUUID.map { SQLValue.text($0) } ?? .null,
            .text(createdAt)
        ])
        
        // Fetch the last inserted rowid
        if let row = try db.query("SELECT last_insert_rowid() as id;").first,
           let fetchedID = row.int("id") {
            id = fetchedID
        }
        return id
    }

    // MARK: - Manual entry

    /// The `source` a hand-entered row carries. Compared as a string because
    /// `vitals_record.source` is a plain TEXT column with no CHECK and no enum
    /// — `VitalsRecordHealthBridge` writes `"healthkit"` by the same kind of
    /// literal, so the same constant is the honest way to agree with it.
    public static let manualSource = "manual"

    /// A reading typed by a person rather than synced from Apple Health.
    ///
    /// `measuredAt` is explicit rather than "now" because the reading is usually
    /// taken somewhere other than the moment it is written down — a watch
    /// battery died overnight, so the number is from this morning but the entry
    /// is made at lunch. It also has to be explicit for `latestValue(for:since:)`
    /// to mean anything: a store that stamped every manual row with the clock
    /// would make back-dating impossible and would quietly turn a truthful
    /// past reading into a fresh one.
    ///
    /// The logical day comes from `TimeModel`, never from the caller, for the
    /// reason §5.1 gives: the day a sample belongs to is decided by the 04:00
    /// boundary, so a reading taken at 03:00 belongs to the day before. Handing
    /// the day in as a parameter — which is what `record(_:logicalDay:)` does —
    /// is how that rule gets re-implemented slightly wrong somewhere else.
    @discardableResult
    public func recordManual(metric: VitalsMetric, value: Double, measuredAt: Date,
                             allowUnusualValue: Bool = false) throws -> Int64 {
        try validate(value, metric: metric, allowUnusualValue: allowUnusualValue)
        return try db.transaction {
            try db.run("""
            INSERT INTO vitals_record
                (timestamp, timezoneOffset, timezoneIdentifier, logicalDay, metric, value,
                 unit, source, createdAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """, [
                .text(iso(measuredAt)),
                zone.offsetMinutes.map { SQLValue.integer(Int64($0)) } ?? .null,
                zone.identifier.map(SQLValue.text) ?? .null,
                .text(timeModel.logicalDay(measuredAt).value),
                .text(metric.rawValue),
                .real(value),
                .text(metric.unit),
                .text(Self.manualSource),
                .text(nowText)
            ])
            return try db.query("SELECT last_insert_rowid() AS id;").first!.int("id")!
        }
    }

    /// Correct a hand-entered reading in place.
    ///
    /// Only `value` moves. The metric, unit and instant stay as recorded,
    /// because the reading is a measurement of a moment: changing when it was
    /// taken is a different claim, not a correction of this one, and letting a
    /// correction rewrite the timestamp would quietly move the reading into
    /// another logical day and out of the score it was part of.
    public func update(id: Int64, value: Double, allowUnusualValue: Bool = false) throws {
        guard let existing = try record(id: id) else { throw VitalsEntryError.notFound }
        guard existing.source == Self.manualSource else { throw VitalsEntryError.notManual }
        guard let metric = VitalsMetric(rawValue: existing.metric) else {
            throw VitalsEntryError.notHandEnterable
        }
        try validate(value, metric: metric, allowUnusualValue: allowUnusualValue)
        try db.run("UPDATE vitals_record SET value = ? WHERE id = ?;",
                   [.real(value), .integer(id)])
    }

    /// Remove a hand-entered reading outright, like `BodyMeasurementStore.delete`.
    ///
    /// Deleted rather than soft-deleted: `deletedAt` exists for HealthKit, where
    /// a retraction arrives from outside and the tombstone is what stops the
    /// next sync resurrecting the row. A person changing their mind needs no
    /// such protection — they are the only writer, and there is no next sync
    /// coming to disagree.
    public func delete(id: Int64) throws {
        guard let existing = try record(id: id) else { throw VitalsEntryError.notFound }
        guard existing.source == Self.manualSource else { throw VitalsEntryError.notManual }
        try db.run("DELETE FROM vitals_record WHERE id = ?;", [.integer(id)])
    }

    /// The hand-entered readings of `metric` on `logicalDay`, newest first.
    /// One metric at a time because that is what an editor shows; a day's mixed
    /// vitals are still available from `records(for:)`.
    public func manualRecords(metric: VitalsMetric, for logicalDay: String) throws -> [VitalsRecord] {
        try db.query("""
        SELECT id, metric, value, unit, timestamp, logicalDay, source, healthKitUUID, createdAt
        FROM vitals_record
        WHERE metric = ? AND logicalDay = ? AND source = ? AND deletedAt IS NULL
        ORDER BY timestamp DESC;
        """, [.text(metric.rawValue), .text(logicalDay), .text(Self.manualSource)]).compactMap(rowToRecord)
    }

    private func validate(_ value: Double, metric: VitalsMetric, allowUnusualValue: Bool) throws {
        // `isFinite` first: NaN fails every comparison, so an `allowUnusualValue`
        // save would otherwise write a NaN that no score could interpret and no
        // band could exclude.
        guard value.isFinite, value > 0 else { throw VitalsEntryError.invalidValue(metric) }
        guard allowUnusualValue || metric.plausibleRange.contains(value) else {
            throw VitalsEntryError.unusuallySized
        }
    }

    // MARK: - Read

    public func record(id: Int64) throws -> VitalsRecord? {
        try db.query("""
        SELECT id, metric, value, unit, timestamp, logicalDay, source, healthKitUUID, createdAt
        FROM vitals_record WHERE id = ?;
        """, [.integer(id)]).first.flatMap(rowToRecord)
    }

    /// Fetch all vitals for a given logical day. Excludes soft-deleted entries.
    public func records(for logicalDay: String) throws -> [VitalsRecord] {
        return try db.query("""
        SELECT id, metric, value, unit, timestamp, logicalDay, source, healthKitUUID, createdAt
        FROM vitals_record WHERE logicalDay = ? AND deletedAt IS NULL
        ORDER BY timestamp;
        """, [.text(logicalDay)]).compactMap(rowToRecord)
    }

    /// Fetch all records for a specific metric. Excludes soft-deleted entries.
    public func records(metric: String, from: String, to: String) throws -> [VitalsRecord] {
        return try db.query("""
        SELECT id, metric, value, unit, timestamp, logicalDay, source, healthKitUUID, createdAt
        FROM vitals_record WHERE metric = ? AND logicalDay >= ? AND logicalDay < ? AND deletedAt IS NULL
        ORDER BY timestamp;
        """, [.text(metric), .text(from), .text(to)]).compactMap(rowToRecord)
    }

    /// The Vitals log: every reading of `metrics` on the `dayCount` logical days
    /// ending with `today` — **today included** — newest first, at most `limit`.
    ///
    /// `records(metric:from:to:)` is half-open, which is right for a range and
    /// wrong for "the last fortnight up to now": `VitalsView` passed today as its
    /// `to:`, so until 2026-10-06 a reading taken today never reached the log, and
    /// the log is where a hand-entered reading is corrected or deleted. The upper
    /// bound here is the day *after* today, walked with `day(after:)` so a DST
    /// day stays the calendar's problem.
    public func log(metrics: [VitalsMetric], dayCount: Int, endingOn today: LogicalDay,
                    timeModel: TimeModel, limit: Int) throws -> [VitalsRecord] {
        guard dayCount > 0, limit > 0, let end = timeModel.day(after: today) else { return [] }
        var start = today
        for _ in 1..<dayCount {
            start = timeModel.day(before: start) ?? start
        }
        let rows = try metrics.flatMap {
            try records(metric: $0.rawValue, from: start.value, to: end.value)
        }
        return Array(rows.sorted { $0.timestamp > $1.timestamp }.prefix(limit))
    }

    /// Fetch the latest value for a specific metric. Excludes soft-deleted
    /// (e.g. HealthKit-retracted) entries.
    public func latestValue(for metric: String) throws -> VitalsRecord? {
        return try db.query("""
        SELECT id, metric, value, unit, timestamp, logicalDay, source, healthKitUUID, createdAt
        FROM vitals_record WHERE metric = ? AND deletedAt IS NULL
        ORDER BY timestamp DESC LIMIT 1;
        """, [.text(metric)]).first.flatMap(rowToRecord)
    }

    /// The newest reading of `metric` at or after `since`.
    ///
    /// Bounded on purpose, and this is the second of two API-level facts about
    /// a readiness input. Whole-history `latestValue(for:)` answers "what is
    /// the last number anyone recorded", which is a question about the archive
    /// rather than about today. Once a reading can be back-dated — and manual
    /// entry deliberately allows that, see `recordManual` — the difference stops
    /// being theoretical: someone who logs last night's resting HR *this
    /// morning* has a row timestamped yesterday, and the unbounded read returns
    /// yesterday's number as today's input on the strength of being the newest
    /// row in the table.
    ///
    /// So a caller scoring today asks for `since:` the start of the thing being
    /// scored, and a reading from before it is not an input. That is the same
    /// reasoning already in `ReadinessModel`'s comment about reading stages from
    /// the episode the duration came from: a score about one night may not mix
    /// a duration from one night with a heart rate from another. Callers that
    /// genuinely want the archive — the timeline, the trend charts — keep using
    /// `latestValue(for:)`.
    public func latestValue(for metric: VitalsMetric, since: Date) throws -> VitalsRecord? {
        return try db.query("""
        SELECT id, metric, value, unit, timestamp, logicalDay, source, healthKitUUID, createdAt
        FROM vitals_record WHERE metric = ? AND timestamp >= ? AND deletedAt IS NULL
        ORDER BY timestamp DESC LIMIT 1;
        """, [.text(metric.rawValue), .text(iso(since))]).first.flatMap(rowToRecord)
    }

    /// Fetch vitals for a range of logical days by metric.
    public func records(metric: String, logicalDays: [String]) throws -> [VitalsRecord] {
        guard !logicalDays.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: logicalDays.count).joined(separator: ",")
        let values: [SQLValue] = [.text(metric)] + logicalDays.map { SQLValue.text($0) }
        return try db.query("""
        SELECT id, metric, value, unit, timestamp, logicalDay, source, healthKitUUID, createdAt
        FROM vitals_record WHERE metric = ? AND logicalDay IN (\(placeholders))
        ORDER BY timestamp;
        """, values).compactMap(rowToRecord)
    }

    // MARK: - Private

    private func rowToRecord(_ row: Row) -> VitalsRecord? {
        guard let id = row.int("id"),
              let metric = row.string("metric"),
              let value = row.double("value"),
              let unit = row.string("unit"),
              let timestampText = row.string("timestamp"),
              let logicalDay = row.string("logicalDay"),
              let source = row.string("source"),
              let timestamp = iso8601ToDate(timestampText) else { return nil }
        
        return VitalsRecord(
            id: id,
            metric: metric,
            value: value,
            unit: unit,
            timestamp: timestamp,
            logicalDay: logicalDay,
            source: source,
            healthKitUUID: row.string("healthKitUUID"),
            createdAt: row.string("createdAt").flatMap(iso8601ToDate) ?? Date()
        )
    }

    private func iso8601ToDate(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }
}
