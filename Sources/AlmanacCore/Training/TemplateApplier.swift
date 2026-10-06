import Foundation

/// What applying a template did.
public struct TemplateApplication: Sendable, Hashable {
    public let sessionId: Int64
    /// The bouts created, in template order.
    public let boutIds: [Int64]
}

public enum TemplateApplyError: Error, Sendable, Equatable {
    case templateNotFound(Int64)
    /// A discontinued template is kept so history can name it, but it is not
    /// offered for new sessions.
    case templateDiscontinued(Int64)
    case templateHasNoExercises(Int64)
    case sessionNotFound(Int64)
    /// A program day's session is the Training Program's to fill. Templates are
    /// kept separate from that layer on purpose.
    case sessionIsFromProgram(Int64)
    /// The session already holds this many logged bouts. The caller asks the
    /// person whether to add the template's exercises after them, and applies
    /// again with `appendingAfterExisting: true` only on a yes.
    case sessionHasBouts(Int)
}

/// Fills a session with a template's exercises as a starting point.
///
/// The owner's decision (2026-10-06): a template is **exercises, but editable**.
/// Applying one copies each of its exercises onto a new `workoutBout` — the
/// exercise, its prescription type, the template's container, and the planned
/// (`prescribed*`) values — and leaves every `actual*` column empty, because
/// nothing has been done yet. The bouts are then ordinary rows: what was done is
/// filled in with `WorkoutBoutStore.updateActuals`, an exercise he skips is
/// deleted, and one he adds is logged as any other.
///
/// **Copied, not referenced.** Editing or discontinuing the template afterwards
/// changes no session it was applied to.
///
/// **A session that already has bouts is not filled silently** (unconfirmed —
/// `CONTEXT.md`, Training 2026-10-06). The first call refuses with
/// `sessionHasBouts(count)`; the screen asks "add after the N already logged?",
/// and a yes applies with `appendingAfterExisting`. Replacing is not offered,
/// because it would delete logged work.
public struct TemplateApplier: Sendable {
    private let db: Database
    private let clock: any Clock

    public init(db: Database, clock: any Clock = SystemClock()) {
        self.db = db
        self.clock = clock
    }

    /// Applies `templateId` to `sessionId`.
    @discardableResult
    public func apply(template templateId: Int64, to sessionId: Int64,
                      appendingAfterExisting: Bool = false) throws -> TemplateApplication {
        let templates = PrescribedWorkoutStore(db: db, clock: clock)
        guard let template = try templates.workout(id: templateId) else {
            throw TemplateApplyError.templateNotFound(templateId)
        }
        guard !template.isDeleted else { throw TemplateApplyError.templateDiscontinued(templateId) }
        let items = try templates.items(of: templateId)
        guard !items.isEmpty else { throw TemplateApplyError.templateHasNoExercises(templateId) }

        let sessions = WorkoutSessionStore(db: db, clock: clock)
        guard let session = try sessions.session(id: sessionId), !session.isDeleted else {
            throw TemplateApplyError.sessionNotFound(sessionId)
        }
        guard !session.isFromProgram, session.programDayId == nil else {
            throw TemplateApplyError.sessionIsFromProgram(sessionId)
        }

        let bouts = WorkoutBoutStore(db: db, clock: clock)
        let existing = try bouts.bouts(sessionId: sessionId)
        if !existing.isEmpty && !appendingAfterExisting {
            throw TemplateApplyError.sessionHasBouts(existing.count)
        }
        let start = (existing.map(\.sequenceIndex).max() ?? -1) + 1

        return try db.transaction {
            var created: [Int64] = []
            for (offset, item) in items.enumerated() {
                let plan = item.draft
                created.append(try bouts.log(WorkoutBoutDraft(
                    sessionId: sessionId, exerciseCatalogId: plan.exerciseCatalogId,
                    sequenceIndex: start + offset, prescriptionType: plan.prescriptionType,
                    containerType: template.containerType,
                    prescribedSets: plan.prescribedSets, prescribedReps: plan.prescribedReps,
                    prescribedLoadKg: plan.prescribedLoadKg,
                    prescribedDurationSeconds: plan.prescribedDurationSeconds,
                    prescribedDistanceMeters: plan.prescribedDistanceMeters,
                    prescribedWorkSeconds: plan.prescribedWorkSeconds,
                    prescribedRestSeconds: plan.prescribedRestSeconds,
                    prescribedRounds: plan.prescribedRounds)))
            }
            try sessions.setTemplateIfUnset(id: sessionId, prescribedWorkoutId: templateId)
            return TemplateApplication(sessionId: sessionId, boutIds: created)
        }
    }

    /// Applies `templateId` to the person's own ad-hoc session on `date` — the
    /// one `TrainingModel.logBout` logs against — creating it when there is none.
    /// A watch-synced session and a program day's session are never chosen.
    @discardableResult
    public func applyToDay(template templateId: Int64, date: String,
                           appendingAfterExisting: Bool = false) throws -> TemplateApplication {
        let sessions = WorkoutSessionStore(db: db, clock: clock)
        if let own = try sessions.sessions(date: date).first(where: { $0.isOwnLog && $0.programDayId == nil }) {
            return try apply(template: templateId, to: own.id, appendingAfterExisting: appendingAfterExisting)
        }
        // Checked before creating a session, so a refused template leaves no
        // empty session behind.
        let templates = PrescribedWorkoutStore(db: db, clock: clock)
        guard let template = try templates.workout(id: templateId) else {
            throw TemplateApplyError.templateNotFound(templateId)
        }
        guard !template.isDeleted else { throw TemplateApplyError.templateDiscontinued(templateId) }
        guard try !templates.items(of: templateId).isEmpty else {
            throw TemplateApplyError.templateHasNoExercises(templateId)
        }
        return try db.transaction {
            let sessionId = try sessions.log(WorkoutSessionDraft(date: date, prescribedWorkoutId: templateId))
            return try apply(template: templateId, to: sessionId)
        }
    }
}
