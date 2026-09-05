import Foundation

/// Injectable time source. Every date in the core comes through this, so tests
/// can pin "now" and DST edges can be exercised deterministically.
public protocol Clock: Sendable {
    var now: Date { get }
}

public struct SystemClock: Clock {
    public init() {}
    public var now: Date { Date() }
}

public final class FixedClock: Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date
    public init(_ now: Date) { self._now = now }
    public var now: Date {
        lock.lock(); defer { lock.unlock() }
        return _now
    }
    public func set(_ date: Date) {
        lock.lock(); defer { lock.unlock() }
        _now = date
    }
    public func advance(by interval: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        _now = _now.addingTimeInterval(interval)
    }
}
