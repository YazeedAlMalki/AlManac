import Foundation

/// Migration 047 — `goal_target_snapshot`, the targets in force for a period.
///
/// **This is a §5 table.** Technical spec v1.0 §5.2 gives the columns and states
/// the rule that shapes everything else here:
///
/// > Records the active targets for each period. A new row is inserted whenever
/// > a goal changes; rows are never updated (immutable history).
///
/// so the columns are §5.2's, in §5.2's order, with §5.2's names. Transcription
/// rather than redesign: the spec is a contract this repo has not yet honoured
/// for this table, and a table that agrees with the document is cheaper to
/// review than a table that has quietly improved on it. Migration 015 records
/// the precedent for the opposite choice, where the spec collided with an
/// existing table and the existing one won.
///
/// **The five `target_*` columns are the one addition, and they are additive.**
/// §5.2 has no body-composition target: a meter needs a target to be a meter,
/// and without these the body-composition cards would show a value against
/// nothing. They are one column per `BodyMetric`, nullable, because "not set" is
/// the state of every install until a person asks for a target — and a card that
/// has to render an absent target has to be able to say so.
///
/// **They have no `manual_target_*` twin, unlike the calorie and macro columns,
/// and that is deliberate.** §5.2's manual columns exist because a *formula*
/// generates those numbers and a person may override one. Nothing generates a
/// body-fat target today, so a `manual_` prefix on those columns would name a
/// distinction that does not exist, and a second NULL would be a second way for
/// the same target to be absent. When a formula does start generating them, the
/// override columns come with it.
///
/// **`effective_date` is the start of the period, and the rule for which row is
/// in force is "the newest one at or before the day".** An end date would be
/// derivable from the next row and would be a second thing to keep true; §5.2
/// does not name one, and deriving it keeps "which targets applied on the 14th"
/// a single indexed read rather than a search.
///
/// **The activity multiplier and calorie adjustment are stored, not derived, for
/// the same reason §5.2 keeps the body stats.** They are the *assumptions* the
/// targets were generated from. A target that cannot say what it assumed cannot
/// be re-derived when the assumption is wrong, and a formula whose inputs live
/// only in a function call is a target nobody can audit. §5.2's own comment gives
/// the adjustments the goal kinds imply — "+300 bulk, -500 cut" — and those
/// defaults are what `GoalTargetSnapshot` carries when the caller does not
/// override them.
public enum Migration047_GoalTargetSnapshot: Migration {
    public static let version = 47
    public static let name = "goal_target_snapshot"

    public static func up(_ db: Database) throws {
        try db.execute("""
        CREATE TABLE goal_target_snapshot (
            id                          INTEGER PRIMARY KEY,
            effective_date              TEXT    NOT NULL,
            goal                        TEXT    NOT NULL,
            formula_version             TEXT    NOT NULL DEFAULT '1.0',
            body_weight_kg              REAL,
            body_fat_pct                REAL,
            activity_multiplier         REAL,
            goal_calorie_adjustment     INTEGER,
            calorie_target              INTEGER,
            protein_target_g            REAL,
            carb_target_g               REAL,
            fat_target_g                REAL,
            hydration_target_ml         INTEGER,
            manual_calorie_target       INTEGER,
            manual_protein_target_g     REAL,
            manual_carb_target_g        REAL,
            manual_fat_target_g         REAL,
            manual_hydration_target_ml  INTEGER,
            target_body_weight_kg       REAL,
            target_body_fat_pct         REAL,
            target_lean_mass_kg         REAL,
            target_skeletal_muscle_kg   REAL,
            target_visceral_rating      REAL,
            created_at                  TEXT    NOT NULL
        );
        """)
        // The read that matters is "the targets in force on day X": newest row at
        // or before X, one row per metric's worth of targets. Without this index
        // that is a sort of the whole table on every card grid, and the table
        // only grows when somebody changes a goal.
        try db.execute("""
        CREATE INDEX idx_goal_target_snapshot_effective
            ON goal_target_snapshot (effective_date DESC);
        """)
    }
}
