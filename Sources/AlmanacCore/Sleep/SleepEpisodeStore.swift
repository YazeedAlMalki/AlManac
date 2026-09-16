import Foundation

/// A `sleep_episode` row read from storage.
///
/// `episodeType` is the classifier's raw call — `userCorrectedType`, when
/// set, is what actually applies (mirrors `SleepEpisode.effectiveType`; the
/// row keeps both so a correction is never destructive).
public struct StoredSleepEpisode: Sendable, Hashable, Identifiable {
    public let id: Int64
    public let start: Date
    public let end: Date
    public let durationMinutes: Int
    public let episodeType: SleepEpisodeType
    public let source: SleepEpisodeSource
    public let healthKitUUID: String?
    public let sourceApp: String?
    public let sourceDevice: String?
    public let userCorrectedType: SleepEpisodeType?
    public let logicalDay: String
    public let createdAt: Date
    public let updatedAt: Date

    public var effectiveType: SleepEpisodeType { userCorrectedType ?? episodeType }
}

/// Persists `SleepClassifier`'s output into `sleep_episode`. The classifier
/// itself is pure and stateless (`SleepClassifier.swift`); this is the
/// "persistence is the caller's job" it defers to.
///
/// Identity for idempotent re-classification is `healthKitUUID` alone — every
/// episode `SleepClassifier` produces has `source = .healthkit`
/// (`groupIntoEpisodes` hardcodes it), and the column already carries a
/// genuine single-column `UNIQUE` constraint (Migration014), so no new index
/// is needed. `healthKitUUIDs.first` stands in for the whole merged group:
/// re-running the classifier over the same raw samples groups them the same
/// way (`groupIntoEpisodes` sorts by start before grouping), so the first
/// UUID is stable across reclassification.
public struct SleepEpisodeStore: @unchecked Sendable {
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

    /// Upserts a classified episode. `timezoneOffset` is minutes from UTC at
    /// the time the underlying samples were recorded (`sleep_episode.timezoneOffset`
    /// is `NOT NULL` — unlike `vitals_record`'s, this one is always known,
    /// since it comes from the same classification run as `logicalDay`).
    @discardableResult
    public func upsert(_ episode: SleepEpisode, timezoneOffset: Int, logicalDay: String) throws -> Int64 {
        let healthKitUUID = episode.healthKitUUIDs.first
        let createdAt = nowText

        try db.run("""
        INSERT INTO sleep_episode
            (startTimestamp, endTimestamp, timezoneOffset, durationMinutes, episodeType,
             source, healthKitUUID, sourceApp, sourceDevice, userCorrectedType, logicalDay,
             createdAt, updatedAt)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(healthKitUUID) WHERE healthKitUUID IS NOT NULL DO UPDATE SET
            startTimestamp    = excluded.startTimestamp,
            endTimestamp      = excluded.endTimestamp,
            timezoneOffset    = excluded.timezoneOffset,
            durationMinutes   = excluded.durationMinutes,
            episodeType       = excluded.episodeType,
            sourceApp         = excluded.sourceApp,
            sourceDevice      = excluded.sourceDevice,
            userCorrectedType = excluded.userCorrectedType,
            logicalDay        = excluded.logicalDay,
            updatedAt         = excluded.updatedAt;
        """, [
            .text(iso(episode.start)),
            .text(iso(episode.end)),
            .integer(Int64(timezoneOffset)),
            .integer(Int64(episode.spanMinutes)),
            .text(episode.type.rawValue),
            .text(episode.source.rawValue),
            healthKitUUID.map { SQLValue.text($0) } ?? .null,
            episode.sourceApp.map { SQLValue.text($0) } ?? .null,
            episode.sourceDevice.map { SQLValue.text($0) } ?? .null,
            episode.userCorrectedType.map { SQLValue.text($0.rawValue) } ?? .null,
            .text(logicalDay),
            .text(createdAt),
            .text(createdAt)
        ])

        // `last_insert_rowid()` only tracks a fresh INSERT, not the UPDATE
        // branch an upsert can take — look the row up by its real identity
        // when there is one, instead of trusting the rowid function.
        let idRow: Row?
        if let healthKitUUID {
            idRow = try db.query("SELECT id FROM sleep_episode WHERE healthKitUUID = ?;",
                                  [.text(healthKitUUID)]).first
        } else {
            idRow = try db.query("SELECT last_insert_rowid() as id;").first
        }
        guard let id = idRow?.int("id") else {
            throw SleepEpisodeStoreError.insertFailed
        }
        return id
    }

    public func episode(id: Int64) throws -> StoredSleepEpisode? {
        try db.query("""
        SELECT id, startTimestamp, endTimestamp, durationMinutes, episodeType, source,
               healthKitUUID, sourceApp, sourceDevice, userCorrectedType, logicalDay,
               createdAt, updatedAt
        FROM sleep_episode WHERE id = ?;
        """, [.integer(id)]).first.flatMap(rowToEpisode)
    }

    /// Episodes for a logical day, ordered by start — a night plus any naps.
    public func episodes(for logicalDay: String) throws -> [StoredSleepEpisode] {
        try db.query("""
        SELECT id, startTimestamp, endTimestamp, durationMinutes, episodeType, source,
               healthKitUUID, sourceApp, sourceDevice, userCorrectedType, logicalDay,
               createdAt, updatedAt
        FROM sleep_episode WHERE logicalDay = ?
        ORDER BY startTimestamp;
        """, [.text(logicalDay)]).compactMap(rowToEpisode)
    }

    private func rowToEpisode(_ row: Row) -> StoredSleepEpisode? {
        guard let id = row.int("id"),
              let startText = row.string("startTimestamp"),
              let endText = row.string("endTimestamp"),
              let durationMinutes = row.int("durationMinutes"),
              let episodeTypeText = row.string("episodeType"),
              let episodeType = SleepEpisodeType(rawValue: episodeTypeText),
              let sourceText = row.string("source"),
              let source = SleepEpisodeSource(rawValue: sourceText),
              let logicalDay = row.string("logicalDay"),
              let start = iso8601ToDate(startText),
              let end = iso8601ToDate(endText) else { return nil }

        return StoredSleepEpisode(
            id: id, start: start, end: end, durationMinutes: Int(durationMinutes),
            episodeType: episodeType, source: source,
            healthKitUUID: row.string("healthKitUUID"),
            sourceApp: row.string("sourceApp"), sourceDevice: row.string("sourceDevice"),
            userCorrectedType: row.string("userCorrectedType").flatMap(SleepEpisodeType.init(rawValue:)),
            logicalDay: logicalDay,
            createdAt: row.string("createdAt").flatMap(iso8601ToDate) ?? Date(),
            updatedAt: row.string("updatedAt").flatMap(iso8601ToDate) ?? Date())
    }

    private func iso8601ToDate(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }
}

public enum SleepEpisodeStoreError: Error, Sendable {
    case insertFailed
}
