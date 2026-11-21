import Foundation
import Testing
@testable import AlmanacCore

/// Regression tests for audit finding S-01 (CWE-501 / CWE-345; see
/// `SECURITY_PRIVACY_AUDIT.md`): `restoreBundle` used to compare only triggers and
/// views, then swap the foreign file in wholesale, so a payload could bring its own
/// expression indexes, virtual tables, loosened CHECK constraints or extra columns
/// into the live database.
///
/// A restore now refuses any payload whose schema (everything but SQLite's own
/// bookkeeping) differs from the migrations' by a single character, and does so
/// before any statement is run against the payload.
@Suite("Restore trusts only the app's own schema (S-01)")
struct RestoreSchemaTrustTests {

    private func makeDB(_ path: String) throws -> Database {
        let db = try Database(path: path)
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        return db
    }

    private func tempDir() throws -> String {
        let dir = NSTemporaryDirectory() + "almanac-schema-trust-\(UUID().uuidString)"
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: dir), withIntermediateDirectories: true)
        return dir
    }

    /// Builds a bundle from a database altered by `tamper`, then tries to restore it
    /// into a pristine, freshly migrated database. Returns what the restore did and
    /// the schema objects the target gained as a result.
    private func restoreTampered(_ tamper: (Database) throws -> Void) throws -> (outcome: Result<Void, Error>, added: Set<String>) {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let bundlePath = dir + "/tampered.almanac-backup"

        let source = try makeDB(dir + "/src.sqlite")
        try tamper(source)
        try BackupService(db: source).writeBundle(to: bundlePath, documentsRoot: nil, note: nil)

        let target = try makeDB(dir + "/tgt.sqlite")
        let before = try schemaObjects(target)
        let outcome: Result<Void, Error>
        do {
            try BackupService(db: target).restoreBundle(at: bundlePath)
            outcome = .success(())
        } catch {
            outcome = .failure(error)
        }
        return (outcome, try schemaObjects(target).subtracting(before))
    }

    private func schemaObjects(_ db: Database) throws -> Set<String> {
        Set(try db.query("SELECT type || ':' || name AS k FROM sqlite_master;").compactMap { $0.string("k") })
    }

    @Test("A payload with an extra expression index is refused")
    func refusesForeignExpressionIndex() throws {
        let result = try restoreTampered { source in
            try source.execute("CREATE INDEX planted_expr_idx ON sync_anchor (length(sampleType) + 1);")
        }
        #expect(throws: BackupService.BackupError.self) { try result.outcome.get() }
        #expect(result.added.isEmpty, "a schema object the app does not define reached the live database: \(result.added)")
    }

    // No virtual-table module is compiled into CSQLite any more (FTS5 was removed
    // with S-04/S-05), so a planted virtual table cannot be built here; an extra
    // view stands in for "a schema object of a kind the app never defines".
    @Test("A payload with an extra view is refused")
    func refusesForeignView() throws {
        let result = try restoreTampered { source in
            try source.execute("CREATE VIEW planted_view AS SELECT sampleType FROM sync_anchor;")
        }
        #expect(throws: BackupService.BackupError.self) { try result.outcome.get() }
        #expect(result.added.isEmpty, "a schema object the app does not define reached the live database: \(result.added)")
    }

    @Test("A payload whose table definition was altered is refused")
    func refusesAlteredTableDefinition() throws {
        let result = try restoreTampered { source in
            try source.execute("ALTER TABLE sync_anchor ADD COLUMN planted TEXT;")
        }
        #expect(throws: BackupService.BackupError.self) { try result.outcome.get() }
    }

    @Test("A payload with no schema drift still restores")
    func acceptsAnUntamperedPayload() throws {
        let result = try restoreTampered { _ in }
        #expect(throws: Never.self) { try result.outcome.get() }
        #expect(result.added.isEmpty)
    }
}
