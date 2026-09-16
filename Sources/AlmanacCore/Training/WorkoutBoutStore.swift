import Foundation

/// One bout of work not yet written to storage.
///
/// Prescribed and actual are separate field groups on purpose — see
/// `Migration016_TrainingSchema`'s header and prescription-model-v0.1.md §1.
/// A bout only ever fills in the fields its `prescriptionType` calls for;
/// the rest stay `nil`, not zero.
public struct WorkoutBoutDraft: Sendable {
    public var sessionId: Int64
    public var exerciseCatalogId: Int64
    public var sequenceIndex: Int
    public var prescriptionType: String
    public var containerType: String?

    public var prescribedSets: Int?
    public var prescribedReps: Int?
    public var prescribedLoadKg: Double?
    public var prescribedDurationSeconds: Double?
    public var prescribedDistanceMeters: Double?
    public var prescribedWorkSeconds: Double?
    public var prescribedRestSeconds: Double?
    public var prescribedRounds: Int?

    public var actualSets: Int?
    public var actualReps: Int?
    public var actualLoadKg: Double?
    public var actualDurationSeconds: Double?
    public var actualDistanceMeters: Double?
    public var actualRounds: Int?
    public var elapsedSeconds: Double?
    public var avgHeartRate: Int?
    public var rpe: Int?
    public var techniqueRating: String?
    public var notes: String?

    public init(sessionId: Int64, exerciseCatalogId: Int64, sequenceIndex: Int = 0,
                prescriptionType: String, containerType: String? = nil,
                prescribedSets: Int? = nil, prescribedReps: Int? = nil, prescribedLoadKg: Double? = nil,
                prescribedDurationSeconds: Double? = nil, prescribedDistanceMeters: Double? = nil,
                prescribedWorkSeconds: Double? = nil, prescribedRestSeconds: Double? = nil,
                prescribedRounds: Int? = nil,
                actualSets: Int? = nil, actualReps: Int? = nil, actualLoadKg: Double? = nil,
                actualDurationSeconds: Double? = nil, actualDistanceMeters: Double? = nil,
                actualRounds: Int? = nil, elapsedSeconds: Double? = nil, avgHeartRate: Int? = nil,
                rpe: Int? = nil, techniqueRating: String? = nil, notes: String? = nil) {
        self.sessionId = sessionId
        self.exerciseCatalogId = exerciseCatalogId
        self.sequenceIndex = sequenceIndex
        self.prescriptionType = prescriptionType
        self.containerType = containerType
        self.prescribedSets = prescribedSets
        self.prescribedReps = prescribedReps
        self.prescribedLoadKg = prescribedLoadKg
        self.prescribedDurationSeconds = prescribedDurationSeconds
        self.prescribedDistanceMeters = prescribedDistanceMeters
        self.prescribedWorkSeconds = prescribedWorkSeconds
        self.prescribedRestSeconds = prescribedRestSeconds
        self.prescribedRounds = prescribedRounds
        self.actualSets = actualSets
        self.actualReps = actualReps
        self.actualLoadKg = actualLoadKg
        self.actualDurationSeconds = actualDurationSeconds
        self.actualDistanceMeters = actualDistanceMeters
        self.actualRounds = actualRounds
        self.elapsedSeconds = elapsedSeconds
        self.avgHeartRate = avgHeartRate
        self.rpe = rpe
        self.techniqueRating = techniqueRating
        self.notes = notes
    }
}

/// A bout read from storage.
public struct WorkoutBoutEntry: Sendable, Hashable, Identifiable {
    public let id: Int64
    public let sessionId: Int64
    public let exerciseCatalogId: Int64
    public let sequenceIndex: Int
    public let prescriptionType: String
    public let containerType: String?

    public let prescribedSets: Int?
    public let prescribedReps: Int?
    public let prescribedLoadKg: Double?
    public let prescribedDurationSeconds: Double?
    public let prescribedDistanceMeters: Double?
    public let prescribedWorkSeconds: Double?
    public let prescribedRestSeconds: Double?
    public let prescribedRounds: Int?

    public let actualSets: Int?
    public let actualReps: Int?
    public let actualLoadKg: Double?
    public let actualDurationSeconds: Double?
    public let actualDistanceMeters: Double?
    public let actualRounds: Int?
    public let elapsedSeconds: Double?
    public let avgHeartRate: Int?
    public let rpe: Int?
    public let techniqueRating: String?
    public let notes: String?

    public let deletedAt: String?
    public let createdAt: String
    public let updatedAt: String

    public var isDeleted: Bool { deletedAt != nil }
}

/// Bout storage over `workoutBout`.
public struct WorkoutBoutStore: @unchecked Sendable {
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
    public func log(_ draft: WorkoutBoutDraft) throws -> Int64 {
        let now = nowText
        try db.run("""
        INSERT INTO workoutBout
            (sessionId, exerciseCatalogId, sequenceIndex, prescriptionType, containerType,
             prescribedSets, prescribedReps, prescribedLoadKg, prescribedDurationSeconds,
             prescribedDistanceMeters, prescribedWorkSeconds, prescribedRestSeconds, prescribedRounds,
             actualSets, actualReps, actualLoadKg, actualDurationSeconds, actualDistanceMeters,
             actualRounds, elapsedSeconds, avgHeartRate, rpe, techniqueRating, notes,
             createdAt, updatedAt)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, [
            .integer(draft.sessionId), .integer(draft.exerciseCatalogId), .integer(Int64(draft.sequenceIndex)),
            .text(draft.prescriptionType), draft.containerType.map { SQLValue.text($0) } ?? .null,
            draft.prescribedSets.map { SQLValue.integer(Int64($0)) } ?? .null,
            draft.prescribedReps.map { SQLValue.integer(Int64($0)) } ?? .null,
            draft.prescribedLoadKg.map { SQLValue.real($0) } ?? .null,
            draft.prescribedDurationSeconds.map { SQLValue.real($0) } ?? .null,
            draft.prescribedDistanceMeters.map { SQLValue.real($0) } ?? .null,
            draft.prescribedWorkSeconds.map { SQLValue.real($0) } ?? .null,
            draft.prescribedRestSeconds.map { SQLValue.real($0) } ?? .null,
            draft.prescribedRounds.map { SQLValue.integer(Int64($0)) } ?? .null,
            draft.actualSets.map { SQLValue.integer(Int64($0)) } ?? .null,
            draft.actualReps.map { SQLValue.integer(Int64($0)) } ?? .null,
            draft.actualLoadKg.map { SQLValue.real($0) } ?? .null,
            draft.actualDurationSeconds.map { SQLValue.real($0) } ?? .null,
            draft.actualDistanceMeters.map { SQLValue.real($0) } ?? .null,
            draft.actualRounds.map { SQLValue.integer(Int64($0)) } ?? .null,
            draft.elapsedSeconds.map { SQLValue.real($0) } ?? .null,
            draft.avgHeartRate.map { SQLValue.integer(Int64($0)) } ?? .null,
            draft.rpe.map { SQLValue.integer(Int64($0)) } ?? .null,
            draft.techniqueRating.map { SQLValue.text($0) } ?? .null,
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

    @discardableResult
    public func delete(id: Int64) throws -> Bool {
        let changes = try db.run("""
        UPDATE workoutBout SET deletedAt = ?, updatedAt = ? WHERE id = ? AND deletedAt IS NULL;
        """, [.text(nowText), .text(nowText), .integer(id)])
        return changes > 0
    }

    // MARK: - Read

    public func bout(id: Int64) throws -> WorkoutBoutEntry? {
        try db.query("SELECT * FROM workoutBout WHERE id = ?;", [.integer(id)])
            .first.flatMap(Self.entry(from:))
    }

    /// Live bouts for a session, in logged order.
    public func bouts(sessionId: Int64) throws -> [WorkoutBoutEntry] {
        try db.query("""
        SELECT * FROM workoutBout WHERE sessionId = ? AND deletedAt IS NULL ORDER BY sequenceIndex, id;
        """, [.integer(sessionId)]).compactMap(Self.entry(from:))
    }

    // MARK: - Private

    private static func entry(from row: Row) -> WorkoutBoutEntry? {
        guard let id = row.int("id"),
              let sessionId = row.int("sessionId"),
              let exerciseCatalogId = row.int("exerciseCatalogId"),
              let sequenceIndex = row.int("sequenceIndex"),
              let prescriptionType = row.string("prescriptionType"),
              let createdAt = row.string("createdAt"),
              let updatedAt = row.string("updatedAt") else { return nil }
        return WorkoutBoutEntry(
            id: id, sessionId: sessionId, exerciseCatalogId: exerciseCatalogId,
            sequenceIndex: Int(sequenceIndex), prescriptionType: prescriptionType,
            containerType: row.string("containerType"),
            prescribedSets: row.int("prescribedSets").map(Int.init),
            prescribedReps: row.int("prescribedReps").map(Int.init),
            prescribedLoadKg: row.double("prescribedLoadKg"),
            prescribedDurationSeconds: row.double("prescribedDurationSeconds"),
            prescribedDistanceMeters: row.double("prescribedDistanceMeters"),
            prescribedWorkSeconds: row.double("prescribedWorkSeconds"),
            prescribedRestSeconds: row.double("prescribedRestSeconds"),
            prescribedRounds: row.int("prescribedRounds").map(Int.init),
            actualSets: row.int("actualSets").map(Int.init),
            actualReps: row.int("actualReps").map(Int.init),
            actualLoadKg: row.double("actualLoadKg"),
            actualDurationSeconds: row.double("actualDurationSeconds"),
            actualDistanceMeters: row.double("actualDistanceMeters"),
            actualRounds: row.int("actualRounds").map(Int.init),
            elapsedSeconds: row.double("elapsedSeconds"),
            avgHeartRate: row.int("avgHeartRate").map(Int.init),
            rpe: row.int("rpe").map(Int.init),
            techniqueRating: row.string("techniqueRating"),
            notes: row.string("notes"),
            deletedAt: row.string("deletedAt"), createdAt: createdAt, updatedAt: updatedAt
        )
    }
}
