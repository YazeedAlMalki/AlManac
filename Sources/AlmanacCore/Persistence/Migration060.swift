import Foundation

/// Migration 060 — two more things a bowel-movement entry can record.
///
/// BRD §6.3's escalation triggers include "severe pain" and
/// "dizziness/weakness", and the logger had no way to record either, so the
/// advisory the owner chose to build (G1, 2026-10-16) could never have fired on
/// them. Both are nullable: null is "not stated", distinct from "no", as `gas`
/// already is.
public enum Migration060_DigestionSymptoms: Migration {
    public static let version = 60
    public static let name = "digestion_symptoms"

    public static func up(_ db: Database) throws {
        try db.execute("""
        ALTER TABLE bowel_movement ADD COLUMN severePain INTEGER;
        ALTER TABLE bowel_movement ADD COLUMN dizzinessOrWeakness INTEGER;
        """)
    }
}
