import SwiftUI
import AlmanacCore

/// Owns training/exercise logging state, the same pattern as
/// `HydrationModel`/`ReadinessModel` — one shared `Database`, configured
/// once from `AlmanacApp`.
///
/// `logBout` deliberately does not expose `PrescribedWorkout` templates,
/// containers, or multi-bout structure — those are real, already-built
/// pieces of `AlmanacCore` (`PrescribedWorkoutStore`, `containerType`) this
/// screen just doesn't reach for. A quick-add flow needs one ad-hoc
/// "today's session" to log bouts against, not a templated workout; each
/// bout's `prescriptionType`/fields come straight from the exercise picked,
/// per `docs/features/training.md` §2.
@MainActor
final class TrainingModel: ObservableObject {
    @Published private(set) var exercises: [ExerciseCatalogEntry] = []
    @Published private(set) var todaysBouts: [WorkoutBoutEntry] = []
    @Published private(set) var todaysSummary: WorkoutLoadSummary?

    private var db: Database?
    private var catalogStore: ExerciseCatalogStore?
    private var sessionStore: WorkoutSessionStore?
    private var boutStore: WorkoutBoutStore?
    private let timeModel = TimeModel(timeZone: .current)

    func configure(db: Database?) {
        guard let db, self.db == nil else { return }
        self.db = db
        catalogStore = ExerciseCatalogStore(db: db)
        sessionStore = WorkoutSessionStore(db: db)
        boutStore = WorkoutBoutStore(db: db)
        refresh()
    }

    func refresh() {
        guard let catalogStore, let sessionStore, let boutStore else { return }
        do {
            exercises = try catalogStore.all()
            let today = timeModel.logicalDay(Date()).value
            let sessions = try sessionStore.sessions(date: today)
            var bouts: [WorkoutBoutEntry] = []
            for session in sessions {
                bouts.append(contentsOf: try boutStore.bouts(sessionId: session.id))
            }
            todaysBouts = bouts
            // Sessions as well as bouts: a workout synced from a watch has no
            // bouts, and without its duration the day's load would not change
            // when one is auto-logged.
            let summary = WorkloadComputer.summary(for: sessions, bouts: bouts)
            todaysSummary = (bouts.isEmpty && summary == WorkoutLoadSummary.empty) ? nil : summary
        } catch {
            // A read failure here should not crash the dashboard; it will
            // simply show stale figures until the next refresh() succeeds.
        }
    }

    func exerciseName(for exerciseCatalogId: Int64) -> String {
        exercises.first { $0.id == exerciseCatalogId }?.name ?? "Unknown exercise"
    }

    /// Logs one bout against today's ad-hoc session, creating that session
    /// first if this is the first bout logged today. `exercise.prescriptionType`
    /// decides which fields the caller should have filled in — this method
    /// just writes whatever it's given, straight onto the `actual*` columns;
    /// nothing here is prescribed in advance.
    func logBout(exercise: ExerciseCatalogEntry, sets: Int?, reps: Int?, loadKg: Double?,
                 durationSeconds: Double?, distanceMeters: Double?, rounds: Int?,
                 rpe: Int?, notes: String?) throws {
        guard let sessionStore, let boutStore else {
            throw EditorFailure(message: "The database is unavailable.")
        }
        let today = timeModel.logicalDay(Date()).value
        let sessionId: Int64
        // A session synced from a watch is not the one to attach a manually
        // logged bout to: it carries no bouts of its own, so a bout filed under
        // it would report as that workout's own detail. The user's own session
        // is preferred, and one is created only if they have none.
        let own = try sessionStore.sessions(date: today).first { $0.isOwnLog }
        if let existing = own {
            sessionId = existing.id
        } else {
            sessionId = try sessionStore.log(WorkoutSessionDraft(date: today))
        }

        let sequenceIndex = try boutStore.bouts(sessionId: sessionId).count
        try boutStore.log(WorkoutBoutDraft(
            sessionId: sessionId, exerciseCatalogId: exercise.id, sequenceIndex: sequenceIndex,
            prescriptionType: exercise.prescriptionType,
            actualSets: sets, actualReps: reps, actualLoadKg: loadKg,
            actualDurationSeconds: durationSeconds, actualDistanceMeters: distanceMeters,
            actualRounds: rounds, rpe: rpe, notes: notes))
        refresh()
    }

    func deleteBout(id: Int64) throws {
        guard let boutStore else { throw EditorFailure(message: "The database is unavailable.") }
        try boutStore.delete(id: id)
        refresh()
    }
}
