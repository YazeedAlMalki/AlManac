import Foundation
import AlmanacCore

/// Where the on-device database lives, shared between the app and its widgets.
///
/// A widget extension runs in its own sandbox and cannot read the app's
/// Application Support directory, so the database lives in an App Group
/// container (`group.com.almanac.personal`) that both processes can open.
/// When the group container is unavailable — an unsigned simulator build, or
/// a pre-App-Group install — callers fall back to the legacy Application
/// Support path so nothing stops working.
///
/// This file is compiled into **both** the app target and the widget
/// extension target (see `project.pbxproj`), which is what keeps the open
/// path identical everywhere instead of drifting.
enum AppGroupDatabase {
    static let appGroupIdentifier = "group.com.almanac.personal"

    /// The App Group container URL, when the entitlements are signed in.
    static var groupContainer: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    /// The database file to use: the App Group copy when that container
    /// exists, otherwise the legacy Application Support copy.
    static func fileURL() throws -> URL {
        if let group = groupContainer {
            return group.appendingPathComponent("almanac.sqlite")
        }
        return try legacyFileURL()
    }

    /// The pre-App-Group location (Application Support / Almanac).
    static func legacyFileURL() throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
            .appendingPathComponent("Almanac", isDirectory: true)
        return root.appendingPathComponent("almanac.sqlite")
    }

    /// Opens the shared database, upgraded to head schema.
    static func open() throws -> Database {
        let url = try fileURL()
        let db = try Database(path: url.path)
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        return db
    }

    /// One-time adoption of a pre-App-Group install's data into the group
    /// container. Checkpoints the legacy WAL first so no recent writes are
    /// lost, then copies the settled main file. No-op when the group container
    /// is unavailable or the group copy already exists.
    static func adoptLegacyData() throws {
        guard let group = groupContainer else { return } // nothing to adopt into
        let target = group.appendingPathComponent("almanac.sqlite")
        guard !FileManager.default.fileExists(atPath: target.path) else { return }
        let legacy = try legacyFileURL()
        guard FileManager.default.fileExists(atPath: legacy.path) else { return }
        let legacyDB = try Database(path: legacy.path)
        try legacyDB.execute("PRAGMA wal_checkpoint(TRUNCATE);")
        try FileManager.default.copyItem(at: legacy, to: target)
    }
}