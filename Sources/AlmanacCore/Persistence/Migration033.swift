import Foundation

/// Migration 033 — Slice 10 schema: `correlation_pair`, `trend_snapshot`,
/// `achievement_record`.
///
/// `correlation_pair.pValue` is nullable and unpopulated by anything in this
/// migration's companion store — `CorrelationEngine` computes `r` and a
/// sample size, not a p-value, so the column exists for the schema the
/// handoff specifies without this session fabricating a statistic it never
/// calculated.
public enum Migration033_InsightsSchema: Migration {
    public static let version = 33
    public static let name = "insights_schema"

    public static func up(_ db: Database) throws {
        try db.execute("""
        CREATE TABLE correlation_pair (
            metricA         TEXT    NOT NULL,
            metricB         TEXT    NOT NULL,
            rValue          REAL,
            pValue          REAL,
            sampleSize      INTEGER NOT NULL,
            confidenceLevel TEXT    NOT NULL,
            lastComputed    TEXT    NOT NULL,
            PRIMARY KEY (metricA, metricB)
        );
        """)

        try db.execute("""
        CREATE TABLE trend_snapshot (
            metric       TEXT    NOT NULL,
            period       TEXT    NOT NULL,
            average      REAL    NOT NULL,
            minimum      REAL    NOT NULL,
            maximum      REAL    NOT NULL,
            direction    TEXT    NOT NULL,
            lastUpdated  TEXT    NOT NULL,
            PRIMARY KEY (metric, period)
        );
        """)

        try db.execute("""
        CREATE TABLE achievement_record (
            logicalDay    TEXT    NOT NULL,
            badgeType     TEXT    NOT NULL,
            metThreshold  INTEGER NOT NULL,
            PRIMARY KEY (logicalDay, badgeType)
        );
        """)
        try db.execute("CREATE INDEX idx_achievement_record_day ON achievement_record(logicalDay);")
    }
}
