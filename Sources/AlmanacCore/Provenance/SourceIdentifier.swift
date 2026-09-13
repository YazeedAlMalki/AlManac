import Foundation

/// Processing Design v0.1 §3 — namespace, never renumber.
///
/// `usda:1105904`, `ciqual:1000`, `cofid:13-145`, `afcd:F002258`.
/// An Almanac-internal integer key is a private detail that must never replace
/// the publisher's identifier. Namespacing keeps a food traceable to its
/// publisher, lets two sources sit side by side, and — the point that matters —
/// keeps "remove a whole source" a one-line delete when a rights holder says no.
public struct SourceIdentifier: Codable, Sendable, Hashable, CustomStringConvertible {
    public let namespace: Namespace
    public let localID: String

    public enum Namespace: String, Codable, Sendable, CaseIterable, Hashable {
        case usda, ciqual, cofid, afcd, frida
        case openFoodFacts = "off"
        case sfda, wger, freeExerciseDB = "fedb", everkinetic, opentraining
        /// Rows Almanac owns outright. The only namespace Almanac may license
        /// independently.
        case almanac

        public var licenceGroup: LicenceGroup {
            switch self {
            case .usda: return .permissive
            case .almanac: return .native
            case .ciqual, .cofid, .afcd, .frida: return .attribution
            case .openFoodFacts: return .shareAlike
            case .sfda: return .restricted
            // Exercise sources carry per-entry licences (wger admits ODbL as a
            // possible value). They are never classified at source level —
            // exercise rows must carry their own group column.
            case .wger, .freeExerciseDB, .everkinetic, .opentraining: return .restricted
            }
        }
    }

    public init(namespace: Namespace, localID: String) {
        self.namespace = namespace
        self.localID = localID
    }

    public var description: String { "\(namespace.rawValue):\(localID)" }

    public init?(parsing text: String) {
        guard let sep = text.firstIndex(of: ":") else { return nil }
        let ns = String(text[text.startIndex..<sep])
        let rest = String(text[text.index(after: sep)...])
        guard let namespace = Namespace(rawValue: ns), !rest.isEmpty else { return nil }
        self.init(namespace: namespace, localID: rest)
    }
}
