import Foundation

/// The bundled exercise catalogue: all 302 exercises from
/// `bryllim/workout-guide` (Bryl Lim), each shipped with the demonstration
/// graphic drawn for that exercise. Both the exercise list and the per-frame
/// attribution come from workout-guide's own `manifest.json`, copied into
/// AlmanacCore's resource bundle — nothing is retyped, so a re-sync can diff
/// against upstream.
///
/// **Why workout-guide and not a wger seed with borrowed graphics.** The
/// requirement is that every shipped exercise has a demonstration graphic.
/// Measured against the sources in `docs/exercise-sources.md`, a name-matched
/// graphic could not satisfy it: "Pause Bench", "Thruster" and "Glute-Ham
/// Raise" have no clean-licensed illustration in any source (only
/// free-exercise-db, whose photo provenance is unverified), and several
/// others only match the *wrong* movement — "Wall Squat" against
/// workout-guide's "Squat". workout-guide's own catalogue sidesteps the
/// problem: the frames were drawn for these exercises, so the graphic is
/// correct for the row it ships with. The 21-row wger CC0 seed that preceded
/// this was removed for the same reason — those exercises have no compliant
/// graphic, so shipping them would break the rule.
///
/// **Licensing.** Every frame is CC BY-SA 4.0 by Bryl Lim, and 76 of the 906
/// frames are vector-traced from Everkinetic art (recorded per frame in
/// `upstreamChanges`, and credited on the Attributions page). Almanac ships
/// the PNGs unmodified.
public enum WorkoutGuideSeed {
    public static let sourceId = "workout-guide"

    public struct Row: Sendable, Decodable {
        public let id: String
        public let name: String
        public let exerciseType: String
        public let equipment: String?
        public let primaryMuscle: String?
        public let isStretch: Bool
        public let graphic: String
        public let license: String?
        public let licenseUrl: String?
        public let licenseAuthor: String?
        public let upstreamName: String?
        public let upstreamUrl: String?
        public let upstreamChanges: String?
    }

    /// Maps workout-guide's `exerciseType` onto Almanac's twelve prescription
    /// types (`docs/features/training.md` §2). The mapping is mechanical and
    /// lives here rather than per row so it is reviewable; the one judgement
    /// it encodes is that a static hold among the `duration` exercises is
    /// `time_under_load` (the model's own table lists wall sits and planks),
    /// recognised by the same name tokens the model's §6 rule uses.
    public static func prescriptionType(exerciseType: String, isStretch: Bool, name: String) -> String {
        if isStretch { return "hold_stretch" }
        switch exerciseType {
        case "weight_reps": return "reps_load"
        case "bodyweight_reps", "assisted_bodyweight": return "reps_bodyweight"
        case "distance_duration": return "distance"
        case "duration":
            let lowered = name.lowercased()
            return ["hold", "plank", "sit", "hang"].contains { lowered.contains($0) }
                ? "time_under_load" : "duration"
        default: return "session_only"
        }
    }

    static func loadRows() -> [Row] {
        guard let url = Bundle.module.url(forResource: "manifest", withExtension: "json",
                                          subdirectory: ExerciseGraphics.directory) else {
            assertionFailure("workout-guide manifest.json missing from AlmanacCore's resource bundle")
            return []
        }
        do {
            return try JSONDecoder().decode([Row].self, from: Data(contentsOf: url))
        } catch {
            assertionFailure("workout-guide manifest.json failed to decode: \(error)")
            return []
        }
    }

    /// Inserts every row not already present, matched on `(sourceId, exerciseId)`
    /// as `WgerCC0Seed` did. Returns how many rows were actually inserted.
    @discardableResult
    public static func seed(into store: ExerciseCatalogStore) throws -> Int {
        var inserted = 0
        for row in loadRows() {
            if try store.exercise(sourceId: sourceId, exerciseId: row.id) != nil { continue }
            let notes = row.upstreamName.map {
                "Graphic derived from \($0): \(row.upstreamChanges ?? "modification not stated")"
            }
            _ = try store.insert(ExerciseCatalogDraft(
                sourceId: sourceId, exerciseId: row.id, name: row.name,
                category: row.primaryMuscle, equipment: row.equipment,
                prescriptionType: prescriptionType(exerciseType: row.exerciseType,
                                                    isStretch: row.isStretch, name: row.name),
                licenseGroup: "cc_by_sa_4", licenseAuthor: row.licenseAuthor,
                graphicPath: row.graphic, confidence: "high", notes: notes
            ))
            inserted += 1
        }
        return inserted
    }
}
