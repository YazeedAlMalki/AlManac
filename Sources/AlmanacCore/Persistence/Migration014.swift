import Foundation

/// Migration 014 — Slice 2 (Core Daily) domain schema, transcribed from
/// Technical Specification v1.0 §5.
///
/// **Where the spec text came from.** Migrations.swift and
/// `docs/architecture/health-data-foundation.md` both record Technical Spec
/// v1.0 as unavailable, and every table in this codebase up to 013 was
/// therefore authored from first principles rather than from the spec. The
/// spec was recovered on 2026-09-15 at `../almanac-tech-spec-v1.0.md` — the
/// full 96 KB original, 48 tables, dated 2026-08-05. The fourteen tables below
/// are transcribed from §5 **verbatim**: column names, types, defaults,
/// comments and indexes are the spec's, not this codebase's.
///
/// **That is why the naming looks wrong here.** Migrations 001-013 use
/// snake_case (`logged_at`, `source_system`); the spec uses camelCase
/// (`logicalDay`, `sourceApp`). Mixing them inside one database is deliberate
/// and temporary: the owner's decision on 2026-09-15 was to make the code
/// match the spec 1:1, which means the *existing* migrations are the ones that
/// will move, not these. See `docs/architecture/spec-reconciliation.md` for
/// the collision list and the renumbering plan. Nothing is applied to a
/// durable database yet, so that renumber is still free.
///
/// **Forward reference, on purpose.** `sleep_episode.readinessCycleId` points
/// at `readiness_cycle`, and `readiness_cycle.primarySleepEpisodeId` points
/// back at `sleep_episode` — the spec defines them as mutually referential
/// (§5.6, §5.7). SQLite resolves foreign keys at DML time, not at CREATE
/// time, so whichever table is created second closes the loop. Both exist
/// before any row is inserted, which is the only thing that matters.
///
/// **No data is written here.** This migration creates tables and indexes and
/// nothing else. The 04:00 logical-day rule that `logicalDay` columns depend
/// on lives in `TimeModel` (spec §7.1), not in a database default.
public enum Migration014_CoreDailySchema: Migration {
    public static let version = 14
    public static let name = "core_daily_schema"

    public static func up(_ db: Database) throws {
        // §5.1 Profile
        try db.execute("""
        CREATE TABLE profile (
            id                  INTEGER PRIMARY KEY,
            displayName         TEXT NOT NULL DEFAULT 'Yazeed',
            dateOfBirth         TEXT,
            biologicalSex       TEXT,
            heightCm            REAL,
            sports              TEXT NOT NULL DEFAULT '[]',
            createdAt           TEXT NOT NULL,
            updatedAt           TEXT NOT NULL
        );
        """)

        // §5.4 CircadianContext — created before day_record, which references it.
        try db.execute("""
        CREATE TABLE circadian_context (
            id              INTEGER PRIMARY KEY,
            date            TEXT NOT NULL,
            shiftType       TEXT,
            contextType     TEXT NOT NULL,
            transitionDayN  INTEGER,
            notes           TEXT,
            createdAt       TEXT NOT NULL
        );
        """)

        // §5.3 DayRecord
        try db.execute("""
        CREATE TABLE day_record (
            id                  INTEGER PRIMARY KEY,
            date                TEXT NOT NULL UNIQUE,
            dayType             TEXT NOT NULL DEFAULT 'normal',
            dayTypeSource       TEXT NOT NULL DEFAULT 'default',
            circadianContextId  INTEGER REFERENCES circadian_context(id),
            createdAt           TEXT NOT NULL,
            updatedAt           TEXT NOT NULL
        );
        """)
        try db.execute("CREATE UNIQUE INDEX idx_day_record_date ON day_record(date);")

        // §5.5 ShiftSchedule
        try db.execute("""
        CREATE TABLE shift_schedule (
            id          INTEGER PRIMARY KEY,
            name        TEXT NOT NULL DEFAULT 'My Schedule',
            isActive    INTEGER NOT NULL DEFAULT 1,
            createdAt   TEXT NOT NULL,
            updatedAt   TEXT NOT NULL
        );
        """)

        try db.execute("""
        CREATE TABLE shift_recurrence_pattern (
            id              INTEGER PRIMARY KEY,
            scheduleId      INTEGER NOT NULL REFERENCES shift_schedule(id),
            patternType     TEXT NOT NULL,
            shiftSequence   TEXT NOT NULL,
            startDate       TEXT NOT NULL,
            endDate         TEXT,
            createdAt       TEXT NOT NULL
        );
        """)

        try db.execute("""
        CREATE TABLE shift_occurrence (
            id                          INTEGER PRIMARY KEY,
            scheduleId                  INTEGER NOT NULL REFERENCES shift_schedule(id),
            date                        TEXT NOT NULL,
            shiftType                   TEXT NOT NULL,
            shiftStartTime              TEXT,
            shiftEndTime                TEXT,
            expectedSleepWindowStart    TEXT,
            expectedSleepWindowEnd      TEXT,
            expectedWakeTime            TEXT,
            isManualOverride            INTEGER NOT NULL DEFAULT 0,
            recurrencePatternId         INTEGER REFERENCES shift_recurrence_pattern(id),
            notes                       TEXT,
            createdAt                   TEXT NOT NULL
        );
        """)
        try db.execute("CREATE INDEX idx_shift_occurrence_date ON shift_occurrence(date);")

        // §5.6 SleepEpisode
        try db.execute("""
        CREATE TABLE sleep_episode (
            id                  INTEGER PRIMARY KEY,
            startTimestamp      TEXT NOT NULL,
            endTimestamp        TEXT NOT NULL,
            timezoneOffset      TEXT NOT NULL,
            durationMinutes     INTEGER NOT NULL,
            episodeType         TEXT NOT NULL,
            source              TEXT NOT NULL,
            healthKitUUID       TEXT UNIQUE,
            sourceApp           TEXT,
            sourceDevice        TEXT,
            userCorrectedType   TEXT,
            userCorrectedAt     TEXT,
            readinessCycleId    INTEGER REFERENCES readiness_cycle(id),
            logicalDay          TEXT NOT NULL,
            createdAt           TEXT NOT NULL,
            updatedAt           TEXT NOT NULL
        );
        """)
        try db.execute("CREATE INDEX idx_sleep_episode_start ON sleep_episode(startTimestamp);")
        try db.execute("CREATE INDEX idx_sleep_episode_cycle ON sleep_episode(readinessCycleId);")

        // §5.7 ReadinessCycle
        try db.execute("""
        CREATE TABLE readiness_cycle (
            id                      INTEGER PRIMARY KEY,
            anchorDate              TEXT NOT NULL,
            primaryWakeTimestamp    TEXT,
            cycleStartTimestamp     TEXT,
            cycleEndTimestamp       TEXT,
            primarySleepEpisodeId   INTEGER REFERENCES sleep_episode(id),
            circadianContextId      INTEGER REFERENCES circadian_context(id),
            createdAt               TEXT NOT NULL,
            updatedAt               TEXT NOT NULL
        );
        """)
        try db.execute("CREATE INDEX idx_readiness_cycle_date ON readiness_cycle(anchorDate);")

        // §5.19 Vitals & Activity
        try db.execute("""
        CREATE TABLE vitals_record (
            id              INTEGER PRIMARY KEY,
            timestamp       TEXT NOT NULL,
            timezoneOffset  TEXT NOT NULL,
            logicalDay      TEXT NOT NULL,
            metric          TEXT NOT NULL,
            value           REAL NOT NULL,
            unit            TEXT NOT NULL,
            source          TEXT NOT NULL,
            healthKitUUID   TEXT UNIQUE,
            createdAt       TEXT NOT NULL
        );
        """)
        try db.execute("CREATE INDEX idx_vitals_metric ON vitals_record(metric, timestamp);")

        // §5.20 Wellness tables
        try db.execute("""
        CREATE TABLE mood_log (
            id                  INTEGER PRIMARY KEY,
            timestamp           TEXT NOT NULL,
            timezoneOffset      TEXT NOT NULL,
            logicalDay          TEXT NOT NULL,
            score               INTEGER NOT NULL CHECK(score BETWEEN 1 AND 10),
            readinessCycleId    INTEGER REFERENCES readiness_cycle(id),
            notes               TEXT,
            createdAt           TEXT NOT NULL
        );
        """)

        try db.execute("""
        CREATE TABLE soreness_log (
            id                  INTEGER PRIMARY KEY,
            timestamp           TEXT NOT NULL,
            timezoneOffset      TEXT NOT NULL,
            logicalDay          TEXT NOT NULL,
            overallScore        INTEGER NOT NULL CHECK(overallScore BETWEEN 1 AND 10),
            bodyAreas           TEXT NOT NULL DEFAULT '[]',
            readinessCycleId    INTEGER REFERENCES readiness_cycle(id),
            notes               TEXT,
            createdAt           TEXT NOT NULL
        );
        """)

        try db.execute("""
        CREATE TABLE injury_note (
            id              INTEGER PRIMARY KEY,
            startDate       TEXT NOT NULL,
            endDate         TEXT,
            bodyArea        TEXT NOT NULL,
            description     TEXT NOT NULL,
            isActive        INTEGER NOT NULL DEFAULT 1,
            affectsTraining INTEGER NOT NULL DEFAULT 1,
            createdAt       TEXT NOT NULL,
            updatedAt       TEXT NOT NULL
        );
        """)

        // §5.23 Readiness tables
        try db.execute("""
        CREATE TABLE readiness_record (
            id                      INTEGER PRIMARY KEY,
            readinessCycleId        INTEGER NOT NULL REFERENCES readiness_cycle(id),
            anchorDate              TEXT NOT NULL,
            state                   TEXT NOT NULL,
            score                   INTEGER,
            colorGrade              TEXT,
            textDescription         TEXT,
            confidence              TEXT NOT NULL,
            missingInputs           TEXT NOT NULL DEFAULT '[]',
            formulaVersion          TEXT NOT NULL DEFAULT '1.0',
            inputSnapshot           TEXT NOT NULL,
            calculationTimestamp    TEXT NOT NULL,
            recommendation          TEXT,
            precedenceApplied       TEXT NOT NULL DEFAULT '[]',
            feedbackValue           TEXT,
            feedbackTimestamp       TEXT,
            baselineContext         TEXT NOT NULL DEFAULT 'general',
            createdAt               TEXT NOT NULL,
            updatedAt               TEXT NOT NULL
        );
        """)

        try db.execute("""
        CREATE TABLE readiness_baseline (
            id                  INTEGER PRIMARY KEY,
            baselineType        TEXT NOT NULL,
            shiftType           TEXT,
            validDayCount       INTEGER NOT NULL,
            rollingWindowDays   INTEGER NOT NULL,
            avgSleepDurationMin REAL,
            avgRHR              REAL,
            avgHRV              REAL,
            avgSoreness         REAL,
            avgMood             REAL,
            windowStartDate     TEXT NOT NULL,
            windowEndDate       TEXT NOT NULL,
            formulaVersion      TEXT NOT NULL DEFAULT '1.0',
            updatedAt           TEXT NOT NULL
        );
        """)
    }
}
