import Foundation

/// The two window kinds `nutrition_window.windowType` names (spec §5.11).
///
/// An enum rather than the column's raw `String` because a window's *type* is
/// what decides whether an entry belongs in it, and a caller who can only spell
/// `"night_nutrition_window"` correctly by hand will eventually not. `db` never
/// sees the case name: the raw values are the spec's.
///
/// **`standardLogicalDay` is named and reachable but never written.** The spec
/// lists it as a possible value and then gives no rule for creating one —
/// §7.2 only ever describes a night window, and its assignment rule covers only
/// the night case. Inventing a creation rule here would be a product decision
/// nobody has made, so the case exists (the column's own vocabulary is
/// complete, and a future rule has somewhere to land) and no code path creates
/// one. That is a recorded gap, not an oversight: see
/// `docs/features/fasting.md`.
public enum NutritionWindowType: String, Sendable, Hashable, CaseIterable {
    case standardLogicalDay = "standard_logical_day"
    case nightNutritionWindow = "night_nutrition_window"
}

/// A `nutrition_window` row (§5.11, §7.2) — the span a `NutritionLog`/
/// `HydrationLog` entry is assigned to on a religious fast day.
public struct NutritionWindow: Sendable, Hashable, Identifiable {
    public let id: Int64
    /// The day the window is *for* — for `night_nutrition_window`, this is
    /// D (Maghrib's day), not D+1 (Fajr's day), even though the window's
    /// own span crosses midnight.
    public let date: String
    public let windowType: NutritionWindowType
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
    public func createWindow(date: String, windowType: NutritionWindowType, startTimestamp: Date, endTimestamp: Date,
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
            .text(date), .text(windowType.rawValue), .text(iso(startTimestamp)), .text(iso(endTimestamp)),
            fajrTimestamp.map { SQLValue.text(iso($0)) } ?? .null,
            maghribTimestamp.map { SQLValue.text(iso($0)) } ?? .null,
            .text(nowText)
        ])
        guard let row = try db.query("SELECT id FROM nutrition_window WHERE date = ? AND windowType = ?;",
                                      [.text(date), .text(windowType.rawValue)]).first,
              let id = row.int("id") else {
            throw NutritionWindowStoreError.insertFailed
        }
        return id
    }

    // MARK: - Read

    public func window(date: String, windowType: NutritionWindowType) throws -> NutritionWindow? {
        try db.query("\(Self.columns) FROM nutrition_window WHERE date = ? AND windowType = ?;",
                      [.text(date), .text(windowType.rawValue)]).first.flatMap { try rowToWindow($0) }
    }

    /// One window by id, for a caller that has just created it and has the id
    /// back from `createWindow`.
    public func window(id: Int64) throws -> NutritionWindow? {
        try db.query("\(Self.columns) FROM nutrition_window WHERE id = ?;",
                      [.integer(id)]).first.flatMap { try rowToWindow($0) }
    }

    /// Every window, oldest first — the set `NightNutritionWindowAssigner`
    /// rebuilds over. Ordering by start makes "outermost first" the reading
    /// order, matching the latest-start precedence `window(containing:)` uses to
    /// break a tie between overlapping windows.
    public func windows() throws -> [NutritionWindow] {
        try db.query("""
        \(Self.columns) FROM nutrition_window ORDER BY startTimestamp ASC, id ASC;
        """).map(rowToWindow)
    }

    /// The windows of one type, oldest first.
    public func windows(ofType windowType: NutritionWindowType) throws -> [NutritionWindow] {
        try db.query("""
        \(Self.columns) FROM nutrition_window WHERE windowType = ? ORDER BY startTimestamp ASC, id ASC;
        """, [.text(windowType.rawValue)]).map(rowToWindow)
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
        """, [.text(text), .text(text)]).first.flatMap { try rowToWindow($0) }
    }

    // MARK: - Private

    private static let columns = """
        SELECT id, date, windowType, startTimestamp, endTimestamp, fajrTimestamp, maghribTimestamp, createdAt
        """

    /// Throws on an unreadable row rather than skipping it. A silent `nil` here
    /// would drop a window out of a list an assignment pass is walking, and the
    /// entry inside it would then be written as NULL — a wrong answer that looks
    /// right, which is the one failure mode this column cannot have.
    private func rowToWindow(_ row: Row) throws -> NutritionWindow {
        let rawType = row.string("windowType")
        guard let id = row.int("id"), let date = row.string("date"),
              let rawType, let windowType = NutritionWindowType(rawValue: rawType) else {
            throw NutritionWindowStoreError.unreadableWindow(rawType: rawType ?? "NULL")
        }
        guard let start = row.string("startTimestamp").flatMap(iso8601ToDate),
              let end = row.string("endTimestamp").flatMap(iso8601ToDate) else {
            throw NutritionWindowStoreError.unreadableWindow(rawType: rawType)
        }

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

public enum NutritionWindowStoreError: Error, Sendable, Equatable {
    case insertFailed
    case unreadableWindow(rawType: String)
}
