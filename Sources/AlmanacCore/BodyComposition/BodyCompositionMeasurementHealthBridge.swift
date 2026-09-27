import Foundation

/// Writes body composition samples from HealthKit into
/// `body_composition_measurement`.
///
/// Per Appendix C of the tech spec, `bodyMass`, `bodyFatPercentage` and
/// `leanBodyMass` are the only body-composition metrics with a HealthKit type
/// at all — skeletal muscle and visceral rating have none (manual/InBody-
/// import only). All three are bi-directional: this type is the inbound half
/// and `BodyCompositionWriteback` the outbound one, joined by the `outbound`
/// table above. Inbound sync is an idempotent upsert by
/// `(source, healthKitUUID)`, mirroring `VitalsRecordHealthBridge`.
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

    /// The outbound half of the same three metrics, keyed by the stored metric
    /// name. Separate from `metricMap` rather than derived from it, because the
    /// two directions do not agree on the unit string: the store spells body
    /// fat `pct` (the BRD's own word) while HealthKit's label is `%`, and
    /// `HealthKitProvider.write` refuses anything else. A single shared table
    /// would have had to carry both spellings anyway, and the two key sets are
    /// asserted equal in `BodyCompositionWritebackTests`.
    ///
    /// Three rows, not five: `skeletal_muscle_kg` and `visceral_rating` have no
    /// HealthKit type at all (Appendix C), so a manual row of either can never
    /// be pushed and is deliberately never queued.
    static let outbound: [String: (domain: HealthDomain, storeUnit: String, healthUnit: String)] = [
        "weight": (.bodyMass, "kg", "kg"),
        "body_fat_pct": (.bodyFatPercentage, "pct", "%"),
        "lean_mass_kg": (.leanBodyMass, "kg", "kg"),
    ]

    /// The HealthKit domain for a stored metric name, or nil for one HealthKit
    /// cannot hold. Read by `BodyCompositionMeasurementStore.log` so a manual
    /// row is queued for write-back only when there is somewhere to send it —
    /// otherwise a metric with no HK type would sit in the queue failing forever.
    public static func healthKitDomain(forMetric metric: String) -> HealthDomain? {
        outbound[metric]?.domain
    }

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

            // A manual row this app exported already holds this HealthKit UUID.
            // Echoing it back must not create a second row for the same reading:
            // `healthKitUUID` is a column-level UNIQUE (Migration018), so the
            // upsert below — whose conflict target is the *partial* index on
            // `(source, healthKitUUID)` — would not catch it and the insert
            // would fail outright. `HealthKitProvider` already drops its own
            // exports by bundle identifier; this is the same guard the waist
            // bridge has, for any other host.
            let holder = try db.query("""
                SELECT source FROM body_composition_measurement WHERE healthKitUUID = ?;
                """, [.text(sample.externalID)]).first
            if let holder, holder.string("source") != sourceSystem { continue }

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

/// Pushes manually-logged body composition entries to HealthKit.
///
/// The queue is `pendingHealthKitWrite = 1`, the flag `Migration018` added for
/// this purpose and `BodyCompositionMeasurementStore.log` sets. It is not
/// `healthKitUUID IS NULL` as the waist writeback uses, because only a metric
/// HealthKit can actually hold is ever flagged: `skeletal_muscle_kg` and
/// `visceral_rating` have no type, and inferring the queue from a null UUID
/// would leave those rows retrying a write that can never succeed.
///
/// Same discipline as `HydrationWriteback` and the mirror of
/// `HealthSyncService`: the write happens outside any SQLite transaction
/// (it is a call to another system), and a row is stamped only after that
/// write has actually succeeded. A failed write is recorded and the loop
/// continues, so one bad row neither blocks the rows after it nor hides itself:
/// the first failure is rethrown once every row has been tried, and the failed
/// row stays flagged, which is the retry.
public struct BodyCompositionWriteback: Sendable {
    private let db: Database
    private let writer: any HealthWriter

    public init(db: Database, writer: any HealthWriter) {
        self.db = db
        self.writer = writer
    }

    private func parse(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }

    /// Pushes every flagged manual row once. Returns the number successfully
    /// pushed.
    @discardableResult
    public func drainOnce() async throws -> Int {
        let rows = try db.query("""
            SELECT id, metric, value, unit, timestamp FROM body_composition_measurement
            WHERE source = 'manual' AND pendingHealthKitWrite = 1 AND deletedAt IS NULL
            ORDER BY timestamp, id;
            """)

        var pushed = 0
        var firstFailure: Error?
        for row in rows {
            // A row whose unit is not the one this metric is stored in cannot be
            // sent under HealthKit's label without relabelling the number — a
            // `weight` in pounds pushed as `kg` is worse than not pushed. It
            // stays flagged rather than being dropped, so the mismatch is
            // visible in the row instead of silently discarded.
            guard let id = row.int("id"),
                  let metric = row.string("metric"),
                  let spec = BodyCompositionMeasurementHealthBridge.outbound[metric],
                  row.string("unit") == spec.storeUnit,
                  let value = row.double("value"), value.isFinite, value > 0,
                  let text = row.string("timestamp"),
                  let date = parse(text) else { continue }

            // Stable per row, so a retried write is the same sync identifier
            // rather than a second sample — see `HealthKitProvider.write`.
            let sample = HealthSample(
                externalID: "almanac.body_composition.\(id).\(date.timeIntervalSince1970)",
                domain: spec.domain, start: date, end: date,
                value: value, unit: spec.healthUnit)
            do {
                let externalID = try await writer.write(sample)
                try db.run("""
                    UPDATE body_composition_measurement
                    SET healthKitUUID = ?, pendingHealthKitWrite = 0
                    WHERE id = ? AND pendingHealthKitWrite = 1;
                    """, [.text(externalID), .integer(id)])
                pushed += 1
            } catch {
                firstFailure = firstFailure ?? error
            }
        }
        if let firstFailure { throw firstFailure }
        return pushed
    }
}
