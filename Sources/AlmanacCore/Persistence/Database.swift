import Foundation
import CSQLite

/// Bound value for a prepared statement parameter.
public enum SQLValue: Sendable, Hashable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob([UInt8])
}

/// A single row, addressable by column name.
public struct Row: Sendable {
    private let values: [String: SQLValue]
    init(_ values: [String: SQLValue]) { self.values = values }

    public subscript(column: String) -> SQLValue? { values[column] }

    public func int(_ column: String) -> Int64? {
        if case .integer(let v)? = values[column] { return v }
        return nil
    }
    public func double(_ column: String) -> Double? {
        switch values[column] {
        case .real(let v)?: return v
        case .integer(let v)?: return Double(v)
        default: return nil
        }
    }
    public func string(_ column: String) -> String? {
        if case .text(let v)? = values[column] { return v }
        return nil
    }
    public func isNull(_ column: String) -> Bool {
        if case .null? = values[column] { return true }
        return values[column] == nil
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// A thin, non-generic wrapper over the SQLite C API.
///
/// Deliberately small. It is a seam, not an ORM: the schema lives in
/// migrations, and everything above this type works in plain SQL so that a
/// migration and a query read the same on Linux and on iOS.
/// Thread safety: the connection is opened with SQLITE_OPEN_FULLMUTEX, so
/// SQLite itself serialises concurrent use of the handle. That is what makes
/// the `@unchecked Sendable` claim true rather than convenient.
public final class Database: @unchecked Sendable {
    private var handle: OpaquePointer?
    /// Internal escape hatch for C APIs that need the raw connection.
    var rawHandle: OpaquePointer? { handle }
    public let path: String

    public init(path: String) throws {
        self.path = path
        var h: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &h, flags, nil)
        guard rc == SQLITE_OK, let opened = h else {
            let err = SQLiteError.from(h, code: rc)
            if h != nil { sqlite3_close_v2(h) }
            throw err
        }
        self.handle = opened
        try execute("PRAGMA foreign_keys = ON;")
        try execute("PRAGMA journal_mode = WAL;")
        try execute("PRAGMA busy_timeout = 5000;")
    }

    public static func inMemory() throws -> Database { try Database(path: ":memory:") }

    deinit { if let handle { sqlite3_close_v2(handle) } }

    /// Runs one or more statements with no parameters and no result rows.
    public func execute(_ sql: String) throws {
        var errmsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &errmsg)
        if rc != SQLITE_OK {
            let message = errmsg.map { String(cString: $0) } ?? "unknown sqlite error"
            if let errmsg { sqlite3_free(errmsg) }
            throw SQLiteError(code: rc, message: message, sql: sql)
        }
    }

    @discardableResult
    public func run(_ sql: String, _ parameters: [SQLValue] = []) throws -> Int {
        let stmt = try prepare(sql, parameters)
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
            throw SQLiteError.from(handle, code: rc, sql: sql)
        }
        return Int(sqlite3_changes(handle))
    }

    public func query(_ sql: String, _ parameters: [SQLValue] = []) throws -> [Row] {
        let stmt = try prepare(sql, parameters)
        defer { sqlite3_finalize(stmt) }

        let columnCount = Int(sqlite3_column_count(stmt))
        var names: [String] = []
        names.reserveCapacity(columnCount)
        for i in 0..<columnCount {
            names.append(String(cString: sqlite3_column_name(stmt, Int32(i))))
        }

        var rows: [Row] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw SQLiteError.from(handle, code: rc, sql: sql) }
            var values: [String: SQLValue] = [:]
            for i in 0..<columnCount {
                values[names[i]] = columnValue(stmt, Int32(i))
            }
            rows.append(Row(values))
        }
        return rows
    }

    private func columnValue(_ stmt: OpaquePointer?, _ index: Int32) -> SQLValue {
        switch sqlite3_column_type(stmt, index) {
        case SQLITE_INTEGER: return .integer(sqlite3_column_int64(stmt, index))
        case SQLITE_FLOAT:   return .real(sqlite3_column_double(stmt, index))
        case SQLITE_TEXT:
            guard let c = sqlite3_column_text(stmt, index) else { return .null }
            return .text(String(cString: c))
        case SQLITE_BLOB:
            let n = Int(sqlite3_column_bytes(stmt, index))
            guard n > 0, let p = sqlite3_column_blob(stmt, index) else { return .blob([]) }
            let buf = UnsafeRawBufferPointer(start: p, count: n)
            return .blob(Array(buf))
        default: return .null
        }
    }

    private func prepare(_ sql: String, _ parameters: [SQLValue]) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else { throw SQLiteError.from(handle, code: rc, sql: sql) }
        for (offset, value) in parameters.enumerated() {
            let i = Int32(offset + 1)
            let brc: Int32
            switch value {
            case .null:            brc = sqlite3_bind_null(stmt, i)
            case .integer(let v):  brc = sqlite3_bind_int64(stmt, i, v)
            case .real(let v):     brc = sqlite3_bind_double(stmt, i, v)
            case .text(let v):     brc = sqlite3_bind_text(stmt, i, v, -1, SQLITE_TRANSIENT)
            case .blob(let bytes):
                brc = bytes.isEmpty
                    ? sqlite3_bind_zeroblob(stmt, i, 0)
                    : bytes.withUnsafeBufferPointer {
                        sqlite3_bind_blob(stmt, i, $0.baseAddress, Int32(bytes.count), SQLITE_TRANSIENT)
                      }
            }
            guard brc == SQLITE_OK else {
                sqlite3_finalize(stmt)
                throw SQLiteError.from(handle, code: brc, sql: sql)
            }
        }
        return stmt
    }

    /// Runs `body` inside a transaction, rolling back on any thrown error.
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE;")
        do {
            let result = try body()
            try execute("COMMIT;")
            return result
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    public var userVersion: Int {
        get { (try? query("PRAGMA user_version;").first?.int("user_version")).flatMap { $0 }.map(Int.init) ?? 0 }
    }
}
