import Foundation
import CSQLite

extension Database {
    /// Grants two databases' raw handles to `body` for C APIs that need both
    /// (currently only the online backup API). Deliberately internal — nothing
    /// outside this module should hold a raw sqlite3 pointer.
    func withHandles<T>(_ other: Database, _ body: (OpaquePointer?, OpaquePointer?) throws -> T) throws -> T {
        try body(rawHandle, other.rawHandle)
    }
}
