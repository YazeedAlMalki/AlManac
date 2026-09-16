import Foundation

/// A HealthKit-style incremental sync anchor, persisted per domain.
///
/// The anchor is an opaque blob on purpose: HKQueryAnchor archives to Data and
/// this core must not know that. On Linux the same store is exercised with
/// arbitrary bytes.
public struct SyncAnchor: Sendable, Hashable {
    public let domain: String
    public let token: [UInt8]?
    public let lastSynced: Date?
    public let lastError: String?

    public init(domain: String, token: [UInt8]?, lastSynced: Date?, lastError: String? = nil) {
        self.domain = domain
        self.token = token
        self.lastSynced = lastSynced
        self.lastError = lastError
    }
}

public struct SyncAnchorStore: Sendable {
    private let db: Database
    private let clock: any Clock

    public init(db: Database, clock: any Clock = SystemClock()) {
        self.db = db
        self.clock = clock
    }

    // ponytail: table is `sync_anchor(sampleType, anchorData, lastSyncTimestamp,
    // lastError, updatedAt)` per Migration015/022 — `domain` below is this
    // store's own vocabulary (kept as the public parameter name; every
    // caller already says "domain"), mapped onto the spec's `sampleType`.

    public func load(_ domain: String) throws -> SyncAnchor? {
        let rows = try db.query(
            "SELECT anchorData, lastSyncTimestamp, lastError FROM sync_anchor WHERE sampleType = ?;",
            [.text(domain)]
        )
        guard let row = rows.first else { return nil }
        var token: [UInt8]?
        if case .blob(let bytes)? = row["anchorData"] { token = bytes }
        let synced = row.string("lastSyncTimestamp").flatMap { ISO8601DateFormatter().date(from: $0) }
        return SyncAnchor(domain: domain, token: token, lastSynced: synced,
                          lastError: row.string("lastError"))
    }

    public func save(domain: String, token: [UInt8]?) throws {
        try db.run("""
        INSERT INTO sync_anchor (sampleType, anchorData, lastSyncTimestamp, lastError, updatedAt)
        VALUES (?, ?, ?, NULL, ?)
        ON CONFLICT(sampleType) DO UPDATE SET
            anchorData        = excluded.anchorData,
            lastSyncTimestamp = excluded.lastSyncTimestamp,
            lastError         = NULL,
            updatedAt         = excluded.updatedAt;
        """, [
            .text(domain),
            token.map { SQLValue.blob($0) } ?? .null,
            .text(ISO8601DateFormatter().string(from: clock.now)),
            .text(ISO8601DateFormatter().string(from: clock.now))
        ])
    }

    /// Records a failure without clearing the last good anchor — a failed sync
    /// must never cause the next one to re-import from the beginning.
    public func recordFailure(domain: String, message: String) throws {
        try db.run("""
        INSERT INTO sync_anchor (sampleType, anchorData, lastSyncTimestamp, lastError, updatedAt)
        VALUES (?, NULL, NULL, ?, ?)
        ON CONFLICT(sampleType) DO UPDATE SET
            lastError = excluded.lastError,
            updatedAt = excluded.updatedAt;
        """, [.text(domain), .text(message), .text(ISO8601DateFormatter().string(from: clock.now))])
    }
}
