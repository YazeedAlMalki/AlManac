import Testing
import Foundation
@testable import AlmanacCore

@Suite("WorkloadComputer Tests")
struct WorkloadComputerTests {
    private func bout(prescriptionType: String, sequenceIndex: Int = 0,
                       prescribedSets: Int? = nil, prescribedReps: Int? = nil, prescribedLoadKg: Double? = nil,
                       prescribedDurationSeconds: Double? = nil, prescribedDistanceMeters: Double? = nil,
                       prescribedRounds: Int? = nil,
                       actualSets: Int? = nil, actualReps: Int? = nil, actualLoadKg: Double? = nil,
                       actualDurationSeconds: Double? = nil, actualDistanceMeters: Double? = nil,
                       actualRounds: Int? = nil, rpe: Int? = nil) -> WorkoutBoutEntry {
        WorkoutBoutEntry(
            id: Int64(sequenceIndex), sessionId: 1, exerciseCatalogId: 1, sequenceIndex: sequenceIndex,
            prescriptionType: prescriptionType, containerType: nil,
            prescribedSets: prescribedSets, prescribedReps: prescribedReps, prescribedLoadKg: prescribedLoadKg,
            prescribedDurationSeconds: prescribedDurationSeconds, prescribedDistanceMeters: prescribedDistanceMeters,
            prescribedWorkSeconds: nil, prescribedRestSeconds: nil, prescribedRounds: prescribedRounds,
            actualSets: actualSets, actualReps: actualReps, actualLoadKg: actualLoadKg,
            actualDurationSeconds: actualDurationSeconds, actualDistanceMeters: actualDistanceMeters,
            actualRounds: actualRounds, elapsedSeconds: nil, avgHeartRate: nil, rpe: rpe,
            techniqueRating: nil, notes: nil, deletedAt: nil, createdAt: "", updatedAt: "")
    }

    @Test("Tonnage for a reps_load bout is sets x reps x load")
    func repsLoadTonnage() {
        let bouts = [bout(prescriptionType: "reps_load", actualSets: 5, actualReps: 5, actualLoadKg: 100)]
        let summary = WorkloadComputer.summary(for: bouts)
        #expect(summary.totalTonnageKg == 2500)
        #expect(summary.totalReps == 25)
    }

    @Test("Tonnage falls back to prescribed values when actuals are missing")
    func fallsBackToPrescribed() {
        let bouts = [bout(prescriptionType: "reps_load", prescribedSets: 3, prescribedReps: 10, prescribedLoadKg: 60)]
        let summary = WorkloadComputer.summary(for: bouts)
        #expect(summary.totalTonnageKg == 1800)
    }

    @Test("Actual values take precedence over prescribed when both are present")
    func actualTakesPrecedence() {
        let bouts = [bout(prescriptionType: "reps_load",
                           prescribedSets: 3, prescribedReps: 10, prescribedLoadKg: 60,
                           actualSets: 3, actualReps: 8, actualLoadKg: 65)]
        let summary = WorkloadComputer.summary(for: bouts)
        #expect(summary.totalTonnageKg == 1560) // 3 x 8 x 65, not 1800
    }

    @Test("Tonnage across multiple reps_load bouts sums")
    func tonnageSumsAcrossBouts() {
        let bouts = [
            bout(prescriptionType: "reps_load", sequenceIndex: 0, actualSets: 5, actualReps: 5, actualLoadKg: 100),
            bout(prescriptionType: "reps_load", sequenceIndex: 1, actualSets: 3, actualReps: 8, actualLoadKg: 40)
        ]
        let summary = WorkloadComputer.summary(for: bouts)
        // `2500 + 960` (an all-Int-literal expression) inside #expect against
        // a Double? LHS mistypes on this toolchain (Swift Testing, Swift
        // 6.3.3, Linux) — confirmed a real macro quirk, not a computation
        // bug: explicit Double literals resolve correctly.
        #expect(summary.totalTonnageKg == 2500.0 + 960.0)
    }

    @Test("reps_bodyweight contributes to total reps but not tonnage (no load tracked)")
    func bodyweightNoTonnage() {
        let bouts = [bout(prescriptionType: "reps_bodyweight", actualSets: 3, actualReps: 12)]
        let summary = WorkloadComputer.summary(for: bouts)
        #expect(summary.totalTonnageKg == nil)
        #expect(summary.totalReps == 36)
    }

    @Test("distance accumulates meters, multiplied by sets when repeated")
    func distanceAccumulates() {
        let bouts = [bout(prescriptionType: "distance", actualSets: 3, actualDistanceMeters: 400)]
        let summary = WorkloadComputer.summary(for: bouts)
        #expect(summary.totalDistanceMeters == 1200)
    }

    @Test("A single, unrepeated distance bout defaults its set count to one")
    func distanceDefaultsToOneSet() {
        let bouts = [bout(prescriptionType: "distance", actualDistanceMeters: 5000)]
        let summary = WorkloadComputer.summary(for: bouts)
        #expect(summary.totalDistanceMeters == 5000)
    }

    @Test("duration and time_under_load accumulate total seconds, multiplied by sets")
    func durationAccumulates() {
        let bouts = [
            bout(prescriptionType: "time_under_load", actualSets: 3, actualDurationSeconds: 30),
            bout(prescriptionType: "duration", actualDurationSeconds: 1200)
        ]
        let summary = WorkloadComputer.summary(for: bouts)
        #expect(summary.totalDurationSeconds == 90.0 + 1200.0)
    }

    @Test("rounds accumulate for work_in_time and rounds_for_time bouts")
    func roundsAccumulate() {
        let bouts = [
            bout(prescriptionType: "work_in_time", actualRounds: 7),
            bout(prescriptionType: "rounds_for_time", actualRounds: 5)
        ]
        let summary = WorkloadComputer.summary(for: bouts)
        #expect(summary.totalRounds == 12)
    }

    @Test("session_only, quality_reps, and release contribute nothing numeric")
    func unmodeledTypesContributeNothing() {
        let bouts = [bout(prescriptionType: "session_only"), bout(prescriptionType: "quality_reps"),
                     bout(prescriptionType: "release")]
        let summary = WorkloadComputer.summary(for: bouts)
        #expect(summary.totalTonnageKg == nil)
        #expect(summary.totalDistanceMeters == nil)
        #expect(summary.totalDurationSeconds == nil)
        #expect(summary.totalReps == nil)
        #expect(summary.totalRounds == nil)
    }

    @Test("Average RPE is computed only over bouts that recorded one")
    func averageRPE() {
        let bouts = [
            bout(prescriptionType: "reps_load", actualSets: 1, actualReps: 1, actualLoadKg: 1, rpe: 8),
            bout(prescriptionType: "reps_load", actualSets: 1, actualReps: 1, actualLoadKg: 1, rpe: 6),
            bout(prescriptionType: "session_only")
        ]
        let summary = WorkloadComputer.summary(for: bouts)
        #expect(summary.averageRPE == 7)
    }

    @Test("An empty session (no bouts) produces an all-nil summary")
    func emptySession() {
        let summary = WorkloadComputer.summary(for: [])
        #expect(summary.totalTonnageKg == nil)
        #expect(summary.averageRPE == nil)
    }

    @Test("A soft-deleted bout is expected to already be filtered by the caller, but is still summed if passed in")
    func doesNotFilterDeletedItself() {
        // WorkloadComputer trusts its input; WorkoutBoutStore.bouts(sessionId:)
        // already excludes soft-deleted rows before this is ever called.
        let deleted = WorkoutBoutEntry(id: 1, sessionId: 1, exerciseCatalogId: 1, sequenceIndex: 0,
                                       prescriptionType: "reps_load", containerType: nil,
                                       prescribedSets: nil, prescribedReps: nil, prescribedLoadKg: nil,
                                       prescribedDurationSeconds: nil, prescribedDistanceMeters: nil,
                                       prescribedWorkSeconds: nil, prescribedRestSeconds: nil, prescribedRounds: nil,
                                       actualSets: 5, actualReps: 5, actualLoadKg: 100, actualDurationSeconds: nil,
                                       actualDistanceMeters: nil, actualRounds: nil, elapsedSeconds: nil,
                                       avgHeartRate: nil, rpe: nil, techniqueRating: nil, notes: nil,
                                       deletedAt: "2026-09-17T00:00:00Z", createdAt: "", updatedAt: "")
        let summary = WorkloadComputer.summary(for: [deleted])
        #expect(summary.totalTonnageKg == 2500)
    }
}
