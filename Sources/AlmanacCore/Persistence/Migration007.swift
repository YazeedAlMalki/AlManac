import Foundation

/// Migration 007 — hydration tracking system.
///
/// Adds comprehensive hydration tracking with samples, metrics, profiles, and reminders.
/// Supports:
/// - Individual hydration events (water, sports drinks, electrolyte solutions, etc.)
/// - Daily hydration metrics and progress
/// - User profiles for personalized recommendations
/// - Configurable reminder system
public enum Migration007_HydrationTracking: Migration {
    public static let version = 7
    public static let name = "hydration_tracking"

    public static func up(_ db: Database) throws {
        // Hydration samples — individual drinking events
        try db.execute("""
        CREATE TABLE hydration_sample (
            id              TEXT        PRIMARY KEY,
            timestamp       TEXT        NOT NULL,
            volume_ml       REAL        NOT NULL,
            liquid_type     TEXT        NOT NULL,
            sodium_mg       REAL,
            calories_kcal   REAL,
            source_name     TEXT,
            recorded_at     TEXT        NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
        """)
        try db.execute("""
        CREATE INDEX idx_hydration_sample_timestamp
            ON hydration_sample (timestamp DESC);
        """)
        try db.execute("""
        CREATE INDEX idx_hydration_sample_date
            ON hydration_sample (DATE(timestamp));
        """)

        // Hydration metrics — daily aggregated data
        try db.execute("""
        CREATE TABLE hydration_metrics (
            date                        TEXT        PRIMARY KEY,
            total_volume_ml             REAL        NOT NULL DEFAULT 0,
            total_sodium_mg             REAL        NOT NULL DEFAULT 0,
            exercise_minutes            REAL,
            recommended_intake_ml       REAL        NOT NULL,
            hydration_percentage        REAL        NOT NULL,
            sample_count                INTEGER     NOT NULL DEFAULT 0,
            last_updated                TEXT        NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
        """)
        try db.execute("""
        CREATE INDEX idx_hydration_metrics_date_desc
            ON hydration_metrics (date DESC);
        """)

        // Hydration profile — per-user personalized settings
        try db.execute("""
        CREATE TABLE hydration_profile (
            user_id                 TEXT        PRIMARY KEY,
            baseline_intake_ml      REAL        NOT NULL DEFAULT 2000,
            body_weight_kg          REAL,
            activity_level          TEXT        NOT NULL DEFAULT 'moderate',
            updated_at              TEXT        NOT NULL,
            created_at              TEXT        NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
        """)

        // Hydration reminders — notification configuration
        try db.execute("""
        CREATE TABLE hydration_reminder (
            id              TEXT        PRIMARY KEY,
            interval_minutes INTEGER     NOT NULL DEFAULT 60,
            start_hour      INTEGER     NOT NULL DEFAULT 7,
            end_hour        INTEGER     NOT NULL DEFAULT 22,
            is_enabled      INTEGER     NOT NULL DEFAULT 1,
            created_at      TEXT        NOT NULL,
            updated_at      TEXT        NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
        """)
        try db.execute("""
        CREATE INDEX idx_hydration_reminder_enabled
            ON hydration_reminder (is_enabled);
        """)

        // Hydration history — track changes to profile for analysis
        try db.execute("""
        CREATE TABLE hydration_profile_history (
            id                  TEXT        PRIMARY KEY,
            user_id             TEXT        NOT NULL
                                            REFERENCES hydration_profile(user_id) ON DELETE CASCADE,
            baseline_intake_ml  REAL        NOT NULL,
            activity_level      TEXT        NOT NULL,
            reason              TEXT,
            recorded_at         TEXT        NOT NULL
        );
        """)
        try db.execute("""
        CREATE INDEX idx_hydration_profile_history_user
            ON hydration_profile_history (user_id DESC, recorded_at DESC);
        """)

        // Hydration trends — weekly/monthly aggregations for insights
        try db.execute("""
        CREATE TABLE hydration_trend (
            id                  TEXT        PRIMARY KEY,
            period_start        TEXT        NOT NULL,
            period_end          TEXT        NOT NULL,
            period_type         TEXT        NOT NULL,
            average_volume_ml   REAL        NOT NULL,
            compliance_percent  REAL        NOT NULL,
            exercise_minutes    REAL,
            computed_at         TEXT        NOT NULL
        );
        """)
        try db.execute("""
        CREATE INDEX idx_hydration_trend_period
            ON hydration_trend (period_start, period_type);
        """)

        // Hydration settings — per-user feature configuration
        try db.execute("""
        CREATE TABLE hydration_settings (
            user_id                         TEXT        PRIMARY KEY,
            calorie_tracking_enabled       INTEGER     NOT NULL DEFAULT 0,
            double_track_warning_enabled   INTEGER     NOT NULL DEFAULT 1,
            auto_log_from_health           INTEGER     NOT NULL DEFAULT 0,
            reminders_enabled              INTEGER     NOT NULL DEFAULT 1,
            reminder_interval_minutes      INTEGER     NOT NULL DEFAULT 60,
            daily_goal_ml                  REAL,
            track_sodium                   INTEGER     NOT NULL DEFAULT 1,
            track_sugar                    INTEGER     NOT NULL DEFAULT 1,
            updated_at                     TEXT        NOT NULL
        );
        """)

        // Calorie entries — track calories from drinks
        try db.execute("""
        CREATE TABLE hydration_calorie_entry (
            id                          TEXT        PRIMARY KEY,
            hydration_sample_id         TEXT        NOT NULL
                                                    REFERENCES hydration_sample(id) ON DELETE CASCADE,
            drink_id                    TEXT        NOT NULL,
            drink_name                  TEXT        NOT NULL,
            calories_kcal               REAL        NOT NULL,
            sugar_grams                 REAL,
            timestamp                   TEXT        NOT NULL,
            double_track_warning        INTEGER     NOT NULL DEFAULT 0,
            recorded_at                 TEXT        NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
        """)
        try db.execute("""
        CREATE INDEX idx_hydration_calorie_entry_timestamp
            ON hydration_calorie_entry (timestamp DESC);
        """)
        try db.execute("""
        CREATE INDEX idx_hydration_calorie_entry_date
            ON hydration_calorie_entry (DATE(timestamp));
        """)
        try db.execute("""
        CREATE INDEX idx_hydration_calorie_entry_sample
            ON hydration_calorie_entry (hydration_sample_id);
        """)

        // Custom drinks — user-defined beverages
        try db.execute("""
        CREATE TABLE hydration_custom_drink (
            id                  TEXT        PRIMARY KEY,
            user_id             TEXT        NOT NULL,
            name                TEXT        NOT NULL,
            liquid_type         TEXT        NOT NULL,
            volume_ml           REAL        NOT NULL,
            calories_kcal       REAL        NOT NULL,
            sodium_mg           REAL        NOT NULL,
            sugar_grams         REAL,
            created_at          TEXT        NOT NULL
        );
        """)
        try db.execute("""
        CREATE INDEX idx_hydration_custom_drink_user
            ON hydration_custom_drink (user_id, created_at DESC);
        """)
        try db.execute("""
        CREATE INDEX idx_hydration_custom_drink_name
            ON hydration_custom_drink (user_id, name);
        """)
    }
}
