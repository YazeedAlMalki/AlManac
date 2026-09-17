import Foundation

/// A session's aggregated training load, computed from its bouts.
///
/// Every field is `nil`, not zero, when no bout contributed to it — the
/// same "never a false zero" discipline `ReadinessOutcome.score` and
/// `SorenessLogEntry` etc. already follow elsewhere in this repo. A session
/// of nothing but `session_only`/`quality_reps`/`release` bouts should show
/// as "no numeric load computed," not "0 kg."
public struct WorkoutLoadSummary: Sendable, Hashable {
    public let totalTonnageKg: Double?
    public let totalDistanceMeters: Double?
    public let totalDurationSeconds: Double?
    public let totalReps: Int?
    public let totalRounds: Int?
    public let averageRPE: Double?
}

/// Turns a session's `WorkoutBoutEntry` list into one `WorkoutLoadSummary`.
///
/// Reconstructed from the master build order's own wording ("tonnage = sets
/// × reps × weight; volume = distance × sets; start simple, expand later")
/// rather than quoted from `prescription-model-v0.1.md` — that document
/// exists only as project memory, not a file in this repo (see
/// `docs/features/training.md` §1 for the full explanation). Coverage below
/// is deliberately partial, matching that "start simple" instruction:
///
/// - `reps_load`: tonnage (sets × reps × load) and reps.
/// - `reps_bodyweight`: reps only — no bodyweight is tracked on a bout, so
///   there is nothing to multiply a load by.
/// - `distance`: metres, multiplied by set count when a distance bout is
///   repeated (e.g. 3×400m).
/// - `duration`, `time_under_load`: seconds, likewise multiplied by sets.
/// - `work_in_time`, `rounds_for_time`: rounds completed.
/// - `interval`, `quality_reps`, `hold_stretch`, `release`, `session_only`:
///   not modeled here — no field of `WorkoutLoadSummary` fits an interval
///   block's work/rest structure or a skill session's qualitative content
///   well enough to be worth a placeholder number. Expand when a real UI
///   need for one of these appears, rather than guessing now.
/// - RPE: averaged across whichever bouts recorded one, regardless of type.
///
/// Trusts its input: filtering out soft-deleted bouts is
/// `WorkoutBoutStore.bouts(sessionId:)`'s job, not this function's.
public enum WorkloadComputer {
    public static func summary(for bouts: [WorkoutBoutEntry]) -> WorkoutLoadSummary {
        var tonnage: Double?
        var distance: Double?
        var duration: Double?
        var reps: Int?
        var rounds: Int?
        var rpeSum = 0.0
        var rpeCount = 0

        for bout in bouts {
            let sets = bout.actualSets ?? bout.prescribedSets

            switch bout.prescriptionType {
            case "reps_load":
                if let sets, let r = bout.actualReps ?? bout.prescribedReps {
                    reps = (reps ?? 0) + sets * r
                    if let load = bout.actualLoadKg ?? bout.prescribedLoadKg {
                        tonnage = (tonnage ?? 0) + Double(sets * r) * load
                    }
                }
            case "reps_bodyweight":
                if let sets, let r = bout.actualReps ?? bout.prescribedReps {
                    reps = (reps ?? 0) + sets * r
                }
            case "distance":
                if let d = bout.actualDistanceMeters ?? bout.prescribedDistanceMeters {
                    distance = (distance ?? 0) + d * Double(sets ?? 1)
                }
            case "duration", "time_under_load":
                if let d = bout.actualDurationSeconds ?? bout.prescribedDurationSeconds {
                    duration = (duration ?? 0) + d * Double(sets ?? 1)
                }
            case "work_in_time", "rounds_for_time":
                if let r = bout.actualRounds ?? bout.prescribedRounds {
                    rounds = (rounds ?? 0) + r
                }
            default:
                break
            }

            if let rpe = bout.rpe {
                rpeSum += Double(rpe)
                rpeCount += 1
            }
        }

        return WorkoutLoadSummary(
            totalTonnageKg: tonnage, totalDistanceMeters: distance, totalDurationSeconds: duration,
            totalReps: reps, totalRounds: rounds,
            averageRPE: rpeCount > 0 ? rpeSum / Double(rpeCount) : nil
        )
    }
}
