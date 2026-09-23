import XCTest
@testable import AlmanacCore

/// The ZIP wrapper (BRD §6.18): export shares a `.zip` around the canonical
/// `.almanac-backup` container; import accepts both. These pin the wrapper
/// without touching the container format itself — the zip must be a lossless
/// envelope and restore must run identically on the unzipped bundle.
final class BackupZipperTests: XCTestCase {

    private func tempDir() throws -> String {
        let dir = NSTemporaryDirectory() + "almanac-zip-\(UUID().uuidString)"
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: dir), withIntermediateDirectories: true)
        return dir
    }

    private func seededDB(_ path: String) throws -> Database {
        let db = try Database(path: path)
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        try SyncAnchorStore(db: db).save(domain: "steps", token: [1, 2, 3])
        return db
    }

    func testZipEnvelopeRoundTripsBundle() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let dbPath = dir + "/src.sqlite"
        let bundlePath = dir + "/snapshot.almanac-backup"
        let db = try seededDB(dbPath)
        try BackupService(db: db).writeBundle(to: bundlePath, documentsRoot: nil, note: "zip round trip")

        let zipPath = try BackupZipper.zip(bundlePath: bundlePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: zipPath))
        XCTAssertTrue(zipPath.hasSuffix(".zip"))

        // Unzip into a clean directory and restore from the extracted bundle —
        // identical to a user importing a shared zip.
        let out = try tempDir()
        defer { try? FileManager.default.removeItem(atPath: out) }
        let extracted = try BackupZipper.unzip(archivePath: zipPath, into: out)
        XCTAssertEqual(URL(fileURLWithPath: extracted).lastPathComponent, "snapshot.almanac-backup")

        let targetPath = out + "/target.sqlite"
        let target = try Database(path: targetPath)
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(target)
        try BackupService(db: target).restoreBundle(at: extracted)
        XCTAssertEqual(try SyncAnchorStore(db: target).load("steps")?.token, [1, 2, 3],
                       "restore from the unzipped bundle must match a direct restore")
    }

    func testUnzipRefusesArchiveWithoutExactlyOneBundle() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        // A zip over a file that is not a backup must be refused, not guessed.
        let junk = dir + "/note.txt"
        try "not a backup".write(toFile: junk, atomically: true, encoding: .utf8)
        let junkZip = try BackupZipper.zip(bundlePath: junk)

        let out = try tempDir()
        defer { try? FileManager.default.removeItem(atPath: out) }
        XCTAssertThrowsError(try BackupZipper.unzip(archivePath: junkZip, into: out)) { error in
            guard case BackupService.BackupError.notABackupFile = error else {
                return XCTFail("expected notABackupFile, got \(error)")
            }
        }
    }

    func testUnzipRejectsPayloadCorruption() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let bundlePath = dir + "/snapshot.almanac-backup"
        let db = try seededDB(dir + "/src.sqlite")
        try BackupService(db: db).writeBundle(to: bundlePath, documentsRoot: nil)
        let zipPath = try BackupZipper.zip(bundlePath: bundlePath)

        // Flip one payload byte in the zip so the CRC-32 check must fire.
        var bytes = try Data(contentsOf: URL(fileURLWithPath: zipPath))
        bytes[bytes.count - 200] ^= 0xFF
        try bytes.write(to: URL(fileURLWithPath: zipPath), options: .atomic)

        let out = try tempDir()
        defer { try? FileManager.default.removeItem(atPath: out) }
        XCTAssertThrowsError(try BackupZipper.unzip(archivePath: zipPath, into: out)) { error in
            guard case BackupService.BackupError.corruptBundle = error else {
                return XCTFail("expected corruptBundle, got \(error)")
            }
        }
    }

    #if os(macOS)
    /// The point of the wrapper is interop: the zip this app exports must be a
    /// plain zip any standard tool opens. `/usr/bin/unzip` is the cheapest
    /// oracle for that (present on every macOS; the core stays Linux-safe
    /// because the test is gated, not the codec).
    func testExportedZipOpensWithSystemUnzip() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let db = try seededDB(dir + "/src.sqlite")
        let bundlePath = dir + "/snapshot.almanac-backup"
        try BackupService(db: db).writeBundle(to: bundlePath, documentsRoot: nil)
        let zipPath = try BackupZipper.zip(bundlePath: bundlePath)

        let out = dir + "/sys-extract"
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: out), withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", zipPath, "-d", out]
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "system unzip must accept the exported zip")
        XCTAssertTrue(FileManager.default.fileExists(atPath: out + "/snapshot.almanac-backup"),
                      "the system tool must reveal the bundle inside")
    }
    #endif
}