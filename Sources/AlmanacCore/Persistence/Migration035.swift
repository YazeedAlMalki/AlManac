import Foundation

/// Migration 035 — `exerciseCatalog.graphicPath`, and withdrawal of the old
/// wger catalogue.
///
/// The requirement is that every exercise shipped in Almanac includes a
/// demonstration graphic, so the catalog row has to name its own graphic
/// rather than leaving the link implicit. Nullable because a future
/// hand-authored (`almanac:`) row may have none; `ExerciseGraphicAudit` is
/// what makes "every *shipped* exercise has one" a build failure.
///
/// The second statement withdraws the 21-row wger CC0 seed an earlier build
/// wrote. Those exercises have no compliant demonstration graphic in any
/// source (see `WorkoutGuideSeed`'s header for the measurement), so leaving
/// them live would put the app in breach of the rule its own launch-time
/// guard enforces — an upgraded app would simply refuse to open. Soft delete,
/// never erase: a `workoutBout` logged against one of those exercises must
/// still resolve to its name, exactly as `nutrition_log`'s pattern requires.
public enum Migration035_ExerciseGraphic: Migration {
    public static let version = 35
    public static let name = "exercise_graphic"

    /// The sources withdrawn for having no compliant demonstration graphic.
    static let withdrawnSourceIds = ["wger"]

    public static func up(_ db: Database) throws {
        try db.execute("ALTER TABLE exerciseCatalog ADD COLUMN graphicPath TEXT;")
        for sourceId in withdrawnSourceIds {
            try db.run("""
            UPDATE exerciseCatalog SET deletedAt = ?, updatedAt = ?
            WHERE sourceId = ? AND deletedAt IS NULL;
            """, [.text(iso), .text(iso), .text(sourceId)])
        }
    }

    private static var iso: String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: Date())
    }
}
