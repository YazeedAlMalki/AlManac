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
            var bouts: [WorkoutBoutEntry] = []
            for session in try sessionStore.sessions(date: today) {
                bouts.append(contentsOf: try boutStore.bouts(sessionId: session.id))
            }
            todaysBouts = bouts
            todaysSummary = bouts.isEmpty ? nil : WorkloadComputer.summary(for: bouts)
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
        if let existing = try sessionStore.sessions(date: today).first {
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
