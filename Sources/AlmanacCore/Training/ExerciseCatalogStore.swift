import Foundation

/// An exercise catalog entry not yet written to storage.
public struct ExerciseCatalogDraft: Sendable {
    public var sourceId: String
    public var exerciseId: String
    public var name: String
    public var category: String?
    public var equipment: String?
    public var force: String?
    public var prescriptionType: String
    public var licenseGroup: String
    /// The publisher's per-row author (wger's `license_author`). Kept so a
    /// per-exercise credit line, or the Attributions page's per-author list,
    /// can name whoever licensed that individual exercise.
    public var licenseAuthor: String?
    public var confidence: String?
    public var notes: String?

    public init(sourceId: String, exerciseId: String, name: String, category: String? = nil,
                equipment: String? = nil, force: String? = nil, prescriptionType: String,
                licenseGroup: String, licenseAuthor: String? = nil,
                confidence: String? = nil, notes: String? = nil) {
        self.sourceId = sourceId
        self.exerciseId = exerciseId
        self.name = name
        self.category = category
        self.equipment = equipment
        self.force = force
        self.prescriptionType = prescriptionType
        self.licenseGroup = licenseGroup
        self.licenseAuthor = licenseAuthor
        self.confidence = confidence
        self.notes = notes
    }
}

/// An exercise catalog entry read from storage.
public struct ExerciseCatalogEntry: Sendable, Hashable, Identifiable {
    public let id: Int64
    public let sourceId: String
    public let exerciseId: String
    public let name: String
    public let category: String?
    public let equipment: String?
    public let force: String?
    public let prescriptionType: String
    public let licenseGroup: String
    public let licenseAuthor: String?
    public let confidence: String?
    public let notes: String?
    public let deletedAt: String?
    public let createdAt: String
    public let updatedAt: String

    public var isDeleted: Bool { deletedAt != nil }
}

/// Exercise library storage over `exerciseCatalog`.
///
/// `(sourceId, exerciseId)` is the identity a re-import de-duplicates on —
/// mirrors `nutrition_food`'s `(source, external id)` pattern rather than
/// inventing a new one.
public struct ExerciseCatalogStore: @unchecked Sendable {
    let db: Database
    private let clock: any Clock

    public init(db: Database, clock: any Clock = SystemClock()) {
        self.db = db
        self.clock = clock
    }

    private var nowText: String { iso(clock.now) }
    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    // MARK: - Write

    @discardableResult
    public func insert(_ draft: ExerciseCatalogDraft) throws -> Int64 {
        let now = nowText
        try db.run("""
        INSERT INTO exerciseCatalog
            (sourceId, exerciseId, name, category, equipment, force, prescriptionType,
             licenseGroup, licenseAuthor, confidence, notes, createdAt, updatedAt)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, [
            .text(draft.sourceId), .text(draft.exerciseId), .text(draft.name),
            draft.category.map { SQLValue.text($0) } ?? .null,
            draft.equipment.map { SQLValue.text($0) } ?? .null,
            draft.force.map { SQLValue.text($0) } ?? .null,
            .text(draft.prescriptionType), .text(draft.licenseGroup),
            draft.licenseAuthor.map { SQLValue.text($0) } ?? .null,
            draft.confidence.map { SQLValue.text($0) } ?? .null,
            draft.notes.map { SQLValue.text($0) } ?? .null,
            .text(now), .text(now)
        ])
        var id: Int64 = 0
        if let row = try db.query("SELECT last_insert_rowid() as id;").first,
           let fetchedID = row.int("id") {
            id = fetchedID
        }
        return id
    }

    /// Soft delete. Returns `false` if the row was already deleted (or does
    /// not exist) — deleting is idempotent, not an error.
    @discardableResult
    public func delete(id: Int64) throws -> Bool {
        let changes = try db.run("""
        UPDATE exerciseCatalog SET deletedAt = ?, updatedAt = ? WHERE id = ? AND deletedAt IS NULL;
        """, [.text(nowText), .text(nowText), .integer(id)])
        return changes > 0
    }

    // MARK: - Read

    public func exercise(id: Int64) throws -> ExerciseCatalogEntry? {
        try db.query("SELECT * FROM exerciseCatalog WHERE id = ?;", [.integer(id)])
            .first.flatMap(Self.entry(from:))
    }

    public func exercise(sourceId: String, exerciseId: String) throws -> ExerciseCatalogEntry? {
        try db.query("""
        SELECT * FROM exerciseCatalog WHERE sourceId = ? AND exerciseId = ? AND deletedAt IS NULL;
        """, [.text(sourceId), .text(exerciseId)]).first.flatMap(Self.entry(from:))
    }

    /// Live (non-deleted) exercises with the given prescription type.
    public func exercises(prescriptionType: String) throws -> [ExerciseCatalogEntry] {
        try db.query("""
        SELECT * FROM exerciseCatalog WHERE prescriptionType = ? AND deletedAt IS NULL ORDER BY name;
        """, [.text(prescriptionType)]).compactMap(Self.entry(from:))
    }

    /// All live (non-deleted) exercises.
    public func all() throws -> [ExerciseCatalogEntry] {
        try db.query("SELECT * FROM exerciseCatalog WHERE deletedAt IS NULL ORDER BY name;")
            .compactMap(Self.entry(from:))
    }

    // MARK: - Private

    private static func entry(from row: Row) -> ExerciseCatalogEntry? {
        guard let id = row.int("id"),
              let sourceId = row.string("sourceId"),
              let exerciseId = row.string("exerciseId"),
              let name = row.string("name"),
              let prescriptionType = row.string("prescriptionType"),
              let licenseGroup = row.string("licenseGroup"),
              let createdAt = row.string("createdAt"),
              let updatedAt = row.string("updatedAt") else { return nil }
        return ExerciseCatalogEntry(
            id: id, sourceId: sourceId, exerciseId: exerciseId, name: name,
            category: row.string("category"), equipment: row.string("equipment"),
            force: row.string("force"), prescriptionType: prescriptionType,
            licenseGroup: licenseGroup, licenseAuthor: row.string("licenseAuthor"),
            confidence: row.string("confidence"),
            notes: row.string("notes"), deletedAt: row.string("deletedAt"),
            createdAt: createdAt, updatedAt: updatedAt
        )
    }
}
