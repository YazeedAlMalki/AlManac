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
    /// File name of the exercise's demonstration graphic inside AlmanacCore's
    /// resource bundle. Every *shipped* row has one — see
    /// `ExerciseGraphicAudit`.
    public var graphicPath: String?
    public var confidence: String?
    public var notes: String?

    public init(sourceId: String, exerciseId: String, name: String, category: String? = nil,
                equipment: String? = nil, force: String? = nil, prescriptionType: String,
                licenseGroup: String, licenseAuthor: String? = nil, graphicPath: String? = nil,
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
        self.graphicPath = graphicPath
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
    public let graphicPath: String?
    public let confidence: String?
    public let notes: String?
    public let deletedAt: String?
    public let createdAt: String
    public let updatedAt: String

    public var isDeleted: Bool { deletedAt != nil }
}

/// One muscle group, with the method-of-training breakdown inside it.
public struct MuscleGroup: Sendable, Hashable, Identifiable {
    public let muscle: String
    /// True when nothing in this group is the exercise's primary muscle — it is
    /// listed here only because the movement also works this group. The browse
    /// UI says so rather than presenting it as a main entry.
    public let hasSecondaryOnly: Bool
    public let byEquipment: [EquipmentGroup]
    public var id: String { muscle }
}

/// One method of training inside a muscle group.
public struct EquipmentGroup: Sendable, Hashable, Identifiable {
    public let equipment: String
    public let exercises: [ExerciseCatalogEntry]
    public var id: String { equipment }
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
             licenseGroup, licenseAuthor, graphicPath, confidence, notes, createdAt, updatedAt)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, [
            .text(draft.sourceId), .text(draft.exerciseId), .text(draft.name),
            draft.category.map { SQLValue.text($0) } ?? .null,
            draft.equipment.map { SQLValue.text($0) } ?? .null,
            draft.force.map { SQLValue.text($0) } ?? .null,
            .text(draft.prescriptionType), .text(draft.licenseGroup),
            draft.licenseAuthor.map { SQLValue.text($0) } ?? .null,
            draft.graphicPath.map { SQLValue.text($0) } ?? .null,
            draft.confidence.map { SQLValue.text($0) } ?? .null,
            draft.notes.map { SQLValue.text($0) } ?? .null,
            .text(now), .text(now)
        ])
        var id: Int64 = 0
        if let row = try db.query("SELECT last_insert_rowid() as id;").first,
           let fetchedID = row.int("id") {
            id = fetchedID
        }
        // Mirror the primary muscle into `exerciseMuscle` here, at the write
        // path, rather than relying on Migration042's backfill alone. The
        // migration only sees rows that existed when it ran; the shipped
        // catalogue is seeded at launch, *after* migrations, so a backfill-only
        // approach would leave every real exercise with no muscle row and the
        // whole browse view reading as one "Unassigned" group. Keeping the
        // mirror here means the invariant holds for every insert, whenever it
        // happens.
        if id != 0, let category = draft.category?.trimmingCharacters(in: .whitespacesAndNewlines),
           !category.isEmpty {
            try addMuscle(to: id, muscle: category, isPrimary: true)
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

    // MARK: - Muscle grouping

    /// The catalogue grouped the way the owner asked to browse it: muscle
    /// group first, then method of training inside it.
    ///
    /// An exercise appears under **every** muscle in `exerciseMuscle`, not just
    /// its primary one, so a movement that works two muscle groups is listed in
    /// both. The primary flag is carried through because "also" and "mainly"
    /// are different claims and the browse UI should be able to say which is
    /// which. `equipment` is grouped inside the muscle, so the same movement
    /// reached by different methods reads as one thing rather than as duplicates
    /// split across sections.
    ///
    /// Exercises with no muscle row at all are **not** dropped silently: they
    /// come back under `"Unassigned"` so a catalogue gap is visible in the UI
    /// instead of making an exercise unreachable. Same for a missing
    /// `equipment`, which lands in `"Unspecified"`.
    public func groupedByMuscleThenEquipment() throws -> [MuscleGroup] {
        let entries = try all()

        // Primary muscle per exercise, for the fallback and for the flag.
        var primaryByExercise: [Int64: String] = [:]
        for row in try db.query("SELECT exerciseCatalogId, muscle FROM exerciseMuscle WHERE isPrimary = 1;") {
            guard let id = row.int("exerciseCatalogId"), let muscle = row.string("muscle") else { continue }
            primaryByExercise[id] = muscle
        }
        var secondaryByExercise: [Int64: [String]] = [:]
        for row in try db.query("SELECT exerciseCatalogId, muscle FROM exerciseMuscle WHERE isPrimary = 0;") {
            guard let id = row.int("exerciseCatalogId"), let muscle = row.string("muscle") else { continue }
            secondaryByExercise[id, default: []].append(muscle)
        }

        struct Accumulated { var primary: [ExerciseCatalogEntry] = []
                             var secondary: [ExerciseCatalogEntry] = [] }
        var byMuscle: [String: Accumulated] = [:]
        for entry in entries {
            let muscles = [primaryByExercise[entry.id]].compactMap { $0 }
                + (secondaryByExercise[entry.id] ?? [])
            let target = muscles.isEmpty ? ["Unassigned"] : muscles
            for muscle in target {
                let slot = byMuscle[muscle] ?? Accumulated()
                if muscle == primaryByExercise[entry.id] {
                    byMuscle[muscle] = Accumulated(primary: slot.primary + [entry],
                                                    secondary: slot.secondary)
                } else {
                    byMuscle[muscle] = Accumulated(primary: slot.primary,
                                                    secondary: slot.secondary + [entry])
                }
            }
        }

        return byMuscle
            .map { muscle, slot in
                var byEquipment: [String: [ExerciseCatalogEntry]] = [:]
                for entry in slot.primary + slot.secondary {
                    byEquipment[entry.equipment?.isEmpty == false ? entry.equipment! : "Unspecified",
                                default: []].append(entry)
                }
                return MuscleGroup(
                    muscle: muscle,
                    hasSecondaryOnly: slot.primary.isEmpty,
                    byEquipment: byEquipment
                        .map { EquipmentGroup(equipment: $0.key,
                                              exercises: $0.value.sorted { $0.name < $1.name }) }
                        .sorted { $0.equipment < $1.equipment })
            }
            // "Unassigned" is a gap, not a muscle, and sorts last so a real
            // catalogue gap does not lead the list.
            .sorted { a, b in
                if a.muscle == "Unassigned" { return false }
                if b.muscle == "Unassigned" { return true }
                return a.muscle < b.muscle
            }
    }

    /// Records an additional muscle for an exercise. `isPrimary` is false here
    /// on purpose — a secondary muscle is by definition not the main one, and
    /// promoting one is a data decision made deliberately, not as a side effect
    /// of adding it.
    public func addMuscle(to exerciseCatalogId: Int64, muscle: String,
                          isPrimary: Bool = false) throws {
        try db.run("""
        INSERT INTO exerciseMuscle (exerciseCatalogId, muscle, isPrimary, createdAt)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(exerciseCatalogId, muscle) DO UPDATE SET isPrimary = excluded.isPrimary;
        """, [.integer(exerciseCatalogId), .text(muscle),
              .integer(isPrimary ? 1 : 0), .text(nowText)])
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
            graphicPath: row.string("graphicPath"), confidence: row.string("confidence"),
            notes: row.string("notes"), deletedAt: row.string("deletedAt"),
            createdAt: createdAt, updatedAt: updatedAt
        )
    }
}
