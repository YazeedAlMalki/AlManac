import Foundation

/// One field of an edit request.
///
/// The three cases are genuinely different instructions, and collapsing the
/// first two — as an optional would — makes "leave the laboratory name alone"
/// indistinguishable from "the laboratory name is now nothing". Both are things
/// a person does, and only one of them should erase a stored value.
public enum FieldEdit<Value: Sendable & Hashable>: Sendable, Hashable {
    /// Not part of this edit. The stored value survives untouched.
    case leaveUnchanged
    /// Replace the stored value with this one.
    case set(Value)
    /// Erase the stored value. For a field that has an explicit "not stated"
    /// member — a specimen kind, a partial date — this means that member, not
    /// a NULL that would be indistinguishable from never having been asked.
    case clear

    public var isChange: Bool {
        if case .leaveUnchanged = self { return false }
        return true
    }

    /// Applies the edit to a current value, for a field whose absence is NULL.
    public func resolve(_ current: Value?) -> Value? {
        switch self {
        case .leaveUnchanged: return current
        case .set(let value):  return value
        case .clear:           return nil
        }
    }

    /// Applies the edit for a field that has its own "not stated" member.
    public func resolve(_ current: Value, cleared: Value) -> Value {
        switch self {
        case .leaveUnchanged: return current
        case .set(let value):  return value
        case .clear:           return cleared
        }
    }
}

/// A correction to an observation's metadata — everything about the
/// measurement except the measured value itself.
///
/// Result content lives in `LabRevisionContent` and is revised separately,
/// because the two answer different questions: this one is "what was this a
/// measurement *of*, and when", that one is "what did it say".
public struct LabObservationMetadataEdit: Sendable, Hashable {
    public var reportID: FieldEdit<String> = .leaveUnchanged
    public var catalogAnalyteID: FieldEdit<String> = .leaveUnchanged
    public var specimenKind: FieldEdit<SpecimenKind> = .leaveUnchanged
    public var specimenText: FieldEdit<String> = .leaveUnchanged
    public var collectedAt: FieldEdit<PartialDateTime> = .leaveUnchanged

    public var actor: String = "user"
    public var reasonText: String? = nil

    public init() {}

    public var touchesAnything: Bool {
        reportID.isChange || catalogAnalyteID.isChange || specimenKind.isChange
            || specimenText.isChange || collectedAt.isChange
    }
}

/// A correction to a report's own metadata, addressed by Almanac's report id.
///
/// Separate from `LabReportDraft`, which describes what a *source* said. A
/// person editing their own record is the authority on it and needs no source
/// identifiers, no ordering marker, and no fabricated report number.
public struct LabReportEdit: Sendable, Hashable {
    public var laboratoryNameText: FieldEdit<String> = .leaveUnchanged
    public var reportedAt: FieldEdit<PartialDateTime> = .leaveUnchanged
    public var headerText: FieldEdit<String> = .leaveUnchanged

    public var actor: String = "user"
    public var reasonText: String? = nil

    public init() {}

    public var touchesAnything: Bool {
        laboratoryNameText.isChange || reportedAt.isChange || headerText.isChange
    }
}

public enum LabMetadataOutcome: Sendable, Hashable {
    case unchanged(observationID: String)
    case updated(observationID: String, revisionID: String, revisionNumber: Int,
                 changedFields: [String])

    public var observationID: String {
        switch self {
        case .unchanged(let id): return id
        case .updated(let id, _, _, _): return id
        }
    }
    public var changedFields: [String] {
        if case .updated(_, _, _, let fields) = self { return fields }
        return []
    }
}

/// A previous set of observation metadata, with who changed it and why.
public struct LabMetadataRevision: Sendable, Hashable {
    public let id: String
    public let observationID: String
    public let revisionNumber: Int
    public let reportID: String?
    public let catalogAnalyteID: String?
    public let specimenKind: SpecimenKind
    public let specimenText: String?
    public let collectedAtText: String?
    public let collectedPrecision: TimePrecision
    /// Which fields this revision is the previous value of.
    public let changedFields: [String]
    public let actor: String
    public let reasonText: String?
    public let recordedAt: String
}
