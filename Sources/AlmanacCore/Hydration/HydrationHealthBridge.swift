import Foundation

/// Reads workout duration out of the shared `health_sample` table so hydration
/// recommendations can react to exercise without hydration owning any health
/// sync logic itself.
///
/// This is a read-only bridge: `HealthSampleStore` (Health module) owns
/// writing `health_sample` rows from `HealthProvider` sync. Hydration only
/// ever reads what is already there, scoped to the `.workouts` domain.
public struct HydrationHealthBridge: Sendable {
    private let db: Database
    private let calendar: Calendar

    public init(db: Database, calendar: Calendar = .current) {
        self.db = db
        self.calendar = calendar
    }

    /// Total workout minutes whose interval overlaps the logical day
    /// containing `date`. A workout that spans midnight is clipped to the
    /// portion that falls within the day, not double-counted or dropped.
    public func exerciseMinutes(on date: Date) throws -> Double {
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return 0
        }

        let iso = ISO8601DateFormatter()
        let rows = try db.query("""
        SELECT start_at, end_at FROM health_sample
        WHERE domain = ? AND deleted_at IS NULL
          AND start_at < ? AND end_at > ?
        """, [
            .text(HealthDomain.workouts.rawValue),
            .text(iso.string(from: dayEnd)),
            .text(iso.string(from: dayStart))
        ])

        var totalSeconds: TimeInterval = 0
        for row in rows {
            guard let startText = row.string("start_at"),
                  let endText = row.string("end_at"),
                  let start = iso.date(from: startText),
                  let end = iso.date(from: endText)
            else { continue }

            let clippedStart = max(start, dayStart)
            let clippedEnd = min(end, dayEnd)
            if clippedEnd > clippedStart {
                totalSeconds += clippedEnd.timeIntervalSince(clippedStart)
            }
        }

        return totalSeconds / 60
    }

    /// True if any workout overlaps the current moment — used to decide
    /// whether a hydration recommendation should treat the user as
    /// "exercising right now" versus "exercised earlier today".
    public func isExerciseActive(at date: Date = Date()) throws -> Bool {
        let iso = ISO8601DateFormatter()
        let rows = try db.query("""
        SELECT 1 FROM health_sample
        WHERE domain = ? AND deleted_at IS NULL
          AND start_at <= ? AND end_at >= ?
        LIMIT 1
        """, [
            .text(HealthDomain.workouts.rawValue),
            .text(iso.string(from: date)),
            .text(iso.string(from: date))
        ])
        return !rows.isEmpty
    }
}
