import Foundation

/// Migration 059 — when the person said which fasts they keep.
///
/// The owner's T02 answer (2026-10-16): the app asks which fasts a person keeps
/// (Ramadan, Mondays and Thursdays, the White Days) rather than assuming. The
/// answer itself lands in `religious_fast_schedule`, as every other fasting
/// choice does; this row only records that the question was answered, so it is
/// asked once. One row, keyed `'local'`, like `activity_ring_settings`. It is in
/// the database rather than in app preferences so a restored backup does not
/// ask again.
public enum Migration059_FastsQuestion: Migration {
    public static let version = 59
    public static let name = "fasts_question"

    public static func up(_ db: Database) throws {
        try db.execute("""
        CREATE TABLE fasts_question (
            id          TEXT PRIMARY KEY CHECK (id = 'local'),
            answeredAt  TEXT NOT NULL
        ) STRICT;
        """)
    }
}
