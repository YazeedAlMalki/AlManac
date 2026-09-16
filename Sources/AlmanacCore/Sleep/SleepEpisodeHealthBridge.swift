import Foundation

/// Writes sleep samples from HealthKit directly into sleep_episode table.
///
/// Per spec §8.1, sleep samples from HealthKit are classified and merged into
/// episodes. This bridge handles the inbound half: idempotent upsert of
/// HealthKit sleep samples with deduplication by (source, healthKitUUID).
public struct SleepEpisodeHealthBridge: HealthSampleWriting, @unchecked Sendable {
    let db: Database
    private let clock: any Clock
    private let zone: ZoneContext
    private let sourceSystem = "healthkit"

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

        for sample in changeSet.added where sample.domain == .sleep {
            let existingRow = try db.query("""
                SELECT id, deletedAt FROM sleep_episode
                WHERE source = ? AND healthKitUUID = ?;
                """, [.text(sourceSystem), .text(sample.externalID)]).first
            
            // A soft delete is sticky: once deleted in-app, don't resurrect via re-sync
            if let existingRow, !existingRow.isNull("deletedAt") { continue }
            let existingId = existingRow?.string("id")

            try db.run("""
            INSERT INTO sleep_episode
                (id, startTime, endTime, source, healthKitUUID, recordedAt, recordedTzOffset)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(source, healthKitUUID) WHERE healthKitUUID IS NOT NULL DO UPDATE SET
                startTime = excluded.startTime,
                endTime = excluded.endTime,
                recordedAt = excluded.recordedAt;
            """, [
                .text(existingId ?? UUID().uuidString),
                .text(iso(sample.start)),
                .text(iso(sample.end)),
                .text(sourceSystem),
                .text(sample.externalID),
                .text(nowText),
                zone.offsetMinutes.map { SQLValue.integer(Int64($0)) } ?? .null
            ])
            
            if existingId == nil { inserted += 1 } else { updated += 1 }
        }

        // Soft delete: source withdrawal does not mean permission to erase
        for externalID in changeSet.deletedExternalIDs {
            deleted += try db.run("""
                UPDATE sleep_episode SET deletedAt = ?
                WHERE source = ? AND healthKitUUID = ? AND deletedAt IS NULL;
                """, [.text(nowText), .text(sourceSystem), .text(externalID)])
        }

        return HealthApplyCounts(inserted: inserted, updated: updated, deleted: deleted)
    }
}
