import Foundation

/// One synced domain's state over a window, for the Health screen.
///
/// The screen's whole job is to answer "what did Health give us, and when",
/// which no existing type does: the three bridges each write their own table
/// (`vitals_record`, `body_composition_measurement`, `sleep_episode`) and none
/// of them reads back across the others.
public struct HealthSummary: Sendable, Hashable, Identifiable {
    public let domain: HealthDomain
    public let title: String
    /// Latest value in `unit`, or nil when the domain has rows but none carry a
    /// value. Sleep reports the most recent episode's duration in minutes.
    public let latestValue: Double?
    public let latestAt: Date?
    /// Rows in the window — samples for quantities, episodes for sleep.
    public let count: Int
    public let unit: String

    public var id: String { domain.rawValue }
}

/// Reads the three tables the HealthKit bridges write, as one list.
///
/// The metric names are the same strings the bridges write, so a metric renamed
/// in a bridge leaves this reading a column that receives nothing rather than
/// silently reporting a different one. Note the three tables do **not** agree on
/// soft deletion — `body_composition_measurement` has `deletedAt`,
/// `vitals_record` has no such column at all, and `sleep_episode` is keyed by
/// source — so each spec carries its own scope predicate rather than one shared
/// filter that would fail on two of the three.
public struct HealthSummaryStore: Sendable {
    private let db: Database

    public init(db: Database) {
        self.db = db
    }

    /// One row per domain that has data in the window, in a stable order.
    /// Domains with nothing in the window are omitted rather than reported as
    /// zero — "no data" and "a value of nothing" are different facts.
    public func summaries(in range: DateRange) throws -> [HealthSummary] {
        // Normalised to UTC for the same reason `HealthSampleStore.entries` does
        // it: these columns hold UTC `...Z` strings, so a caller's offset text
        // would compare wrongly, and silently so.
        let bounds = range.utcTextBounds
        return try Self.specs.compactMap { spec in
            try summary(for: spec, from: bounds.start, to: bounds.end)
        }
    }

    private func summary(for spec: Spec, from start: String, to end: String) throws -> HealthSummary? {
        let window = spec.scopeBindings + [.text(start), .text(end)]
        let row = try db.query("""
        SELECT COUNT(*) AS n, MAX(\(spec.timeColumn)) AS latest_at FROM \(spec.table)
        WHERE \(spec.scope) AND \(spec.timeColumn) >= ? AND \(spec.timeColumn) < ?;
        """, window).first
        let count = Int(row?.int("n") ?? 0)
        guard count > 0 else { return nil }

        // Matched on the stored text rather than a re-formatted date: these
        // columns are UTC `...Z` strings, and round-tripping one through a
        // formatter can change its precision enough to match nothing.
        let latestText = row?.string("latest_at")
        var value: Double?
        if let latestText {
            let hit = try db.query("""
            SELECT \(spec.valueColumn) AS v FROM \(spec.table)
            WHERE \(spec.scope) AND \(spec.timeColumn) = ? LIMIT 1;
            """, spec.scopeBindings + [.text(latestText)]).first
            value = hit?.double("v") ?? nil
        }
        return HealthSummary(domain: spec.domain, title: spec.title,
                             latestValue: value, latestAt: latestText.flatMap(parseISO),
                             count: count, unit: spec.unit)
    }

    // MARK: - Specs

    private struct Spec {
        let domain: HealthDomain
        let title: String
        let table: String
        /// When the row happened. Sleep is selected by when the episode *ended*,
        /// because an episode belongs to the day it woke.
        let timeColumn: String
        let valueColumn: String
        let unit: String
        /// Narrows the table to this domain's rows. Bindings are positional and
        /// come before the window bounds.
        let scope: String
        let scopeBindings: [SQLValue]

        fileprivate init(domain: HealthDomain, title: String, table: String,
                         timeColumn: String = "timestamp", valueColumn: String = "value",
                         unit: String, scope: String, scopeBindings: [SQLValue] = []) {
            self.domain = domain
            self.title = title
            self.table = table
            self.timeColumn = timeColumn
            self.valueColumn = valueColumn
            self.unit = unit
            self.scope = scope
            self.scopeBindings = scopeBindings
        }

        /// A `vitals_record` metric. No soft-delete column on that table.
        fileprivate static func vitals(_ domain: HealthDomain, _ title: String,
                                        _ metric: String, _ unit: String) -> Spec {
            .init(domain: domain, title: title, table: "vitals_record", unit: unit,
                  scope: "metric = ?", scopeBindings: [.text(metric)])
        }

        /// A `body_composition_measurement` metric, which does soft-delete.
        fileprivate static func body(_ domain: HealthDomain, _ title: String,
                                     _ metric: String, _ unit: String) -> Spec {
            .init(domain: domain, title: title, table: "body_composition_measurement", unit: unit,
                  scope: "metric = ? AND deletedAt IS NULL", scopeBindings: [.text(metric)])
        }
    }

    private static let specs: [Spec] = [
        .vitals(.heartRate, "Resting heart rate", "rhr", "bpm"),
        .vitals(.hrv, "Heart rate variability", "hrv", "ms"),
        .vitals(.steps, "Steps", "steps", "count"),
        .vitals(.activeEnergy, "Active energy", "activeEnergy", "kcal"),
        .vitals(.restingEnergy, "Resting energy", "restingEnergy", "kcal"),
        .body(.bodyMass, "Weight", "weight", "kg"),
        .body(.bodyFatPercentage, "Body fat", "body_fat_pct", "%"),
        .body(.leanBodyMass, "Lean mass", "lean_mass_kg", "kg"),
        // Episodes are counted and measured in minutes rather than valued, and
        // a manual wake-time marker is not a synced episode.
        .init(domain: .sleep, title: "Sleep", table: "sleep_episode",
              timeColumn: "endTimestamp", valueColumn: "durationMinutes", unit: "min",
              scope: "source = 'healthkit'"),
    ]

    private func parseISO(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
