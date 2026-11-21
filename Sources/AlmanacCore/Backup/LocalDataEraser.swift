import Foundation

/// The file half of "erase all data" (remediation P1-5): removes the SQLite
/// database files and the folders the app keeps its records in.
///
/// Kept in the core, away from the view that asks for it, so the part that must
/// not be wrong (every file really gone, and a failure *reported* rather than
/// ignored) is tested on Linux. The app-side caller (`AppDataEraser`) adds what
/// only the app can do: pending reminders, preferences, widgets, quitting.
///
/// What it cannot do, and the screen says so: data the person already put into
/// Apple Health lives in Apple Health, not in Almanac, and is removed there; a
/// backup already shared with somebody else is theirs.
public enum LocalDataEraser {
    public struct Failure: Error, CustomStringConvertible, Sendable {
        /// Paths that still exist after the attempt.
        public let remaining: [String]
        public var description: String {
            localized("Could not remove: %@", remaining.joined(separator: ", "))
        }
    }

    /// Removes each database file together with its `-wal` and `-shm` sidecars, then
    /// each directory with everything in it. A path that does not exist is not an
    /// error. Throws `Failure` listing whatever is still there afterwards.
    @discardableResult
    public static func erase(databaseFiles: [String], directories: [String]) throws -> [String] {
        let fm = FileManager.default
        var removed: [String] = []
        var remaining: [String] = []
        let files = databaseFiles.flatMap { [$0, $0 + "-wal", $0 + "-shm", $0 + "-journal"] }
        for path in files + directories {
            guard fm.fileExists(atPath: path) else { continue }
            do {
                try fm.removeItem(atPath: path)
                removed.append(path)
            } catch {
                remaining.append(path)
            }
            if fm.fileExists(atPath: path) { remaining.append(path) }
        }
        guard remaining.isEmpty else { throw Failure(remaining: Array(Set(remaining)).sorted()) }
        return removed
    }
}
