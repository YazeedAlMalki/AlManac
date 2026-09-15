import Foundation

/// Migration 009 — the food log.
///
/// Appended; 001-008 are untouched.
///
/// The reference database answers "what is in this food". Nothing recorded
/// "the user ate 150 g of it". That is this table.
///
/// Two decisions worth the words:
///
/// 1. **`food_ref` is text, with no foreign key.** It holds a
///    `SourceIdentifier` — `usda:1105904`, `almanac:dish-kabsa`. Processing
///    Design v0.1 §3 keeps "remove a whole source" a one-line delete when a
///    rights holder says no; a foreign key with ON DELETE CASCADE would turn
///    that delete into the erasure of the user's own meal history. The log is
///    the user's record, not the publisher's, and it outlives the reference
///    rows it points at. `food_name_text` is what keeps an orphaned row
///    readable.
/// 2. **`grams` is nullable.** "Some rice, amount not stated" is a thing a
///    person logs, and `NutrientQualifier` already establishes that this
///    codebase does not write a number where nobody supplied one. An entry
///    with no amount yields no energy and says so, rather than yielding zero.
///
/// Energy is deliberately not a column here. It is a derivation from the
/// reference values and the grams, and storing it would freeze one answer to
/// a question whose inputs get corrected.
public enum Migration009_NutritionLog: Migration {
    public static let version = 9
    public static let name = "nutrition_log"

    public static func up(_ db: Database) throws {
        try db.execute("""
        CREATE TABLE nutrition_log (
            id                          TEXT    PRIMARY KEY,
            source_system               TEXT    NOT NULL,
            external_id                 TEXT,
            food_ref                    TEXT    NOT NULL,
            food_name_text              TEXT,
            grams                       REAL,
            quantity_text               TEXT,
            eaten_at                    TEXT,
            eaten_precision             TEXT    NOT NULL,
            eaten_tz_offset_minutes     INTEGER,
            eaten_tz_id                 TEXT,
            recorded_at                 TEXT    NOT NULL,
            recorded_tz_offset_minutes  INTEGER,
            deleted_at                  TEXT
        );
        """)

        // Identity is (source_system, external_id), as for health_sample: the
        // same string from a different source is a different meal. Manual
        // entries carry no external id and are therefore never deduplicated
        // against each other — eating the same food twice is not a replay.
        try db.execute("""
        CREATE UNIQUE INDEX idx_nutrition_log_source
            ON nutrition_log (source_system, external_id)
            WHERE external_id IS NOT NULL;
        """)
        try db.execute("CREATE INDEX idx_nutrition_log_time ON nutrition_log (eaten_at);")
        try db.execute("CREATE INDEX idx_nutrition_log_food ON nutrition_log (food_ref);")

        // One revision table, not two. A log entry is small enough that "what
        // was eaten" and "how much, when" are one fact; Laboratory splits them
        // only because a result's content and its metadata are revised by
        // different actors for different reasons.
        try db.execute("""
        CREATE TABLE nutrition_log_revision (
            id                      TEXT    PRIMARY KEY,
            log_id                  TEXT    NOT NULL
                                        REFERENCES nutrition_log(id) ON DELETE CASCADE,
            revision_number         INTEGER NOT NULL,
            food_ref                TEXT    NOT NULL,
            food_name_text          TEXT,
            grams                   REAL,
            quantity_text           TEXT,
            eaten_at                TEXT,
            eaten_precision         TEXT    NOT NULL,
            eaten_tz_offset_minutes INTEGER,
            eaten_tz_id             TEXT,
            changed_fields          TEXT    NOT NULL,
            actor                   TEXT    NOT NULL,
            reason_text             TEXT,
            recorded_at             TEXT    NOT NULL
        );
        """)
        try db.execute("""
        CREATE UNIQUE INDEX idx_nutrition_log_revision_number
            ON nutrition_log_revision (log_id, revision_number);
        """)
    }
}
