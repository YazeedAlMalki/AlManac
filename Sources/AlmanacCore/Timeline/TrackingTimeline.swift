import Foundation

/// The timeline used by the Today tracking calendar.
///
/// Each provider owns its table, occurrence placement, and value presentation;
/// this type only composes the existing module seams and performs the merge.
public struct TrackingTimeline {
    private let timeline: Timeline

    public init(db: Database) {
        var providers: [any TimelineProviding] = [
            LabStore(db: db),
            NutritionLogStore(db: db),
            HydrationStore(db: db)
        ]
        for domain in HealthDomain.allCases where domain != .water {
            providers.append(HealthSampleStore(db: db, healthDomain: domain))
        }
        timeline = Timeline(providers: providers)
    }

    public func items(from: String, to: String) throws -> [TrackingTimelineItem] {
        try timeline.entries(from: from, to: to).map { entry in
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
        case .none, .missing:
            return nil
        case .quantity(let text, let unit):
            return unit.map { "\(text) \($0)" } ?? text
        case .bounded(let comparator, let text, let unit):
            let body = "\(comparator) \(text)"
            return unit.map { "\(body) \($0)" } ?? body
        case .coded(let text), .narrative(let text), .ratio(let text), .titer(let text):
            return text
        case .derived(let text, _):
            return text
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
