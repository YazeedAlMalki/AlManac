import Foundation

/// Persists `TrendEngine` output, keyed by (metric, period). Recomputing a
/// metric's trend overwrites its prior snapshot outright — a snapshot is a
/// current summary, not a history.
public struct TrendSnapshotStore: @unchecked Sendable {
    let db: Database
    private let clock: any Clock

    public init(db: Database, clock: any Clock = SystemClock()) {
        self.db = db
        self.clock = clock
    }

    public func save(metric: String, period: String, snapshot: TrendSnapshot) throws {
        let now = ISO8601DateFormatter().string(from: clock.now)
        try db.run("""
        INSERT OR REPLACE INTO trend_snapshot (metric, period, average, minimum, maximum, direction, lastUpdated)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """, [
            .text(metric), .text(period),
            .real(snapshot.average), .real(snapshot.minimum), .real(snapshot.maximum),
            .text(String(describing: snapshot.direction)),
            .text(now)
        ])
    }

    public func snapshot(metric: String, period: String) throws -> TrendSnapshot? {
        guard let row = try db.query("""
        SELECT average, minimum, maximum, direction FROM trend_snapshot
        WHERE metric = ? AND period = ?;
        """, [.text(metric), .text(period)]).first else { return nil }

        guard let average = row.double("average"),
              let minimum = row.double("minimum"),
              let maximum = row.double("maximum"),
              let directionText = row.string("direction"),
              let direction = TrendDirection(directionText) else { return nil }

        return TrendSnapshot(average: average, minimum: minimum, maximum: maximum, direction: direction)
    }
}

private extension TrendDirection {
    init?(_ text: String) {
        switch text {
        case "up": self = .up
        case "down": self = .down
        case "flat": self = .flat
        default: return nil
        }
    }
}
