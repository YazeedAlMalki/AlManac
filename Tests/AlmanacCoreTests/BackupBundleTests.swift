import XCTest
@testable import AlmanacCore

/// Whole-app bundle tests: the `.almanac-backup` container carries the live
/// database *and* every document file. These mirror the raw-database
/// `BackupService` tests in SyncAndBackupTests and pin the bundle-specific
/// guarantees — schema gating, integrity checks, and that nothing about the
/// live database changes until every validation has passed.
final class BackupBundleTests: XCTestCase {

    private func makeDB(_ path: String, anchors: [(domain: String, token: [UInt8])] = []) throws -> Database {
        let db = try Database(path: path)
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        for (domain, token) in anchors {
            try SyncAnchorStore(db: db).save(domain: domain, token: token)
        }
        return db
    }

    private func writeDoc(_ root: URL, _ relative: String, _ contents: String) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Creates a throwaway directory (SQLite does not create parent folders).
    private func tempDir() throws -> String {
        let dir = NSTemporaryDirectory() + "almanac-bundle-\(UUID().uuidString)"
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: dir), withIntermediateDirectories: true)
        return dir
    }

    private func fileSize(_ path: String) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }

    func testBundleRoundTripsDatabaseAndDocuments() throws {
        let dir = try tempDir()
        let sourcePath = dir + "/src.sqlite"
        let bundlePath = dir + "/snapshot.almanac-backup"
        let targetPath = dir + "/tgt.sqlite"
        let sourceDocs = URL(fileURLWithPath: dir + "/src-docs", isDirectory: true)
        let targetDocs = URL(fileURLWithPath: dir + "/tgt-docs", isDirectory: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        try FileManager.default.createDirectory(at: sourceDocs, withIntermediateDirectories: true)
        try writeDoc(sourceDocs, "d2a3f9/d1.txt", "lab result bytes")
        try writeDoc(sourceDocs, "abc.txt", "plain doc")

        let source = try makeDB(sourcePath, anchors: [("hrv", [4, 2])])
        let info = try BackupService(db: source).writeBundle(to: bundlePath, documentsRoot: sourceDocs, note: "round trip")
        XCTAssertEqual(info.documentCount, 2, "both documents must be captured")
        XCTAssertEqual(info.note, "round trip")

        // The bundle's own metadata is readable without any live database.
        let readBack = try BackupService(db: source).readBundleInfo(at: bundlePath)
        XCTAssertEqual(readBack.documentCount, 2)
        XCTAssertEqual(readBack.schemaVersion, info.schemaVersion,
                       "the bundle must record whatever schema it was taken at")
        XCTAssertEqual(readBack.byteCount, info.byteCount)
        XCTAssertEqual(info.byteCount, fileSize(bundlePath), "reported size must be the finished file's")

        // Restore into a separate, freshly migrated database + empty doc root.
        let target = try makeDB(targetPath)
        try BackupService(db: target).restoreBundle(at: bundlePath, documentsRoot: targetDocs)

        XCTAssertEqual(try SyncAnchorStore(db: target).load("hrv")?.token, [4, 2])
        XCTAssertEqual(
            try String(contentsOf: targetDocs.appendingPathComponent("d2a3f9/d1.txt"), encoding: .utf8),
            "lab result bytes")
        XCTAssertEqual(
            try String(contentsOf: targetDocs.appendingPathComponent("abc.txt"), encoding: .utf8),
            "plain doc")
    }

    func testDocumentWriteFailureLeavesTheTargetDocumentsUntouched() throws {
        let dir = try tempDir()
        let sourcePath = dir + "/src.sqlite"
        let bundlePath = dir + "/snapshot.almanac-backup"
        let targetPath = dir + "/tgt.sqlite"
        let sourceDocs = URL(fileURLWithPath: dir + "/src-docs", isDirectory: true)
        let targetDocs = URL(fileURLWithPath: dir + "/tgt-docs", isDirectory: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        try writeDoc(sourceDocs, "a.txt", "first document")
        try writeDoc(sourceDocs, "nested/b.txt", "second document")
        let source = try makeDB(sourcePath)
        try BackupService(db: source).writeBundle(to: bundlePath, documentsRoot: sourceDocs, note: nil)

        try FileManager.default.createDirectory(at: targetDocs, withIntermediateDirectories: true)
        try Data("not a directory".utf8).write(to: targetDocs.appendingPathComponent("nested"), options: .atomic)
        let target = try makeDB(targetPath, anchors: [("steps", [9])])

        do {
            try BackupService(db: target).restoreBundle(at: bundlePath, documentsRoot: targetDocs)
            XCTFail("restore must reject an unwritable document path")
        } catch BackupService.BackupError.cannotWriteDocument(let relativePath, _) {
            XCTAssertEqual(relativePath, "nested/b.txt")
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: targetDocs.appendingPathComponent("a.txt").path),
                       "a failed restore must not leave an earlier document behind")
        XCTAssertEqual(try SyncAnchorStore(db: target).load("steps")?.token, [9],
                       "a failed document restore must not replace the database")
    }

    func testRestoreReplacesDatabaseWholesaleAndLeavesExtraFiles() throws {
        let dir = try tempDir()
        let sourcePath = dir + "/src.sqlite"
        let bundlePath = dir + "/snapshot.almanac-backup"
        let targetPath = dir + "/tgt.sqlite"
        let sourceDocs = URL(fileURLWithPath: dir + "/src-docs", isDirectory: true)
        let targetDocs = URL(fileURLWithPath: dir + "/tgt-docs", isDirectory: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        try FileManager.default.createDirectory(at: sourceDocs, withIntermediateDirectories: true)
        try writeDoc(sourceDocs, "d1.txt", "from backup")
        let source = try makeDB(sourcePath, anchors: [("hrv", [4, 2])])
        try BackupService(db: source).writeBundle(to: bundlePath, documentsRoot: sourceDocs, note: nil)

        let target = try makeDB(targetPath, anchors: [("steps", [9])])
        try FileManager.default.createDirectory(at: targetDocs, withIntermediateDirectories: true)
        try writeDoc(targetDocs, "stray.bin", "not in backup")

        try BackupService(db: target).restoreBundle(at: bundlePath, documentsRoot: targetDocs)

        // Wholesale: newer target anchors are gone, snapshot anchors are back.
        XCTAssertEqual(try SyncAnchorStore(db: target).load("hrv")?.token, [4, 2])
        XCTAssertNil(try SyncAnchorStore(db: target).load("steps"),
                     "restore must replace the database wholesale, not merge into it")
        // Documents in the bundle are restored…
        XCTAssertEqual(try String(contentsOf: targetDocs.appendingPathComponent("d1.txt"), encoding: .utf8),
                       "from backup")
        // …and files outside it are left alone, unreferenced rather than deleted.
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetDocs.appendingPathComponent("stray.bin").path))
    }

    func testSchemaVersionGateRejectsMismatchedBundleBeforeMutating() throws {
        let dir = try tempDir()
        let sourcePath = dir + "/src.sqlite"
        let bundlePath = dir + "/snapshot.almanac-backup"
        let targetPath = dir + "/tgt.sqlite"
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let source = try makeDB(sourcePath, anchors: [("hrv", [4, 2])])
        try BackupService(db: source).writeBundle(to: bundlePath, documentsRoot: nil, note: nil)

        // Falsify the bundle's declared schema version.
        do {
            let tampered = try Database(path: bundlePath)
            try tampered.run("UPDATE bundle_meta SET schema_version = 999;")
        }

        let target = try makeDB(targetPath, anchors: [("steps", [9])])
        let service = BackupService(db: target)

        // Listing still works: an incompatible bundle is reported, not hidden.
        XCTAssertEqual(try service.readBundleInfo(at: bundlePath).schemaVersion, 999)

        do {
            try service.restoreBundle(at: bundlePath)
            XCTFail("restore must refuse a foreign schema")
        } catch BackupService.BackupError.incompatibleSchemaVersion(let found, let expected) {
            XCTAssertEqual(found, 999)
            XCTAssertEqual(expected, try migrationHead(targetPath))
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        XCTAssertEqual(try SyncAnchorStore(db: target).load("steps")?.token, [9],
                       "the schema gate must fail before any mutation")
    }

    func testTamperedDatabasePayloadIsRejectedBeforeMutating() throws {
        let dir = try tempDir()
        let sourcePath = dir + "/src.sqlite"
        let bundlePath = dir + "/snapshot.almanac-backup"
        let targetPath = dir + "/tgt.sqlite"
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let source = try makeDB(sourcePath, anchors: [("hrv", [4, 2])])
        try BackupService(db: source).writeBundle(to: bundlePath, documentsRoot: nil, note: nil)

        // Corrupt the database payload; the digest recorded in bundle_meta no
        // longer matches, and every check must run before anything mutates.
        do {
            let tampered = try Database(path: bundlePath)
            try tampered.run("UPDATE bundle_db SET bytes = x'deadbeef';")
        }

        let target = try makeDB(targetPath, anchors: [("steps", [9])])
        do {
            try BackupService(db: target).restoreBundle(at: bundlePath)
            XCTFail("restore must reject a checksum mismatch")
        } catch BackupService.BackupError.corruptBundle(let reason) {
            XCTAssertTrue(reason.contains("checksum"), "unexpected reason: \(reason)")
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        XCTAssertEqual(try SyncAnchorStore(db: target).load("steps")?.token, [9],
                       "a corrupt bundle must not touch the live database")
    }

    func testCorruptAndMissingFilesAreRejected() throws {
        let dir = try tempDir()
        let bundlePath = dir + "/broken.almanac-backup"
        defer { try? FileManager.default.removeItem(atPath: dir) }

        try Data("this is not a sqlite database at all".utf8)
            .write(to: URL(fileURLWithPath: bundlePath), options: .atomic)

        let service = BackupService(db: try makeDB(dir + "/live.sqlite"))
        do {
            _ = try service.readBundleInfo(at: bundlePath)
            XCTFail("garbage must not pass as a backup")
        } catch BackupService.BackupError.notABackupFile {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        do {
            let missing = dir + "/never-created.almanac-backup"
            _ = try service.readBundleInfo(at: missing)
            XCTFail("a missing file must not pass as a backup")
        } catch BackupService.BackupError.notABackupFile {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testBundleIsRecordedInManifest() throws {
        let dir = try tempDir()
        let sourcePath = dir + "/src.sqlite"
        let bundlePath = dir + "/snapshot.almanac-backup"
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let source = try makeDB(sourcePath)
        let info = try BackupService(db: source).writeBundle(to: bundlePath, documentsRoot: nil, note: "unit note")

        let row = try XCTUnwrap(try source.query(
            "SELECT sha256, schema_version, byte_count, note FROM backup_manifest ORDER BY id DESC LIMIT 1;"
        ).first)
        XCTAssertEqual(row.string("sha256")?.count, 64)
        XCTAssertEqual(row.int("byte_count"), info.byteCount, "manifest size must match the finished file")
        XCTAssertEqual(row.int("schema_version"), info.schemaVersion)
        XCTAssertEqual(row.string("note"), "unit note")
    }

    func testListBundlesReturnsNewestFirstAndSkipsBroken() throws {
        let dir = try tempDir()
        let sourcePath = dir + "/src.sqlite"
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let source = try makeDB(sourcePath)
        let early = FixedClock(Date(timeIntervalSince1970: 1_780_000_000))
        let late = FixedClock(Date(timeIntervalSince1970: 1_780_000_002))
        try BackupService(db: source, clock: early).writeBundle(to: dir + "/a.almanac-backup", documentsRoot: nil, note: nil)
        try BackupService(db: source, clock: late).writeBundle(to: dir + "/b.almanac-backup", documentsRoot: nil, note: nil)
        try Data("junk".utf8).write(to: URL(fileURLWithPath: dir + "/broken.almanac-backup"), options: .atomic)

        let listed = try BackupService(db: source).listBundles(in: dir)
        XCTAssertEqual(listed.map(\.fileName), ["b.almanac-backup", "a.almanac-backup"],
                       "valid bundles only, newest first")
    }

    private func migrationHead(_ dbPath: String) throws -> Int64 {
        let db = try Database(path: dbPath)
        return try db.query("SELECT COALESCE(MAX(version), 0) AS v FROM schema_migrations;")
            .first?.int("v") ?? 0
    }
}