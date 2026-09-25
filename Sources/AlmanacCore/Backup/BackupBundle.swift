import Foundation

/// Whole-app backups: one self-contained `.almanac-backup` file carrying the
/// live database **and** every document file, so a restore returns both to
/// the snapshot point.
///
/// The container is itself a SQLite database — no archive library, the same
/// open/query machinery as everything else, and free `file`-type inspection.
/// It holds three tables:
///
/// ```
/// bundle_meta (
///   format INTEGER NOT NULL,        -- 1
///   created_at TEXT NOT NULL,       -- ISO-8601, from the injected clock
///   schema_version INTEGER NOT NULL,-- migration head of the captured db
///   note TEXT,
///   db_sha256 TEXT NOT NULL         -- digest over the bundle_db payload
/// )
/// bundle_db (bytes BLOB NOT NULL)                 -- one consistent db file
/// bundle_files (relative_path TEXT PRIMARY KEY, bytes BLOB NOT NULL)
/// ```
///
/// A restore refuses to run when the bundle's `schema_version` differs from
/// the live database's head, and refuses to mutate anything until the
/// database payload has matched its recorded digest. Documents are staged
/// first, then committed with rollback before the database is swapped, so a
/// document-write failure cannot leave a partial set of files. Files on disk
/// that are not in the bundle are deliberately left alone — after a restore
/// they are simply unreferenced by the restored metadata.
public extension BackupService {

    /// Writes a whole-app snapshot to `path` and records it in
    /// `backup_manifest` exactly like `snapshot(to:note:)` does.
    ///
    /// - Parameters:
    ///   - documentsRoot: directory whose files are captured, each under its
    ///     path relative to this root. Pass `nil` for a database-only bundle.
    ///   - note: user-visible label, stored in the bundle and the manifest.
    /// - Returns: metadata straight from the finished file (its byte count is
    ///   the on-disk size, so it can be reported before the file is shared).
    @discardableResult
    func writeBundle(to path: String, documentsRoot: URL?, note: String? = nil) throws -> BackupBundleInfo {
        let fm = FileManager.default

        // 1. A consistent copy of the live database, flattened into one file.
        //    Copying the db file itself would be a moment that never existed
        //    under WAL; the online-backup API is the consistent primitive.
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("AlmanacBundle-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }
        let dbFile = tmpDir.appendingPathComponent("db.sqlite")
        do {
            let snapshot = try Database(path: dbFile.path)
            try db.backup(into: snapshot)
            // The payload blob must be the whole database, not the main file
            // plus a WAL sidecar carrying the newest pages.
            try snapshot.execute("PRAGMA wal_checkpoint(TRUNCATE);")
        }
        let dbBytes = try [UInt8](Data(contentsOf: dbFile))
        let dbDigest = SHA256File.hex(of: dbBytes)

        // 2. Every document, recorded by its path relative to the document root.
        var files: [(relativePath: String, bytes: [UInt8])] = []
        if let documentsRoot, fm.fileExists(atPath: documentsRoot.path) {
            guard let enumerator = fm.enumerator(at: documentsRoot,
                                                  includingPropertiesForKeys: [.isRegularFileKey],
                                                  options: [.skipsHiddenFiles]) else {
                throw BackupError.cannotReadDirectory(documentsRoot.path)
            }
            // The enumerator yields real paths (`/private/var/…` even when the
            // root was reached as `/var/…`), so resolve both sides before the
            // root prefix is stripped, or every relative path would come back
            // as an absolute path that the restore-side escape check rejects.
            let base = documentsRoot.resolvingSymlinksInPath().path + "/"
            for case let url as URL in enumerator {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey])
                guard values.isRegularFile == true else { continue }
                let full = url.resolvingSymlinksInPath().path
                guard full.hasPrefix(base) else { continue }
                let relative = String(full.dropFirst(base.count))
                files.append((relative, try [UInt8](Data(contentsOf: url))))
            }
        }

        // 3. Assemble the container. Any existing bundle at `path` is replaced;
        //    unrelated SQLite files are untouched (DROP ... IF EXISTS).
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path).deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let container: Database
        do {
            container = try Database(path: path)
        } catch {
            throw BackupError.cannotOpenDestination(path)
        }
        do {
            try container.execute("""
            DROP TABLE IF EXISTS bundle_meta;
            DROP TABLE IF EXISTS bundle_db;
            DROP TABLE IF EXISTS bundle_files;
            CREATE TABLE bundle_meta (
                format INTEGER NOT NULL,
                created_at TEXT NOT NULL,
                schema_version INTEGER NOT NULL,
                note TEXT,
                db_sha256 TEXT NOT NULL
            );
            CREATE TABLE bundle_db (bytes BLOB NOT NULL);
            CREATE TABLE bundle_files (relative_path TEXT PRIMARY KEY, bytes BLOB NOT NULL);
            """)
        } catch {
            throw BackupError.cannotOpenDestination(path)
        }

        let createdAt = ISO8601DateFormatter().string(from: clock.now)
        let schemaVersion = Int64(try currentSchemaVersion())
        try container.transaction {
            try container.run(
                "INSERT INTO bundle_meta (format, created_at, schema_version, note, db_sha256) VALUES (1, ?, ?, ?, ?);",
                [.text(createdAt), .integer(schemaVersion), note.map(SQLValue.text) ?? .null, .text(dbDigest)])
            try container.run("INSERT INTO bundle_db (bytes) VALUES (?);", [.blob(dbBytes)])
            for file in files {
                try container.run(
                    "INSERT INTO bundle_files (relative_path, bytes) VALUES (?, ?);",
                    [.text(file.relativePath), .blob(file.bytes)])
            }
        }
        // The shared file must be complete on its own: checkpoint the WAL into
        // the main file, then leave the container in DELETE mode so no sidecar
        // survives next to a bundle the user is about to share.
        try container.execute("PRAGMA wal_checkpoint(TRUNCATE);")
        try container.execute("PRAGMA journal_mode = DELETE;")
        removeSidecars(at: path)

        // 4. Record it like `snapshot(to:note:)` would have.
        let attrs = try fm.attributesOfItem(atPath: path)
        let byteCount = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        try db.run("""
        INSERT INTO backup_manifest (created_at, schema_version, byte_count, sha256, note)
        VALUES (?, ?, ?, ?, ?);
        """, [
            .text(createdAt),
            .integer(schemaVersion),
            .integer(byteCount),
            .text(try SHA256File.hex(ofFileAt: path)),
            note.map(SQLValue.text) ?? .null,
        ])

        return BackupBundleInfo(filePath: path, createdAt: createdAt, schemaVersion: schemaVersion,
                                note: note, byteCount: byteCount, documentCount: files.count)
    }

    /// Reads and validates a bundle **without touching the live database**.
    ///
    /// Throws `notABackupFile` for anything that is not a structurally valid
    /// bundle and `corruptBundle` when the database payload fails its checksum
    /// (a truncated or tampered transfer). A schema-version mismatch is
    /// *reported*, not thrown, so a list can show older backups and disable
    /// restore on them; only `restoreBundle` gates.
    func readBundleInfo(at path: String) throws -> BackupBundleInfo {
        let fm = FileManager.default
        let (_, meta, _) = try openValidBundle(at: path)
        let attrs = try fm.attributesOfItem(atPath: path)
        let byteCount = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        return BackupBundleInfo(filePath: path, createdAt: meta.createdAt, schemaVersion: meta.schemaVersion,
                                note: meta.note, byteCount: byteCount, documentCount: meta.documentCount)
    }

    /// Replaces this database's contents with a bundle's, wholesale, and
    /// writes every bundled document back under its recorded relative path.
    ///
    /// Runs nothing that mutates until the file is a valid, untampered bundle
    /// of a compatible schema. See the file header for why documents are
    /// written before the database is swapped, and what is left alone.
    func restoreBundle(at path: String, documentsRoot: URL? = nil) throws {
        let fm = FileManager.default
        let expected = Int64(try currentSchemaVersion())
        let (container, meta, dbBytes) = try openValidBundle(at: path)
        defer { removeSidecars(at: path) }
        guard meta.schemaVersion == expected else {
            throw BackupError.incompatibleSchemaVersion(found: meta.schemaVersion, expected: expected)
        }

        // Materialize and validate the database before committing any live
        // document. HealthKit de-duplication also happens on this private copy,
        // so the only remaining database operation is the final swap.
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("AlmanacRestore-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }
        let restoredFile = tmpDir.appendingPathComponent("restored.sqlite")
        try Data(dbBytes).write(to: restoredFile, options: .atomic)
        let restored = try Database(path: restoredFile.path)
        do {
            _ = try restored.query("SELECT COUNT(*) AS n FROM schema_migrations;")
        } catch {
            throw BackupError.corruptBundle(reason: "database payload is not an Almanac database")
        }
        try HydrationStore(db: restored).reconcileAfterRestore()

        var attemptedDocumentTargets: [URL] = []
        var originalDocuments: [(target: URL, data: Data?)] = []
        var createdDocumentDirectories: [URL] = []

        // Documents first; database last (see file header for the asymmetry).
        // Stage every payload before touching the live document root, then
        // commit with a small rollback journal so a write/move failure cannot
        // leave a half-restored set of files behind.
        if let documentsRoot {
            let fileRows: [Row]
            do {
                fileRows = try container.query("SELECT relative_path, bytes FROM bundle_files ORDER BY relative_path;")
            } catch {
                throw BackupError.notABackupFile(path)
            }
            let staging = fm.temporaryDirectory.appendingPathComponent(
                "AlmanacDocuments-\(UUID().uuidString)", isDirectory: true
            )
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: staging) }

            var staged: [(relativePath: String, target: URL, bytes: [UInt8])] = []
            for row in fileRows {
                guard let relativePath = row.string("relative_path"),
                      case .blob(let bytes)? = row["bytes"] else {
                    throw BackupError.corruptBundle(reason: "unreadable document payload")
                }
                let target = try validatedDocumentTarget(relativePath: relativePath, under: documentsRoot)
                do {
                    let stagedURL = staging.appendingPathComponent(relativePath).standardizedFileURL
                    let stagingPath = staging.resolvingSymlinksInPath().standardizedFileURL.path
                    guard stagedURL.resolvingSymlinksInPath().standardizedFileURL.path
                        .hasPrefix(stagingPath + "/") else {
                        throw BackupError.corruptBundle(
                            reason: "staged document path escapes its staging root: \\(relativePath)"
                        )
                    }
                    try fm.createDirectory(at: stagedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try Data(bytes).write(to: stagedURL, options: .atomic)
                    staged.append((relativePath, target, bytes))
                } catch {
                    throw BackupError.cannotWriteDocument(relativePath: relativePath,
                                                          underlying: String(describing: error))
                }
            }

            for document in staged {
                do {
                    try validateDocumentTarget(document.target, under: documentsRoot)
                    if fm.fileExists(atPath: document.target.path) {
                        originalDocuments.append((document.target, try Data(contentsOf: document.target)))
                    } else {
                        originalDocuments.append((document.target, nil))
                    }
                } catch {
                    throw BackupError.cannotWriteDocument(relativePath: document.relativePath,
                                                          underlying: String(describing: error))
                }
            }

            var currentRelativePath = "document"
            do {
                for document in staged {
                    currentRelativePath = document.relativePath
                    attemptedDocumentTargets.append(document.target)
                    for directory in missingDocumentDirectories(for: document.target, under: documentsRoot)
                    where !createdDocumentDirectories.contains(directory) {
                        createdDocumentDirectories.append(directory)
                    }
                    try fm.createDirectory(at: document.target.deletingLastPathComponent(),
                                           withIntermediateDirectories: true)
                    try Data(document.bytes).write(to: document.target, options: .atomic)
                }
            } catch {
                let rollbackFailures = rollbackDocuments(
                    attemptedDocumentTargets,
                    originals: originalDocuments,
                    createdDirectories: createdDocumentDirectories
                )
                if !rollbackFailures.isEmpty {
                    throw BackupError.rollbackFailed(rollbackFailures.joined(separator: "; "))
                }
                throw BackupError.cannotWriteDocument(relativePath: currentRelativePath,
                                                      underlying: String(describing: error))
            }
        }

        do {
            // Database last, wholesale: the target's current contents are replaced.
            try restored.backup(into: db)
        } catch {
            let failures = rollbackDocuments(
                attemptedDocumentTargets,
                originals: originalDocuments,
                createdDirectories: createdDocumentDirectories
            )
            if !failures.isEmpty {
                throw BackupError.rollbackFailed(failures.joined(separator: "; "))
            }
            throw error
        }
    }

    private func validatedDocumentTarget(relativePath: String, under root: URL) throws -> URL {
        let components = URL(fileURLWithPath: relativePath).pathComponents
        guard !components.contains("..") else {
            throw BackupError.corruptBundle(reason: "document path contains '..': \\(relativePath)")
        }
        let target = URL(fileURLWithPath: relativePath, relativeTo: root).standardizedFileURL
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        let resolvedParent = target.deletingLastPathComponent().resolvingSymlinksInPath()
        let targetPath = resolvedParent
            .appendingPathComponent(target.lastPathComponent)
            .resolvingSymlinksInPath()
            .standardizedFileURL.path
        guard targetPath.hasPrefix(rootPath + "/") else {
            throw BackupError.corruptBundle(
                reason: "document path escapes the document root: \(relativePath)"
            )
        }
        return target
    }

    private func validateDocumentTarget(_ target: URL, under root: URL) throws {
        let fm = FileManager.default
        let rootPath = root.standardizedFileURL.path
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: rootPath, isDirectory: &isDirectory), !isDirectory.boolValue {
            throw NSError(domain: "AlmanacBackup", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "document root is not a directory"
            ])
        }
        if fm.fileExists(atPath: target.path, isDirectory: &isDirectory), isDirectory.boolValue {
            throw NSError(domain: "AlmanacBackup", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "document target is a directory"
            ])
        }
    }

    private func missingDocumentDirectories(for target: URL, under root: URL) -> [URL] {
        let fm = FileManager.default
        let rootPath = root.standardizedFileURL.path
        var current = target.deletingLastPathComponent().standardizedFileURL
        var directories: [URL] = []
        while current.path != rootPath {
            guard !fm.fileExists(atPath: current.path) else { break }
            directories.append(current)
            let parent = current.deletingLastPathComponent()
            guard parent.path != current.path else { break }
            current = parent
        }
        return directories.reversed()
    }

    private func rollbackDocuments(_ targets: [URL],
                                   originals: [(target: URL, data: Data?)],
                                   createdDirectories: [URL]) -> [String] {
        let fm = FileManager.default
        var failures: [String] = []
        for target in targets.reversed() {
            do {
                if let original = originals.first(where: { $0.target == target })?.data {
                    try Data(original).write(to: target, options: .atomic)
                } else if fm.fileExists(atPath: target.path) {
                    try fm.removeItem(at: target)
                }
            } catch {
                failures.append("\(target.path): \(String(describing: error))")
            }
        }
        for directory in createdDirectories.reversed() {
            do {
                guard fm.fileExists(atPath: directory.path) else { continue }
                var isDirectory: ObjCBool = false
                guard fm.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                    continue
                }
                if try fm.contentsOfDirectory(atPath: directory.path).isEmpty {
                    try fm.removeItem(at: directory)
                }
            } catch {
                failures.append("\(directory.path): \(String(describing: error))")
            }
        }
        return failures
    }

    /// Enumerates the valid bundles in a directory, newest first.
    ///
    /// The list is keyed on the files themselves, not on `backup_manifest`:
    /// that table lives inside the database a restore replaces, so a list keyed
    /// on it would forget every bundle created after the restored snapshot
    /// point. Files that fail validation (a `.almanac-backup` that did not
    /// survive a transfer) are skipped rather than fatal.
    func listBundles(in directory: String) throws -> [BackupBundleInfo] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory) else { return [] }
        let entries: [URL]
        do {
            entries = try fm.contentsOfDirectory(at: URL(fileURLWithPath: directory),
                                                 includingPropertiesForKeys: nil,
                                                 options: [.skipsHiddenFiles])
        } catch {
            throw BackupError.cannotReadDirectory(directory)
        }
        var infos: [BackupBundleInfo] = []
        for url in entries where url.pathExtension == "almanac-backup" {
            if let info = try? readBundleInfo(at: url.path) { infos.append(info) }
        }
        // `created_at` is ISO-8601 from one formatter, so lexical order is
        // chronological order.
        return infos.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Container internals

    private struct BundleMeta {
        let createdAt: String
        let schemaVersion: Int64
        let note: String?
        let documentCount: Int
    }

    /// Opens a bundle and validates its structure, its declared schema row and
    /// the database payload's checksum. Throws before returning on any
    /// failure; the returned handle stays open for the caller to read files
    /// from.
    private func openValidBundle(at path: String) throws -> (Database, BundleMeta, [UInt8]) {
        guard FileManager.default.fileExists(atPath: path) else { throw BackupError.notABackupFile(path) }
        let container: Database
        do { container = try Database(path: path) }
        catch { throw BackupError.notABackupFile(path) }

        let rows: [Row]
        do { rows = try container.query("SELECT format, created_at, schema_version, note, db_sha256 FROM bundle_meta;") }
        catch { throw BackupError.notABackupFile(path) }

        guard let row = rows.first, rows.count == 1, row.int("format") == 1,
              let createdAt = row.string("created_at"),
              let schemaVersion = row.int("schema_version"),
              let dbSHA256 = row.string("db_sha256") else {
            throw BackupError.notABackupFile(path)
        }

        let dbBytes = try extractDBPayload(container, path: path)
        guard SHA256File.hex(of: dbBytes) == dbSHA256 else {
            throw BackupError.corruptBundle(reason: "database payload failed its checksum")
        }
        let documentCount = (try? container.query("SELECT COUNT(*) AS n FROM bundle_files;").first?.int("n")) ?? 0
        let meta = BundleMeta(createdAt: createdAt, schemaVersion: schemaVersion,
                              note: row.string("note"), documentCount: Int(documentCount))
        return (container, meta, dbBytes)
    }

    private func extractDBPayload(_ container: Database, path: String) throws -> [UInt8] {
        let rows: [Row]
        do { rows = try container.query("SELECT bytes FROM bundle_db;") }
        catch { throw BackupError.notABackupFile(path) }
        guard let row = rows.first, rows.count == 1,
              case .blob(let bytes)? = row["bytes"], !bytes.isEmpty else {
            throw BackupError.missingPayload("database")
        }
        return bytes
    }

    /// Opening a bundle runs `PRAGMA journal_mode = WAL` and can drop `-shm`/
    /// `-wal` sidecars next to a file that must stay a single shareable blob.
    /// Removing them after the handle is gone is safe (they are rebuildable
    /// scaffolding, and a bundle is never written outside `writeBundle`).
    private func removeSidecars(at path: String) {
        let fm = FileManager.default
        for suffix in ["-wal", "-shm"] {
            try? fm.removeItem(atPath: path + suffix)
        }
    }
}

/// Metadata about one `.almanac-backup` file, read from the file itself.
///
/// Deliberately file-derived rather than manifest-derived: the
/// `backup_manifest` table lives inside a database that restores replace.
public struct BackupBundleInfo: Sendable, Hashable, Identifiable {
    public let filePath: String
    public let createdAt: String
    public let schemaVersion: Int64
    public let note: String?
    public let byteCount: Int64
    public let documentCount: Int

    public var id: String { filePath }
    public var fileName: String { (filePath as NSString).lastPathComponent }

    public init(filePath: String, createdAt: String, schemaVersion: Int64,
                note: String?, byteCount: Int64, documentCount: Int) {
        self.filePath = filePath
        self.createdAt = createdAt
        self.schemaVersion = schemaVersion
        self.note = note
        self.byteCount = byteCount
        self.documentCount = documentCount
    }
}