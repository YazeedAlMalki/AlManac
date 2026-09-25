import Foundation

/// Merges module-provided entries into one ordered sequence.
///
/// Holds no state and stores nothing. Ordering is a total order over fields
/// every entry carries, so the result does not depend on provider order or on
/// the order rows came back from SQLite.
public struct Timeline: Sendable {
    private let providers: [any TimelineProviding]

    public init(providers: [any TimelineProviding]) {
        self.providers = providers
    }

    public func entries(from: String, to: String) throws -> [TimelineEntry] {
        var merged: [TimelineEntry] = []
        for provider in providers {
            merged.append(contentsOf: try provider.entries(from: from, to: to))
        }
        return merged.sorted(by: Timeline.precedes)
    }

    // There is deliberately no `undatedEntries`. Every module resolves a
    // placement — occurrence, else reported, else recorded — so no entry
    // currently reaches the timeline with an unknown time, and an accessor
    // that could only ever return an empty array would imply a bucket that
    // does not exist. `TimelineEntry.basis` is what distinguishes a weak
    // placement from a real occurrence.

    static func precedes(_ a: TimelineEntry, _ b: TimelineEntry) -> Bool {
        if let aStart = a.occurrence.span?.start,
           let bStart = b.occurrence.span?.start,
           aStart != bStart {
            return aStart < bStart
        }
        if a.occurrence.span?.start != nil, b.occurrence.span?.start == nil {
            return true
        }
        if a.occurrence.span?.start == nil, b.occurrence.span?.start != nil {
            return false
        }
        if a.occurrence != b.occurrence { return a.occurrence < b.occurrence }
        if a.domain != b.domain { return a.domain < b.domain }
        if a.kind != b.kind { return a.kind < b.kind }
        if a.recordTable != b.recordTable { return a.recordTable < b.recordTable }
        return a.recordID < b.recordID
    }
}
