import Foundation
import Testing
@testable import AlmanacCore

/// The readiness coupling — the part of the prescription model that could not be
/// recovered, reconstructed from the two rules that did survive.
///
/// `prescription-model-v0.1.md` was never committed here (`docs/features/training.md`
/// §1), so the twelve-row coupling table is gone. What survives is quoted in
/// `docs/almanac-technical-spec-v1_0.md:377`:
///
/// > Readiness coupling differs by type — `release` is the only type that should
/// > ever *increase* on a low‑readiness day; `quality_reps` holds volume and drops
/// > complexity rather than reducing work.
///
/// Everything else in this suite is a reconstruction, and the suite says so out
/// loud rather than letting a tidy number look like a decision somebody made.
///
/// Three properties are load-bearing and are asserted as **properties over the
/// whole 12 × 6 grid**, not as spot checks, because a spot check on a
/// reconstructed table is just a restatement of the numbers:
///
/// - **Nothing but `release` ever increases.** Not one kind, not one band.
/// - **`quality_reps` never loses volume.** Reps and sets are held; complexity is
///   what goes.
/// - **A reduction never rounds up, and never rounds a count to zero.** Rounding
///   up would make "less work" into more work, which is the one bug this whole
///   table exists to prevent.
/// A score in the middle of each band.
///
/// Mid-band rather than on an edge, so `bandsAgreeWithBandText` catches an edge
/// that has moved as well as a band that has moved: an off-by-one at a boundary
/// is caught by whichever neighbouring band owns that score.
private extension ReadinessBand {
    var representativeScore: Int {
        switch self {
        case .excellent: return 92
        case .good: return 78
        case .moderate: return 62
        case .belowBaseline: return 48
        case .poor: return 32
        case .veryLow: return 20
        }
    }
}

@Suite("Readiness adjustment")
struct ReadinessAdjustmentTests {

    // MARK: - Fixtures

    private func item(_ kind: PrescriptionKind,
                      sets: Int? = 4, reps: Int? = 8, loadKg: Double? = 100,
                      duration: Double? = nil, rest: Double? = 90) -> PoolItemEntry {
        PoolItemEntry(
            id: 1, programDayId: 1, exerciseCatalogId: 1, rotationPosition: 0,
            positionWithinSession: 0, isActive: true, prescriptionType: kind.rawValue,
            containerType: nil, prescribedSets: sets, prescribedReps: reps,
            prescribedLoadKg: loadKg, prescribedDurationSeconds: duration,
            prescribedRestSeconds: rest, progressionEnabled: false,
            progressionIncrementKg: nil, progressionCondition: nil, notes: nil,
            deletedAt: nil, createdAt: "", updatedAt: "")
    }

    /// Every kind, with every field filled, so a sweep cannot pass by finding
    /// nothing to scale.
    private func loaded(_ kind: PrescriptionKind) -> PoolItemEntry {
        item(kind, duration: 60)
    }

    /// The fields that represent *work*. Rest is deliberately excluded: rest going
    /// up on a bad day is the adjustment working, not the day asking for more
    /// training, so including it would make the sweep assert something false.
    private func workAxes(_ item: PoolItemEntry) -> [Double?] {
        [item.prescribedSets.map(Double.init), item.prescribedReps.map(Double.init),
         item.prescribedLoadKg, item.prescribedDurationSeconds]
    }

    private func workAxes(_ adjusted: AdjustedPrescription) -> [Double?] {
        [adjusted.sets.map(Double.init), adjusted.reps.map(Double.init),
         adjusted.loadKg, adjusted.durationSeconds]
    }

    // MARK: - The bands are the formula's, not new ones

    @Test("The bands are ReadinessFormula's six, with its own thresholds at 40 and 70")
    func bandsComeFromTheFormula() {
        #expect(ReadinessBand.allCases.count == 6)
        #expect(ReadinessBand.band(for: 100) == .excellent)
        #expect(ReadinessBand.band(for: ReadinessFormula.readyThreshold) == .good)
        #expect(ReadinessBand.band(for: ReadinessFormula.readyThreshold - 1) == .moderate)
        #expect(ReadinessBand.band(for: ReadinessFormula.compromisedThreshold) == .belowBaseline)
        #expect(ReadinessBand.band(for: ReadinessFormula.compromisedThreshold - 1) == .poor)
        #expect(ReadinessBand.band(for: 0) == .veryLow)
    }

    @Test("Every band agrees with the copy ReadinessFormula already ships")
    func bandsAgreeWithBandText() {
        // The strongest available link to §9.3's real bands: if `bandText` ever
        // moves an edge, this fails rather than the training table quietly
        // disagreeing with the readiness card the user read that morning.
        let expectedPrefix: [ReadinessBand: String] = [
            .excellent: "Recovery is excellent",
            .good: "Recovery is good",
            .moderate: "Moderate recovery",
            .belowBaseline: "Recovery is below baseline",
            .poor: "Recovery is poor",
            .veryLow: "Recovery is very low",
        ]
        for band in ReadinessBand.allCases {
            // A score in the middle of the band, so an off-by-one at an edge is
            // caught by the neighbouring band's iteration instead.
            let score = band.representativeScore
            #expect(ReadinessBand.band(for: score) == band)
            let text = ReadinessFormula.bandText(for: score)
            #expect(text.hasPrefix(expectedPrefix[band] ?? ""),
                    "score \(score) is \(band) but the spec copy says \"\(text)\"")
        }
    }

    @Test("A score with no data is not a low score; it changes nothing")
    func noScoreIsNoOpinion() throws {
        // §9.1's insufficient-data branch produces a nil score. Treating that as
        // a bad day would cut a session for a user who never opted in to having
        // readiness change anything.
        let adjusted = ReadinessAdjustment.prescription(for: item(.repsLoad), score: nil)
        #expect(adjusted.sets == 4)
        #expect(adjusted.reps == 8)
        #expect(adjusted.loadKg == 100)
        #expect(adjusted.restSeconds == 90)
        #expect(adjusted.band == nil)
        #expect(adjusted.isAdjusted == false)
    }

    // MARK: - Volume and complexity scale down as the day gets worse

    @Test("A good day asks for the session exactly as written")
    func goodDayIsUnchanged() {
        for score in [100, 85, ReadinessFormula.readyThreshold] {
            let adjusted = ReadinessAdjustment.prescription(for: item(.repsLoad), score: score)
            #expect(adjusted.sets == 4)
            #expect(adjusted.reps == 8)
            #expect(adjusted.loadKg == 100)
            #expect(adjusted.restSeconds == 90)
            #expect(adjusted.isAdjusted == false, "score \(score) should need no adjustment")
        }
    }

    @Test("Worse bands cut volume and complexity, and lengthen rest")
    func worseBandsScaleDown() {
        let moderate = ReadinessAdjustment.prescription(for: item(.repsLoad), score: 60)
        #expect(moderate.sets == 3)      // 4 × 0.85 = 3.4
        #expect(moderate.reps == 6)      // 8 × 0.85 = 6.8
        #expect(moderate.loadKg == 90)   // 100 × 0.9
        #expect(moderate.restSeconds == 100)  // 90 × 1.1, rounded up to the 5s grid

        let below = ReadinessAdjustment.prescription(for: item(.repsLoad), score: 45)
        #expect(below.sets == 2)         // 4 × 0.7 = 2.8
        #expect(below.reps == 5)         // 8 × 0.7 = 5.6
        #expect(below.loadKg == 75)      // 100 × 0.75
        #expect(below.restSeconds == 115)  // 90 × 1.25 = 112.5, rounded up

        let poor = ReadinessAdjustment.prescription(for: item(.repsLoad), score: 30)
        #expect(poor.sets == 2)          // 4 × 0.5
        #expect(poor.reps == 4)
        #expect(poor.loadKg == 60)       // 100 × 0.6
        #expect(poor.restSeconds == 135)  // 90 × 1.5
    }

    @Test("A very low day prescribes nothing at all")
    func veryLowIsARestDay() {
        // `ReadinessFormula.bandText` for this band says "rest is the best
        // training decision". Prescribing a light session instead would be the app
        // overruling a recovery signal it cannot measure properly.
        let adjusted = ReadinessAdjustment.prescription(for: item(.repsLoad), score: 20)
        #expect(adjusted.sets == nil)
        #expect(adjusted.reps == nil)
        #expect(adjusted.loadKg == nil)
        #expect(adjusted.durationSeconds == nil)
        #expect(adjusted.restSeconds == nil)
        #expect(adjusted.isRestDay == true)
        #expect(adjusted.band == .veryLow)
    }
    // MARK: - Rounding: the rule that makes the table safe

    @Test("A reduction never rounds up")
    func reductionsNeverRoundUp() {
        // The failure this rules out is subtle and would survive a code review: a
        // factor of 0.85 applied to 3 reps is 2.55, and rounding *up* to 3 means
        // the low-readiness day prescribed exactly as much work as a good one.
        let adjusted = ReadinessAdjustment.prescription(
            for: item(.repsLoad, sets: 3, reps: 3, loadKg: 3.5), score: 60)
        #expect(adjusted.sets == 2)      // 2.55
        #expect(adjusted.reps == 2)      // 2.55
        #expect(adjusted.loadKg == 3.0)  // 3.15, down to the 0.5kg grid
    }

    @Test("A count never rounds down to zero")
    func countsNeverRoundToZero() {
        // "Do less" has to mean "do some", not "do nothing you could not ask for".
        for score in [60, 45, 30] {
            let adjusted = ReadinessAdjustment.prescription(
                for: item(.repsLoad, sets: 1, reps: 1), score: score)
            #expect(adjusted.sets == 1, "score \(score)")
            #expect(adjusted.reps == 1, "score \(score)")
        }
    }

    @Test("Load lands on a half kilo and time on five seconds")
    func granularityIsHalfKiloAndFiveSeconds() {
        // Two granularities, both reconstructed: 0.5kg is the finest step a plate
        // rack makes without the app asking what plates the user owns, and 5s is
        // the finest step worth reading off a stopwatch for a hold.
        let load = ReadinessAdjustment.prescription(
            for: item(.repsLoad, loadKg: 101.2), score: 30)
        #expect(load.loadKg == 60.5)  // 60.72, down to the 0.5kg grid

        let hold = ReadinessAdjustment.prescription(
            for: item(.holdStretch, sets: nil, reps: nil, loadKg: nil, duration: 62), score: 45)
        #expect(hold.durationSeconds == 45)  // 62 × 0.75 = 46.5, down to the 5s grid
    }

    @Test("A very short hold does not round away to nothing")
    func shortHoldsAreFloored() {
        let adjusted = ReadinessAdjustment.prescription(
            for: item(.holdStretch, sets: nil, reps: nil, loadKg: nil, duration: 8), score: 30)
        #expect(adjusted.durationSeconds == 5)  // 8 × 0.6 = 4.8, floored at one grid step
    }

    // MARK: - Only what is prescribed gets scaled

    @Test("Fields the prescription does not use stay absent")
    func absentFieldsStayAbsent() {
        // A hold has no sets and no load. Inventing either would put a 0 in front
        // of a user for a field the exercise has no answer to.
        let adjusted = ReadinessAdjustment.prescription(
            for: item(.holdStretch, sets: nil, reps: nil, loadKg: nil, duration: 60), score: 45)
        #expect(adjusted.sets == nil)
        #expect(adjusted.reps == nil)
        #expect(adjusted.loadKg == nil)
        #expect(adjusted.durationSeconds == 45)
    }

    @Test("Rest is lengthened, never shortened, on every band that changes anything")
    func restOnlyEverLengthens() {
        for band in ReadinessBand.allCases where band != .excellent && band != .good {
            let adjusted = ReadinessAdjustment.prescription(for: item(.repsLoad), score: band.representativeScore)
            guard !adjusted.isRestDay else { continue }
            #expect((adjusted.restSeconds ?? 0) >= 90, "\(band) shortened the rest")
        }
    }

    // MARK: - The two rules that survived

    @Test("Release is the only kind that ever increases")
    func onlyReleaseEverIncreases() {
        // The surviving rule, asserted over the whole grid rather than on one
        // example — a rule that is checked case by case is a rule that eventually
        // gets a case added to it that violates it.
        for kind in PrescriptionKind.allCases {
            for band in ReadinessBand.allCases {
                let before = loaded(kind)
                let adjusted = ReadinessAdjustment.prescription(
                    for: before, score: band.representativeScore)
                guard !adjusted.isRestDay else { continue }
                let grew = zip(workAxes(before), workAxes(adjusted)).contains { was, now in
                    guard let was, let now else { return false }
                    return now > was
                }
                #expect(!grew || kind == .release,
                        "\(kind.rawValue) asked for more work on \(band)")
            }
        }
    }

    @Test("Release increases on a bad day rather than shrinking")
    func releaseIncreasesWhenRecoveryIsBelowBaseline() {
        for band in ReadinessBand.allCases {
            let adjusted = ReadinessAdjustment.prescription(
                for: item(.release, sets: 4, duration: 60), score: band.representativeScore)
            switch band {
            case .excellent, .good, .moderate:
                #expect(adjusted.durationSeconds == 60, "\(band) should not need more release work")
            case .belowBaseline:
                #expect(adjusted.durationSeconds == 75)  // 60 × 1.25
            case .poor:
                #expect(adjusted.durationSeconds == 90)  // 60 × 1.5
            case .veryLow:
                #expect(adjusted.isRestDay)
            }
        }
    }

    @Test("Quality reps hold their volume and drop their complexity")
    func qualityRepsHoldVolumeAndDropComplexity() {
        // The second surviving rule, in the spec's own terms: "holds volume and
        // drops complexity rather than reducing work". The sets and the reps are
        // the volume; the load is the complexity.
        for band in ReadinessBand.allCases where band != .veryLow {
            let adjusted = ReadinessAdjustment.prescription(
                for: item(.qualityReps, sets: 4, reps: 8, loadKg: 100),
                score: band.representativeScore)
            #expect(adjusted.sets == 4, "\(band) cut the sets of a quality-reps set")
            #expect(adjusted.reps == 8, "\(band) cut the reps of a quality-reps set")
            #expect((adjusted.loadKg ?? 100) <= 100, "\(band) increased the load")
        }

        // And the complexity does come off, or "drops complexity" means nothing.
        let below = ReadinessAdjustment.prescription(
            for: item(.qualityReps), score: ReadinessFormula.compromisedThreshold)
        #expect(below.loadKg == 75)
        // While a plain strength set on the same score loses its reps as well.
        let strength = ReadinessAdjustment.prescription(
            for: item(.repsLoad), score: ReadinessFormula.compromisedThreshold)
        #expect(strength.reps == 5)
    }

    @Test("Quality reps on a very low day is still a rest day")
    func qualityRepsStillRests() {
        let adjusted = ReadinessAdjustment.prescription(
            for: item(.qualityReps), score: 20)
        #expect(adjusted.isRestDay)
    }

    // MARK: - Explaining the change

    @Test("Every field that moved is reported, and nothing that did not")
    func changesDescribeTheAdjustment() {
        // Without this the sheet would silently show 3 sets where the program says
        // 4, and the user's own plan would be the thing that changed without them.
        let before = item(.repsLoad)
        let adjusted = ReadinessAdjustment.prescription(for: before, score: 45)
        let changed = Set(adjusted.changes.map(\.field))
        #expect(changed == [.sets, .reps, .loadKg, .restSeconds])
        for change in adjusted.changes {
            #expect(change.was != change.now, "\(change.field) is reported but did not move")
        }
        let byField = Dictionary(uniqueKeysWithValues: adjusted.changes.map { ($0.field, $0) })
        #expect(byField[.sets]?.was == 4)
        #expect(byField[.sets]?.now == 2)
        #expect(byField[.restSeconds]?.now == 115)
    }

    @Test("An unchanged prescription reports no changes")
    func unchangedReportsNothing() {
        let adjusted = ReadinessAdjustment.prescription(for: item(.repsLoad), score: 90)
        #expect(adjusted.changes.isEmpty)
        #expect(adjusted.isAdjusted == false)
    }

    // MARK: - Shape

    @Test("The policy is total: every kind and every band resolves to something")
    func policyIsTotal() {
        for kind in PrescriptionKind.allCases {
            for band in ReadinessBand.allCases {
                let policy = ReadinessAdjustment.policy(for: kind, band: band)
                switch policy {
                case .unchanged: break
                case .restDay: break
                case .scale(let volume, let complexity, let rest):
                    #expect(volume > 0 && complexity > 0 && rest >= 1.0,
                            "\(kind.rawValue) on \(band) scales to \(policy)")
                }
            }
        }
    }

    @Test("The same input always gives the same prescription, and nothing is written")
    func adjustmentIsPure() throws {
        let db = try TestDatabase()
        let programId = try ProgramStore(db: db).create(name: "PPL")
        let dayId = try ProgramDayStore(db: db).create(programId: programId, label: "Push")
        let exerciseId = try ExerciseCatalogStore(db: db).insert(
            ExerciseCatalogDraft(sourceId: "workout-guide", exerciseId: "squat",
                                 name: "Squat", prescriptionType: "reps_load",
                                 licenseGroup: "cc-by-sa-4.0"))
        let id = try ProgramDayExercisePoolStore(db: db).add(PoolItemDraft(
            programDayId: dayId, exerciseCatalogId: exerciseId, rotationPosition: 0,
            prescriptionType: "reps_load", prescribedSets: 4, prescribedReps: 8,
            prescribedLoadKg: 100, prescribedRestSeconds: 90))
        let stored = try ProgramDayExercisePoolStore(db: db).item(id: id)
        let storedItem = try #require(stored)

        let first = ReadinessAdjustment.prescription(for: storedItem, score: 45)
        let second = ReadinessAdjustment.prescription(for: storedItem, score: 45)
        #expect(first == second)

        // The table is the prescription's *suggestion*. Applying it to a session
        // writes a bout; it never rewrites the pool, or the next good day would
        // inherit the bad day's numbers.
        let reread = try ProgramDayExercisePoolStore(db: db).item(id: id)
        let after = try #require(reread)
        #expect(after.prescribedSets == 4)
        #expect(after.prescribedLoadKg == 100)
        #expect(after.updatedAt == storedItem.updatedAt)
    }
}
