import Foundation

/// One forward schema change. Migrations are append-only and never edited
/// once they have run on a device — that is the whole contract.
public protocol Migration: Sendable {
    /// Strictly increasing, unique, never reused.
    static var version: Int { get }
    /// Human label recorded in `schema_migrations` for forensics.
    static var name: String { get }
    static func up(_ db: Database) throws
}

public struct AppliedMigration: Sendable, Hashable {
    public let version: Int
    public let name: String
    public let appliedAt: Date
}

public enum MigrationError: Error, CustomStringConvertible, Sendable {
    case duplicateVersion(Int)
    case outOfOrder(applied: Int, pending: Int)
    case checksumDrift(version: Int, storedName: String, incomingName: String)

    public var description: String {
        switch self {
        case .duplicateVersion(let v):
            return "Two migrations declare version \(v). Versions must be unique."
        case .outOfOrder(let applied, let pending):
            return """
            Migration \(pending) is older than \(applied), which is already applied. \
            A migration inserted behind the head would run on new installs but never \
            on existing ones. Give it a version above \(applied).
            """
        case .checksumDrift(let v, let stored, let incoming):
            return """
            Migration \(v) ran as "\(stored)" but is now declared as "\(incoming)". \
            An applied migration must never be edited — add a new one instead.
            """
        }
    }
}
