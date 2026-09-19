import Foundation

/// Migration 032 — Slice 9 schema only: `bowel_movement` and `urination_record`.
///
/// BRD §6.3 requires clinician review of the medical escalation *wording*
/// before ship — that is a process gate on UI copy, not on this table. Per
/// the Slice 9 handoff, the schema doesn't wait: `clinicianEscalationLevel`
/// is a plain nullable column that a future, clinician-approved classifier
/// will populate. Nothing here computes a value for it — guessing that
/// mapping now is exactly the "medical wording before review" the handoff
/// flags as unsafe.
public enum Migration032_DigestionSchema: Migration {
    public static let version = 32
    public static let name = "digestion_schema"

    public static func up(_ db: Database) throws {
        try db.execute("""
        CREATE TABLE bowel_movement (
            id                       INTEGER PRIMARY KEY,
            logicalDay               TEXT    NOT NULL,
            timestamp                TEXT    NOT NULL,
            bristolType              INTEGER NOT NULL,
            color                    TEXT,
            bloodPresent             INTEGER NOT NULL DEFAULT 0,
            bloodAmount              TEXT,
            gas                      INTEGER,
            urgency                  INTEGER,
            notes                    TEXT,
            clinicianEscalationLevel TEXT,
            createdAt                TEXT    NOT NULL
        );
        """)
        try db.execute("CREATE INDEX idx_bowel_movement_logical_day ON bowel_movement(logicalDay);")

        try db.execute("""
        CREATE TABLE urination_record (
            id                       INTEGER PRIMARY KEY,
            logicalDay               TEXT    NOT NULL,
            timestamp                TEXT    NOT NULL,
            colorGrade               INTEGER NOT NULL,
            notes                    TEXT,
            clinicianEscalationLevel TEXT,
            createdAt                TEXT    NOT NULL
        );
        """)
        try db.execute("CREATE INDEX idx_urination_record_logical_day ON urination_record(logicalDay);")
    }
}
