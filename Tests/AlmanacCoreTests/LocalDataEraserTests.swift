import Foundation
import Testing
@testable import AlmanacCore

/// The file half of "erase all data" (remediation P1-5).
@Suite("Erase all data (P1-5)")
struct LocalDataEraserTests {
    private func scratch() throws -> String {
        let dir = NSTemporaryDirectory() + "almanac-erase-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("A real database in WAL mode, its sidecars and the folders are all gone")
    func removesEverything() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let dbPath = dir + "/almanac.sqlite"
        let db = try Database(path: dbPath)                 // WAL mode: creates -wal and -shm
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        try ProfileStore(db: db).updateEmail("name@example.com")
        let backups = dir + "/Almanac/Backups", documents = dir + "/Almanac/Documents"
        for folder in [backups, documents] {
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            try Data("private".utf8).write(to: URL(fileURLWithPath: folder + "/file.bin"))
        }
        #expect(FileManager.default.fileExists(atPath: dbPath + "-wal") || FileManager.default.fileExists(atPath: dbPath))

        let removed = try LocalDataEraser.erase(databaseFiles: [dbPath], directories: [dir + "/Almanac"])

        for path in [dbPath, dbPath + "-wal", dbPath + "-shm", dir + "/Almanac", backups, documents] {
            #expect(!FileManager.default.fileExists(atPath: path), "\(path) is still there")
        }
        #expect(removed.contains(dbPath))
        #expect(removed.contains(dir + "/Almanac"))
    }

    @Test("Paths that do not exist are not an error, and nothing else is touched")
    func missingPathsAndNeighbours() throws {
        let dir = try scratch()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let neighbour = dir + "/keep.txt"
        try Data("keep".utf8).write(to: URL(fileURLWithPath: neighbour))
        let removed = try LocalDataEraser.erase(databaseFiles: [dir + "/nope.sqlite"], directories: [dir + "/nothing-here"])
        #expect(removed.isEmpty)
        #expect(FileManager.default.fileExists(atPath: neighbour))
    }

    @Test("A path that cannot be removed is reported, not hidden")
    func failureIsReported() throws {
        let dir = try scratch()
        let locked = dir + "/locked"
        try FileManager.default.createDirectory(atPath: locked, withIntermediateDirectories: true)
        let inside = locked + "/file.txt"
        try Data("x".utf8).write(to: URL(fileURLWithPath: inside))
        // A directory without write permission cannot have entries removed from it.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: locked)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked)
            try? FileManager.default.removeItem(atPath: dir)
        }
        // Running as root (some CI containers) ignores permissions; then there is nothing to test.
        guard getuid() != 0 else { return }
        #expect(throws: LocalDataEraser.Failure.self) {
            try LocalDataEraser.erase(databaseFiles: [], directories: [locked])
        }
        #expect(FileManager.default.fileExists(atPath: inside))
    }
}
