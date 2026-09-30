import Foundation

/// Reads and writes `goal_target_snapshot`.
///
/// ## The only write is an insert
///
/// There is no `update` here, and that is the whole of §5.2's immutability rule
/// made structural rather than conventional. An `updateTargets` that "updated the
/// active row" would be the obvious convenience and it is the thing that must not
/// exist: it would rewrite the targets that applied on a past day, which is the
/// one mistake the table exists to prevent. Changing a goal means writing a new row
/// from a later date, and the past stays as it was.
///
/// ## Which row is in force
///
/// "The newest row whose `effective_date` is at or before the day asked about."
/// That is one indexed read, and it is also the rule that makes overlapping
/// snapshots harmless: inserting a row dated today does not invalidate yesterday's
/// row, and a lookup for yesterday still finds it. A schema with an `end_date`
/// would need the same answer to be maintained on every write for no gain.
public struct GoalTargetSnapshotStore: @unchecked Sendable {
    private let db: Database
    private let clock: any Clock

    public init(db: Database, clock: any Clock = SystemClock()) {
        self.db = db
        self.clock = clock
    }

    // MARK: - Write

    /// Records a new set of targets. Always inserts.
    ///
    /// - Returns: the row as stored, with its new `id`.
    @discardableResult
    public func insert(_ snapshot: GoalTargetSnapshot) throws -> GoalTargetSnapshot {
        let targetColumns = BodyMetric.allCases
        var columns = [
            "effective_date", "goal", "formula_version",
            "body_weight_kg", "body_fat_pct", "activity_multiplier", "goal_calorie_adjustment",
            "calorie_target", "protein_target_g", "carb_target_g", "fat_target_g", "hydration_target_ml",
            "manual_calorie_target", "manual_protein_target_g", "manual_carb_target_g",
            "manual_fat_target_g", "manual_hydration_target_ml",
            "created_at"
        ]
        var values: [SQLValue] = [
            .text(snapshot.effectiveDate),
            .text(snapshot.goal.rawValue),
            .text(snapshot.formulaVersion),
            snapshot.bodyWeightKg.map(SQLValue.real) ?? .null,
            snapshot.bodyFatPercent.map(SQLValue.real) ?? .null,
            snapshot.activityMultiplier.map(SQLValue.real) ?? .null,
            snapshot.goalCalorieAdjustment.map { SQLValue.integer(Int64($0)) } ?? .null,
            snapshot.calorieTarget.map { SQLValue.integer(Int64($0)) } ?? .null,
            snapshot.proteinTargetG.map(SQLValue.real) ?? .null,
            snapshot.carbTargetG.map(SQLValue.real) ?? .null,
            snapshot.fatTargetG.map(SQLValue.real) ?? .null,
            snapshot.hydrationTargetMl.map { SQLValue.integer(Int64($0)) } ?? .null,
            snapshot.manualCalorieTarget.map { SQLValue.integer(Int64($0)) } ?? .null,
            snapshot.manualProteinTargetG.map(SQLValue.real) ?? .null,
            snapshot.manualCarbTargetG.map(SQLValue.real) ?? .null,
            snapshot.manualFatTargetG.map(SQLValue.real) ?? .null,
            snapshot.manualHydrationTargetMl.map { SQLValue.integer(Int64($0)) } ?? .null,
            .text(Self.iso(snapshot.createdAt))
        ]
        for metric in targetColumns {
            columns.append(Self.targetColumn(for: metric))
            values.append(snapshot.bodyCompositionTargets[metric].map(SQLValue.real) ?? .null)
        }

        let placeholders = Array(repeating: "?", count: columns.count).joined(separator: ", ")
        try db.run(
            "INSERT INTO goal_target_snapshot (\(columns.joined(separator: ", "))) VALUES (\(placeholders));",
            values)

        guard let id = try db.query("SELECT last_insert_rowid() AS id;").first?.int("id") else {
            throw GoalTargetSnapshotError.insertDidNotReportAnId
        }
        return GoalTargetSnapshot(
            id: id,
            effectiveDate: snapshot.effectiveDate,
            goal: snapshot.goal,
            formulaVersion: snapshot.formulaVersion,
            bodyWeightKg: snapshot.bodyWeightKg,
            bodyFatPercent: snapshot.bodyFatPercent,
            activityMultiplier: snapshot.activityMultiplier,
            goalCalorieAdjustment: snapshot.goalCalorieAdjustment,
            calorieTarget: snapshot.calorieTarget,
            proteinTargetG: snapshot.proteinTargetG,
            carbTargetG: snapshot.carbTargetG,
            fatTargetG: snapshot.fatTargetG,
            hydrationTargetMl: snapshot.hydrationTargetMl,
            manualCalorieTarget: snapshot.manualCalorieTarget,
            manualProteinTargetG: snapshot.manualProteinTargetG,
            manualCarbTargetG: snapshot.manualCarbTargetG,
            manualFatTargetG: snapshot.manualFatTargetG,
            manualHydrationTargetMl: snapshot.manualHydrationTargetMl,
            bodyCompositionTargets: snapshot.bodyCompositionTargets,
            createdAt: snapshot.createdAt
        )
    }

    /// Builds a snapshot from the stated inputs and records it.
    ///
    /// The convenience the setting screen wants: a person changes one thing —
    /// the goal, or their activity — and the numbers are re-derived. It inserts
    /// rather than replaces, which is what makes a change of mind safe: the
    /// targets that were in force yesterday are still the ones yesterday's chart
    /// was drawn against.
    @discardableResult
    public func record(builder: GoalTargetBuilder) throws -> GoalTargetSnapshot {
        try insert(builder.build(now: clock.now))
    }

    // MARK: - Read

    /// The targets in force on `day`, or `nil` when none are.
    public func active(on day: String) throws -> GoalTargetSnapshot? {
        try db.query("""
        SELECT \(Self.allColumns) FROM goal_target_snapshot
        WHERE effective_date <= ?
        ORDER BY effective_date DESC, id DESC
        LIMIT 1;
        """, [.text(day)]).first.flatMap(Self.rowToSnapshot)
    }

    /// Every snapshot, newest first. For the history list.
    public func history(limit: Int = 50) throws -> [GoalTargetSnapshot] {
        try db.query("""
        SELECT \(Self.allColumns) FROM goal_target_snapshot
        ORDER BY effective_date DESC, id DESC
        LIMIT ?;
        """, [.integer(Int64(limit))]).compactMap(Self.rowToSnapshot)
    }

    /// The targets in force on `day`.
    ///
    /// **The newest row is the whole answer, absences included.** A NULL in the
    /// row in force means "no target", and does not fall back to an older row.
    /// The per-metric alternative — each column taken from the newest row that
    /// sets it — was written first and is wrong: it makes a target impossible to
    /// remove, since clearing one leaves the value from whenever it was set still
    /// in force behind the row that cleared it. A setting a person can add but not
    /// take away is a setting they will stop trusting.
    ///
    /// The cost is that re-saving a goal re-states every target on it, which is
    /// why the caller is handed the current targets to write back. That is how a
    /// settings form behaves anyway: it loads what is there, and it saves all of it.
    public func activeTargets(on day: String) throws -> [BodyMetric: Double] {
        let columns = BodyMetric.allCases.map(Self.targetColumn(for:))
        let rows = try db.query("""
        SELECT \(columns.joined(separator: ", ")) FROM goal_target_snapshot
        WHERE effective_date <= ?
        ORDER BY effective_date DESC, id DESC
        LIMIT 1;
        """, [.text(day)])

        guard let row = rows.first else { return [:] }
        var out: [BodyMetric: Double] = [:]
        for metric in BodyMetric.allCases {
            if let value = row.double(Self.targetColumn(for: metric)) { out[metric] = value }
        }
        return out
    }

    /// The snapshot in force on `day`, mapped to each metric it carries a target
    /// for, in the shape `BodyCompositionProgress.all` wants.
    ///
    /// One read, then one projection, so the call site does not build it and — more
    /// usefully — so the rule for which snapshot supplies a target is in one place
    /// rather than restated by every card.
    public func snapshotsInForce(on day: String) throws -> [BodyMetric: GoalTargetSnapshot] {
        guard let snapshot = try active(on: day) else { return [:] }
        var out: [BodyMetric: GoalTargetSnapshot] = [:]
        for metric in BodyMetric.allCases where snapshot.bodyCompositionTargets[metric] != nil {
            out[metric] = snapshot
        }
        return out
    }

    // MARK: - Private

    private static let allColumns = """
    id, effective_date, goal, formula_version,
    body_weight_kg, body_fat_pct, activity_multiplier, goal_calorie_adjustment,
    calorie_target, protein_target_g, carb_target_g, fat_target_g, hydration_target_ml,
    manual_calorie_target, manual_protein_target_g, manual_carb_target_g,
    manual_fat_target_g, manual_hydration_target_ml,
    target_body_weight_kg, target_body_fat_pct, target_lean_mass_kg,
    target_skeletal_muscle_kg, target_visceral_rating,
    created_at
    """

    private static func targetColumn(for metric: BodyMetric) -> String {
        switch metric {
        case .weight: return "target_body_weight_kg"
        case .bodyFatPercent: return "target_body_fat_pct"
        case .leanMassKg: return "target_lean_mass_kg"
        case .skeletalMuscleKg: return "target_skeletal_muscle_kg"
        case .visceralRating: return "target_visceral_rating"
        }
    }

    private static func rowToSnapshot(_ row: Row) -> GoalTargetSnapshot? {
        guard let id = row.int("id"),
              let effectiveDate = row.string("effective_date"),
              let goalRaw = row.string("goal"),
              let goal = GoalKind(rawValue: goalRaw),
              let createdRaw = row.string("created_at"),
              let createdAt = isoFormatter.date(from: createdRaw)
        else { return nil }

        var targets: [BodyMetric: Double] = [:]
        for metric in BodyMetric.allCases {
            if let value = row.double(targetColumn(for: metric)) { targets[metric] = value }
        }

        return GoalTargetSnapshot(
            id: id,
            effectiveDate: effectiveDate,
            goal: goal,
            formulaVersion: row.string("formula_version") ?? "1.0",
            bodyWeightKg: row.double("body_weight_kg"),
            bodyFatPercent: row.double("body_fat_pct"),
            activityMultiplier: row.double("activity_multiplier"),
            goalCalorieAdjustment: row.int("goal_calorie_adjustment").map(Int.init),
            calorieTarget: row.int("calorie_target").map(Int.init),
            proteinTargetG: row.double("protein_target_g"),
            carbTargetG: row.double("carb_target_g"),
            fatTargetG: row.double("fat_target_g"),
            hydrationTargetMl: row.int("hydration_target_ml").map(Int.init),
            manualCalorieTarget: row.int("manual_calorie_target").map(Int.init),
            manualProteinTargetG: row.double("manual_protein_target_g"),
            manualCarbTargetG: row.double("manual_carb_target_g"),
            manualFatTargetG: row.double("manual_fat_target_g"),
            manualHydrationTargetMl: row.int("manual_hydration_target_ml").map(Int.init),
            bodyCompositionTargets: targets,
            createdAt: createdAt
        )
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func iso(_ date: Date) -> String { isoFormatter.string(from: date) }
}

public enum GoalTargetSnapshotError: Error, Equatable {
    /// SQLite reported success but no row id, so the snapshot that was just
    /// written cannot be read back. Its own case rather than a `nil` return,
    /// because a caller that got `nil` would carry on and draw a card from a
    /// target it does not have.
    case insertDidNotReportAnId
}
