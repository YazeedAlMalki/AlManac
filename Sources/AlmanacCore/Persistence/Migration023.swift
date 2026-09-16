import Foundation

/// Migration 023 — a unique index on `readiness_record.readinessCycleId`.
///
/// Migration014's `readiness_record` (§5.23) has no constraint on
/// `readinessCycleId` at all, so nothing stops the same cycle from
/// accumulating duplicate rows as its score is recomputed through the day
/// (provisional at wake, final after the mood/soreness check-in, again if a
/// vitals sample arrives late). One record per cycle — the later evaluation
/// replaces the earlier one — is the only reading that matches §9.1's model
/// of a cycle having *a* readiness state, not a history of attempts.
/// `ReadinessRecordStore.record` relies on this index as an `ON
/// CONFLICT(readinessCycleId)` target for that upsert.
public enum Migration023_ReadinessRecordUniqueCycle: Migration {
    public static let version = 23
    public static let name = "readiness_record_unique_cycle"

    public static func up(_ db: Database) throws {
        try db.execute("""
        CREATE UNIQUE INDEX idx_readiness_record_cycle ON readiness_record(readinessCycleId);
        """)
    }
}
