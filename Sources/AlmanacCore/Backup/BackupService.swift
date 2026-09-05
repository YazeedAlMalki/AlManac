import Foundation
import CSQLite

/// Skeleton backup/restore.
///
/// Uses SQLite's online backup API rather than copying the file, because a WAL
/// database on disk is not a consistent snapshot — copying it while the app is
/// running produces a backup that restores to a moment that never existed.
public struct BackupService: Sendable {
    private let db: Database
    private let clock: any Clock

    public init(db: Database, clock: any Clock = SystemClock()) {
        self.db = db
        self.clock = clock
    }

    public enum BackupError: Error, CustomStringConvertible, Sendable {
        case cannotOpenDestination(String)
        case backupFailed(Int32)
        case restoreNotImplemented

        public var description: String {
            switch self {
            case .cannotOpenDestination(let p): return "Could not open backup destination at \(p)"
            case .backupFailed(let c): return "SQLite backup failed with code \(c)"
            case .restoreNotImplemented:
                return "Restore is deliberately unimplemented until the spec's restore semantics are available."
            }
        }
    }

    /// Writes a consistent snapshot to `path` and records it in `backup_manifest`.
    @discardableResult
    public func snapshot(to path: String, note: String? = nil) throws -> Int64 {
        let destination = try Database(path: path)
        try db.backup(into: destination)

        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        let bytes = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let digest = try SHA256File.hex(ofFileAt: path)
        let version = try currentSchemaVersion()

        try db.run("""
        INSERT INTO backup_manifest (created_at, schema_version, byte_count, sha256, note)
        VALUES (?, ?, ?, ?, ?);
        """, [
            .text(ISO8601DateFormatter().string(from: clock.now)),
            .integer(Int64(version)),
            .integer(bytes),
            .text(digest),
            note.map { SQLValue.text($0) } ?? .null
        ])
        return bytes
    }

    private func currentSchemaVersion() throws -> Int {
        let rows = try db.query("SELECT COALESCE(MAX(version), 0) AS v FROM schema_migrations;")
        return Int(rows.first?.int("v") ?? 0)
    }

    /// Restore is intentionally not implemented. The spec defines what happens
    /// to in-flight sync anchors and to user rows created after the snapshot;
    /// guessing that is how a restore silently loses a day of logs.
    public func restore(from path: String) throws -> Never {
        throw BackupError.restoreNotImplemented
    }
}

extension Database {
    /// SQLite online backup API — a consistent copy even under WAL.
    func backup(into destination: Database) throws {
        try withHandles(destination) { src, dst in
            guard let b = sqlite3_backup_init(dst, "main", src, "main") else {
                throw BackupService.BackupError.backupFailed(sqlite3_errcode(dst))
            }
            sqlite3_backup_step(b, -1)
            let rc = sqlite3_backup_finish(b)
            guard rc == SQLITE_OK else { throw BackupService.BackupError.backupFailed(rc) }
        }
    }
}
