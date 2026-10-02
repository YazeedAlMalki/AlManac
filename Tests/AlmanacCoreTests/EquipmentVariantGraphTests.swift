import Foundation
import Testing
@testable import AlmanacCore

/// Decision 1 — equipment variants are tracked separately, and only the *graph*
/// chooses to draw them together.
///
/// The mode is a toggle on the graph, one mode covers both graphs, and the reason
/// both is a test rather than a comment: `bothGraphsShareTheMode` draws weight and
/// volume in each mode and asserts they agree about which series exist. A pair of
/// graphs that disagreed about the variants would be asking the same question
/// twice with different answers.
///
/// The other load-bearing property is that **the unspecified variant is a
/// series, not a hole**. Every bout logged before Migration049 has a null variant,
/// so in separate mode a movement whose whole history predates the column would
/// otherwise draw nothing at all — the graph would be empty exactly for the users
/// with the longest history.
@Suite("Equipment variant graphs")
struct EquipmentVariantGraphTests {
    let db = try! TestDatabase()

    private var graph: EquipmentVariantGraph { EquipmentVariantGraph(db: db) }
    private var sessions: WorkoutSessionStore { WorkoutSessionStore(db: db) }
    private var bouts: WorkoutBoutStore { WorkoutBoutStore(db: db) }

    // MARK: - Fixtures

    private func makeExercise(_ id: String = "fly") throws -> Int64 {
        try ExerciseCatalogStore(db: db).insert(
            ExerciseCatalogDraft(sourceId: "workout-guide", exerciseId: id,
                                 name: "Dumbbell Fly", prescriptionType: "reps_load",
                                 licenseGroup: "cc-by-sa-4.0"))
    }

    @discardableResult
    private func log(exerciseId: Int64, date: String,
                     variant: String? = nil,
                     loadKg: Double? = 20,
                     sets: Int? = 3, reps: Int? = 10,
                     skipped: Bool = false) throws -> Int64 {
        let sessionId = try sessions.log(WorkoutSessionDraft(date: date))
        return try bouts.log(WorkoutBoutDraft(
            sessionId: sessionId, exerciseCatalogId: exerciseId, sequenceIndex: 0,
            prescriptionType: "reps_load", actualSets: sets, actualReps: reps,
            actualLoadKg: loadKg, equipmentVariant: variant,
            wasSkippedForSession: skipped))
    }

    private func weight(_ exerciseId: Int64, _ mode: EquipmentVariantDisplay) throws -> [ProgressGraphSeries] {
        try graph.points(for: exerciseId, mode: mode, graph: .weight)
    }

    private func volume(_ exerciseId: Int64, _ mode: EquipmentVariantDisplay) throws -> [ProgressGraphSeries] {
        try graph.points(for: exerciseId, mode: mode, graph: .volume)
    }

    // MARK: - Separate

    @Test("Separate mode gives each variant its own series")
    func separateGroupsByVariant() throws {
        let exerciseId = try makeExercise()
        try log(exerciseId: exerciseId, date: "2026-09-01", variant: "dumbbell", loadKg: 20)
        try log(exerciseId: exerciseId, date: "2026-09-02", variant: "cable", loadKg: 45)
        try log(exerciseId: exerciseId, date: "2026-09-03", variant: "dumbbell", loadKg: 22.5)

        let series = try weight(exerciseId, .separate)
        #expect(series.count == 2)
        #expect(series.map(\.variant) == [.dumbbell, .cable])
        #expect(series[0].points.map(\.value) == [20, 22.5])
        #expect(series[0].points.map(\.date) == ["2026-09-01", "2026-09-03"])
        #expect(series[1].points.map(\.value) == [45])
    }

    @Test("A bout with no variant recorded is a series of its own, not a hole")
    func unspecifiedIsASeries() throws {
        // Every bout logged before Migration049 has a null variant. In separate mode
        // this is the series holding that history, so the users with the longest
        // record are not the ones with an empty graph.
        let exerciseId = try makeExercise()
        try log(exerciseId: exerciseId, date: "2026-09-01", variant: nil, loadKg: 18)
        try log(exerciseId: exerciseId, date: "2026-09-08", variant: "dumbbell", loadKg: 20)

        let series = try weight(exerciseId, .separate)
        #expect(series.count == 2)
        // Last, not first: "Not recorded" leads a legend with the weakest evidence
        // in it, so it goes at the bottom like the doc comment says.
        #expect(series[0].variant == .dumbbell)
        #expect(series[1].variant == nil)
        #expect(series[1].displayName == "Not recorded")
        #expect(series[1].points.map(\.value) == [18])
    }

    @Test("Series come back in the variant's own order, with the unspecified one last")
    func seriesOrderIsDeterministic() throws {
        // A graph whose lines move around between redraws is a graph nobody reads a
        // trend off. The order is `EquipmentVariant`'s declaration order — barbell,
        // dumbbell, cable, machine — not alphabetical, because the enum is the thing
        // that decided it and re-sorting it here would be a second opinion.
        let exerciseId = try makeExercise()
        try log(exerciseId: exerciseId, date: "2026-09-01", variant: "machine")
        try log(exerciseId: exerciseId, date: "2026-09-02", variant: "barbell")
        try log(exerciseId: exerciseId, date: "2026-09-03", variant: nil)
        try log(exerciseId: exerciseId, date: "2026-09-04", variant: "cable")
        try log(exerciseId: exerciseId, date: "2026-09-05", variant: "dumbbell")

        let series = try weight(exerciseId, .separate)
        #expect(series.map(\.variant) == [.barbell, .dumbbell, .cable, .machine, nil])
    }

    // MARK: - Combined

    @Test("Combined mode is one series, in date order, whatever the variant was")
    func combinedDrawsOneLine() throws {
        let exerciseId = try makeExercise()
        try log(exerciseId: exerciseId, date: "2026-09-02", variant: "cable", loadKg: 45)
        try log(exerciseId: exerciseId, date: "2026-09-01", variant: "dumbbell", loadKg: 20)

        let series = try weight(exerciseId, .combined)
        #expect(series.count == 1)
        #expect(series[0].variant == nil)
        #expect(series[0].points.map(\.date) == ["2026-09-01", "2026-09-02"])
        #expect(series[0].points.map(\.value) == [20, 45])
    }

    @Test("Only combined mode says the numbers may not be comparable")
    func comparabilityFootnote() throws {
        // One place, both graphs: two hand-typed copies of a caveat is how one of
        // them ends up wrong.
        #expect(EquipmentVariantDisplay.combined.showsComparabilityFootnote)
        #expect(EquipmentVariantDisplay.separate.showsComparabilityFootnote == false)
        #expect(EquipmentVariant.combinedModeFootnote.isEmpty == false)
    }

    @Test("Combined mode keeps each point's variant, so a combined line can be explained")
    func combinedKeepsTheVariantOnEachPoint() throws {
        // Combined means drawn together, not stripped of provenance: "why did my
        // weight jump" is answerable only if the cable session is still identifiable.
        let exerciseId = try makeExercise()
        try log(exerciseId: exerciseId, date: "2026-09-01", variant: "dumbbell", loadKg: 20)
        try log(exerciseId: exerciseId, date: "2026-09-08", variant: "cable", loadKg: 45)

        let series = try weight(exerciseId, .combined)
        #expect(series[0].points.map(\.variant) == [.dumbbell, .cable])
    }

    // MARK: - Both graphs agree

    @Test("The two graphs read the same variants in the same mode")
    func bothGraphsShareTheMode() throws {
        // One toggle for both, so the graph above and the graph below cannot
        // disagree about how many lines there are.
        let exerciseId = try makeExercise()
        try log(exerciseId: exerciseId, date: "2026-09-01", variant: "dumbbell")
        try log(exerciseId: exerciseId, date: "2026-09-02", variant: "cable")
        try log(exerciseId: exerciseId, date: "2026-09-03", variant: nil)

        for mode in EquipmentVariantDisplay.allCases {
            let weight = try self.weight(exerciseId, mode)
            let volume = try self.volume(exerciseId, mode)
            #expect(weight.map(\.variant) == volume.map(\.variant),
                    "\(mode.rawValue): the two graphs disagree about the series")
        }
    }

    @Test("Weight is the load lifted; volume is the reps performed")
    func theTwoGraphsMeasureDifferentThings() throws {
        let exerciseId = try makeExercise()
        try log(exerciseId: exerciseId, date: "2026-09-01", loadKg: 100, sets: 4, reps: 5)

        #expect(try weight(exerciseId, .combined)[0].points.map(\.value) == [100])
        // Four sets of five, not 100 × 20: a volume graph in kilogram-reps would
        // make a heavy lift look like a big session and a light one look empty.
        #expect(try volume(exerciseId, .combined)[0].points.map(\.value) == [20])
    }

    // MARK: - What is left out

    @Test("A movement with no history draws nothing, in either mode")
    func noHistory() throws {
        let exerciseId = try makeExercise()
        #expect(try weight(exerciseId, .separate).isEmpty)
        #expect(try volume(exerciseId, .combined).isEmpty)
        #expect(try weight(9999, .separate).isEmpty)
    }

    @Test("A bout with nothing recorded for the graph's measure is left out of it")
    func missingMeasureIsNotZero() throws {
        // A bodyweight movement has no load, and §9.1's rule against standing in for
        // absence with zero applies to a graph axis too: a 0 kg point would draw a
        // crash where nothing was measured.
        let exerciseId = try makeExercise()
        try log(exerciseId: exerciseId, date: "2026-09-01", variant: "dumbbell", loadKg: nil)
        try log(exerciseId: exerciseId, date: "2026-09-08", variant: "dumbbell", loadKg: 20)

        let weight = try weight(exerciseId, .combined)
        #expect(weight[0].points.map(\.date) == ["2026-09-08"])
        // The volume graph still has both, because the reps were recorded.
        #expect(try volume(exerciseId, .combined)[0].points.count == 2)
    }

    @Test("A slot skipped for the session is not a point on either graph")
    func skippedBoutIsNotAPoint() throws {
        // Decision 3's skip writes a bout with no actuals. Drawing it would put a
        // hole on the line and a fake zero on the volume axis.
        let exerciseId = try makeExercise()
        try log(exerciseId: exerciseId, date: "2026-09-01", loadKg: 20)
        try log(exerciseId: exerciseId, date: "2026-09-08", loadKg: nil, sets: nil,
                reps: nil, skipped: true)

        #expect(try weight(exerciseId, .combined)[0].points.count == 1)
        #expect(try volume(exerciseId, .combined)[0].points.count == 1)
    }

    @Test("A deleted bout and a deleted session both leave the graph")
    func deletedRowsLeaveTheGraph() throws {
        let exerciseId = try makeExercise()
        try log(exerciseId: exerciseId, date: "2026-09-01", loadKg: 20)
        let second = try log(exerciseId: exerciseId, date: "2026-09-08", loadKg: 22)

        let sessionId = try sessions.log(WorkoutSessionDraft(date: "2026-09-15"))
        let third = try bouts.log(WorkoutBoutDraft(
            sessionId: sessionId, exerciseCatalogId: exerciseId, sequenceIndex: 0,
            prescriptionType: "reps_load", actualLoadKg: 25))

        _ = try bouts.delete(id: second)
        _ = try sessions.delete(id: sessionId)

        #expect(try weight(exerciseId, .combined)[0].points.map(\.value) == [20])
        #expect(third > 0)
    }

    @Test("Another exercise's bouts are not on this graph")
    func graphsArePerExercise() throws {
        let fly = try makeExercise("fly")
        let raise = try makeExercise("raise")
        try log(exerciseId: fly, date: "2026-09-01", variant: "dumbbell", loadKg: 20)
        try log(exerciseId: raise, date: "2026-09-01", variant: "dumbbell", loadKg: 8)

        #expect(try weight(fly, .combined)[0].points.map(\.value) == [20])
        #expect(try weight(raise, .combined)[0].points.map(\.value) == [8])
    }

    @Test("Two bouts of one exercise in one session are both points")
    func sameSessionIsTwoPoints() throws {
        // Warm-up and working set. Collapsing a session into one point would make a
        // straight-set day look like an interval day.
        let exerciseId = try makeExercise()
        let sessionId = try sessions.log(WorkoutSessionDraft(date: "2026-09-01"))
        for (index, load) in [10.0, 20.0].enumerated() {
            _ = try bouts.log(WorkoutBoutDraft(
                sessionId: sessionId, exerciseCatalogId: exerciseId, sequenceIndex: index,
                prescriptionType: "reps_load", actualSets: 3, actualReps: 10,
                actualLoadKg: load, equipmentVariant: "dumbbell"))
        }

        #expect(try weight(exerciseId, .combined)[0].points.map(\.value) == [10, 20])
    }

    @Test("The graph never has to guess a variant, because the column refuses one")
    func unknownVariantCannotBeStored() throws {
        // A series labelled with a string the app has no name for would be worse
        // than omitting it, and folding an unrecognised value into the unspecified
        // series would silently merge two different kinds of work. The CHECK is
        // what makes the graph's parsing total, so it is the graph's guarantee and
        // it is asserted here rather than assumed.
        let exerciseId = try makeExercise()
        let boutId = try log(exerciseId: exerciseId, date: "2026-09-01",
                             variant: "dumbbell", loadKg: 20)

        for bad in ["DB", "kettlebell", ""] {
            #expect(throws: (any Error).self, "equipmentVariant accepted \(bad.debugDescription)") {
                try db.run("UPDATE workoutBout SET equipmentVariant = ? WHERE id = ?;",
                           [.text(bad), .integer(boutId)])
            }
        }
        // What survives is still exactly one series, and it is labelled.
        let series = try weight(exerciseId, .separate)
        #expect(series.count == 1)
        #expect(series[0].variant == .dumbbell)
        #expect(series[0].displayName == "Dumbbell")
    }
}
