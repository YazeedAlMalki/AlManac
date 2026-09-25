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
        var providers: [any TimelineProviding] = [
            LabStore(db: db),
            NutritionLogStore(db: db),
            HydrationStore(db: db)
        ]
        // The supplement provider below owns the health domains that have
        // specialised stores (sleep, workouts, body composition and vitals),
        // so raw health samples are not added here as a second representation.
        self.providers = providers
    }

    public func items(from: String, to: String) throws -> [TrackingTimelineItem] {
        map(try Timeline(providers: providers).entries(from: from, to: to))
    }

    public func items(for day: String, timeModel: TimeModel) throws -> [TrackingTimelineItem] {
        let logicalDay = LogicalDay(day)
        guard let bounds = timeModel.bounds(of: logicalDay) else { return [] }
        let range = DateRange(start: bounds.start, end: bounds.end)
        let utcBounds = range.utcTextBounds
        var providers = providers
        providers.append(TrackingSupplementProvider(
            db: db, day: day, timeModel: timeModel
        ))
        return map(try Timeline(providers: providers).entries(
            from: utcBounds.start, to: utcBounds.end
        ))
    }

    private func map(_ entries: [TimelineEntry]) -> [TrackingTimelineItem] {
        entries.map { entry in
            let detailParts = [entry.detail,
                               entry.rangeFit == .potential ? "Date may overlap this day" : nil]
                .compactMap { $0 }
            return TrackingTimelineItem(
                id: "\(entry.domain)-\(entry.recordID)",
                title: entry.title,
                detail: detailParts.isEmpty ? nil : detailParts.joined(separator: " · "),
                value: displayValue(entry.value)
            )
        }
    }

    private func displayValue(_ value: ValuePresentation) -> String? {
        switch value {
        case .none:
            return nil
        case .missing(let reason):
            return "Missing: \(reason)"
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

private struct TrackingSupplementProvider: TimelineProviding {
    let domain = "tracking-supplement"
    let db: Database
    let day: String
    let timeModel: TimeModel

    func entries(from: String, to: String) throws -> [TimelineEntry] {
        let nextDay = timeModel.day(after: LogicalDay(day))?.value ?? day
        var result: [TimelineEntry] = []

        for session in try WorkoutSessionStore(db: db).sessions(date: day) {
            let details = [
                session.durationMinutes.map { "\($0) min" },
                session.rpe.map { "RPE \($0)/10" },
                session.notes
            ].compactMap { $0 }
            result.append(makeEntry(
                kind: "session", table: "workoutSession", id: String(session.id),
                occurrence: occurrence(session.startTimestamp, fallback: day),
                title: session.sessionType ?? "Training",
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
                title: "Mood", detail: record.notes,
                value: .quantity(text: String(record.score), unit: "/10")
            ))
        }

        for record in try SorenessLogStore(db: db).logs(for: day) {
            let areas = record.bodyAreas.isEmpty ? nil : record.bodyAreas.joined(separator: ", ")
            result.append(makeEntry(
                kind: "soreness", table: "soreness_log", id: String(record.id),
                occurrence: occurrence(record.timestamp, fallback: day),
                title: "Soreness", detail: areas ?? record.notes,
                value: .quantity(text: String(record.overallScore), unit: "/10")
            ))
        }

        for record in try SleepEpisodeStore(db: db).episodes(for: day) {
            result.append(makeEntry(
                kind: "episode", table: "sleep_episode", id: String(record.id),
                occurrence: occurrence(record.start, fallback: day),
                title: "Sleep · \(record.effectiveType)",
                detail: "\(record.durationMinutes) min",
                value: .quantity(text: String(record.durationMinutes), unit: "min")
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
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    private func bodyTitle(_ metric: String) -> String {
        switch metric {
        case "weight": return "Weight"
        case "body_fat_pct": return "Body fat"
        case "lean_mass_kg": return "Lean mass"
        case "skeletal_muscle_kg": return "Skeletal muscle"
        case "visceral_rating": return "Visceral rating"
        default: return metric.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func vitalTitle(_ metric: String) -> String {
        switch metric {
        case "rhr": return "Resting heart rate"
        case "hrv": return "Heart-rate variability"
        case "steps": return "Steps"
        case "activeEnergy": return "Active energy"
        case "restingEnergy": return "Resting energy"
        default: return metric.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

public struct TrackingTimelineItem: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let detail: String?
    public let value: String?

    public init(id: String, title: String, detail: String?, value: String?) {
        self.id = id
        self.title = title
        self.detail = detail
        self.value = value
    }
}
