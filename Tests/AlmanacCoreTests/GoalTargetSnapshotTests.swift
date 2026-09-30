import Foundation
import Testing
@testable import AlmanacCore

/// The targets a card is measured against, and the rule that they are historical.
///
/// §5.2's own words are "a new row is inserted whenever a goal changes; rows are
/// never updated". Most of what is tested here is that sentence: a change of
/// mind must not rewrite yesterday.
@Suite("Goal target snapshots")
struct GoalTargetSnapshotTests {

    // MARK: - Immutability

    @Test("Recording a second target does not disturb the first")
    func secondSnapshotLeavesTheFirstAlone() {
        let db = try! Database.inMemory()
        try! MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let clock = FixedClock(Date(timeIntervalSince1970: 1_800_000_000))
        let store = GoalTargetSnapshotStore(db: db, clock: clock)

        let first = try! store.insert(.init(
            effectiveDate: "2026-09-01", goal: .maintain,
            bodyCompositionTargets: [.weight: 80], createdAt: clock.now))
        try! store.insert(.init(
            effectiveDate: "2026-09-15", goal: .cut,
            bodyCompositionTargets: [.weight: 75], createdAt: clock.now))

        // The point of the table: a reading from the 10th is still measured
        // against what was in force on the 10th.
        let onTheTenth = try! store.active(on: "2026-09-10")
        #expect(onTheTenth?.id == first.id)
        #expect(onTheTenth?.bodyCompositionTargets[.weight] == 80)

        let today = try! store.active(on: "2026-09-30")
        #expect(today?.goal == .cut)
        #expect(today?.bodyCompositionTargets[.weight] == 75)
    }

    @Test("A snapshot dated in the future is not in force yet")
    func futureSnapshotIsNotInForce() {
        let db = try! Database.inMemory()
        try! MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let store = GoalTargetSnapshotStore(db: db)
        try! store.insert(.init(effectiveDate: "2026-10-01", goal: .bulk,
                                bodyCompositionTargets: [.weight: 85], createdAt: Date()))

        #expect(try! store.active(on: "2026-09-30") == nil)
        #expect(try! store.active(on: "2026-10-01")?.bodyCompositionTargets[.weight] == 85)
    }

    @Test("No snapshot is a normal answer, not an error")
    func noSnapshotIsNormal() {
        let db = try! Database.inMemory()
        try! MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let store = GoalTargetSnapshotStore(db: db)
        // Every install before somebody sets a goal is here. It has to read as
        // "no targets yet" rather than throwing, or the card grid cannot draw
        // itself on first launch.
        #expect(try! store.active(on: "2026-09-30") == nil)
        #expect(try! store.snapshotsInForce(on: "2026-09-30").isEmpty)
        #expect(try! store.activeTargets(on: "2026-09-30").isEmpty)
        #expect(try! store.history().isEmpty)
    }

    @Test("The row in force is the whole answer, including its absences")
    func newestRowIsAuthoritative() {
        // Setting a body-fat target in June and a weight target in September does
        // *not* leave both in force. The September row is the current statement of
        // the targets, and it does not mention body fat, so there is no body-fat
        // target. The alternative — each column taken from the newest row that sets
        // it — was written first and makes a target impossible to remove.
        let db = try! Database.inMemory()
        try! MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let store = GoalTargetSnapshotStore(db: db)
        try! store.insert(.init(effectiveDate: "2026-06-01", goal: .cut,
                                bodyCompositionTargets: [.bodyFatPercent: 15], createdAt: Date()))
        try! store.insert(.init(effectiveDate: "2026-09-01", goal: .cut,
                                bodyCompositionTargets: [.weight: 75], createdAt: Date()))

        let targets = try! store.activeTargets(on: "2026-09-30")
        #expect(targets == [.weight: 75])
        // And a form that re-saves the goal carries them forward, which is why the
        // newest-row rule is a rule a settings form can work with.
        let inForce = try! store.snapshotsInForce(on: "2026-09-30")
        #expect(inForce.count == 1)
        #expect(inForce[.weight]?.effectiveDate == "2026-09-01")
        #expect(inForce[.bodyFatPercent] == nil)
    }

    @Test("A metric whose target is cleared stops being in force")
    func clearingATarget() {
        // There is no update, so "cleared" is a new row with no target for that
        // metric — and the older row must not keep supplying it, or a target can
        // never be removed.
        let db = try! Database.inMemory()
        try! MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let store = GoalTargetSnapshotStore(db: db)
        try! store.insert(.init(effectiveDate: "2026-09-01", goal: .cut,
                                bodyCompositionTargets: [.weight: 75], createdAt: Date()))
        try! store.insert(.init(effectiveDate: "2026-09-20", goal: .maintain,
                                bodyCompositionTargets: [:], createdAt: Date()))

        let targets = try! store.activeTargets(on: "2026-09-30")
        // The row in force is the 20th, and it has no target for weight.
        #expect(targets[.weight] == nil)
    }

    @Test("History is newest first and bounded")
    func historyOrder() {
        let db = try! Database.inMemory()
        try! MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let store = GoalTargetSnapshotStore(db: db)
        for (day, goal) in [("2026-01-01", GoalKind.bulk), ("2026-05-01", .cut),
                            ("2026-09-01", .maintain)] {
            try! store.insert(.init(effectiveDate: day, goal: goal, createdAt: Date()))
        }
        let all = try! store.history()
        #expect(all.map(\.effectiveDate) == ["2026-09-01", "2026-05-01", "2026-01-01"])
        #expect(try! store.history(limit: 2).count == 2)
    }

    // MARK: - Overrides

    @Test("A manual override wins without erasing what was calculated")
    func overrideWins() {
        // §5.2: "Manual overrides allowed, stored alongside (never erase)
        // calculated." So both are stored, and the effective one is the override.
        let snapshot = GoalTargetSnapshot(
            effectiveDate: "2026-09-01", goal: .cut,
            calorieTarget: 2100, proteinTargetG: 150, hydrationTargetMl: 2500,
            manualCalorieTarget: 1800, manualProteinTargetG: 180, manualHydrationTargetMl: 3000,
            createdAt: Date())
        #expect(snapshot.effectiveCalorieTarget == 1800)
        #expect(snapshot.effectiveProteinTargetG == 180)
        #expect(snapshot.effectiveHydrationTargetMl == 3000)
        // Untouched columns still read through as themselves.
        #expect(snapshot.effectiveCarbTargetG == nil)
        // And the calculated values are still there, which is the "never erase".
        #expect(snapshot.calorieTarget == 2100)
        #expect(snapshot.proteinTargetG == 150)
    }

    @Test("Overrides survive a round trip")
    func overridesRoundTrip() {
        let db = try! Database.inMemory()
        try! MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let store = GoalTargetSnapshotStore(db: db)
        try! store.insert(.init(effectiveDate: "2026-09-01", goal: .cut,
                                calorieTarget: 2100, manualCalorieTarget: 1800,
                                createdAt: Date()))
        let back = try! store.active(on: "2026-09-30")!
        #expect(back.calorieTarget == 2100)
        #expect(back.manualCalorieTarget == 1800)
        #expect(back.effectiveCalorieTarget == 1800)
    }

    // MARK: - Generation

    @Test("Mifflin-St Jeor is the published equation")
    func mifflinStJeor() {
        // Male: 10w + 6.25h − 5a + 5.  800 + 1125 − 150 = 1775; +5 = 1780
        let male = MifflinStJeor.basalMetabolicRate(weightKg: 80, heightCm: 180, ageYears: 30, sex: .male)!
        #expect(abs(male - 1780) < 0.001)
        // Female: same, with −161 → 1614
        let female = MifflinStJeor.basalMetabolicRate(weightKg: 80, heightCm: 180, ageYears: 30, sex: .female)!
        #expect(abs(female - 1614) < 0.001)
        // The two differ by exactly the 166 between the constants, which is the
        // whole reason this is the published equation rather than a variant.
        #expect(abs((male - female) - 166) < 0.001)
        // `other` is the mean of the two constants, the standard neutral
        // treatment.  (5 + −161) / 2 = −78  →  1697
        let other = MifflinStJeor.basalMetabolicRate(weightKg: 80, heightCm: 180, ageYears: 30, sex: .other)!
        #expect(abs(other - 1697) < 0.001)
        #expect(abs(other - (male + female) / 2) < 0.001)
    }

    @Test("A resting burn needs a body to describe")
    func mifflinStJeorRefusesToGuess() {
        // `notSet` produces nothing. Returning zero would store a target of zero
        // and then show it as a number; picking `male` because it is the first
        // case would claim a body the person did not describe.
        #expect(MifflinStJeor.basalMetabolicRate(weightKg: 80, heightCm: 180, ageYears: 30, sex: .notSet) == nil)
        // And the inputs have to be real numbers.
        #expect(MifflinStJeor.basalMetabolicRate(weightKg: 0, heightCm: 180, ageYears: 30, sex: .male) == nil)
        #expect(MifflinStJeor.basalMetabolicRate(weightKg: 80, heightCm: -1, ageYears: 30, sex: .male) == nil)
        #expect(MifflinStJeor.basalMetabolicRate(weightKg: 80, heightCm: 180, ageYears: 0, sex: .male) == nil)
    }

    @Test("Biological sex is the spec's closed set, and declining is its own answer")
    func biologicalSex() {
        #expect(BiologicalSex.allCases.map(\.rawValue) == ["male", "female", "other", "not_set"])
        // Blank, garbage and `nil` all mean the same thing: the app has no idea,
        // which is not an error state to present differently from a declined
        // answer.
        #expect(BiologicalSex.parse(nil) == .notSet)
        #expect(BiologicalSex.parse("") == .notSet)
        #expect(BiologicalSex.parse("nonsense") == .notSet)
        #expect(BiologicalSex.parse("female") == .female)
    }

    @Test("Age counts completed years, against the day in question")
    func ageInCompletedYears() {
        let builder = GoalTargetBuilder(effectiveDate: "2026-09-30", goal: .maintain,
                                        referenceDate: "2026-09-30")
        #expect(builder.ageYears(from: "1996-09-30", to: "2026-09-30") == 30)
        // Three days short of 31 is still 30, and a resting burn computed at 30 and
        // read at 31 would be a target that quietly changed on its own.
        #expect(builder.ageYears(from: "1996-10-03", to: "2026-09-30") == 29)
        #expect(builder.ageYears(from: nil, to: "2026-09-30") == nil)
        #expect(builder.ageYears(from: "not-a-date", to: "2026-09-30") == nil)
        // A birth date after the reference date is a data error, not a negative age.
        #expect(builder.ageYears(from: "2020-01-01", to: "2019-01-01") == nil)
    }

    @Test("A calorie target needs a weight, a height, an age, a sex and an activity level")
    func calorieTargetNeedsEverything() {
        func builder(weight: Double? = 80, height: Double? = 180, dob: String? = "1996-09-30",
                     sex: BiologicalSex = .male, activity: ActivityLevel? = .moderate) -> GoalTargetBuilder {
            GoalTargetBuilder(effectiveDate: "2026-09-30", goal: .maintain, weightKg: weight,
                              heightCm: height, dateOfBirth: dob, referenceDate: "2026-09-30",
                              sex: sex, activity: activity)
        }
        // 1780 BMR × 1.55 (moderately active) = 2759, no adjustment for maintain.
        #expect(builder().calorieTarget() == 2759)
        // Each missing piece yields no target rather than a default.
        #expect(builder(weight: nil).calorieTarget() == nil)
        #expect(builder(height: nil).calorieTarget() == nil)
        #expect(builder(dob: nil).calorieTarget() == nil)
        #expect(builder(sex: .notSet).calorieTarget() == nil)
        #expect(builder(activity: nil).calorieTarget() == nil)
    }

    @Test("A cut is a deficit and a bulk is a surplus, of the size §5.2 names")
    func goalAdjustments() {
        // §5.2's own comment: "+300 bulk, -500 cut". Transcribed, not invented,
        // and overridable per snapshot.
        #expect(GoalKind.bulk.defaultCalorieAdjustment == 300)
        #expect(GoalKind.cut.defaultCalorieAdjustment == -500)
        #expect(GoalKind.maintain.defaultCalorieAdjustment == 0)
        #expect(GoalKind.performance.defaultCalorieAdjustment == 0)

        func target(_ goal: GoalKind) -> Int? {
            GoalTargetBuilder(effectiveDate: "2026-09-30", goal: goal, weightKg: 80,
                              heightCm: 180, dateOfBirth: "1996-09-30",
                              referenceDate: "2026-09-30", sex: .male, activity: .moderate).calorieTarget()
        }
        #expect(target(.cut) == 2759 - 500)
        #expect(target(.bulk) == 2759 + 300)
        #expect(target(.maintain) == 2759)
    }

    @Test("An impossible target is refused rather than stored")
    func negativeTargetIsRefused() {
        // A large cut against a small resting burn goes negative. The answer is no
        // target, not a card telling somebody to eat minus 300 kcal.
        // 30 kg, 100 cm, 90 y, female, sedentary: 300 + 625 - 450 - 161 = 314 BMR,
        // ×1.2 = 377, and −500 for a cut is negative. A -500 cut against a normal
        // adult's burn is not, which is why the numbers here look extreme.
        let builder = GoalTargetBuilder(effectiveDate: "2026-09-30", goal: .cut, weightKg: 30,
                                        heightCm: 100, dateOfBirth: "1936-01-01",
                                        referenceDate: "2026-09-30", sex: .female,
                                        activity: .sedentary)
        #expect(builder.calorieTarget() == nil)
    }

    @Test("No macro target is generated, because no split has been decided")
    func noInventedMacros() {
        // The protein/carb/fat split is not specified in the spec, the BRD or the
        // handoff. Inventing grams-per-kilo ratios would put five numbers on a
        // card that nobody chose, so the columns stay null and say so.
        let snapshot = GoalTargetBuilder(effectiveDate: "2026-09-30", goal: .bulk, weightKg: 80,
                                         heightCm: 180, dateOfBirth: "1996-09-30",
                                         referenceDate: "2026-09-30", sex: .male,
                                         activity: .moderate).build(now: Date())
        #expect(snapshot.proteinTargetG == nil)
        #expect(snapshot.carbTargetG == nil)
        #expect(snapshot.fatTargetG == nil)
        #expect(snapshot.calorieTarget != nil)
    }

    @Test("A snapshot keeps the assumptions its targets were derived from")
    func assumptionsAreKept() {
        // A target that cannot say what it assumed cannot be re-derived when the
        // assumption is wrong. The stored multiplier is the one that generated
        // the number, not the enum's current default.
        let snapshot = GoalTargetBuilder(effectiveDate: "2026-09-30", goal: .cut, weightKg: 80,
                                         bodyFatPercent: 22, heightCm: 180,
                                         dateOfBirth: "1996-09-30", referenceDate: "2026-09-30",
                                         sex: .male, activity: .high).build(now: Date())
        #expect(snapshot.activityMultiplier == 1.725)
        #expect(snapshot.goalCalorieAdjustment == -500)
        #expect(snapshot.bodyWeightKg == 80)
        #expect(snapshot.bodyFatPercent == 22)
        #expect(snapshot.formulaVersion == "1.0")
    }

    @Test("Hydration is suggested from the standard rule, and is still only a suggestion")
    func hydrationSuggestion() {
        // 35 mL/kg, a published figure rather than a judgement call. It becomes a
        // target when a person accepts one; until then the builder's own output is
        // a number nothing has claimed.
        let builder = GoalTargetBuilder(effectiveDate: "2026-09-30", goal: .maintain, weightKg: 80,
                                        referenceDate: "2026-09-30")
        #expect(builder.suggestedHydrationTargetMl() == 2800)
        #expect(builder.suggestedHydrationTargetMl() != builder.build(now: Date()).manualHydrationTargetMl)
        #expect(GoalTargetBuilder(effectiveDate: "2026-09-30", goal: .maintain,
                                  referenceDate: "2026-09-30").suggestedHydrationTargetMl() == nil)
    }

    @Test("The record path builds and stores in one call")
    func recordHelper() {
        let db = try! Database.inMemory()
        try! MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let clock = FixedClock(Date(timeIntervalSince1970: 1_800_000_000))
        let store = GoalTargetSnapshotStore(db: db, clock: clock)
        let builder = GoalTargetBuilder(effectiveDate: "2026-09-30", goal: .cut, weightKg: 80,
                                        heightCm: 180, dateOfBirth: "1996-09-30",
                                        referenceDate: "2026-09-30", sex: .male, activity: .moderate)
        let stored = try! store.record(builder: builder)
        #expect(stored.id > 0)
        #expect(stored.createdAt == clock.now)
        #expect(try! store.active(on: "2026-09-30")?.id == stored.id)
    }
}

