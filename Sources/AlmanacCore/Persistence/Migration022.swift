import Foundation

/// Migration 022 — Slice 6 (Fasting), the intermittent-fasting core only.
///
/// Transcribed verbatim from `../../../almanac-tech-spec-v1.0.md` §5.21, the
/// `fasting_session` table (`religious_fast_schedule`, `prayer_settings`,
/// `prayer_times_cache`, `nutrition_window` deliberately not yet included —
/// they depend on the prayer-time engine, a separate task; see
/// `docs/features/fasting.md`).
public enum Migration022_FastingSchema: Migration {
    public static let version = 22
    public static let name = "fasting_schema"

    public static func up(_ db: Database) throws {
        try db.execute("""
        CREATE TABLE fasting_session (
            id                  INTEGER PRIMARY KEY,
            startTimestamp      TEXT NOT NULL,
            endTimestamp        TEXT,
            timezoneOffset      TEXT,
            logicalDay          TEXT NOT NULL,
            sessionType         TEXT NOT NULL,
            isDryFast           INTEGER NOT NULL DEFAULT 0,
            protocol            TEXT,
            windowHours         REAL,
            isActive            INTEGER NOT NULL DEFAULT 0,
            isInvalidated       INTEGER NOT NULL DEFAULT 0,
            finalDurationMinutes INTEGER,
            correctionHistory   TEXT NOT NULL DEFAULT '[]',
            createdAt           TEXT NOT NULL,
            updatedAt           TEXT NOT NULL
        );
        """)
        try db.execute("CREATE INDEX idx_fasting_session_day ON fasting_session(logicalDay);")
        // Partial: only one session may be active at a time. Enforced here
        // rather than in Swift, so a bug can't silently open two.
        try db.execute("""
        CREATE UNIQUE INDEX idx_fasting_session_one_active
            ON fasting_session(isActive) WHERE isActive = 1;
        """)
    }
}
