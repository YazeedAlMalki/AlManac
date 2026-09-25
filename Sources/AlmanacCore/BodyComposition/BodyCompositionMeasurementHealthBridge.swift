import Foundation

/// Writes body composition samples from HealthKit into
/// `body_composition_measurement`.
///
/// Per Appendix C of the tech spec, `bodyMass`, `bodyFatPercentage` and
/// `leanBodyMass` are the only body-composition metrics with a HealthKit type
/// at all — skeletal muscle and visceral rating have none (manual/InBody-
/// import only). All three mapped here are bi-directional in principle
/// (`pendingHealthKitWrite` on the table exists for the outbound half); this
/// bridge covers inbound sync, mirroring `VitalsRecordHealthBridge`'s
/// idempotent upsert-by-`(source, healthKitUUID)` shape.
///
/// HealthKit carries no fasted/non-fasted state, so every sample lands with
/// `conditions = 'unknown'` — a manual entry can express the real condition;
/// an imported one cannot.
public struct BodyCompositionMeasurementHealthBridge: HealthSampleWriting, @unchecked Sendable {
    let db: Database
    private let clock: any Clock
    private let timeModel: TimeModel
    private let zone: ZoneContext
    private let sourceSystem = "apple_health"

    private let metricMap: [HealthDomain: (metric: String, unit: String)] = [
        .bodyMass: ("weight", "kg"),
        .bodyFatPercentage: ("body_fat_pct", "pct"),
        .leanBodyMass: ("lean_mass_kg", "kg")
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
        FROM body_composition_measurement
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
                "UPDATE body_composition_measurement SET logicalDay = ? WHERE id = ?;",
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
                SELECT id FROM body_composition_measurement
                WHERE source = ? AND healthKitUUID = ?;
                """, [.text(sourceSystem), .text(sample.externalID)]).first

            let existingId = existingRow?.int("id")

            try db.run("""
            INSERT INTO body_composition_measurement
                (timestamp, timezoneOffset, timezoneIdentifier, logicalDay, metric, value, unit, source, conditions, healthKitUUID, createdAt)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                .text("unknown"),
                .text(sample.externalID),
                .text(nowText)
            ])

            if existingId == nil { inserted += 1 } else { updated += 1 }
        }

        for externalID in changeSet.deletedExternalIDs {
            deleted += try db.run("""
                UPDATE body_composition_measurement SET deletedAt = ?
                WHERE source = ? AND healthKitUUID = ? AND deletedAt IS NULL;
                """, [.text(nowText), .text(sourceSystem), .text(externalID)])
        }

        return HealthApplyCounts(inserted: inserted, updated: updated, deleted: deleted)
    }
}
