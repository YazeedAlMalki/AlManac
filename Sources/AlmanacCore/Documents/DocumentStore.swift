import Foundation

/// Decision recorded for this slice: a document the user adds is copied into a
/// **private, app-managed directory**, and SQLite holds only metadata plus a
/// path **relative to that directory's root**. Relative, because an absolute
/// path breaks on restore, on migration to a new device, and on any iOS
/// container-path change.
///
/// The root is injected rather than discovered, so the same code serves a test
/// temp directory and an app container.
///
/// **`BackupService.snapshot` does not cover these files.** It backs up the
/// SQLite database only, so after a restore the metadata rows can reference
/// files that are not there. Document import and backup integration are a
/// later slice; this slice records the decision and the interface.
public struct StoredDocument: Sendable, Hashable {
    public let relativePath: String
    public let byteCount: Int
    public let sha256: String
}

public protocol DocumentStoring: Sendable {
    var rootDescription: String { get }
    func store(bytes: [UInt8], preferredName: String) throws -> StoredDocument
    func read(relativePath: String) throws -> [UInt8]
    func exists(relativePath: String) -> Bool
}

public struct FileSystemDocumentStore: DocumentStoring {
    private let root: URL
    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    public var rootDescription: String { root.path }

    public func store(bytes: [UInt8], preferredName: String) throws -> StoredDocument {
        let digest = SHA256File.hex(of: bytes)
        let suffix = (preferredName as NSString).pathExtension
        let name = suffix.isEmpty ? digest : "\(digest).\(suffix)"
        let relative = "\(digest.prefix(2))/\(name)"
        let target = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: target.path) {
            try Data(bytes).write(to: target)
        }
        return StoredDocument(relativePath: relative, byteCount: bytes.count, sha256: digest)
    }

    public func read(relativePath: String) throws -> [UInt8] {
        Array(try Data(contentsOf: root.appendingPathComponent(relativePath)))
    }

    public func exists(relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(relativePath).path)
    }
}

/// Metadata rows and their links. Registration is separate from storing bytes,
/// so a document that exists only as a reference can still be recorded.
public struct LabDocumentStore: Sendable {
    private let db: Database
    private let clock: any Clock

    public init(db: Database, clock: any Clock = SystemClock()) {
        self.db = db
        self.clock = clock
    }

    @discardableResult
    public func register(kind: String, document: StoredDocument,
                         originalName: String? = nil) throws -> String {
        let id = UUID().uuidString
        try db.run("""
        INSERT INTO lab_document (id, kind, relative_path, original_name, byte_count, sha256, added_at)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """, [
            .text(id), .text(kind), .text(document.relativePath),
            originalName.map { SQLValue.text($0) } ?? .null,
            .integer(Int64(document.byteCount)), .text(document.sha256),
            .text(ISO8601DateFormatter().string(from: clock.now))
        ])
        return id
    }

    /// Many-to-many: one document may back many records, and one record may be
    /// evidenced by an original plus an amendment letter.
    public func link(documentID: String, to targetTable: String, targetID: String,
                     role: String) throws {
        try db.run("""
        INSERT INTO lab_document_link (document_id, target_table, target_id, role)
        VALUES (?, ?, ?, ?) ON CONFLICT DO NOTHING;
        """, [.text(documentID), .text(targetTable), .text(targetID), .text(role)])
    }

    public func documentIDs(for targetTable: String, targetID: String) throws -> [String] {
        try db.query("""
        SELECT document_id FROM lab_document_link WHERE target_table = ? AND target_id = ?;
        """, [.text(targetTable), .text(targetID)]).compactMap { $0.string("document_id") }
    }
}
