import Foundation
import Testing
@testable import AlmanacCore

/// The body-composition card's arithmetic, and the vocabulary it is drawn from.
///
/// The decisions under test are the ones that make a meter honest rather than
/// decorative: which way is progress, what an empty meter means, and how much of
/// the distance has been covered. All of it is here, in values, so it is tested
/// exhaustively rather than eyeballed in a simulator.
@Suite("Body composition vocabulary and progress")
struct BodyCompositionProgressTests {

    // MARK: - The vocabulary

    @Test("Every stored metric string is in the closed set")
    func everyStoredMetricIsKnown() {
        // These are the strings already in every install's
        // `body_composition_measurement.metric` column. If one of them were not a
        // `BodyMetric`, the card grid would silently drop a card somebody's data
        // was on — the failure this test exists to prevent, and the reason the
        // list was a `let` in a view file until now.
        let stored = ["weight", "body_fat_pct", "lean_mass_kg", "skeletal_muscle_kg", "visceral_rating"]
        #expect(stored.count == BodyMetric.allCases.count)
        for raw in stored {
            #expect(BodyMetric.parse(raw) != nil, "\(raw) is stored but not in the closed set")
        }
    }

    @Test("An unknown metric is not coerced into a known one")
    func unknownMetricIsNotGuessed() {
        // The tempting alternative is `?? .weight`, which turns a typo'd import
        // into a plausible-looking weight card. Leaving it out is visible; the
        // guess is not.
        #expect(BodyMetric.parse("body_fat_percentage") == nil)
        #expect(BodyMetric.parse("") == nil)
        #expect(BodyMetric.parse("WEIGHT") == nil)
    }

    @Test("Percentage and mass are properties of the metric, not of unit strings")
    func percentageAndMass() {
        #expect(BodyMetric.bodyFatPercent.isPercentage)
        #expect(!BodyMetric.weight.isPercentage)
        #expect(BodyMetric.weight.isMass)
        #expect(BodyMetric.leanMassKg.isMass)
        // Deliberately not a mass: it is a rating on a device's own scale, and
        // dressing it as kilograms would be a unit the number has never been in.
        #expect(!BodyMetric.visceralRating.isMass)
        #expect(!BodyMetric.visceralRating.isPercentage)
    }

    @Test("Precision is a claim about what the app knows")
    func precisionIsNotDecoration() {
        // "7.4" for a visceral rating implies a precision the scale does not
        // have, and a body-fat tenth invites reading the decimal as real.
        #expect(BodyMetric.format(7.4, metric: .visceralRating) == "7")
        #expect(BodyMetric.format(72.36, metric: .weight) == "72.4")
        #expect(BodyMetric.format(18.04, metric: .bodyFatPercent) == "18.0")
    }

    @Test("A rating gets no unit appended")
    func ratingHasNoUnit() {
        #expect(BodyMetric.formatWithUnit(7.2, metric: .visceralRating) == "7")
        #expect(BodyMetric.formatWithUnit(72.4, metric: .weight) == "72.4 kg")
    }

    @Test("Direction of improvement differs per metric")
    func directions() {
        // Weight and body fat improve downward; lean and skeletal muscle improve
        // upward. Getting this backwards is the failure that makes a chart lie
        // most confidently, because every number stays correct.
        #expect(BodyMetric.weight.progressDirection == .towardLower)
        #expect(BodyMetric.bodyFatPercent.progressDirection == .towardLower)
        #expect(BodyMetric.visceralRating.progressDirection == .towardLower)
        #expect(BodyMetric.leanMassKg.progressDirection == .towardHigher)
        #expect(BodyMetric.skeletalMuscleKg.progressDirection == .towardHigher)

        #expect(BodyMetric.weight.progressDirection.isImprovement(previous: 80, current: 79))
        #expect(!BodyMetric.weight.progressDirection.isImprovement(previous: 79, current: 80))
        #expect(BodyMetric.leanMassKg.progressDirection.isImprovement(previous: 55, current: 56))
        // A flat week is not progress, and it is certainly not decline.
        #expect(!BodyMetric.weight.progressDirection.isImprovement(previous: 80, current: 80))
        // One reading is not a direction.
        #expect(!BodyMetric.weight.progressDirection.isImprovement(previous: nil, current: 80))
    }

    // MARK: - Unit basis

    @Test("Pounds and kilograms round-trip")
    func unitBasisRoundTrip() {
        let pounds = UnitBasis.pounds
        #expect(abs(pounds.mass(100) - 220.46226) < 0.001)
        #expect(abs(pounds.kilograms(fromMass: pounds.mass(72.5)) - 72.5) < 0.0001)
        #expect(UnitBasis.kilograms.mass(72.5) == 72.5)
        // The inverse matters for a target typed in pounds: read back into the
        // stored unit, or the meter compares pounds against kilograms and reports
        // a fraction of 2.2.
        #expect(abs(pounds.kilograms(fromMass: 165) - 74.842) < 0.001)
    }

    // MARK: - The meter

    @Test("A metric with no reading says so, and claims no progress")
    func noReading() {
        let progress = BodyCompositionProgress(metric: .weight)
        #expect(progress.current == nil)
        #expect(progress.fraction == nil)
        #expect(!progress.isTargetMet)
        #expect(progress.directionOfTravel == .unknown)
        #expect(progress.statusText == "Nothing recorded yet")
        #expect(progress.accessibilityDescription == "Weight: nothing recorded yet.")
    }

    @Test("A reading with no target says the target is missing, not that the meter is broken")
    func noTarget() {
        // This is the case the handoff asked about and the one an empty meter
        // without an explanation gets wrong: the reading is right there, so
        // "broken" is the natural wrong conclusion.
        let progress = BodyCompositionProgress(metric: .weight, current: 82.4, previous: 82.9, readingCount: 2)
        #expect(progress.fraction == nil)
        #expect(progress.statusText == "No target set")
        #expect(progress.accessibilityDescription == "Weight: 82.4 kg. No target set.")
    }

    @Test("One reading and a target is not progress")
    func oneReadingIsNotATrend() {
        // There is no origin to measure from, so any fraction would be drawn out
        // of a single point.
        let progress = BodyCompositionProgress(metric: .weight, current: 82.4, start: 82.4,
                                              target: 75, readingCount: 1)
        #expect(progress.fraction == nil)
        #expect(!progress.isTargetMet)
        #expect(progress.directionOfTravel == .unknown)
        // The honest text is the gap, which needs no history to state.
        #expect(progress.statusText == "7.4 kg to go")
        #expect(progress.accessibilityDescription == "Weight: 82.4 kg. Your target of 75.0 kg, 7.4 kg to go.")
    }

    @Test("Progress is the distance travelled over the whole distance")
    func fractionDefinition() {
        func progress(_ current: Double, _ start: Double, _ target: Double) -> Double? {
            BodyCompositionProgress(metric: .weight, current: current, start: start,
                                    target: target, readingCount: 2).fraction
        }
        // Halfway: 5 kg covered of 10.
        #expect(progress(20, 25, 15) == 0.5)
        // Set a target without moving: nothing covered.
        #expect(progress(25, 25, 15) == 0.0)
        #expect(progress(17, 25, 15) == 0.8)
        // Moving the wrong way: empty bar, and the travel is not negative.
        #expect(progress(26, 25, 15) == 0.0)
        // Past the target is not "wrong way", it is met — see the test below.
        #expect(progress(10, 25, 15) == nil)
    }

    @Test("A target reached is stated, not drawn as a full bar")
    func targetMet() {
        // The case the fraction definition deliberately refuses: a bar at 150%, or
        // one silently pinned at full, says less than "Target met" and invites
        // the reader to think there is more to do.
        let progress = BodyCompositionProgress(metric: .weight, current: 74, start: 82,
                                              target: 75, readingCount: 3)
        #expect(progress.isTargetMet)
        #expect(progress.fraction == nil)
        #expect(progress.statusText == "Target met")
        #expect(progress.remaining == nil)
        #expect(progress.accessibilityDescription.contains("reached"))
    }

    @Test("A metric that improves upward is measured the same way")
    func upwardMetric() {
        // Lean mass going 50 → 53 against a target of 55 is halfway there, exactly
        // as 20 kg against 15 is halfway *down* from 25. The definition is one
        // definition; only the direction flips.
        let progress = BodyCompositionProgress(metric: .leanMassKg, current: 53, start: 50,
                                              target: 55, readingCount: 2)
        #expect(progress.fraction == 0.6)
        #expect(!progress.isTargetMet)
        #expect(progress.statusText == "2.0 kg to go")
    }

    @Test("Unchanged is neither progress nor decline")
    func unchanged() {
        // Three states, not two. A week of the same weight is information, and
        // rendering it as either is how a chart starts lying.
        let flat = BodyCompositionProgress(metric: .weight, current: 80, previous: 80,
                                          start: 80, target: 75, readingCount: 2)
        #expect(flat.directionOfTravel == .unchanged)
        #expect(flat.change == 0)

        let down = BodyCompositionProgress(metric: .weight, current: 79, previous: 80,
                                          start: 80, target: 75, readingCount: 2)
        #expect(down.directionOfTravel == .improving)
        #expect(down.change == -1)

        let up = BodyCompositionProgress(metric: .weight, current: 81, previous: 80,
                                        start: 80, target: 75, readingCount: 2)
        #expect(up.directionOfTravel == .declining)
        // Signed by amount, not by good-or-bad — the judgement is a separate ask.
        #expect(up.change == 1)
    }

    @Test("The status text names the gap in the metric's own unit")
    func statusTextUsesMetricUnits() {
        let fat = BodyCompositionProgress(metric: .bodyFatPercent, current: 18.4, start: 21,
                                          target: 15, readingCount: 2)
        #expect(fat.statusText == "3.4% to go")
        #expect(fat.accessibilityDescription == "Body fat: 18.4%. Your target of 15.0%, 3.4% to go.")

        // A rating has no unit, so neither the short text nor the long one
        // invents one.
        let visceral = BodyCompositionProgress(metric: .visceralRating, current: 8, start: 11,
                                               target: 6, readingCount: 2)
        // No unit at all, on screen or spoken: a rating is a rating, and "2 rating"
        // is worse than "2".
        #expect(visceral.statusText == "2 to go")
        #expect(visceral.accessibilityDescription == "Visceral rating: 8. Your target of 6, 2 to go.")
    }

    // MARK: - One pass over the readings

    @Test("Every metric gets a card whether or not it has readings")
    func everyMetricGetsACard() {
        // A grid whose set of cards depends on the data changes shape under the
        // reader, and a metric that appears only once something is logged is a
        // layout bug waiting for a person to notice.
        let db = try! Database.inMemory()
        try! MigrationRunner(migrations: AlmanacMigrations.all).migrate(db)
        let store = BodyCompositionMeasurementStore(db: db)
        let day = "2026-09-30"
        try! store.log(.init(metric: "weight", value: 80, unit: "kg",
                             timestamp: day.date, source: "manual", conditions: "fasted"), logicalDay: day)
        try! store.log(.init(metric: "weight", value: 79, unit: "kg",
                             timestamp: "2026-09-20".date, source: "manual", conditions: "fasted"), logicalDay: day)

        let all = BodyCompositionProgress.all(from: try! store.records(from: "2026-09-01", to: "2026-10-01"))
        #expect(all.count == BodyMetric.allCases.count)
        #expect(all.map(\.metric) == BodyMetric.allCases)

        let weight = all.first { $0.metric == .weight }!
        #expect(weight.current == 80)
        #expect(weight.previous == 79)
        #expect(weight.start == 79)
        #expect(weight.readingCount == 2)

        let fat = all.first { $0.metric == .bodyFatPercent }!
        #expect(fat.current == nil)
        #expect(fat.readingCount == 0)
    }

    @Test("Targets arrive from the snapshot keyed by metric")
    func targetsFromSnapshots() {
        let snapshot = GoalTargetSnapshot(
            effectiveDate: "2026-09-01", goal: .cut,
            bodyCompositionTargets: [.weight: 75, .bodyFatPercent: 15],
            createdAt: Date())
        let map = snapshot.targetMap()
        let all = BodyCompositionProgress.all(from: [], targets: map)

        let weight = all.first { $0.metric == .weight }!
        #expect(weight.target == 75)
        // No target on the snapshot means no target, and the card has to be able
        // to say so — not a default, and not a guess.
        let muscle = all.first { $0.metric == .skeletalMuscleKg }!
        #expect(muscle.target == nil)
        #expect(muscle.statusText == "Nothing recorded yet")
    }
}

/// `YYYY-MM-DD` → a fixed instant, so a test's dates do not move with the clock.
private extension String {
    var date: Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.date(from: self)!
    }
}
