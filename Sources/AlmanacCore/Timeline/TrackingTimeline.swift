import Foundation

/// The timeline used by the Today tracking calendar.
///
/// Each provider owns its table, occurrence placement, and value presentation;
/// this type composes the existing module seams and a small compatibility
/// adapter for stores that have not yet adopted `TimelineProviding` directly.
public struct TrackingTimeline {
    private let db: Database
    private let providers: [any TimelineProviding]

    public init(db: Database) {
        self.db = db
        // The supplement provider appended per query owns the health domains
        // that have specialised stores (sleep, workouts, body composition,
        // mood, soreness, custom measurements and vitals), so raw health
        // samples are not added here as a second representation.
        self.providers = [
            LabStore(db: db),
            NutritionLogStore(db: db),
            HydrationStore(db: db)
        ]
    }

    /// The three table-backed providers, and **only** those.
    ///
    /// The health domains — sleep, workouts, body composition, vitals, mood,
    /// soreness, custom measurements — come from `TrackingSupplementProvider`
    /// below, and that provider places entries by *logical day* rather than by
    /// UTC text. A `[from, to)` pair of UTC instants does not determine a set of
    /// logical days without a timezone, and picking one would silently file a
    /// 03:00 entry under whichever day the wrong zone decided — the exact
    /// confusion §7.2's night window exists to prevent.
    ///
    /// So this is honestly the lesser timeline, and the day-range entry point
    /// below is the one to use for anything user-facing. It exists because the
    /// three stores are `TimelineProviding` in their own right and composing
    /// them directly is legitimate; it is not the whole of what was recorded.
    public func items(from: String, to: String) throws -> [TrackingTimelineItem] {
        map(try Timeline(providers: providers).entries(from: from, to: to))
    }

    /// Everything recorded across `[fromDay, toDay)`, in occurrence order.
    ///
    /// **The single implementation of "what happened".** `items(for:)` is a
    /// one-day call to this, and it used to be a separate code path that
    /// appended a provider the range query did not have — so the two entry
    /// points answered different questions under the same name, and the range
    /// one quietly omitted sleep, workouts, mood, vitals and body composition.
    ///
    /// `toDay` is exclusive and is a *logical* day, because a logical day is
    /// what every one of these tables is keyed by and the 04:00 boundary is what
    /// the app is organised around.
    public func items(fromDay: String, toDay: String, timeModel: TimeModel) throws -> [TrackingTimelineItem] {
        let days = logicalDays(from: fromDay, to: toDay, timeModel: timeModel)
        guard let first = days.first,
              let last = days.last,
              let start = timeModel.bounds(of: LogicalDay(first))?.start,
              let end = timeModel.bounds(of: LogicalDay(last))?.end else { return [] }

        var providers = providers
        providers.append(TrackingSupplementProvider(db: db, days: days, timeModel: timeModel))
        return map(try Timeline(providers: providers).entries(from: iso(start), to: iso(end)))
    }

    public func items(for day: String, timeModel: TimeModel) throws -> [TrackingTimelineItem] {
        let next = timeModel.day(after: LogicalDay(day))?.value ?? day
        return try items(fromDay: day, toDay: next, timeModel: timeModel)
    }

    /// The logical days in `[from, to)`, walked through `TimeModel` so the 04:00
    /// boundary is applied between them rather than assumed away.
    private func logicalDays(from: String, to: String, timeModel: TimeModel) -> [String] {
        var days: [String] = []
        var cursor = LogicalDay(from)
        let last = LogicalDay(to)
        // Bounded so a reversed or nonsensical range cannot spin. 370 is a year
        // of days; a wider range than that is a mistake, not a request.
        for _ in 0..<370 {
            if cursor.value >= last.value { break }
            days.append(cursor.value)
            guard let next = timeModel.day(after: cursor) else { break }
            cursor = next
        }
        return days
    }

    private func iso(_ date: Date) -> String {
        DateRange.utcFormatter.string(from: date)
    }

    private func map(_ entries: [TimelineEntry]) -> [TrackingTimelineItem] {
        entries.map { entry in
            let detailParts = [entry.detail,
                               entry.rangeFit == .potential ? localized("Date may overlap this day") : nil]
                .compactMap { $0 }
            return TrackingTimelineItem(
                id: "\(entry.domain)-\(entry.recordID)",
                title: entry.title,
                detail: detailParts.isEmpty ? nil : detailParts.joined(separator: " · "),
                value: displayValue(entry.value),
                // Carried through rather than left for the caller to recover.
                // A reading surface needs the time of day on every row, and
                // reconstructing it meant matching on a hand-built id string
                // ("domain-table-id") that any change to a provider's naming
                // would silently break.
                occurredAt: entry.occurrence.span?.start,
                basis: entry.basis
            )
        }
    }

    private func displayValue(_ value: ValuePresentation) -> String? {
        switch value {
        case .none:
            return nil
        case .missing(let reason):
            return localized("Missing: %@", reason)
        case .quantity(let text, let unit):
            return unit.map { "\(text) \($0)" } ?? text
        case .bounded(let comparator, let text, let unit):
            let body = "\(comparator) \(text)"
            return unit.map { "\(body) \($0)" } ?? body
        case .coded(let text), .narrative(let text), .ratio(let text), .titer(let text):
            return text
        case .derived(let text, let ruleVersion):
            return "\(text) (rule \(ruleVersion))"
        }
    }
}

/// The health domains, for days the caller named.
///
/// A range rather than one day because the Today surface asks about one and a
/// reading surface asks about several, and a provider that only answered for a
/// single day would force the second caller to loop over the first one's
/// contract. Every query below is already keyed by logical day, so the range is
/// just a walk.
private struct TrackingSupplementProvider: TimelineProviding {
    let domain = "tracking-supplement"
    let db: Database
    let days: [String]
    let timeModel: TimeModel

    func entries(from: String, to: String) throws -> [TimelineEntry] {
        var result: [TimelineEntry] = []
        for day in days {
            result.append(contentsOf: try entries(forDay: day))
        }
        return result
    }

    private func entries(forDay day: String) throws -> [TimelineEntry] {
        let nextDay = timeModel.day(after: LogicalDay(day))?.value ?? day
        var result: [TimelineEntry] = []

        for session in try WorkoutSessionStore(db: db).sessions(date: day) {
            let details = [
                session.durationMinutes.map { "\($0) min" },
                session.rpe.map { localized("RPE %@/10", NumberDisplay.localized(String($0))) },
                session.notes
            ].compactMap { $0 }
            result.append(makeEntry(
                kind: "session", table: "workoutSession", id: String(session.id),
                occurrence: occurrence(session.startTimestamp, fallback: day),
                title: session.sessionType ?? localized("Training"),
                detail: details.isEmpty ? nil : details.joined(separator: " · "),
                value: .none
            ))
        }

        let bodyStore = BodyCompositionMeasurementStore(db: db)
        for metric in ["weight", "body_fat_pct", "lean_mass_kg", "skeletal_muscle_kg", "visceral_rating"] {
            for record in try bodyStore.records(metric: metric, from: day, to: nextDay) {
                result.append(makeEntry(
                    kind: "measurement", table: "body_composition_measurement", id: String(record.id),
                    occurrence: occurrence(record.timestamp, fallback: day),
                    title: bodyTitle(record.metric), detail: record.source,
                    value: .quantity(text: numberText(record.value), unit: record.unit)
                ))
            }
        }

        let customStore = CustomMeasurementStore(db: db)
        for definition in try customStore.definitions() {
            for record in try customStore.history(definitionId: definition.id, from: day, to: nextDay) {
                result.append(makeEntry(
                    kind: "custom_measurement", table: "custom_measurement_log", id: String(record.id),
                    occurrence: occurrence(record.timestamp, fallback: day),
                    title: definition.name, detail: record.notes,
                    value: .quantity(text: numberText(record.value), unit: definition.unit)
                ))
            }
        }

        for record in try MoodLogStore(db: db).logs(for: day) {
            result.append(makeEntry(
                kind: "mood", table: "mood_log", id: String(record.id),
                occurrence: occurrence(record.timestamp, fallback: day),
                title: localized("Mood"), detail: record.notes,
                value: .quantity(text: String(record.score), unit: "/10")
            ))
        }

        for record in try SorenessLogStore(db: db).logs(for: day) {
            let areas = record.bodyAreas.isEmpty ? nil : record.bodyAreas.joined(separator: ", ")
            result.append(makeEntry(
                kind: "soreness", table: "soreness_log", id: String(record.id),
                occurrence: occurrence(record.timestamp, fallback: day),
                title: localized("Soreness"), detail: areas ?? record.notes,
                value: .quantity(text: String(record.overallScore), unit: "/10")
            ))
        }

        for record in try SleepEpisodeStore(db: db).episodes(for: day) {
            result.append(makeEntry(
                kind: "episode", table: "sleep_episode", id: String(record.id),
                occurrence: occurrence(record.start, fallback: day),
                title: localized("Sleep · %@", "\(record.effectiveType)"),
                detail: localized("%@ min", NumberDisplay.localized(String(record.durationMinutes))),
                value: .quantity(text: String(record.durationMinutes), unit: localized("min"))
            ))
        }

        for record in try VitalsRecordStore(db: db).records(for: day) {
            result.append(makeEntry(
                kind: "vital", table: "vitals_record", id: String(record.id),
                occurrence: occurrence(record.timestamp, fallback: day),
                title: vitalTitle(record.metric), detail: record.source,
                value: .quantity(text: numberText(record.value), unit: record.unit)
            ))
        }

        return result
    }

    private func makeEntry(kind: String, table: String, id: String,
                           occurrence: PartialDateTime, title: String, detail: String?,
                           value: ValuePresentation) -> TimelineEntry {
        TimelineEntry(domain: domain, kind: kind, recordTable: table, recordID: "\(table)-\(id)",
                      occurrence: occurrence, basis: .occurrence, title: title,
                      detail: detail, value: value)
    }

    private func occurrence(_ date: Date?, fallback: String) -> PartialDateTime {
        date.map { PartialDateTime(instant: $0, zone: .unknown) }
            ?? PartialDateTime(text: fallback, precision: .day)
    }

    private func occurrence(_ text: String?, fallback: String) -> PartialDateTime {
        guard let text, let date = Self.parse(text) else {
            return PartialDateTime(text: fallback, precision: .day)
        }
        return PartialDateTime(instant: date, zone: .unknown)
    }

    private static func parse(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    private func numberText(_ value: Double) -> String {
        NumberDisplay.localized(value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value))
    }

    private func bodyTitle(_ metric: String) -> String {
        switch metric {
        case "weight": return localized("Weight")
        case "body_fat_pct": return localized("Body fat")
        case "lean_mass_kg": return localized("Lean mass")
        case "skeletal_muscle_kg": return localized("Skeletal muscle")
        case "visceral_rating": return localized("Visceral rating")
        default: return metric.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func vitalTitle(_ metric: String) -> String {
        switch metric {
        case "rhr": return localized("Resting heart rate")
        case "hrv": return localized("Heart-rate variability")
        case "steps": return localized("Steps")
        case "activeEnergy": return localized("Active energy")
        case "restingEnergy": return localized("Resting energy")
        default: return metric.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

public struct TrackingTimelineItem: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let detail: String?
    public let value: String?
    /// When it happened, as an instant.
    ///
    /// Nil when the placement is not an instant — a `.recorded` basis, or a
    /// day-precision fallback. That is a real placement and not a missing one,
    /// so a caller shows it as such rather than treating it as zero.
    public let occurredAt: Date?
    /// How strong the placement is. `.occurrence` is a real clock time; anything
    /// else is the timeline saying this entry's time is a weaker claim, which
    /// the detail column already words.
    public let basis: TimeBasis

    public init(id: String, title: String, detail: String?, value: String?,
                occurredAt: Date? = nil, basis: TimeBasis = .occurrence) {
        self.id = id
        self.title = title
        self.detail = detail
        self.value = value
        self.occurredAt = occurredAt
        self.basis = basis
    }
}
