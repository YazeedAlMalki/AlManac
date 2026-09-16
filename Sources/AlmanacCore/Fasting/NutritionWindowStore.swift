import Foundation

/// A `nutrition_window` row (§5.11, §7.2) — the span a `NutritionLog`/
/// `HydrationLog` entry is assigned to on a religious fast day.
public struct NutritionWindow: Sendable, Hashable, Identifiable {
    public let id: Int64
    /// The day the window is *for* — for `night_nutrition_window`, this is
    /// D (Maghrib's day), not D+1 (Fajr's day), even though the window's
    /// own span crosses midnight.
    public let date: String
    /// `"standard_logical_day"` or `"night_nutrition_window"`.
    public let windowType: String
    public let startTimestamp: Date
    public let endTimestamp: Date
    public let fajrTimestamp: Date?
    public let maghribTimestamp: Date?
    public let createdAt: Date
}

/// Creating and looking up `nutrition_window` rows.
///
/// §7.2's defining example is what `window(containing:)` exists for: a
/// suhoor entry at 03:50 on calendar day D+1 belongs to D's night window
/// (`Maghrib(D)` to `Fajr(D+1)`), never to D+1's own window. Matching by the
/// entry's actual timestamp against `startTimestamp`/`endTimestamp` — not by
/// comparing calendar-date strings — is what makes that automatic; the
/// window's own `date` column (D) is for lookup/creation by the day the fast
/// happened, not for matching an entry against it.
public struct NutritionWindowStore: @unchecked Sendable {
    let db: Database
    private let clock: any Clock

    public init(db: Database, clock: any Clock = SystemClock()) {
        self.db = db
        self.clock = clock
    }

    private var nowText: String { iso(clock.now) }
    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    // MARK: - Write

    /// Upserts by `(date, windowType)` (Migration024's unique index) — §7.2
    /// says a window is "created automatically when a day is marked as
    /// Religious Fast and prayer times are available"; re-running that
    /// (e.g. prayer times recalculated) replaces the same row.
    @discardableResult
    public func createWindow(date: String, windowType: String, startTimestamp: Date, endTimestamp: Date,
                              fajrTimestamp: Date? = nil, maghribTimestamp: Date? = nil) throws -> Int64 {
        try db.run("""
        INSERT INTO nutrition_window (date, windowType, startTimestamp, endTimestamp, fajrTimestamp, maghribTimestamp, createdAt)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(date, windowType) DO UPDATE SET
            startTimestamp = excluded.startTimestamp,
            endTimestamp = excluded.endTimestamp,
            fajrTimestamp = excluded.fajrTimestamp,
            maghribTimestamp = excluded.maghribTimestamp;
        """, [
            .text(date), .text(windowType), .text(iso(startTimestamp)), .text(iso(endTimestamp)),
            fajrTimestamp.map { SQLValue.text(iso($0)) } ?? .null,
            maghribTimestamp.map { SQLValue.text(iso($0)) } ?? .null,
            .text(nowText)
        ])
        guard let row = try db.query("SELECT id FROM nutrition_window WHERE date = ? AND windowType = ?;",
                                      [.text(date), .text(windowType)]).first,
              let id = row.int("id") else {
            throw NutritionWindowStoreError.insertFailed
        }
        return id
    }

    // MARK: - Read

    public func window(date: String, windowType: String) throws -> NutritionWindow? {
        try db.query("\(Self.columns) FROM nutrition_window WHERE date = ? AND windowType = ?;",
                      [.text(date), .text(windowType)]).first.flatMap(rowToWindow)
    }

    /// The window (of any type) whose span contains `timestamp`, if any —
    /// see the type-level doc comment for why this is timestamp-range
    /// containment rather than a date-string lookup.
    public func window(containing timestamp: Date) throws -> NutritionWindow? {
        let text = iso(timestamp)
        return try db.query("""
        \(Self.columns) FROM nutrition_window
        WHERE startTimestamp <= ? AND endTimestamp > ?
        ORDER BY startTimestamp DESC LIMIT 1;
        """, [.text(text), .text(text)]).first.flatMap(rowToWindow)
    }

    // MARK: - Private

    private static let columns = """
        SELECT id, date, windowType, startTimestamp, endTimestamp, fajrTimestamp, maghribTimestamp, createdAt
        """

    private func rowToWindow(_ row: Row) -> NutritionWindow? {
        guard let id = row.int("id"), let date = row.string("date"), let windowType = row.string("windowType"),
              let start = row.string("startTimestamp").flatMap(iso8601ToDate),
              let end = row.string("endTimestamp").flatMap(iso8601ToDate) else { return nil }

        return NutritionWindow(
            id: id, date: date, windowType: windowType, startTimestamp: start, endTimestamp: end,
            fajrTimestamp: row.string("fajrTimestamp").flatMap(iso8601ToDate),
            maghribTimestamp: row.string("maghribTimestamp").flatMap(iso8601ToDate),
            createdAt: row.string("createdAt").flatMap(iso8601ToDate) ?? Date()
        )
    }

    private func iso8601ToDate(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }
}

public enum NutritionWindowStoreError: Error, Sendable {
    case insertFailed
}
