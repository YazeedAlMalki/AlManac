import Foundation
import CSQLite

public struct SQLiteError: Error, CustomStringConvertible, Sendable {
    public let code: Int32
    public let message: String
    public let sql: String?

    public init(code: Int32, message: String, sql: String? = nil) {
        self.code = code
        self.message = message
        self.sql = sql
    }

    static func from(_ handle: OpaquePointer?, code: Int32, sql: String? = nil) -> SQLiteError {
        let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown sqlite error"
        return SQLiteError(code: code, message: msg, sql: sql)
    }

    public var description: String {
        if let sql { return "SQLite error \(code): \(message) — while running: \(sql)" }
        return "SQLite error \(code): \(message)"
    }
}

@inline(__always)
func check(_ code: Int32, _ handle: OpaquePointer?, sql: String? = nil) throws {
    guard code == SQLITE_OK || code == SQLITE_DONE || code == SQLITE_ROW else {
        throw SQLiteError.from(handle, code: code, sql: sql)
    }
}
