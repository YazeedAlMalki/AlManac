import Foundation

/// A recovery day the person declared, read from storage.
public struct RecoveryDayDeclaration: Sendable, Hashable {
    public let logicalDay: String  // YYYY-MM-DD
    /// When it was declared, which need not fall on `logicalDay`: a declaration
    /// made this morning about yesterday is yesterday's.
    public let declaredAt: Date

    public init(logicalDay: String, declaredAt: Date) {
        self.logicalDay = logicalDay
        self.declaredAt = declaredAt
    }
}

/// §9.6's "manually selected recovery day (user set via UI)", over
/// `recovery_day_declaration` (Migration 057).
///
/// Shaped like `MoodLogStore` and `SorenessLogStore`: the caller names the
/// logical day, and the store never works one out from a timestamp, so a
/// back-dated declaration lands on the day it names rather than the day it was
/// made. Unlike those two it holds at most one row per day, because a recovery
/// day is a yes-or-no about the day rather than a reading taken during it.
///
/// It is the person's own override, **not** a planned rest day. §9.6 keeps the
/// two apart by who planned them, and `ReadinessContext.plannedRestDay` is the
/// other one.
public struct RecoveryDayStore: @unchecked Sendable {
    let db: Database

    public init(db: Database) {
        self.db = db
    }

    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    // MARK: - Write

    /// Marks `logicalDay` a recovery day. Declaring a day already declared keeps
    /// the first declaration's time, since the day was a recovery day from then.
    public func declare(logicalDay: String, at date: Date, timezoneOffset: Int? = nil) throws {
        try db.run("""
        INSERT INTO recovery_day_declaration (logicalDay, declaredAt, timezoneOffset)
        VALUES (?, ?, ?)
        ON CONFLICT(logicalDay) DO NOTHING;
        """, [
            .text(logicalDay),
            .text(iso(date)),
            timezoneOffset.map { SQLValue.integer(Int64($0)) } ?? .null
        ])
    }

    /// Takes the declaration off `logicalDay`. Clearing a day that was never
    /// declared is not an error: the day ends up as asked either way.
    public func clear(logicalDay: String) throws {
        try db.run("DELETE FROM recovery_day_declaration WHERE logicalDay = ?;", [.text(logicalDay)])
    }

    /// Declares or clears, for a control that is a switch.
    public func set(_ isRecoveryDay: Bool, logicalDay: String, at date: Date,
                    timezoneOffset: Int? = nil) throws {
        if isRecoveryDay {
            try declare(logicalDay: logicalDay, at: date, timezoneOffset: timezoneOffset)
        } else {
            try clear(logicalDay: logicalDay)
        }
    }

    // MARK: - Read

    public func declaration(for logicalDay: String) throws -> RecoveryDayDeclaration? {
        try db.query("""
        SELECT logicalDay, declaredAt FROM recovery_day_declaration WHERE logicalDay = ?;
        """, [.text(logicalDay)]).first.flatMap { row in
            guard let day = row.string("logicalDay"),
                  let text = row.string("declaredAt"),
                  let declaredAt = ISO8601DateFormatter().date(from: text) else { return nil }
            return RecoveryDayDeclaration(logicalDay: day, declaredAt: declaredAt)
        }
    }

    /// What `ReadinessContext.manualRecoveryDay` is set from.
    public func isRecoveryDay(_ logicalDay: String) throws -> Bool {
        try declaration(for: logicalDay) != nil
    }
}
