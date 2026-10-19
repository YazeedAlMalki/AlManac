import Foundation

/// The exercise library on top of workout-guide: free-exercise-db (primary)
/// and wger (secondary), chosen by the owner on 2026-10-19, merged so each
/// real exercise is one record (`tools/exercises`, which writes the bundled
/// `exercise-library.json` and `docs/features/exercise-merge-log.md`).
///
/// A record is either a new `exerciseCatalog` row (its base is a
/// free-exercise-db row, shipped with that row's photo) or an existing
/// workout-guide row that other sources matched. Either way every contributing
/// source gets an `exerciseSource` row carrying its own licence, author and
/// field values, so attribution and "which source said what" survive the merge.
///
/// **Licensing.** free-exercise-db is released under the Unlicense; the
/// provenance of its photos is not stated by its publisher, a risk the owner
/// accepted on 2026-10-19 (`docs/exercise-sources.md`). wger licenses each
/// exercise separately (CC BY-SA 3.0/4.0, CC BY 4.0, CC0) and its rows carry
/// that licence and author here. wger's images are not shipped; a wger-only
/// exercise has no graphic and is held by the build, not shipped.
public enum ExerciseLibrarySeed {
    public static let freeExerciseDbSourceId = "free-exercise-db"
    public static let wgerSourceId = "wger"

    struct Library: Decodable {
        let records: [Record]
    }

    struct Record: Decodable {
        let sourceId: String
        let exerciseId: String
        let insert: Insert?
        let sources: [Source]
    }

    struct Insert: Decodable {
        let name: String
        let category: String?
        let equipment: String?
        let force: String?
        let secondaryMuscles: [String]
        let prescriptionType: String
        let licenseGroup: String
        let licenseAuthor: String?
        let graphicPath: String
    }

    struct Source: Decodable {
        let sourceId: String
        let exerciseId: String
        let licenseGroup: String
        let licenseAuthor: String?
        let fields: Fields
    }

    struct Fields: Codable {
        let name: String
        let primaryMuscle: String?
        let equipment: String?
        let secondaryMuscles: [String]?
        let force: String?
    }

    static func loadRecords() -> [Record] {
        guard let url = Bundle.module.url(forResource: "exercise-library", withExtension: "json") else {
            assertionFailure("exercise-library.json missing from AlmanacCore's resource bundle")
            return []
        }
        do {
            return try JSONDecoder().decode(Library.self, from: Data(contentsOf: url)).records
        } catch {
            assertionFailure("exercise-library.json failed to decode: \(error)")
            return []
        }
    }

    /// Inserts every record and source row not already present. Run after
    /// `WorkoutGuideSeed`, whose rows some records extend. Returns how many
    /// catalogue rows were inserted.
    @discardableResult
    public static func seed(into store: ExerciseCatalogStore) throws -> Int {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let now = ISO8601DateFormatter().string(from: Date())
        let records = loadRecords()
        // This runs at every launch: once every source row is in, there is
        // nothing to do, so skip the write transaction on the main thread.
        let expected = records.reduce(0) { $0 + $1.sources.count }
        if let held = try store.db.query("SELECT COUNT(*) AS n FROM exerciseSource;").first?.int("n"),
           held >= expected { return 0 }
        return try store.db.transaction {
            var inserted = 0
            for record in records {
                var row = try store.exercise(sourceId: record.sourceId, exerciseId: record.exerciseId)
                if row == nil, let new = record.insert {
                    let id = try store.insert(ExerciseCatalogDraft(
                        sourceId: record.sourceId, exerciseId: record.exerciseId, name: new.name,
                        category: new.category, equipment: new.equipment, force: new.force,
                        prescriptionType: new.prescriptionType, licenseGroup: new.licenseGroup,
                        licenseAuthor: new.licenseAuthor, graphicPath: new.graphicPath,
                        confidence: "high"))
                    for muscle in new.secondaryMuscles where muscle != new.category {
                        try store.addMuscle(to: id, muscle: muscle)
                    }
                    inserted += 1
                    row = try store.exercise(id: id)
                }
                // A workout-guide row a person deleted stays deleted; its sources go with it.
                guard let catalogId = row?.id else { continue }
                for source in record.sources {
                    let fields = String(decoding: try encoder.encode(source.fields), as: UTF8.self)
                    try store.db.run("""
                    INSERT OR IGNORE INTO exerciseSource
                        (exerciseCatalogId, sourceId, sourceExerciseId, licenseGroup, licenseAuthor, fields, createdAt)
                    VALUES (?, ?, ?, ?, ?, ?, ?);
                    """, [.integer(catalogId), .text(source.sourceId), .text(source.exerciseId),
                          .text(source.licenseGroup), source.licenseAuthor.map { SQLValue.text($0) } ?? .null,
                          .text(fields), .text(now)])
                }
            }
            return inserted
        }
    }
}

/// One source behind an exercise record, read from `exerciseSource`.
public struct ExerciseSourceRecord: Sendable, Hashable {
    public let exerciseCatalogId: Int64
    public let sourceId: String
    public let sourceExerciseId: String
    public let licenseGroup: String
    public let licenseAuthor: String?
    /// That source's own values, as JSON (`name`, `primaryMuscle`, `equipment`…).
    public let fields: String
}

extension ExerciseCatalogStore {
    /// Every source row, or only those behind one record.
    public func sources(exerciseCatalogId: Int64? = nil) throws -> [ExerciseSourceRecord] {
        let rows = try exerciseCatalogId.map {
            try db.query("SELECT * FROM exerciseSource WHERE exerciseCatalogId = ? ORDER BY sourceId, sourceExerciseId;",
                         [.integer($0)])
        } ?? db.query("SELECT * FROM exerciseSource ORDER BY sourceId, sourceExerciseId;")
        return rows.compactMap { row in
            guard let catalogId = row.int("exerciseCatalogId"), let sourceId = row.string("sourceId"),
                  let sourceExerciseId = row.string("sourceExerciseId"),
                  let licenseGroup = row.string("licenseGroup"), let fields = row.string("fields")
            else { return nil }
            return ExerciseSourceRecord(exerciseCatalogId: catalogId, sourceId: sourceId,
                                        sourceExerciseId: sourceExerciseId, licenseGroup: licenseGroup,
                                        licenseAuthor: row.string("licenseAuthor"), fields: fields)
        }
    }
}
