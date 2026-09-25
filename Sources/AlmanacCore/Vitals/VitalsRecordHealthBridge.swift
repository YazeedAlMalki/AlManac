import Foundation

/// Writes vitals samples from HealthKit directly into vitals_record table.
///
/// Handles inbound sync for heart rate metrics: RHR (resting heart rate),
/// HRV (heart rate variability), and active energy and steps. Performs idempotent
/// upsert with deduplication by (source, healthKitUUID).
///
/// `.bodyMass` deliberately does NOT go through this bridge — weight lives in
/// `body_composition_measurement` via `BodyCompositionMeasurementHealthBridge`,
/// not here. See `docs/architecture/spec-reconciliation.md` §7: this bridge
/// used to write bodyMass into vitals_record as `metric = 'weight'`, which
/// collided with §5.18's dedicated table (no `conditions`/InBody-source
/// support). `restingEnergy` stays here — it doesn't collide with anything.
public struct VitalsRecordHealthBridge: HealthSampleWriting, @unchecked Sendable {
    let db: Database
    private let clock: any Clock
    private let timeModel: TimeModel
    private let zone: ZoneContext
    private let sourceSystem = "healthkit"

    // Map HealthDomain to metric name and unit for vitals_record
    private let metricMap: [HealthDomain: (metric: String, unit: String)] = [
        .heartRate: ("rhr", "bpm"),
        .hrv: ("hrv", "ms"),
        .steps: ("steps", "count"),
        .activeEnergy: ("activeEnergy", "kcal"),
        .restingEnergy: ("restingEnergy", "kcal")
    ]

    public init(db: Database, clock: any Clock = SystemClock(),
                timeModel: TimeModel = TimeModel(timeZone: .current),
                zone: ZoneContext = ZoneContext(TimeZone.current)) {
        self.db = db
        self.clock = clock
        self.timeModel = timeModel
        self.zone = zone
    }

    private var nowText: String { iso(clock.now) }
    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    private func parse(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }

    /// Repairs rows written by the pre-04:00 bridge when their timezone
    /// identifier is known. This is deliberately callable without a HealthKit
    /// provider so an upgrade is corrected even before the next sync; legacy
    /// offset-only rows are repaired only when their offset still matches the
    /// sample's current zone.
    public func reconcileLogicalDays() throws {
        let rows = try db.query("""
        SELECT id, timestamp, timezoneOffset, timezoneIdentifier, logicalDay
        FROM vitals_record
        WHERE source = ? AND deletedAt IS NULL;
        """, [.text(sourceSystem)])

        for row in rows {
            guard let id = row.int("id"),
                  let timestamp = row.string("timestamp"),
                  let instant = parse(timestamp) else { continue }
            let model: TimeModel
            if let identifier = row.string("timezoneIdentifier"),
               let zone = TimeZone(identifier: identifier) {
                model = TimeModel(timeZone: zone, boundary: timeModel.boundary)
            } else {
                // Legacy rows have only an offset. It is safe to use the
                // current zone only when that offset still matches at the
                // sample instant; otherwise DST history is unknowable.
                guard let offset = row.int("timezoneOffset")
                    ?? row.string("timezoneOffset").flatMap({ Int64($0) }) else { continue }
                let currentOffset = timeModel.timeZone.secondsFromGMT(for: instant) / 60
                guard offset == Int64(currentOffset) else { continue }
                model = timeModel
            }
            let day = model.logicalDay(instant).value
            guard row.string("logicalDay") != day else { continue }
            try db.run(
                "UPDATE vitals_record SET logicalDay = ? WHERE id = ?;",
                [.text(day), .integer(id)]
            )
        }
    }

    @discardableResult
    public func apply(_ changeSet: HealthChangeSet, in db: Database) throws -> HealthApplyCounts {
        var inserted = 0, updated = 0, deleted = 0

        for sample in changeSet.added {
            guard let (metricName, unitName) = metricMap[sample.domain],
                  let value = sample.value else { continue }
            
            let logicalDayText = timeModel.logicalDay(sample.start).value

            let existingRow = try db.query("""
                SELECT id FROM vitals_record
                WHERE source = ? AND healthKitUUID = ?;
                """, [.text(sourceSystem), .text(sample.externalID)]).first
            
            let existingId = existingRow?.int("id")

            try db.run("""
            INSERT INTO vitals_record
                (timestamp, timezoneOffset, timezoneIdentifier, logicalDay, metric, value, unit, source, healthKitUUID, createdAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(source, healthKitUUID) WHERE healthKitUUID IS NOT NULL DO UPDATE SET
                timestamp = excluded.timestamp,
                timezoneOffset = excluded.timezoneOffset,
                timezoneIdentifier = excluded.timezoneIdentifier,
                logicalDay = excluded.logicalDay,
                value = excluded.value,
                createdAt = excluded.createdAt;
            """, [
                .text(iso(sample.start)),
                zone.offsetMinutes.map { SQLValue.integer(Int64($0)) } ?? .null,
                zone.identifier.map { SQLValue.text($0) } ?? .null,
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

        // Soft delete. `deletedAt` (Migration020) — not `createdAt`, which is
        // NOT NULL and cannot double as a deletion flag; see that migration.
        for externalID in changeSet.deletedExternalIDs {
            deleted += try db.run("""
                UPDATE vitals_record SET deletedAt = ?
                WHERE source = ? AND healthKitUUID = ? AND deletedAt IS NULL;
                """, [.text(nowText), .text(sourceSystem), .text(externalID)])
        }

        return HealthApplyCounts(inserted: inserted, updated: updated, deleted: deleted)
    }
}
