import Foundation

/// A launch argument that puts the shift schedule in a known state, for UI
/// tests.
///
/// The simulator's database is shared across runs and never reset, and the
/// shift editor persists what it is given, so a test that enters a shift would
/// otherwise leave it for the next run. The spec is **authoritative, not
/// additive** (the same rule `VitalsSeedPlan` follows): applying it first
/// removes every shift the database holds, then plants the entries, so the
/// same spec always lands the same state.
///
/// `-AlmanacSeedShifts night:-1,night:0` plants a night shift yesterday and
/// today; `-AlmanacSeedShifts none` only clears. An ordinary launch carries no
/// such argument and gets nil — that guard, and the `#if DEBUG` around the one
/// call site, are what keep this away from a real person's schedule.
public struct ShiftSeedPlan: Sendable, Equatable {
    public static let launchArgument = "-AlmanacSeedShifts"

    public struct Entry: Sendable, Equatable {
        public let shiftType: ShiftType
        public let dayOffset: Int
    }

    public let entries: [Entry]

    /// `none`, or comma-separated `shift:offset` pairs. Anything else is no
    /// plan, rather than the readable half of one.
    public init?(spec: String) {
        if spec == "none" {
            entries = []
            return
        }
        var parsed: [Entry] = []
        for pair in spec.split(separator: ",", omittingEmptySubsequences: false) {
            let parts = pair.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  let shift = ShiftType(rawValue: String(parts[0])),
                  let offset = Int(parts[1]) else { return nil }
            parsed.append(Entry(shiftType: shift, dayOffset: offset))
        }
        guard !parsed.isEmpty else { return nil }
        entries = parsed
    }

    public static func fromLaunchArguments(_ arguments: [String]) -> ShiftSeedPlan? {
        guard let index = arguments.firstIndex(of: launchArgument),
              arguments.indices.contains(index + 1) else { return nil }
        return ShiftSeedPlan(spec: arguments[index + 1])
    }

    /// Replaces every shift in `db` with this plan's entries, dated from
    /// today's logical day at `now`. Children go before parents, because the
    /// foreign keys are enforced.
    public func apply(into db: Database, now: Date, timeModel: TimeModel) throws {
        try db.transaction {
            try db.run("DELETE FROM shift_occurrence;")
            try db.run("DELETE FROM shift_recurrence_pattern;")
            try db.run("DELETE FROM shift_schedule;")
            guard !entries.isEmpty else { return }

            let store = ShiftScheduleStore(db: db)
            let scheduleId = try store.createSchedule(ShiftScheduleDraft(name: "Seeded"))
            for entry in entries {
                guard let day = logicalDay(for: entry.dayOffset, now: now, timeModel: timeModel) else { continue }
                try store.logOccurrence(ShiftOccurrenceDraft(
                    scheduleId: scheduleId, date: day.value, shiftType: entry.shiftType))
            }
        }
    }

    /// Counted along the repo's 04:00 logical days with `day(before:)` /
    /// `day(after:)`, not by subtracting 86,400 seconds — a DST day is not
    /// that long.
    private func logicalDay(for dayOffset: Int, now: Date, timeModel: TimeModel) -> LogicalDay? {
        var day = timeModel.logicalDay(now)
        for _ in 0..<abs(dayOffset) {
            guard let next = dayOffset < 0 ? timeModel.day(before: day) : timeModel.day(after: day) else { return nil }
            day = next
        }
        return day
    }
}
