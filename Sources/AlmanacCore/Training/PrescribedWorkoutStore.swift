import Foundation

/// A workout template read from storage.
public struct PrescribedWorkoutEntry: Sendable, Hashable, Identifiable {
    public let id: Int64
    public let name: String
    public let containerType: String
    public let notes: String?
    public let deletedAt: String?
    public let createdAt: String
    public let updatedAt: String

    public var isDeleted: Bool { deletedAt != nil }
}

/// One exercise a template prescribes, not yet stored. Only the fields its
/// `prescriptionType` calls for are set; the rest stay nil, not zero.
public struct PrescribedWorkoutItemDraft: Sendable, Hashable {
    public var exerciseCatalogId: Int64
    public var prescriptionType: String
    public var prescribedSets: Int?
    public var prescribedReps: Int?
    public var prescribedLoadKg: Double?
    public var prescribedDurationSeconds: Double?
    public var prescribedDistanceMeters: Double?
    public var prescribedWorkSeconds: Double?
    public var prescribedRestSeconds: Double?
    public var prescribedRounds: Int?

    public init(exerciseCatalogId: Int64, prescriptionType: String,
                prescribedSets: Int? = nil, prescribedReps: Int? = nil, prescribedLoadKg: Double? = nil,
                prescribedDurationSeconds: Double? = nil, prescribedDistanceMeters: Double? = nil,
                prescribedWorkSeconds: Double? = nil, prescribedRestSeconds: Double? = nil,
                prescribedRounds: Int? = nil) {
        self.exerciseCatalogId = exerciseCatalogId
        self.prescriptionType = prescriptionType
        self.prescribedSets = prescribedSets
        self.prescribedReps = prescribedReps
        self.prescribedLoadKg = prescribedLoadKg
        self.prescribedDurationSeconds = prescribedDurationSeconds
        self.prescribedDistanceMeters = prescribedDistanceMeters
        self.prescribedWorkSeconds = prescribedWorkSeconds
        self.prescribedRestSeconds = prescribedRestSeconds
        self.prescribedRounds = prescribedRounds
    }
}

/// One stored template exercise, in template order.
public struct PrescribedWorkoutItem: Sendable, Hashable, Identifiable {
    public let id: Int64
    public let prescribedWorkoutId: Int64
    public let sequenceIndex: Int
    public let draft: PrescribedWorkoutItemDraft

    public var exerciseCatalogId: Int64 { draft.exerciseCatalogId }
    public var prescriptionType: String { draft.prescriptionType }
}

/// Reusable workout templates over `prescribedWorkout`, and since 2026-10-06
/// the exercises each one prescribes (`prescribedWorkoutItem`, Migration 055).
///
/// The owner's decision: a template is **exercises, but editable**. A template's
/// items are copied onto a session's bouts when it is applied
/// (`TemplateApplier`), never referenced, so editing a template later never
/// rewrites a session the way it would if sessions pointed at mutable template
/// rows for their prescribed values.
public struct PrescribedWorkoutStore: @unchecked Sendable {
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

    /// Creates a template.
    ///
    /// `containerType` is validated against `TrainingContainer` rather than left
    /// free, because the column has a CHECK constraint: a value outside the
    /// model's ten would otherwise be a runtime SQL error at the insert instead
    /// of a typed mistake at the call site. The error names the offending value
    /// so the caller can say which one it was.
    @discardableResult
    public func create(name: String, containerType: String, notes: String? = nil) throws -> Int64 {
        guard TrainingContainer(rawValue: containerType) != nil else {
            throw PrescribedWorkoutStoreError.unknownContainerType(containerType)
        }
        let now = nowText
        try db.run("""
        INSERT INTO prescribedWorkout (name, containerType, notes, createdAt, updatedAt)
        VALUES (?, ?, ?, ?, ?);
        """, [.text(name), .text(containerType), notes.map { SQLValue.text($0) } ?? .null, .text(now), .text(now)])

        var id: Int64 = 0
        if let row = try db.query("SELECT last_insert_rowid() as id;").first,
           let fetchedID = row.int("id") {
            id = fetchedID
        }
        return id
    }

    @discardableResult
    public func delete(id: Int64) throws -> Bool {
        let changes = try db.run("""
        UPDATE prescribedWorkout SET deletedAt = ?, updatedAt = ? WHERE id = ? AND deletedAt IS NULL;
        """, [.text(nowText), .text(nowText), .integer(id)])
        return changes > 0
    }

    /// Live templates, by name.
    ///
    /// Excludes soft-deleted ones. `workout(id:)` deliberately does **not** — a
    /// past session can still name a template that has since been discontinued,
    /// and the review screen needs to be able to say which one that was. Listing
    /// deleted templates as if they were current is the trap; reading one
    /// because a history row points at it is not.
    public func templates() throws -> [PrescribedWorkoutEntry] {
        try db.query("""
        SELECT * FROM prescribedWorkout WHERE deletedAt IS NULL ORDER BY name COLLATE NOCASE;
        """).compactMap(Self.entry(from:))
    }

    public func update(id: Int64, name: String, containerType: String, notes: String?) throws -> Bool {
        try db.run("""
        UPDATE prescribedWorkout SET name = ?, containerType = ?, notes = ?, updatedAt = ?
        WHERE id = ? AND deletedAt IS NULL;
        """, [
            .text(name), .text(containerType),
            notes.map { SQLValue.text($0) } ?? .null,
            .text(nowText), .integer(id)
        ]) > 0
    }

    // MARK: - The exercises a template prescribes

    /// The template's exercises, in order.
    public func items(of workoutId: Int64) throws -> [PrescribedWorkoutItem] {
        try db.query("""
        SELECT * FROM prescribedWorkoutItem WHERE prescribedWorkoutId = ? ORDER BY sequenceIndex;
        """, [.integer(workoutId)]).compactMap(Self.item(from:))
    }

    /// Replaces the template's exercises with `drafts`, in that order, in one
    /// transaction. Refuses a discontinued template, a prescription type outside
    /// the twelve, and a count or measure that is not greater than zero — a
    /// blank is nil, never zero.
    public func setItems(_ drafts: [PrescribedWorkoutItemDraft], for workoutId: Int64) throws {
        guard let template = try workout(id: workoutId), !template.isDeleted else {
            throw PrescribedWorkoutStoreError.templateNotFound(workoutId)
        }
        for draft in drafts {
            guard PrescriptionKind(rawValue: draft.prescriptionType) != nil else {
                throw PrescribedWorkoutStoreError.unknownPrescriptionType(draft.prescriptionType)
            }
            let counts = [draft.prescribedSets, draft.prescribedReps, draft.prescribedRounds].compactMap { $0 }
            let measures = [draft.prescribedLoadKg, draft.prescribedDurationSeconds, draft.prescribedDistanceMeters,
                            draft.prescribedWorkSeconds, draft.prescribedRestSeconds].compactMap { $0 }
            guard counts.allSatisfy({ $0 > 0 }), measures.allSatisfy({ $0.isFinite && $0 > 0 }) else {
                throw PrescribedWorkoutStoreError.invalidPrescription
            }
        }
        let now = nowText
        try db.transaction {
            try db.run("DELETE FROM prescribedWorkoutItem WHERE prescribedWorkoutId = ?;", [.integer(workoutId)])
            for (index, draft) in drafts.enumerated() {
                try db.run("""
                INSERT INTO prescribedWorkoutItem
                    (prescribedWorkoutId, exerciseCatalogId, sequenceIndex, prescriptionType,
                     prescribedSets, prescribedReps, prescribedLoadKg, prescribedDurationSeconds,
                     prescribedDistanceMeters, prescribedWorkSeconds, prescribedRestSeconds,
                     prescribedRounds, createdAt)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """, [
                    .integer(workoutId), .integer(draft.exerciseCatalogId), .integer(Int64(index)),
                    .text(draft.prescriptionType),
                    Self.value(draft.prescribedSets), Self.value(draft.prescribedReps),
                    Self.value(draft.prescribedLoadKg), Self.value(draft.prescribedDurationSeconds),
                    Self.value(draft.prescribedDistanceMeters), Self.value(draft.prescribedWorkSeconds),
                    Self.value(draft.prescribedRestSeconds), Self.value(draft.prescribedRounds),
                    .text(now)
                ])
            }
        }
    }

    private static func value(_ int: Int?) -> SQLValue { int.map { .integer(Int64($0)) } ?? .null }
    private static func value(_ double: Double?) -> SQLValue { double.map { .real($0) } ?? .null }

    private static func item(from row: Row) -> PrescribedWorkoutItem? {
        guard let id = row.int("id"), let workoutId = row.int("prescribedWorkoutId"),
              let exerciseId = row.int("exerciseCatalogId"), let index = row.int("sequenceIndex"),
              let type = row.string("prescriptionType") else { return nil }
        return PrescribedWorkoutItem(
            id: id, prescribedWorkoutId: workoutId, sequenceIndex: Int(index),
            draft: PrescribedWorkoutItemDraft(
                exerciseCatalogId: exerciseId, prescriptionType: type,
                prescribedSets: row.int("prescribedSets").map { Int($0) },
                prescribedReps: row.int("prescribedReps").map { Int($0) },
                prescribedLoadKg: row.double("prescribedLoadKg"),
                prescribedDurationSeconds: row.double("prescribedDurationSeconds"),
                prescribedDistanceMeters: row.double("prescribedDistanceMeters"),
                prescribedWorkSeconds: row.double("prescribedWorkSeconds"),
                prescribedRestSeconds: row.double("prescribedRestSeconds"),
                prescribedRounds: row.int("prescribedRounds").map { Int($0) }))
    }

    public func workout(id: Int64) throws -> PrescribedWorkoutEntry? {
        try db.query("SELECT * FROM prescribedWorkout WHERE id = ?;", [.integer(id)])
            .first.flatMap(Self.entry(from:))
    }

    private static func entry(from row: Row) -> PrescribedWorkoutEntry? {
        guard let id = row.int("id"),
              let name = row.string("name"),
              let containerType = row.string("containerType"),
              let createdAt = row.string("createdAt"),
              let updatedAt = row.string("updatedAt") else { return nil }
        return PrescribedWorkoutEntry(id: id, name: name, containerType: containerType,
                                       notes: row.string("notes"), deletedAt: row.string("deletedAt"),
                                       createdAt: createdAt, updatedAt: updatedAt)
    }
}

public enum PrescribedWorkoutStoreError: Error, Sendable, Equatable {
    case unknownContainerType(String)
    case unknownPrescriptionType(String)
    case templateNotFound(Int64)
    /// A count or measure was zero, negative or not finite. Blank is nil.
    case invalidPrescription
}
