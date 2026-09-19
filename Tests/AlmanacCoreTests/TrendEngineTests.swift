import Testing
@testable import AlmanacCore

@Suite("TrendEngine Tests")
struct TrendEngineTests {

    @Test("An upward series is directed up, and captures min/max/avg correctly")
    func upwardSeries() throws {
        let snapshot = try #require(TrendEngine.snapshot(of: [1, 2, 3, 4, 5, 6]))
        #expect(snapshot.direction == .up)
        #expect(snapshot.minimum == 1)
        #expect(snapshot.maximum == 6)
        #expect(abs(snapshot.average - 3.5) < 0.0001)
    }

    @Test("A downward series is directed down")
    func downwardSeries() throws {
        let snapshot = try #require(TrendEngine.snapshot(of: [6, 5, 4, 3, 2, 1]))
        #expect(snapshot.direction == .down)
    }

    @Test("A constant series is flat")
    func flatSeries() throws {
        let snapshot = try #require(TrendEngine.snapshot(of: [5, 5, 5, 5]))
        #expect(snapshot.direction == .flat)
    }

    @Test("An empty series has no snapshot")
    func emptySeries() {
        #expect(TrendEngine.snapshot(of: []) == nil)
    }
}
