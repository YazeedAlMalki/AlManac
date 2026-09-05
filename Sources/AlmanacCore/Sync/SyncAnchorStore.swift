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

    public func load(_ domain: String) throws -> SyncAnchor? {
        let rows = try db.query(
            "SELECT domain, anchor_token, last_synced, last_error FROM sync_anchor WHERE domain = ?;",
            [.text(domain)]
        )
        guard let row = rows.first else { return nil }
        var token: [UInt8]?
        if case .blob(let bytes)? = row["anchor_token"] { token = bytes }
        let synced = row.string("last_synced").flatMap { ISO8601DateFormatter().date(from: $0) }
        return SyncAnchor(domain: domain, token: token, lastSynced: synced,
                          lastError: row.string("last_error"))
    }

    public func save(domain: String, token: [UInt8]?) throws {
        try db.run("""
        INSERT INTO sync_anchor (domain, anchor_token, last_synced, last_error)
        VALUES (?, ?, ?, NULL)
        ON CONFLICT(domain) DO UPDATE SET
            anchor_token = excluded.anchor_token,
            last_synced  = excluded.last_synced,
            last_error   = NULL;
        """, [
            .text(domain),
            token.map { SQLValue.blob($0) } ?? .null,
            .text(ISO8601DateFormatter().string(from: clock.now))
        ])
    }

    /// Records a failure without clearing the last good anchor — a failed sync
    /// must never cause the next one to re-import from the beginning.
    public func recordFailure(domain: String, message: String) throws {
        try db.run("""
        INSERT INTO sync_anchor (domain, anchor_token, last_synced, last_error)
        VALUES (?, NULL, NULL, ?)
        ON CONFLICT(domain) DO UPDATE SET last_error = excluded.last_error;
        """, [.text(domain), .text(message)])
    }
}
