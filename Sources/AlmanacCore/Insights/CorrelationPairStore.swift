import Foundation

/// One persisted `CorrelationEngine` result. `rValue` is nil exactly when
/// the underlying result was `.insufficientData` — never a placeholder
/// number standing in for "not enough data yet."
public struct CorrelationPairRecord: Sendable, Equatable {
    public let metricA: String
    public let metricB: String
    public let rValue: Double?
    public let sampleSize: Int
    public let confidenceLevel: String
}

/// Persists `CorrelationEngine` results, keyed by the unordered metric pair.
public struct CorrelationPairStore: @unchecked Sendable {
    let db: Database
    private let clock: any Clock

    public init(db: Database, clock: any Clock = SystemClock()) {
        self.db = db
        self.clock = clock
    }

    public func save(metricA: String, metricB: String, result: CorrelationResult) throws {
        let now = ISO8601DateFormatter().string(from: clock.now)
        let rValue: SQLValue
        let sampleSize: Int
        let confidenceLevel: String
        switch result {
        case .computed(let r, let n):
            rValue = .real(r)
            sampleSize = n
            confidenceLevel = "confident"
        case .insufficientData(let n, _):
            rValue = .null
            sampleSize = n
            confidenceLevel = "insufficient"
        }

        try db.run("""
        INSERT OR REPLACE INTO correlation_pair
            (metricA, metricB, rValue, pValue, sampleSize, confidenceLevel, lastComputed)
        VALUES (?, ?, ?, NULL, ?, ?, ?);
        """, [
            .text(metricA), .text(metricB), rValue,
            .integer(Int64(sampleSize)), .text(confidenceLevel), .text(now)
        ])
    }

    public func pair(metricA: String, metricB: String) throws -> CorrelationPairRecord? {
        guard let row = try db.query("""
        SELECT metricA, metricB, rValue, sampleSize, confidenceLevel FROM correlation_pair
        WHERE metricA = ? AND metricB = ?;
        """, [.text(metricA), .text(metricB)]).first,
              let sampleSize = row.int("sampleSize"),
              let confidenceLevel = row.string("confidenceLevel") else { return nil }

        return CorrelationPairRecord(
            metricA: metricA, metricB: metricB,
            rValue: row.double("rValue"),
            sampleSize: Int(sampleSize),
            confidenceLevel: confidenceLevel
        )
    }
}
