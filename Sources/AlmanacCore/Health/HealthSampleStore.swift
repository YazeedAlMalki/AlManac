import Foundation

public struct HealthApplyCounts: Sendable, Hashable {
    public let inserted: Int
    public let updated: Int
    public let deleted: Int
    public init(inserted: Int, updated: Int, deleted: Int) {
        self.inserted = inserted; self.updated = updated; self.deleted = deleted
    }
    public static let zero = HealthApplyCounts(inserted: 0, updated: 0, deleted: 0)
}

/// Writes a change set. **Must not open its own transaction** — the caller
/// owns it, because the rows and the cursor advance have to commit together.
public protocol HealthSampleWriting: Sendable {
    func apply(_ changeSet: HealthChangeSet, in db: Database) throws -> HealthApplyCounts
}

/// Persists samples for one `HealthDomain`. This slice wires up `.bodyMass`
/// only; the table and this type are domain-agnostic, but no other domain is
/// enabled, tested, or claimed to work.
public struct HealthSampleStore: HealthSampleWriting, TimelineProviding, @unchecked Sendable {
    public let domain: String
    public let healthDomain: HealthDomain
    public let sourceSystem: String
    private let db: Database
    private let clock: any Clock
    private let zone: ZoneContext

    public init(db: Database, healthDomain: HealthDomain = .bodyMass,
                sourceSystem: String = "healthkit",
                clock: any Clock = SystemClock(),
                zone: ZoneContext = ZoneContext(TimeZone.current)) {
        self.db = db
        self.healthDomain = healthDomain
        self.sourceSystem = sourceSystem
        self.domain = healthDomain.rawValue
        self.clock = clock
        self.zone = zone
    }

    private var nowText: String { ISO8601DateFormatter().string(from: clock.now) }
    private func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

    @discardableResult
    public func apply(_ changeSet: HealthChangeSet, in db: Database) throws -> HealthApplyCounts {
        var inserted = 0, updated = 0, deleted = 0

        for sample in changeSet.added where sample.domain == healthDomain {
            let existing = try db.query("""
                SELECT id FROM health_sample WHERE source_system = ? AND external_id = ?;
                """, [.text(sourceSystem), .text(sample.externalID)]).first?.string("id")
            // Identity is (source_system, external_id): the same string from a
            // different source is a different sample, never an update of this one.
            try db.run("""
            INSERT INTO health_sample
                (id, source_system, external_id, domain, start_at, end_at, value, unit,
                 source_name, recorded_at, recorded_tz_offset_minutes, deleted_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)
            ON CONFLICT(source_system, external_id) DO UPDATE SET
                start_at    = excluded.start_at,
                end_at      = excluded.end_at,
                value       = excluded.value,
                unit        = excluded.unit,
                source_name = excluded.source_name,
                recorded_at = excluded.recorded_at,
                deleted_at  = NULL;
            """, [
                .text(existing ?? UUID().uuidString), .text(sourceSystem),
                .text(sample.externalID), .text(sample.domain.rawValue),
                .text(iso(sample.start)), .text(iso(sample.end)),
                sample.value.map { SQLValue.real($0) } ?? .null,
                sample.unit.map { SQLValue.text($0) } ?? .null,
                sample.sourceName.map { SQLValue.text($0) } ?? .null,
                .text(nowText),
                zone.offsetMinutes.map { SQLValue.integer(Int64($0)) } ?? .null
            ])
            if existing == nil { inserted += 1 } else { updated += 1 }
        }

        // Soft delete. A source withdrawing a sample is a fact about the
        // source, not permission to erase what was already recorded.
        for externalID in changeSet.deletedExternalIDs {
            deleted += try db.run("""
                UPDATE health_sample SET deleted_at = ?
                WHERE source_system = ? AND external_id = ? AND deleted_at IS NULL;
                """, [.text(nowText), .text(sourceSystem), .text(externalID)])
        }

        return HealthApplyCounts(inserted: inserted, updated: updated, deleted: deleted)
    }

    public func liveSampleCount() throws -> Int {
        Int(try db.query("""
            SELECT COUNT(*) AS n FROM health_sample
            WHERE source_system = ? AND domain = ? AND deleted_at IS NULL;
            """, [.text(sourceSystem), .text(healthDomain.rawValue)])
            .first?.int("n") ?? 0)
    }

    public func isDeleted(externalID: String) throws -> Bool {
        guard let row = try db.query("""
            SELECT deleted_at FROM health_sample WHERE source_system = ? AND external_id = ?;
            """, [.text(sourceSystem), .text(externalID)]).first else { return false }
        return !row.isNull("deleted_at")
    }

    public func entries(from: String, to: String) throws -> [TimelineEntry] {
        try db.query("""
        SELECT id, external_id, start_at, value, unit, source_name
        FROM health_sample
        WHERE source_system = ? AND domain = ? AND deleted_at IS NULL
          AND start_at >= ? AND start_at < ?
        ORDER BY start_at;
        """, [.text(sourceSystem), .text(healthDomain.rawValue), .text(from), .text(to)])
        .compactMap { row in
            guard let id = row.string("id"), let start = row.string("start_at"),
                  let occurrence = PartialDateTime(storedText: start, precision: .instant,
                                                   zone: .unknown) else { return nil }
            let value: ValuePresentation
            if let v = row.double("value") {
                value = .quantity(text: String(v), unit: row.string("unit"))
            } else {
                value = .missing(reason: LabMissingReason.notReportedBySource.rawValue)
            }
            return TimelineEntry(
                domain: domain, kind: "sample", recordTable: "health_sample", recordID: id,
                occurrence: occurrence, basis: .occurrence,
                title: healthDomain.rawValue, detail: row.string("source_name"),
                value: value, lifecycle: nil)
        }
    }
}
