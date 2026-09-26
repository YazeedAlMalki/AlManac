import Foundation

/// Waist only. HealthSyncService commits these rows and its cursor together.
public struct BodyMeasurementHealthBridge: HealthSampleWriting, Sendable {
    private let timeModel: TimeModel

    public init(timeModel: TimeModel = TimeModel(timeZone: .current)) {
        self.timeModel = timeModel
    }

    public func apply(_ changeSet: HealthChangeSet, in db: Database) throws -> HealthApplyCounts {
        var inserted = 0, updated = 0, deleted = 0
        for sample in changeSet.added where sample.domain == .waistCircumference {
            guard let value = sample.value, value.isFinite, value > 0,
                  sample.unit == "cm", !sample.externalID.isEmpty else {
                throw BodyMeasurementError.invalidValue
            }
            let existing = try db.query("SELECT source FROM body_measurement WHERE source_identifier = ?;",
                                        [.text(sample.externalID)]).first
            // An exported manual row remains manual when HealthKit echoes its UUID.
            if existing?.string("source") == "manual" { continue }
            try db.run("""
                INSERT INTO body_measurement
                    (measured_at, logical_day, measurement_type, value_cm, source, source_identifier)
                VALUES (?, ?, 'waist', ?, 'healthkit', ?)
                ON CONFLICT(source_identifier) DO UPDATE SET
                    measured_at = excluded.measured_at, logical_day = excluded.logical_day,
                    value_cm = excluded.value_cm;
                """, [.text(ISO8601DateFormatter().string(from: sample.start)),
                      .text(timeModel.logicalDay(sample.start).value), .real(value), .text(sample.externalID)])
            if existing == nil { inserted += 1 } else { updated += 1 }
        }
        for id in changeSet.deletedExternalIDs {
            deleted += try db.run("DELETE FROM body_measurement WHERE source = 'healthkit' AND source_identifier = ?;",
                                  [.text(id)])
        }
        return HealthApplyCounts(inserted: inserted, updated: updated, deleted: deleted)
    }
}

/// The pending queue is the manual waist rows without a HealthKit UUID.
/// Like HydrationWriteback, failed writes stay pending for the next drain.
public struct BodyMeasurementWriteback: Sendable {
    private let db: Database
    private let writer: any HealthWriter

    public init(db: Database, writer: any HealthWriter) {
        self.db = db
        self.writer = writer
    }

    @discardableResult
    public func drainOnce() async throws -> Int {
        let rows = try db.query("""
            SELECT id, measured_at, value_cm FROM body_measurement
            WHERE source = 'manual' AND measurement_type = 'waist' AND source_identifier IS NULL
            ORDER BY measured_at, id;
            """)
        var pushed = 0
        for row in rows {
            guard let id = row.int("id"), let value = row.double("value_cm"),
                  let date = row.string("measured_at").flatMap({ ISO8601DateFormatter().date(from: $0) }) else { continue }
            let sample = HealthSample(externalID: "almanac.body_measurement.\(id).\(date.timeIntervalSince1970)", domain: .waistCircumference,
                                      start: date, end: date, value: value, unit: "cm")
            let externalID = try await writer.write(sample)
            try db.run("UPDATE body_measurement SET source_identifier = ? WHERE id = ? AND source_identifier IS NULL;",
                       [.text(externalID), .integer(id)])
            pushed += 1
        }
        return pushed
    }
}
