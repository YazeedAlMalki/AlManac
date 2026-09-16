import Foundation

/// Migration 024 — Slice 6 (Fasting), the religious-fasting and prayer-time
/// tables that Migration022 deliberately left out.
///
/// Transcribed verbatim from `../../../almanac-tech-spec-v1.0.md` §5.21–5.22
/// (`religious_fast_schedule`, `prayer_settings`, `prayer_times_cache`) and
/// §5.11 (`nutrition_window`, owned by this slice even though the table name
/// says nutrition), camelCase, following the Migration014-onward convention.
/// See `docs/features/fasting.md` §4/§6 for the design this implements.
///
/// Deliberately not touched here: `nutrition_log`/`hydration_log` gain no
/// `nutritionWindowId` column in this migration. Wiring an entry to its
/// night-nutrition window (§7.2) is its own cross-module task — Nutrition
/// and Hydration are each their own slice, and neither should gain a column
/// serving a feature (religious fasting) they have no other knowledge of in
/// the same pass that builds that feature's own tables.
public enum Migration024_ReligiousFastingAndPrayerSchema: Migration {
    public static let version = 24
    public static let name = "religious_fasting_and_prayer_schema"

    public static func up(_ db: Database) throws {
        try db.execute("""
        CREATE TABLE religious_fast_schedule (
            id                  INTEGER PRIMARY KEY,
            scheduleType        TEXT NOT NULL,
            hijriYear           INTEGER,
            startGregorianDate  TEXT,
            endGregorianDate    TEXT,
            isActive            INTEGER NOT NULL DEFAULT 1,
            manualCorrections   TEXT NOT NULL DEFAULT '[]',
            createdAt           TEXT NOT NULL,
            updatedAt           TEXT NOT NULL
        );
        """)

        try db.execute("""
        CREATE TABLE prayer_settings (
            id                      INTEGER PRIMARY KEY DEFAULT 1,
            calculationMethod       TEXT NOT NULL DEFAULT 'umm_al_qura',
            customFajrAngleDeg      REAL,
            customIshaAngleDeg      REAL,
            latitude                REAL,
            longitude               REAL,
            city                    TEXT,
            country                 TEXT,
            manualCityOverride      INTEGER NOT NULL DEFAULT 0,
            fajrOffsetMin           INTEGER NOT NULL DEFAULT 0,
            dhuhrOffsetMin          INTEGER NOT NULL DEFAULT 0,
            asrOffsetMin            INTEGER NOT NULL DEFAULT 0,
            maghribOffsetMin        INTEGER NOT NULL DEFAULT 0,
            ishaOffsetMin           INTEGER NOT NULL DEFAULT 0,
            timezone                TEXT NOT NULL DEFAULT 'Asia/Riyadh',
            updatedAt               TEXT NOT NULL
        );
        """)

        try db.execute("""
        CREATE TABLE prayer_times_cache (
            id                  INTEGER PRIMARY KEY,
            date                TEXT NOT NULL UNIQUE,
            fajr                TEXT NOT NULL,
            sunrise             TEXT NOT NULL,
            dhuhr               TEXT NOT NULL,
            asr                 TEXT NOT NULL,
            maghrib             TEXT NOT NULL,
            isha                TEXT NOT NULL,
            latitude            REAL NOT NULL,
            longitude           REAL NOT NULL,
            calculationMethod   TEXT NOT NULL,
            isManualOverride    INTEGER NOT NULL DEFAULT 0,
            createdAt           TEXT NOT NULL
        );
        """)
        try db.execute("CREATE UNIQUE INDEX idx_prayer_cache_date ON prayer_times_cache(date);")

        try db.execute("""
        CREATE TABLE nutrition_window (
            id                  INTEGER PRIMARY KEY,
            date                TEXT NOT NULL,
            windowType          TEXT NOT NULL,
            startTimestamp      TEXT NOT NULL,
            endTimestamp        TEXT NOT NULL,
            fajrTimestamp       TEXT,
            maghribTimestamp    TEXT,
            createdAt           TEXT NOT NULL
        );
        """)
        // Beyond the spec's literal text: (date, windowType) is unique so
        // "created automatically when a day is marked as Religious Fast and
        // prayer times are available" (§7.2) can be a real upsert rather
        // than accumulating a duplicate window if the auto-creation runs
        // twice for the same day.
        try db.execute("CREATE UNIQUE INDEX idx_nutrition_window_date_type ON nutrition_window(date, windowType);")
    }
}
