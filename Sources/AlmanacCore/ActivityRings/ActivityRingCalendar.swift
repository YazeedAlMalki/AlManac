import Foundation

public enum ActivityRingBinaryState: String, Sendable, Hashable {
    case complete
    case incomplete
}

// Hit/off/mess are the BRD vocabulary reserved for the Diet Profile resolver;
// this reader deliberately produces only the two states it can know today.
public enum ActivityRingNutritionState: String, Sendable, Hashable {
    case hit
    case off
    case mess
    case notLogged
    case dietProfileRequired
}

public enum ActivityRingDigestionState: String, Sendable, Hashable {
    case disabled
    case fillRuleUnavailable
}

public struct ActivityRingDay: Sendable, Hashable, Identifiable {
    public let day: LogicalDay
    public let hydrationTotalMilliliters: Milliliters
    public let hydrationTargetMilliliters: Milliliters
    public let hydration: ActivityRingBinaryState
    public let training: ActivityRingBinaryState
    public let nutrition: ActivityRingNutritionState
    public let digestion: ActivityRingDigestionState

    public var id: String { day.value }
    public var dayNumber: Int { Int(day.value.suffix(2)) ?? 0 }
    public var isGolden: Bool {
        hydration == .complete
            && training == .complete
            && nutrition == .hit
            && digestion != .fillRuleUnavailable
    }

    public init(day: LogicalDay, hydrationTotalMilliliters: Milliliters,
                hydrationTargetMilliliters: Milliliters, hydration: ActivityRingBinaryState,
                training: ActivityRingBinaryState, nutrition: ActivityRingNutritionState,
                digestion: ActivityRingDigestionState) {
        self.day = day
        self.hydrationTotalMilliliters = hydrationTotalMilliliters
        self.hydrationTargetMilliliters = hydrationTargetMilliliters
        self.hydration = hydration
        self.training = training
        self.nutrition = nutrition
        self.digestion = digestion
    }
}

public struct ActivityRingMonth: Sendable, Hashable {
    public let id: String
    public let days: [ActivityRingDay]

    public init(id: String, days: [ActivityRingDay]) {
        self.id = id
        self.days = days
    }

    public func day(on logicalDay: String) -> ActivityRingDay? {
        day(on: LogicalDay(logicalDay))
    }

    public func day(on logicalDay: LogicalDay) -> ActivityRingDay? {
        days.first { $0.day == logicalDay }
    }
}

/// Computes one local calendar month of Activity Rings from the existing
/// module stores. Nutrition classification and the Digestion fill rule remain
/// explicit unavailable states until their product rules exist.
public struct ActivityRingCalendar: Sendable {
    private let db: Database
    private let timeModel: TimeModel

    public init(db: Database, timeModel: TimeModel) {
        self.db = db
        self.timeModel = timeModel
    }

    public func month(containing date: Date) throws -> ActivityRingMonth {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeModel.timeZone
        guard let interval = calendar.dateInterval(of: .month, for: date),
              let dayRange = calendar.range(of: .day, in: .month, for: date)
        else { return ActivityRingMonth(id: "", days: []) }

        let dates = dayRange.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: interval.start)
        }
        let logicalDays = dates.map { date in
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return LogicalDay(String(format: "%04d-%02d-%02d",
                                     parts.year ?? 0, parts.month ?? 0, parts.day ?? 0))
        }
        guard let first = logicalDays.first, let last = logicalDays.last,
              let firstBounds = timeModel.bounds(of: first),
              let afterLast = timeModel.day(after: last),
              let lastBounds = timeModel.bounds(of: afterLast)
        else { return ActivityRingMonth(id: "", days: []) }

        // ponytail: §6.10 target snapshots are not built yet; use the current
        // explicit goal for the displayed month rather than inventing history.
        let target = Milliliters(try HydrationSettingsStore(db: db).fetch()?.dailyGoalMilliliters ?? 2_000)
        let queryBounds = DateRange(start: firstBounds.start, end: lastBounds.end).utcTextBounds
        var totals = Dictionary(uniqueKeysWithValues: logicalDays.map { ($0.value, 0.0) })
        for entry in try HydrationStore(db: db).logs(from: queryBounds.start, to: queryBounds.end) {
            guard let instant = entry.loggedAt.span?.start else { continue }
            let day = timeModel.logicalDay(instant).value
            if totals[day] != nil { totals[day, default: 0] += entry.amount.value }
        }

        var nutritionLogged = Set<String>()
        for placed in try NutritionLogStore(db: db).logged(from: queryBounds.start, to: queryBounds.end) {
            guard let instant = placed.occurrence.span?.start else { continue }
            let day = timeModel.logicalDay(instant).value
            if totals[day] != nil { nutritionLogged.insert(day) }
        }

        let digestionEnabled = try ActivityRingSettingsStore(db: db).isDigestionEnabled()
        let parts = calendar.dateComponents([.year, .month], from: interval.start)
        let monthID = String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
        let days = try logicalDays.map { day in
            let total = Milliliters(totals[day.value, default: 0])
            return ActivityRingDay(
                day: day,
                hydrationTotalMilliliters: total,
                hydrationTargetMilliliters: target,
                hydration: total >= target ? .complete : .incomplete,
                training: try WorkoutSessionStore(db: db).sessions(date: day.value).isEmpty
                    ? .incomplete : .complete,
                nutrition: nutritionLogged.contains(day.value)
                    ? .dietProfileRequired : .notLogged,
                digestion: digestionEnabled ? .fillRuleUnavailable : .disabled
            )
        }
        return ActivityRingMonth(id: monthID, days: days)
    }
}

/// The singleton display preference for optional rings. It is persisted so
/// backup/restore and the Settings screen share the same source of truth.
public struct ActivityRingSettingsStore: Sendable {
    private let db: Database

    public init(db: Database) {
        self.db = db
    }

    public func isDigestionEnabled() throws -> Bool {
        guard let value = try db.query(
            "SELECT digestion_enabled FROM activity_ring_settings WHERE id = 'local';"
        ).first?.int("digestion_enabled") else { return false }
        return value != 0
    }

    public func setDigestionEnabled(_ enabled: Bool) throws {
        try db.run("""
        INSERT INTO activity_ring_settings (id, digestion_enabled, updated_at)
        VALUES ('local', ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            digestion_enabled = excluded.digestion_enabled,
            updated_at = excluded.updated_at;
        """, [
            .integer(enabled ? 1 : 0),
            .text(ISO8601DateFormatter().string(from: Date()))
        ])
    }
}
