import Foundation

/// Writes vitals samples from HealthKit directly into vitals_record table.
///
/// Handles inbound sync for heart rate metrics: RHR (resting heart rate),
/// HRV (heart rate variability), and active energy and steps. Performs idempotent
/// upsert with deduplication by (source, healthKitUUID).
public struct VitalsRecordHealthBridge: HealthSampleWriting, @unchecked Sendable {
    let db: Database
    private let clock: any Clock
    private let zone: ZoneContext
    private let sourceSystem = "healthkit"
    
    // Map HealthDomain to metric name and unit for vitals_record
    private let metricMap: [HealthDomain: (metric: String, unit: String)] = [
        .heartRate: ("rhr", "bpm"),
        .hrv: ("hrv", "ms"),
        .steps: ("steps", "count"),
        .activeEnergy: ("activeEnergy", "kcal"),
        .restingEnergy: ("restingEnergy", "kcal"),
        .bodyMass: ("weight", "kg")
    ]

    public init(db: Database, clock: any Clock = SystemClock(),
                zone: ZoneContext = ZoneContext(TimeZone.current)) {
        self.db = db
        self.clock = clock
        self.zone = zone
    }

    private var nowText: String { iso(clock.now) }
    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    @discardableResult
    public func apply(_ changeSet: HealthChangeSet, in db: Database) throws -> HealthApplyCounts {
        var inserted = 0, updated = 0, deleted = 0

        for sample in changeSet.added {
            guard let (metricName, unitName) = metricMap[sample.domain],
                  let value = sample.value else { continue }
            
            // Determine logical day from sample.start
            let logicalDayText = iso(sample.start).prefix(10)  // YYYY-MM-DD
            
            let existingRow = try db.query("""
                SELECT id FROM vitals_record
                WHERE source = ? AND healthKitUUID = ?;
                """, [.text(sourceSystem), .text(sample.externalID)]).first
            
            let existingId = existingRow?.int64("id")

            try db.run("""
            INSERT INTO vitals_record
                (timestamp, timezoneOffset, logicalDay, metric, value, unit, source, healthKitUUID, createdAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(source, healthKitUUID) WHERE healthKitUUID IS NOT NULL DO UPDATE SET
                timestamp = excluded.timestamp,
                value = excluded.value,
                createdAt = excluded.createdAt;
            """, [
                .text(iso(sample.start)),
                zone.offsetMinutes.map { SQLValue.integer(Int64($0)) } ?? .null,
                .text(String(logicalDayText)),
                .text(metricName),
                .real(value),
                sample.unit.map { SQLValue.text($0) } ?? .text(unitName),
                .text(sourceSystem),
                .text(sample.externalID),
                .text(nowText)
            ])
            
            if existingId == nil { inserted += 1 } else { updated += 1 }
        }

        // Soft delete
        for externalID in changeSet.deletedExternalIDs {
            deleted += try db.run("""
                UPDATE vitals_record SET createdAt = NULL
                WHERE source = ? AND healthKitUUID = ? AND createdAt IS NOT NULL;
                """, [.text(sourceSystem), .text(externalID)])
        }

        return HealthApplyCounts(inserted: inserted, updated: updated, deleted: deleted)
    }
}
