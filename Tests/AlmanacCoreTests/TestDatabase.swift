import Foundation
@testable import AlmanacCore

/// Shared test helper: an in-memory database with every migration already
/// applied, for tests that exercise a store or bridge against real tables
/// rather than hand-rolled schema.
///
/// Added 2026-09-16 while fixing the build: every Slice 2 (and drink/caffeine)
/// Swift Testing file already called `TestDatabase()` as if this existed —
/// it never did, so the test target did not compile. This restores the
/// helper those files were written against, rather than rewriting ten test
/// files to a different pattern.
func TestDatabase() throws -> Database {
    let db = try Database.inMemory()
    let runner = try MigrationRunner(migrations: AlmanacMigrations.all)
    try runner.migrate(db)
    return db
}
