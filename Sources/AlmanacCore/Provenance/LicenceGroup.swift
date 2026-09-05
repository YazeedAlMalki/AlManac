import Foundation

/// Licence groups from the Almanac collection reports and Processing Design v0.1 §1.
///
/// This is not documentation. It is the value that the bundle build asserts on,
/// so that shipping a restricted row is a build failure rather than a discovery
/// made after user data has accumulated against it.
public enum LicenceGroup: String, Codable, Sendable, CaseIterable, Hashable {
    /// Permissive core. Currently: USDA FoodData Central (CC0 1.0).
    case permissive = "A"
    /// Attribution required. CIQUAL, CoFID, Frida, AFCD.
    case attribution = "B"
    /// Share-alike on the derived database. Open Food Facts (ODbL).
    case shareAlike = "C"
    /// Restricted or unconfirmed rights. Quarantined.
    case restricted = "D"

    /// Whether rows in this group may be redistributed inside the app bundle.
    ///
    /// Processing Design v0.1 §1: putting a row in the bundle is redistributing
    /// it to every installing user, commercially, in a form they keep.
    public var isShippable: Bool {
        switch self {
        case .permissive, .attribution: return true
        case .shareAlike, .restricted: return false
        }
    }
}

public struct LicenceViolation: Error, CustomStringConvertible, Sendable {
    public let identifier: String
    public let group: LicenceGroup
    public init(identifier: String, group: LicenceGroup) {
        self.identifier = identifier
        self.group = group
    }
    public var description: String {
        "BUILD FAILURE: \(identifier) is licence group \(group.rawValue) and must never enter the bundle."
    }
}

public enum BundleGuard {
    /// Fails loudly rather than filtering silently. Processing Design v0.1 §5.
    public static func assertShippable<S: Sequence>(_ rows: S) throws
    where S.Element == (identifier: String, group: LicenceGroup) {
        for row in rows where !row.group.isShippable {
            throw LicenceViolation(identifier: row.identifier, group: row.group)
        }
    }
}
