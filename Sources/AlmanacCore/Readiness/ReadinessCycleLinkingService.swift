import Foundation

/// Service for linking wellness logs (mood, soreness) to their readiness cycles.
///
/// Per §8.4, after determining the primary sleep episode for a readiness cycle,
/// all logs created between the cycle's start timestamp (wake time) and the next
/// cycle's start timestamp are linked to that cycle via their readinessCycleId.
public struct ReadinessCycleLinkingService {
    let db: Database
    private let moodStore: MoodLogStore
    private let sorenessStore: SorenessLogStore

    public init(db: Database, clock: any Clock = SystemClock(),
                zone: ZoneContext = ZoneContext(TimeZone.current)) {
        self.db = db
        self.moodStore = MoodLogStore(db: db, clock: clock, zone: zone)
        self.sorenessStore = SorenessLogStore(db: db, clock: clock, zone: zone)
    }

    /// Link all wellness logs within a cycle's time window to the cycle.
    ///
    /// Called after a ReadinessCycle is created following primary sleep determination.
    /// Links all mood_log and soreness_log entries with timestamps between
    /// cycleStartTimestamp (inclusive) and cycleEndTimestamp (exclusive) to this cycle.
    ///
    /// - Parameters:
    ///   - cycleId: The ID of the readiness cycle to link to
    ///   - cycleStartTimestamp: When the cycle starts (wake time from primary sleep episode)
    ///   - cycleEndTimestamp: When the cycle ends (next cycle's wake time, or nil if current)
    /// - Returns: Number of entries linked
    @discardableResult
    public func linkLogsToReadinessCycle(
        cycleId: Int64,
        cycleStartTimestamp: Date,
        cycleEndTimestamp: Date?
    ) throws -> (moodLinked: Int, sorenessLinked: Int) {
        var moodCount = 0
        var sorenessCount = 0

        let startText = iso(cycleStartTimestamp)
        let endText = cycleEndTimestamp.map(iso)

        // Link mood logs
        if let endText = endText {
            moodCount = try db.run("""
            UPDATE mood_log SET readinessCycleId = ?
            WHERE timestamp >= ? AND timestamp < ? AND readinessCycleId IS NULL;
            """, [.integer(cycleId), .text(startText), .text(endText)])
        } else {
            // Current cycle — link everything from start onward (no end bound)
            moodCount = try db.run("""
            UPDATE mood_log SET readinessCycleId = ?
            WHERE timestamp >= ? AND readinessCycleId IS NULL;
            """, [.integer(cycleId), .text(startText)])
        }

        // Link soreness logs
        if let endText = endText {
            sorenessCount = try db.run("""
            UPDATE soreness_log SET readinessCycleId = ?
            WHERE timestamp >= ? AND timestamp < ? AND readinessCycleId IS NULL;
            """, [.integer(cycleId), .text(startText), .text(endText)])
        } else {
            // Current cycle — link everything from start onward
            sorenessCount = try db.run("""
            UPDATE soreness_log SET readinessCycleId = ?
            WHERE timestamp >= ? AND readinessCycleId IS NULL;
            """, [.integer(cycleId), .text(startText)])
        }

        return (moodLinked: moodCount, sorenessLinked: sorenessCount)
    }

    /// Relink logs for a cycle after a change (e.g., wake time adjustment).
    ///
    /// Clears existing links and relinks all logs within the new time window.
    @discardableResult
    public func relinkLogsToReadinessCycle(
        cycleId: Int64,
        cycleStartTimestamp: Date,
        cycleEndTimestamp: Date?
    ) throws -> (moodLinked: Int, sorenessLinked: Int) {
        // Clear existing links for this cycle
        try db.run("""
        UPDATE mood_log SET readinessCycleId = NULL WHERE readinessCycleId = ?;
        """, [.integer(cycleId)])
        try db.run("""
        UPDATE soreness_log SET readinessCycleId = NULL WHERE readinessCycleId = ?;
        """, [.integer(cycleId)])

        // Relink
        return try linkLogsToReadinessCycle(cycleId: cycleId,
                                            cycleStartTimestamp: cycleStartTimestamp,
                                            cycleEndTimestamp: cycleEndTimestamp)
    }

    // MARK: - Private

    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
}
