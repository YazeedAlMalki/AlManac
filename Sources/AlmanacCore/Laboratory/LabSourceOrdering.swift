import Foundation

/// What to do with an import that carries new content the source did not rank.
///
/// Unordered changes are held by default. A person can explicitly accept or
/// reject them; arrival order does not establish source authority.
public enum UnrankedImportPolicy: Sendable, Hashable {
    /// Apply it, and mark the stored revision `superseded_unranked` so the
    /// assumption is visible in the history rather than implied by its absence.
    case applyAndFlag
    /// Leave the current version alone and record the incoming one as a
    /// conflict for a person to resolve.
    case holdAsConflict
}

/// What a source says about where one version of a report sits in its own
/// sequence.
///
/// This exists because arrival order is not authority. A laboratory's systems
/// re-send reports, queues replay, and a nightly job can hand back last week's
/// file after this week's correction. Taking "most recently received" as "most
/// recent" is how a corrected potassium result quietly reverts.
public enum SourceOrdering: Sendable, Hashable {
    /// The source said nothing about ordering. Not an error — most PDFs do not
    /// carry a version — but it means a differing version cannot be ranked, and
    /// the conflict is flagged rather than resolved by guessing.
    case unavailable
    /// A version or amendment number the source states.
    case sequence(Int)
    /// An issue or amendment timestamp the source states, as an ISO-8601
    /// prefix of any precision.
    case issuedAt(String)

    var kindText: String? {
        switch self {
        case .unavailable:  return nil
        case .sequence:     return "sequence"
        case .issuedAt:     return "issued_at"
        }
    }

    var valueText: String? {
        switch self {
        case .unavailable:        return nil
        case .sequence(let n):    return String(n)
        case .issuedAt(let text): return text
        }
    }

    static func from(kind: String?, value: String?) -> SourceOrdering {
        guard let kind, let value else { return .unavailable }
        switch kind {
        case "sequence": return Int(value).map(SourceOrdering.sequence) ?? .unavailable
        case "issued_at": return .issuedAt(value)
        default: return .unavailable
        }
    }

    /// How this version ranks against one already held.
    ///
    /// `nil` means the two cannot be ranked at all — either side is
    /// `unavailable`, or they use different kinds of marker. A nil answer is
    /// the trigger for flagging a conflict, never for picking a winner.
    func compare(to other: SourceOrdering) -> ComparisonResult? {
        switch (self, other) {
        case (.sequence(let a), .sequence(let b)):
            return a == b ? .orderedSame : (a < b ? .orderedAscending : .orderedDescending)
        case (.issuedAt(let a), .issuedAt(let b)):
            guard let l = PartialDateTime(inferringPrecisionFrom: a),
                  let r = PartialDateTime(inferringPrecisionFrom: b),
                  let left = l.possibleSpan, let right = r.possibleSpan else { return nil }
            if l.precision == .instant && r.precision == .instant && l.hasKnownOffset && r.hasKnownOffset {
                return left.start == right.start ? .orderedSame : (left.start < right.start ? .orderedAscending : .orderedDescending)
            }
            if left.end <= right.start { return .orderedAscending }
            if right.end <= left.start { return .orderedDescending }
            return nil // overlapping uncertainty cannot establish source ordering
        default:
            return nil
        }
    }
}
