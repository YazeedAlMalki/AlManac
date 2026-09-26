import Foundation

/// Migration 043 — `sync_source_preference`: which synced source wins per
/// domain when two disagree.
///
/// Asked for by the owner on 2026-09-26, answering the question this repo had
/// recorded as a blocker on any second-provider work: *"a decision about which
/// source wins when Whoop and HealthKit disagree about sleep — user gets to pick
/// when setting up their profile and can change it later from settings."*
///
/// There is no defensible default for that, which is why it is a preference and
/// not a constant: two providers will not agree about sleep staging, they use
/// different sensors and different epoch definitions, and "prefer the
/// specialist" is wrong for at least one domain just as surely as "prefer the
/// phone" is.
///
/// `sourceId` is a free-text column rather than a foreign key to a providers
/// table, because no providers table exists and inventing one for a provider
/// that has not been written would be a table describing a fiction. It is also
/// what makes adding Whoop or Fitbit a data change instead of a migration.
///
/// One row per domain — `domain` is the primary key — so re-picking overwrites
/// and "change it later" is an update rather than a second, competing opinion.
/// Absent rows are meaningful: an absent row means the user has not been asked
/// about that domain, which is different from having been asked and left it on a
/// default.
public enum Migration043_SyncSourcePreference: Migration {
    public static let version = 43
    public static let name = "sync_source_preference"

    public static func up(_ db: Database) throws {
        try db.execute("""
        CREATE TABLE sync_source_preference (
            domain    TEXT NOT NULL PRIMARY KEY,
            sourceId  TEXT NOT NULL,
            updatedAt TEXT NOT NULL
        );
        """)
    }
}
