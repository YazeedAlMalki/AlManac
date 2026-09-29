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
///
/// **The pair really is unordered now.** The doc comment said so and the code
/// did not: `save` inserted the two metrics in the order given and `pair`
/// looked up that exact order, so `("sleep", "readiness")` and
/// `("readiness",
/// "sleep")` were two different rows holding the same number. A caller that
/// offered a pair in a different order next time would see the old row's sample
/// size next to a fresh `r`, or two rows in a list of "your correlations".
/// Both metrics are sorted into a canonical order on the way in and on the way
/// out, so the key is the one the comment always claimed.
public struct CorrelationPairStore: @unchecked Sendable {
    let db: Database
    private let clock: any Clock

    public init(db: Database, clock: any Clock = SystemClock()) {
        self.db = db
        self.clock = clock
    }

    /// The two metrics in a stable order, so a pair is one key and not two.
    private static func canonical(_ a: String, _ b: String) -> (String, String) {
        a <= b ? (a, b) : (b, a)
    }

    public func save(metricA: String, metricB: String, result: CorrelationResult) throws {
        let (first, second) = Self.canonical(metricA, metricB)
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
            .text(first), .text(second), rValue,
            .integer(Int64(sampleSize)), .text(confidenceLevel), .text(now)
        ])
    }

    public func pair(metricA: String, metricB: String) throws -> CorrelationPairRecord? {
        let (first, second) = Self.canonical(metricA, metricB)
        guard let row = try db.query("""
        SELECT metricA, metricB, rValue, sampleSize, confidenceLevel FROM correlation_pair
        WHERE metricA = ? AND metricB = ?;
        """, [.text(first), .text(second)]).first,
              let sampleSize = row.int("sampleSize"),
              let confidenceLevel = row.string("confidenceLevel") else { return nil }

        return CorrelationPairRecord(
            metricA: first, metricB: second,
            rValue: row.double("rValue"),
            sampleSize: Int(sampleSize),
            confidenceLevel: confidenceLevel
        )
    }

    /// Every stored pair, most confident first.
    ///
    /// Reads the canonical `metricA < metricB` rows only, so a database written
    /// before the ordering fix — which could hold both orders — reports each
    /// pair once rather than twice. The `metricA < metricB` filter is the same
    /// test `canonical` applies, so a pre-fix duplicate of a pair whose stored
    /// order happens to be non-canonical is simply not listed rather than
    /// listed alongside its twin.
    public func allPairs() throws -> [CorrelationPairRecord] {
        let rows = try db.query("""
        SELECT metricA, metricB, rValue, sampleSize, confidenceLevel FROM correlation_pair
        WHERE metricA < metricB
        ORDER BY (rValue IS NULL), ABS(rValue) DESC;
        """)
        return rows.compactMap { row in
            guard let first = row.string("metricA"), let second = row.string("metricB"),
                  let sampleSize = row.int("sampleSize"),
                  let confidenceLevel = row.string("confidenceLevel") else { return nil }
            return CorrelationPairRecord(metricA: first, metricB: second,
                                         rValue: row.double("rValue"),
                                         sampleSize: Int(sampleSize),
                                         confidenceLevel: confidenceLevel)
        }
    }
}
