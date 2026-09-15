import XCTest
import Dispatch
@testable import AlmanacCore

/// Transaction semantics, which nothing tested directly before and which every
/// store now composes on.
final class DatabaseTests: XCTestCase {

    private var path = ""
    private var db: Database!

    override func setUpWithError() throws {
        try super.setUpWithError()
        path = NSTemporaryDirectory() + "almanac-db-\(UUID().uuidString).sqlite"
        db = try Database(path: path)
        try db.execute("CREATE TABLE t (x INTEGER PRIMARY KEY);")
    }

    override func tearDown() {
        db = nil
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: path + suffix)
        }
        super.tearDown()
    }

    private struct Boom: Error {}

    private func rows() throws -> [Int64] {
        try db.query("SELECT x FROM t ORDER BY x;").compactMap { $0.int("x") }
    }

    private func insert(_ x: Int) throws {
        try db.run("INSERT INTO t (x) VALUES (?);", [.integer(Int64(x))])
    }

    func testACommittedTransactionKeepsItsWrites() throws {
        try db.transaction { try insert(1) }
        XCTAssertEqual(try rows(), [1])
    }

    func testAThrowingTransactionKeepsNothing() throws {
        XCTAssertThrowsError(try db.transaction {
            try insert(1)
            throw Boom()
        })
        XCTAssertEqual(try rows(), [])
    }

    /// `BEGIN` inside an open transaction is an error in SQLite, so this used
    /// to throw rather than nest. Two stores that each own their own
    /// consistency can now be composed without either knowing which is outer.
    func testTransactionsNest() throws {
        try db.transaction {
            try insert(1)
            try db.transaction { try insert(2) }
            try insert(3)
        }
        XCTAssertEqual(try rows(), [1, 2, 3])
    }

    /// The point of nesting: the inner scope can fail on its own terms without
    /// discarding work the outer scope had already done.
    func testAFailedInnerScopeLeavesTheOuterOneIntact() throws {
        try db.transaction {
            try insert(1)
            XCTAssertThrowsError(try db.transaction {
                try insert(2)
                throw Boom()
            })
            try insert(3)
        }
        XCTAssertEqual(try rows(), [1, 3], "only the inner scope's write is gone")
    }

    /// And the other direction: nothing an inner scope committed survives the
    /// outer one failing, because nothing commits until the outermost does.
    func testAnInnerScopeCommitsNothingUntilTheOutermostDoes() throws {
        XCTAssertThrowsError(try db.transaction {
            try db.transaction { try insert(1) }
            throw Boom()
        })
        XCTAssertEqual(try rows(), [])
    }

    func testNestingSeveralDeepStillUnwindsInOrder() throws {
        try db.transaction {
            try insert(1)
            try db.transaction {
                try insert(2)
                XCTAssertThrowsError(try db.transaction {
                    try insert(3)
                    throw Boom()
                })
                try insert(4)
            }
        }
        XCTAssertEqual(try rows(), [1, 2, 4])
    }

    func testATransactionReturnsItsBodysValue() throws {
        XCTAssertEqual(try db.transaction { 42 }, 42)
        XCTAssertEqual(try db.transaction { try db.transaction { "nested" } }, "nested")
    }

    /// SQLite reports an open transaction for the *connection*, not for the
    /// caller, so a second thread arriving mid-transaction must not read
    /// "already open" and attach its savepoint to work it has nothing to do
    /// with. Each of these is its own unit: all of them land, and none of them
    /// takes another's rollback with it.
    func testConcurrentTransactionsDoNotJoinEachOther() throws {
        let db = self.db!
        let failures = Collected()
        DispatchQueue.concurrentPerform(iterations: 16) { i in
            do {
                try db.transaction {
                    try db.run("INSERT INTO t (x) VALUES (?);", [.integer(Int64(i))])
                    // Every other one throws away its own work and must take
                    // nothing else with it.
                    if i % 2 == 1 { throw Boom() }
                }
            } catch is Boom {
                // expected for the odd ones
            } catch {
                failures.add("\(i): \(error)")
            }
        }
        XCTAssertEqual(failures.all, [], "no transaction should collide")
        XCTAssertEqual(try rows(), [0, 2, 4, 6, 8, 10, 12, 14],
                       "the even ones committed; the odd ones rolled back only themselves")
    }

    /// `NSLock`, not `objc_sync_enter` — there is no Objective-C runtime on
    /// Linux, which is where this suite actually runs.
    private final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ item: String) {
            lock.lock(); defer { lock.unlock() }
            items.append(item)
        }
        var all: [String] {
            lock.lock(); defer { lock.unlock() }
            return items
        }
    }

    /// After a failure the connection is back in autocommit, so the next
    /// transaction is a fresh outer one rather than a savepoint on a corpse.
    func testTheConnectionIsUsableAfterAFailedTransaction() throws {
        XCTAssertThrowsError(try db.transaction { throw Boom() })
        try db.transaction { try insert(1) }
        XCTAssertEqual(try rows(), [1])
    }
}
