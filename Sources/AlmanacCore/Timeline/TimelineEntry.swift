import Foundation

/// Which of a record's times the timeline placed it by.
///
/// `recorded` means the record carried no occurrence or report time and fell
/// back to when it was entered into Almanac. That is a materially weaker
/// claim, so it travels with the entry rather than being smoothed away.
public enum TimeBasis: String, Codable, Sendable, Hashable {
    case occurrence, reported, recorded
}

/// How a module chose to present its value.
///
/// Deliberately not a number and not a Bool. Missing, qualitative and bounded
/// values are three different facts, and the timeline never reinterprets what
/// a module formatted.
public enum ValuePresentation: Sendable, Hashable {
    case none
    case quantity(text: String, unit: String?)
    case bounded(comparator: String, text: String, unit: String?)
    case coded(text: String)
    case narrative(text: String)
    case ratio(text: String)
    case titer(text: String)
    case missing(reason: String)
    case derived(text: String, ruleVersion: String)
}

public struct TimelineEntry: Sendable, Hashable {
    public let domain: String
    public let kind: String
    public let recordTable: String
    public let recordID: String
    public let occurrence: PartialDateTime
    public let basis: TimeBasis
    public let title: String
    public let detail: String?
    public let value: ValuePresentation
    public let lifecycle: String?

    public init(domain: String, kind: String, recordTable: String, recordID: String,
                occurrence: PartialDateTime, basis: TimeBasis, title: String,
                detail: String? = nil, value: ValuePresentation = .none,
                lifecycle: String? = nil) {
        self.domain = domain
        self.kind = kind
        self.recordTable = recordTable
        self.recordID = recordID
        self.occurrence = occurrence
        self.basis = basis
        self.title = title
        self.detail = detail
        self.value = value
        self.lifecycle = lifecycle
    }
}

/// Implemented by each module, over its own tables.
///
/// There is no persisted event index: the module's records are the only copy,
/// so a deletion or a revision needs no second write to stay consistent.
/// `from`/`to` are ISO-8601 prefixes compared lexically, half-open [from, to).
public protocol TimelineProviding: Sendable {
    var domain: String { get }
    func entries(from: String, to: String) throws -> [TimelineEntry]
}
