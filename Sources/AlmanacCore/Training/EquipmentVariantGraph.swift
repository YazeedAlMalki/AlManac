import Foundation

/// Which of the two graphs of an exercise this read is for.
///
/// Both graphs exist because "is this getting heavier" and "am I doing more work"
/// are different questions that a single axis answers badly — a user adding reps
/// at a lower weight is doing more and lifting less, and one line cannot say both.
public enum ProgressGraph: String, Sendable, Hashable, CaseIterable {
    /// Kilograms on the plate. Points with no recorded load have no place on it.
    case weight
    /// Reps performed: sets × reps.
    ///
    /// Deliberately not kilogram-reps. Volume weighted by load makes a heavy triple
    /// outweigh a light set of twenty, which is a statement about the barbell rather
    /// than about the session, and it would make a heavy day's volume spike for a
    /// reason the graph cannot explain.
    case volume
}

/// One plotted measurement: a bout, its value on this graph's axis, and the
/// equipment it was performed with.
///
/// `variant` is kept on the point even in combined mode, so a combined line can
/// still be explained: "why did my weight jump 20 kg" is answerable only if the
/// cable session is identifiable after the fact.
public struct ProgressGraphPoint: Sendable, Hashable, Identifiable {
    public let boutId: Int64
    public let date: String
    public let value: Double
    /// Null when nobody chose one — a bodyweight movement, and every bout logged
    /// before Migration049.
    public let variant: EquipmentVariant?

    public var id: Int64 { boutId }

    public init(boutId: Int64, date: String, value: Double, variant: EquipmentVariant?) {
        self.boutId = boutId
        self.date = date
        self.value = value
        self.variant = variant
    }
}

/// One line on a graph.
public struct ProgressGraphSeries: Sendable, Hashable, Identifiable {
    /// The variant this line is, or nil for the unspecified series — which is a
    /// real series in separate mode and the only series in combined mode.
    public let variant: EquipmentVariant?
    public let points: [ProgressGraphPoint]

    public var id: String { variant?.rawValue ?? "unspecified" }

    public init(variant: EquipmentVariant?, points: [ProgressGraphPoint]) {
        self.variant = variant
        self.points = points
    }

    /// What to call the line. Null is a name, not a blank — "the graph is
    /// untitled" is not a thing a user should have to interpret.
    public var displayName: String { variant?.displayName ?? localized("Not recorded") }
}

/// **Decision 1 — the equipment-variant toggle, on the graph rather than in the
/// log.** Variants are tracked separately at write time; this type is the only
/// place they are drawn together, and it is a read.
public struct EquipmentVariantGraph: @unchecked Sendable {
    private let db: Database

    public init(db: Database) {
        self.db = db
    }

    /// One movement's history, split into the lines the mode calls for.
    ///
    /// **Separate** returns one series per variant, in `EquipmentVariant`'s own
    /// order with the unspecified series last, so a graph's lines do not move
    /// between redraws. **Combined** returns exactly one series of everything, in
    /// date order.
    ///
    /// A bout with nothing recorded for this graph's measure is left out rather
    /// than plotted as zero — §9.1 forbids standing in for absence with a number,
    /// and that holds for an axis as much as for a score. A skipped slot
    /// (`wasSkippedForSession`) has no actuals, so it is left out by that same rule
    /// rather than needing a filter of its own.
    ///
    /// **One query per read**, whichever mode and whichever graph: the split into
    /// series happens after the rows are in, because a graph that asked per variant
    /// would be a query per line, and the toggle is the thing that makes the number
    /// of lines change.
    public func points(for exerciseCatalogId: Int64,
                       mode: EquipmentVariantDisplay,
                       graph: ProgressGraph) throws -> [ProgressGraphSeries] {
        let rows = try db.query("""
        SELECT b.id AS boutId, s.date AS date, b.equipmentVariant AS equipmentVariant,
               b.actualLoadKg AS actualLoadKg, b.actualSets AS actualSets,
               b.actualReps AS actualReps
        FROM workoutBout b
        JOIN workoutSession s ON s.id = b.sessionId
        WHERE b.exerciseCatalogId = ?
          AND b.deletedAt IS NULL AND s.deletedAt IS NULL
          AND b.wasSkippedForSession = 0
        ORDER BY s.date, b.id;
        """, [.integer(exerciseCatalogId)])

        // Measure first, group second. A bout missing this graph's measure cannot
        // belong to a series, and deciding that per variant would mean re-reading
        // rows the mode does not affect.
        var measured: [ProgressGraphPoint] = []
        for row in rows {
            guard let boutId = row.int("boutId"),
                  let date = row.string("date"),
                  let value = Self.value(row: row, graph: graph) else { continue }
            let variant = row.string("equipmentVariant").flatMap(EquipmentVariant.init(rawValue:))
            measured.append(ProgressGraphPoint(boutId: boutId, date: date,
                                               value: value, variant: variant))
        }
        guard !measured.isEmpty else { return [] }

        guard mode == .combined else {
            return Self.separateSeries(from: measured)
        }
        // One line, still sorted by date, still carrying each point's variant.
        return [ProgressGraphSeries(variant: nil, points: measured)]
    }

    /// One series per variant, ordered deterministically.
    ///
    /// The unspecified series is last rather than first: it is the one the user is
    /// least likely to have chosen, and leading with "Not recorded" would put the
    /// weakest-evidence line at the top of a legend.
    private static func separateSeries(from points: [ProgressGraphPoint]) -> [ProgressGraphSeries] {
        var grouped: [String: [ProgressGraphPoint]] = [:]
        var order: [String] = []
        for point in points {
            let key = point.variant?.rawValue ?? "unspecified"
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(point)
        }
        // `EquipmentVariant`'s declaration order, then whatever is unspecified.
        let ranked = EquipmentVariant.allCases.map(\.rawValue) + ["unspecified"]
        return ranked.compactMap { key in
            guard let points = grouped[key] else { return nil }
            return ProgressGraphSeries(variant: EquipmentVariant(rawValue: key), points: points)
        }
    }

    /// This graph's value for one bout, or nil when the bout does not have one.
    ///
    /// The two graphs measure different things, so neither is derived from the
    /// other: weight is the load lifted, volume is the reps performed.
    private static func value(row: Row, graph: ProgressGraph) -> Double? {
        switch graph {
        case .weight:
            return row.double("actualLoadKg")
        case .volume:
            guard let sets = row.int("actualSets"), let reps = row.int("actualReps") else { return nil }
            return Double(sets * reps)
        }
    }
}
