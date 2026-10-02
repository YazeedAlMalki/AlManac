import Foundation

/// What a progression rule says about an exercise's next load.
public struct ProgressionSuggestion: Sendable, Hashable {
    /// The three things a rule can conclude. They are distinct outcomes rather
    /// than an optional load, because "do it again at the same weight" is an
    /// answer the user needs to see — collapsing it into no answer would leave the
    /// sheet showing nothing on the day after a missed set, which reads as "this
    /// app has forgotten about this exercise".
    public enum Outcome: Sendable, Hashable {
        /// The condition held. The increment is the user's, applied once.
        case increase(toKg: Double)
        /// The condition did not hold, so the load stands.
        case hold(atKg: Double)
        /// The exercise has never been performed, so there is no weight to
        /// progress from. Never a suggestion to jump to the pool's prescribed
        /// load: that number is a plan, not an achievement.
        case nothingLogged
    }

    public let exerciseCatalogId: Int64
    /// The pool item the rule is attached to — per exercise, and a rule belongs
    /// to the item, not to the movement in the abstract.
    public let poolItemId: Int64
    public let outcome: Outcome
    /// The last weight actually lifted, when there is one. Nil with
    /// `.nothingLogged`, because there is nothing to read.
    public let currentLoadKg: Double?
    /// The user's own increment. Nil only with `.nothingLogged`, where there is
    /// nothing to add it to.
    public let incrementKg: Double?
    public let condition: ProgressionCondition

    public init(exerciseCatalogId: Int64, poolItemId: Int64, outcome: Outcome,
                currentLoadKg: Double?, incrementKg: Double?, condition: ProgressionCondition) {
        self.exerciseCatalogId = exerciseCatalogId
        self.poolItemId = poolItemId
        self.outcome = outcome
        self.currentLoadKg = currentLoadKg
        self.incrementKg = incrementKg
        self.condition = condition
    }

    /// The load to show, whichever outcome this is. Nil only when nothing has been
    /// logged.
    public var suggestedLoadKg: Double? {
        switch outcome {
        case .increase(let toKg): return toKg
        case .hold(let atKg): return atKg
        case .nothingLogged: return nil
        }
    }
}

/// Decision 4 — progression, one exercise at a time.
///
/// **Per exercise, never a global rule.** The increment and the condition live on
/// the pool item, and a suggestion is only ever produced for an item whose own
/// rule is complete. There is no fallback number and no default increment, because
/// a default is a global rule with extra steps: "+2.5 kg everywhere" is exactly
/// the thing the handoff ruled out, and having it as a fallback would make the
/// per-exercise rule decorative.
///
/// **A suggestion, not a write.** Nothing here edits the pool. The user's
/// prescription is their own; accepting a suggestion is a separate, explicit act.
/// An engine that moved the number by itself would be indistinguishable from
/// one that had decided the user agreed.
///
/// **Built from actuals, never from the prescription.** The base is the last load
/// the user actually lifted. Progressing from the written prescription would
/// under-read anyone who has been loading slightly more than the sheet says, and
/// would do it by their increment, every session, for ever.
///
/// **The increment applies once per suggestion**, not once per set and not once
/// per session. A rule that read "+2.5 kg" against five sets would propose 12.5 kg
/// to someone doing five good sets, which is not what a user who typed "2.5" meant.
public struct ExerciseProgression: @unchecked Sendable {
    private let progressStore: ExerciseProgressStore

    public init(db: Database) {
        self.progressStore = ExerciseProgressStore(db: db)
    }

    /// A rule that can be acted on, or nil when there is not one.
    ///
    /// Nil for: progression off, a rule with only half of itself, and a condition
    /// this build does not know. All three are "do not guess" rather than "treat as
    /// satisfied", because the expensive direction to guess in is the one that adds
    /// weight to someone who cannot do the reps.
    private func rule(for item: PoolItemEntry) -> (increment: Double, condition: ProgressionCondition)? {
        guard item.progressionEnabled,
              let increment = item.progressionIncrementKg,
              let raw = item.progressionCondition,
              let condition = ProgressionCondition(rawValue: raw) else { return nil }
        return (increment, condition)
    }

    /// One pool item's suggestion, or nil when it has no rule.
    ///
    /// One query. `suggestions(for:)` is the batch form and is what a day's sheet
    /// should call — a caller looping over `suggestion(for:)` re-reads the same
    /// exercise's history once per item, which for a day that repeats an exercise
    /// is a read per appearance rather than per exercise.
    public func suggestion(for item: PoolItemEntry) throws -> ProgressionSuggestion? {
        guard let rule = rule(for: item) else { return nil }
        let history = try progressStore.history(exerciseCatalogId: item.exerciseCatalogId)
        return Self.suggestion(for: item, rule: rule,
                               history: attempts(in: history))
    }

    /// A whole day's suggestions in **one** query, keyed by pool item id.
    ///
    /// Items with no rule are absent rather than present-and-nil, so a caller
    /// iterating the result cannot render a suggestion of nothing for an exercise
    /// the user never asked to progress.
    public func suggestions(for items: [PoolItemEntry]) throws -> [Int64: ProgressionSuggestion] {
        let ruled = items.compactMap { item -> (PoolItemEntry, (increment: Double, condition: ProgressionCondition))? in
            guard let rule = rule(for: item) else { return nil }
            return (item, rule)
        }
        guard !ruled.isEmpty else { return [:] }

        let history = try progressStore.history(
            exerciseCatalogIds: ruled.map { $0.0.exerciseCatalogId })

        var suggestions: [Int64: ProgressionSuggestion] = [:]
        for (item, rule) in ruled {
            // Filtered per exercise, not once over the merged set: two items on one
            // day can share a movement, and their histories are the same history.
            let own = attempts(in: history[item.exerciseCatalogId] ?? [])
            suggestions[item.id] = Self.suggestion(for: item, rule: rule, history: own)
        }
        return suggestions
    }

    /// The rule applied to one exercise's history. Pure, so the two entry points
    /// above cannot disagree about the same item.
    private static func suggestion(for item: PoolItemEntry,
                                   rule: (increment: Double, condition: ProgressionCondition),
                                   history: [ExerciseProgressPoint]) -> ProgressionSuggestion {
        func make(_ outcome: ProgressionSuggestion.Outcome, current: Double?) -> ProgressionSuggestion {
            ProgressionSuggestion(
                exerciseCatalogId: item.exerciseCatalogId, poolItemId: item.id,
                outcome: outcome, currentLoadKg: current,
                incrementKg: current == nil ? nil : rule.increment,
                condition: rule.condition)
        }

        // A skipped slot is a log row with no actuals, not an attempt: counting it
        // would either hold the load for ever or suggest an increase from a
        // session the user never did. The filter is on the *attempt*, so a session
        // whose only bout was skipped cannot become "the latest".
        guard let attempt = history.last, let current = attempt.actualLoadKg else {
            return make(.nothingLogged, current: nil)
        }

        switch rule.condition {
        case .allRepsCompleted:
            // Both numbers have to be there. `all_reps_completed` cannot be
            // evaluated against an absent prescription, and evaluating it as
            // satisfied is the failure this whole check exists to prevent.
            let completed = attempt.actualReps.flatMap { reps in
                attempt.prescribedReps.map { reps >= $0 }
            } ?? false
            return make(completed ? .increase(toKg: current + rule.increment) : .hold(atKg: current),
                        current: current)
        }
    }

    /// History with the sessions that were not attempts removed.
    private func attempts(in history: [ExerciseProgressPoint]) -> [ExerciseProgressPoint] {
        history.filter { $0.actualLoadKg != nil }
    }
}
