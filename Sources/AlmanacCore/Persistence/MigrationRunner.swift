import Foundation

/// Applies pending migrations in version order, each in its own transaction.
///
/// Three guarantees, in order of how expensive they are to lose:
///  1. A migration that throws leaves the database exactly as it was.
///  2. A migration already applied never runs twice.
///  3. Editing an applied migration is detected and refused, rather than
///     silently producing two different schemas in the field.
public struct MigrationRunner: Sendable {
    private let migrations: [any Migration.Type]
    private let clock: any Clock

    public init(migrations: [any Migration.Type], clock: any Clock = SystemClock()) throws {
        var seen = Set<Int>()
        for m in migrations {
            guard seen.insert(m.version).inserted else {
                throw MigrationError.duplicateVersion(m.version)
            }
        }
        self.migrations = migrations.sorted { $0.version < $1.version }
        self.clock = clock
    }

    private static let bootstrap = """
    CREATE TABLE IF NOT EXISTS schema_migrations (
        version     INTEGER PRIMARY KEY,
        name        TEXT    NOT NULL,
        applied_at  TEXT    NOT NULL
    );
    """

    public func applied(in db: Database) throws -> [AppliedMigration] {
        try db.execute(Self.bootstrap)
        let rows = try db.query("SELECT version, name, applied_at FROM schema_migrations ORDER BY version;")
        return rows.compactMap { row in
            guard let v = row.int("version"),
                  let n = row.string("name"),
                  let t = row.string("applied_at"),
                  let d = ISO8601DateFormatter().date(from: t) else { return nil }
            return AppliedMigration(version: Int(v), name: n, appliedAt: d)
        }
    }

    /// Returns the versions actually applied by this call.
    @discardableResult
    public func migrate(_ db: Database) throws -> [Int] {
        let already = try applied(in: db)
        let appliedByVersion = Dictionary(uniqueKeysWithValues: already.map { ($0.version, $0.name) })
        let head = already.map(\.version).max() ?? 0

        for m in migrations {
            if let storedName = appliedByVersion[m.version], storedName != m.name {
                throw MigrationError.checksumDrift(
                    version: m.version, storedName: storedName, incomingName: m.name
                )
            }
            if appliedByVersion[m.version] == nil && m.version < head {
                throw MigrationError.outOfOrder(applied: head, pending: m.version)
            }
        }

        var ran: [Int] = []
        for m in migrations where appliedByVersion[m.version] == nil {
            try db.transaction {
                try m.up(db)
                try db.run(
                    "INSERT INTO schema_migrations (version, name, applied_at) VALUES (?, ?, ?);",
                    [.integer(Int64(m.version)),
                     .text(m.name),
                     .text(ISO8601DateFormatter().string(from: clock.now))]
                )
            }
            ran.append(m.version)
        }
        return ran
    }
}
