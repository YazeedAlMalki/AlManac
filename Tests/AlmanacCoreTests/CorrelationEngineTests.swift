import Testing
@testable import AlmanacCore

@Suite("CorrelationEngine Tests")
struct CorrelationEngineTests {

    @Test("Perfect positive correlation computes r = 1.0")
    func perfectPositive() {
        let pairs: [(Double, Double)] = [(1, 2), (2, 4), (3, 6), (4, 8), (5, 10)]
        let result = CorrelationEngine.pearson(pairs, minimumSampleSize: 5)
        guard case .computed(let r, let n) = result else {
            Issue.record("expected a computed result, got \(result)")
            return
        }
        #expect(abs(r - 1.0) < 0.0001)
        #expect(n == 5)
    }

    @Test("Perfect negative correlation computes r = -1.0")
    func perfectNegative() {
        let pairs: [(Double, Double)] = [(1, 10), (2, 8), (3, 6), (4, 4), (5, 2)]
        let result = CorrelationEngine.pearson(pairs, minimumSampleSize: 5)
        guard case .computed(let r, _) = result else {
            Issue.record("expected a computed result, got \(result)")
            return
        }
        #expect(abs(r - (-1.0)) < 0.0001)
    }

    @Test("Zero variance on one axis reports r = 0, not NaN or a crash")
    func allSameValueDoesNotDivideByZero() {
        let pairs: [(Double, Double)] = [(1, 5), (2, 5), (3, 5), (4, 5)]
        let result = CorrelationEngine.pearson(pairs, minimumSampleSize: 4)
        guard case .computed(let r, _) = result else {
            Issue.record("expected a computed result, got \(result)")
            return
        }
        #expect(r == 0.0)
    }

    @Test("Below the minimum sample size reports insufficient data, never a guessed r")
    func insufficientSampleSize() {
        let pairs: [(Double, Double)] = [(1, 2), (2, 4)]
        let result = CorrelationEngine.pearson(pairs)
        #expect(result == .insufficientData(sampleSize: 2, minimumRequired: CorrelationEngine.minimumSampleSize))
    }
}
