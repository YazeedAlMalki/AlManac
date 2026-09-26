import Foundation

/// Migration 042 — `exerciseMuscle`: an exercise can belong to more than one
/// muscle group.
///
/// The owner asked (2026-09-26) for exercises to be browsable as
/// **muscle group → method of training**, with exercises that activate several
/// muscles appearing under each of them. The two halves of that were in
/// different states:
///
/// - **Method already existed.** `exerciseCatalog.equipment` carries 17
///   distinct values across the shipped catalogue (Barbell, Dumbbell, Cable,
///   Machine, Bodyweight, Kettlebell, Resistance Band, Pull-up Bar, …).
/// - **Muscle group half-existed.** `exerciseCatalog.category` holds a single
///   primary muscle (Chest, Quads, Lats, Rear Delts, …), which is enough to
///   browse by group but structurally cannot express "this movement also
///   works the triceps".
///
/// So the schema is added here and seeded with the primary muscle, which makes
/// the many-to-many real without inventing a single anatomy claim. Populating
/// *secondary* muscles is deliberately left as a data task: naming the
/// secondary movers of 300-odd movements is a judgement about physiology, and
/// this repo's standing rule is that a guessed value written into user data is
/// worse than an absent one. The table is the missing half; the data is a
/// separate, reviewable import.
///
/// `primaryMuscle` is stored rather than inferred so the browse order and the
/// "primary" flag cannot drift from each other. One row per (exercise, muscle)
/// so a re-import is idempotent.
public enum Migration042_ExerciseMuscle: Migration {
    public static let version = 42
    public static let name = "exercise_muscle"

    public static func up(_ db: Database) throws {
        try db.execute("""
        CREATE TABLE exerciseMuscle (
            exerciseCatalogId INTEGER NOT NULL REFERENCES exerciseCatalog(id),
            muscle            TEXT NOT NULL,
            isPrimary         INTEGER NOT NULL DEFAULT 0,
            createdAt         TEXT NOT NULL,
            PRIMARY KEY (exerciseCatalogId, muscle)
        );
        """)
        try db.execute(
            "CREATE INDEX idx_exerciseMuscle_muscle ON exerciseMuscle(muscle);")

        // Seed the primary muscle from `category`, which is where the shipped
        // catalogue already records it. `category` is nullable and free text, so
        // both the null and the blank case are excluded rather than becoming a
        // group literally named "nil".
        try db.run("""
        INSERT OR IGNORE INTO exerciseMuscle
            (exerciseCatalogId, muscle, isPrimary, createdAt)
        SELECT id, TRIM(category), 1, ?
        FROM exerciseCatalog
        WHERE deletedAt IS NULL
          AND category IS NOT NULL
          AND TRIM(category) <> '';
        """, [.text(isoNow())])
    }

    private static func isoNow() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date())
    }
}
