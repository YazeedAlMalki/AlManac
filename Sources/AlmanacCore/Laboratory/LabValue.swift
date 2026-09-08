import Foundation

// The five dimensions. Each is set independently; none defaults to a guess.
// A single enum collapsing these was the v0.1 error: "pending", "qualitative"
// and "< 0.01" are not points on one scale.

public enum LabLifecycle: String, Codable, Sendable, CaseIterable, Hashable {
    case pending, final, amended, corrected, cancelled
    case enteredInError = "entered_in_error"
    case superseded, unknown
}

public enum LabValueType: String, Codable, Sendable, CaseIterable, Hashable {
    case quantitative
    case semiQuantitative = "semi_quantitative"
    case ordinal
    case qualitativeCoded = "qualitative_coded"
    case ratio, titer, text, absent
}

/// Reported exactly as the source printed it, and **never** read as a limit
/// of detection or quantification. `<0.01` says the value is below 0.01 as
/// this source reported it, nothing more. LOD and LOQ are separate fields
/// populated only when the source states them.
public enum LabComparator: String, Codable, Sendable, CaseIterable, Hashable {
    case none, lt, lte, gt, gte, approx

    public var symbol: String? {
        switch self {
        case .none:   return nil
        case .lt:     return "<"
        case .lte:    return "\u{2264}"
        case .gt:     return ">"
        case .gte:    return "\u{2265}"
        case .approx: return "~"
        }
    }
    public var isBounded: Bool { self != .none }
}

/// Defaults to `unknown`, not `measured`. Most reports do not say how a value
/// was produced, and asserting `measured` would be inference.
public enum LabDerivation: String, Codable, Sendable, CaseIterable, Hashable {
    case measured
    case calculatedBySource = "calculated_by_source"
    case reportedWithoutDerivationStated = "reported_without_derivation_stated"
    case unknown
}

/// Set if and only if `valueType == .absent`. Absence always carries a reason,
/// even when the reason is that nobody knows.
public enum LabMissingReason: String, Codable, Sendable, CaseIterable, Hashable {
    case notPerformed = "not_performed"
    case specimenRejected = "specimen_rejected"
    case quantityInsufficient = "quantity_insufficient"
    case pending
    case notReportedBySource = "not_reported_by_source"
    case illegibleInDocument = "illegible_in_document"
    case notEntered = "not_entered"
    case unknown
}

/// Where this revision's content came from. Distinguishes a machine reading a
/// report, a person typing one in, and a person later fixing it.
public enum LabContentOrigin: String, Codable, Sendable, CaseIterable, Hashable {
    case sourceExtraction = "source_extraction"
    case userTranscription = "user_transcription"
    case userCorrection = "user_correction"
}

public enum LabError: Error, CustomStringConvertible, Sendable {
    case missingReasonRequired
    case missingReasonNotAllowed(LabValueType)
    case observationNotFound(String)
    case reportNotFound(String)
    case noCurrentRevision(String)

    public var description: String {
        switch self {
        case .missingReasonRequired:
            return "value_type 'absent' requires a missing reason; use .unknown rather than none."
        case .missingReasonNotAllowed(let t):
            return "a missing reason is only valid for value_type 'absent', not '\(t.rawValue)'."
        case .observationNotFound(let id):
            return "no observation with id \(id)."
        case .reportNotFound(let id):
            return "no report with id \(id)."
        case .noCurrentRevision(let id):
            return "observation \(id) has no current revision."
        }
    }
}

/// One version of an observation's content.
///
/// Every source field is optional: a manual entry made from memory has no
/// printed text to preserve, and that must not block entry. Where source text
/// exists it is stored verbatim and never overwritten by interpretation.
public struct LabRevisionContent: Sendable, Hashable {
    public var lifecycle: LabLifecycle = .unknown
    public var valueType: LabValueType = .absent
    public var comparator: LabComparator = .none
    public var derivation: LabDerivation = .unknown
    public var missingReason: LabMissingReason? = nil

    public var numericValue: Double? = nil
    public var codedValue: String? = nil
    public var textValue: String? = nil
    public var ratioNumerator: Double? = nil
    public var ratioDenominator: Double? = nil
    public var titerNumerator: Int? = nil
    public var titerDenominator: Int? = nil

    public var unitText: String? = nil
    public var lodText: String? = nil
    public var loqText: String? = nil
    public var rangeText: String? = nil
    public var rangeLow: Double? = nil
    public var rangeHigh: Double? = nil
    public var rangeUnitText: String? = nil
    public var flagText: String? = nil
    public var commentText: String? = nil
    public var methodText: String? = nil

    public var sourceAnalyteText: String? = nil
    public var sourceValueText: String? = nil

    public var contentOrigin: LabContentOrigin = .userTranscription
    public var actor: String = "user"
    public var reasonText: String? = nil
    public var sourceRevisionID: String? = nil

    public init() {}

    public func validated() throws -> LabRevisionContent {
        if valueType == .absent && missingReason == nil { throw LabError.missingReasonRequired }
        if valueType != .absent && missingReason != nil {
            throw LabError.missingReasonNotAllowed(valueType)
        }
        return self
    }

    /// Identifies this content for idempotent re-import.
    ///
    /// Covers every field a source could restate. The three provenance fields
    /// — `contentOrigin`, `actor` and `reasonText` — are excluded on purpose:
    /// the same reported content arriving twice is the same content whoever
    /// carried it and however it was carried, which is what makes a re-import
    /// a no-op instead of a spurious revision. Provenance is still stored on
    /// every revision row; it just does not participate in identity.
    public var fingerprint: String {
        let parts: [String?] = [
            lifecycle.rawValue, valueType.rawValue, comparator.rawValue, derivation.rawValue,
            missingReason?.rawValue,
            numericValue.map { String($0) }, codedValue, textValue,
            ratioNumerator.map { String($0) }, ratioDenominator.map { String($0) },
            titerNumerator.map { String($0) }, titerDenominator.map { String($0) },
            unitText, lodText, loqText, rangeText,
            rangeLow.map { String($0) }, rangeHigh.map { String($0) }, rangeUnitText,
            flagText, commentText, methodText,
            sourceAnalyteText, sourceValueText, sourceRevisionID
        ]
        let joined = parts.map { $0 ?? "\u{0}" }.joined(separator: "\u{1}")
        return SHA256File.hex(of: Array(joined.utf8))
    }

    /// How the timeline should show this value. The module decides; the
    /// timeline never reinterprets.
    public var presentation: ValuePresentation {
        switch valueType {
        case .absent:
            return .missing(reason: (missingReason ?? .unknown).rawValue)
        case .qualitativeCoded, .ordinal:
            return .coded(text: codedValue ?? sourceValueText ?? "")
        case .text:
            return .narrative(text: textValue ?? sourceValueText ?? "")
        case .ratio:
            if let n = ratioNumerator, let d = ratioDenominator {
                return .ratio(text: "\(n):\(d)")
            }
            return .ratio(text: sourceValueText ?? "")
        case .titer:
            if let n = titerNumerator, let d = titerDenominator {
                return .titer(text: "\(n):\(d)")
            }
            return .titer(text: sourceValueText ?? "")
        case .quantitative, .semiQuantitative:
            let shown = sourceValueText ?? numericValue.map { String($0) } ?? ""
            if let symbol = comparator.symbol {
                return .bounded(comparator: symbol, text: shown, unit: unitText)
            }
            if derivation == .calculatedBySource {
                return .derived(text: shown, ruleVersion: "source")
            }
            return .quantity(text: shown, unit: unitText)
        }
    }
}
