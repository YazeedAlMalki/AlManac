import Foundation

/// Plants a few months of lived-in history — water, meals, training, sleep,
/// readiness, vitals, mood, body composition, circumferences, digestion and
/// supplements — so the app can be scrolled as somebody who has used it for a
/// while would see it. Asked for with `-AlmanacSeedDemoHistory <days>`.
///
/// It is for a person looking at the app, not for a test: the values wander
/// (a seeded generator, so the same days get the same numbers), there are rest
/// days and missed days, and the trends point somewhere plausible — weight
/// drifts down, lifts creep up, resting heart rate eases. Gated exactly as
/// `VitalsSeedPlan` is, by a launch argument no ordinary launch carries and by
/// the app's `#if DEBUG` around its only call site.
///
/// Everything is written through the same public stores a person's entries go
/// through, so a seeded row is a real row in every way except who typed it.
///
/// **Once, not authoritative.** Unlike the test plans this one adds rows, and
/// adding them twice would double a day's water. So it does nothing when any
/// training session already exists in the window it would fill.
public struct DemoHistorySeedPlan: Sendable, Hashable {
    public static let launchArgument = "-AlmanacSeedDemoHistory"
    public static let maximumDays = 180

    public let days: Int

    public init?(days: Int) {
        guard (1...Self.maximumDays).contains(days) else { return nil }
        self.days = days
    }

    /// The plan the launch arguments asked for, or nil when they did not ask.
    public static func fromLaunchArguments(_ arguments: [String]) -> DemoHistorySeedPlan? {
        guard let index = arguments.firstIndex(of: launchArgument),
              arguments.indices.contains(index + 1),
              let days = Int(arguments[index + 1].trimmingCharacters(in: .whitespaces)) else { return nil }
        return DemoHistorySeedPlan(days: days)
    }

    /// Plants every day, oldest first, ending with today. Returns the number of
    /// days planted — zero when the window already had history.
    @discardableResult
    public func apply(into db: Database,
                      now: Date = Date(),
                      timeModel: TimeModel = TimeModel(timeZone: .current)) throws -> Int {
        let zone = timeModel.timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone

        // The window, oldest first, today last.
        var window: [LogicalDay] = [timeModel.logicalDay(now)]
        while window.count < days, let earlier = timeModel.day(before: window[0]) {
            window.insert(earlier, at: 0)
        }
        guard let first = window.first, let last = window.last else { return 0 }

        let sessions = WorkoutSessionStore(db: db)
        guard try sessions.sessions(from: first.value, to: last.value).isEmpty else { return 0 }

        // Meals need the food reference. On a first install the app imports it
        // on a background task; doing it here first is idempotent and makes the
        // food refs below resolve either way.
        try NutritionReferenceBundle.installIfNeeded(into: db)
        let foods = try Self.availableFoods(in: db)

        let hydration = HydrationStore(db: db)
        let nutrition = NutritionLogStore(db: db)
        let bouts = WorkoutBoutStore(db: db)
        let catalog = ExerciseCatalogStore(db: db)
        let sleep = SleepEpisodeStore(db: db)
        let vitals = VitalsRecordStore(db: db, zone: ZoneContext(zone), timeModel: timeModel)
        let cycles = ReadinessCycleStore(db: db)
        let readiness = ReadinessRecordStore(db: db)
        let baselines = ReadinessBaselineService(db: db, timeModel: timeModel)
        let mood = MoodLogStore(db: db)
        let body = BodyCompositionMeasurementStore(db: db)
        let circumferences = BodyMeasurementStore(db: db, timeModel: timeModel)
        let bowel = DigestionStore(db: db)
        let urination = UrinationStore(db: db)
        let supplementPlans = SupplementPlanStore(db: db)
        let supplementLogs = SupplementLogStore(db: db)

        let exercises = try Self.exercises(in: catalog)
        let creatine = try supplementPlans.create(SupplementPlanDraft(
            name: "Creatine monohydrate", doseAmount: 5, doseUnit: "g", frequency: "daily",
            timingNotes: "With breakfast"))
        let vitaminD = try supplementPlans.create(SupplementPlanDraft(
            name: "Vitamin D3", doseAmount: 1, doseUnit: "capsule", frequency: "daily"))

        var rng = SeededGenerator(seed: 0xA1_3A_AC)
        let count = window.count

        for (k, day) in window.enumerated() {
            guard let dayStart = timeModel.start(of: day) else { continue }
            let isToday = k == count - 1
            let progress = Double(k) / Double(max(count - 1, 1))  // 0 oldest … 1 today
            let weekday = calendar.component(.weekday, from: dayStart)  // 1 = Sunday
            func at(_ hour: Int, _ minute: Int = 0) -> Date {
                calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayStart) ?? dayStart
            }
            func instant(_ date: Date) -> PartialDateTime {
                PartialDateTime(instant: date, zone: ZoneContext(zone, at: date))
            }
            let offset = zone.secondsFromGMT(for: dayStart) / 60
            // Today stops at the current hour, so nothing is logged in the future.
            let nowHour = isToday ? calendar.component(.hour, from: now) : 24
            func happened(_ hour: Int) -> Bool { hour < nowHour }

            // Sleep, vitals and the morning's readiness score.
            let lateNight = weekday == 6 || weekday == 7 || rng.chance(0.12)
            let asleep = Int(rng.normal(mean: lateNight ? 395 : 440, sd: 30)).clamped(300, 540)
            let wake = at(lateNight ? 8 : 6, rng.int(0...45))
            let bed = wake.addingTimeInterval(-Double(asleep + rng.int(8...25)) * 60)
            try sleep.upsert(
                SleepEpisode(start: bed, end: wake, type: .primary, source: .manual,
                             asleepMinutes: asleep,
                             healthKitUUIDs: ["almanac-demo-sleep-\(day.value)"]),
                timezoneOffset: offset, logicalDay: day.value)
            let rhr = (rng.normal(mean: 61 - 4 * progress, sd: 1.6) + (lateNight ? 2 : 0)).rounded()
            let hrv = (rng.normal(mean: 44 + 10 * progress, sd: 5) - (lateNight ? 5 : 0)).rounded()
            _ = try vitals.recordManual(metric: .restingHeartRate, value: rhr, measuredAt: at(9))
            _ = try vitals.recordManual(metric: .heartRateVariability, value: max(18, hrv), measuredAt: at(9))
            let resolution = try baselines.resolve(for: day)
            let outcome = ReadinessEngine.evaluate(
                state: .provisional,
                inputs: ReadinessInputs(sleepDurationMinutes: asleep, restingHeartRate: rhr,
                                        hrv: max(18, hrv), totalSleepAcrossEpisodesMinutes: asleep),
                baseline: resolution.baseline,
                context: ReadinessContext(calibrationDay: resolution.calibrationDay))
            let cycle = try cycles.ensureCycle(anchorDate: day.value, at: wake)
            try readiness.record(outcome, cycleId: cycle, anchorDate: day.value)

            // A day now and then goes unlogged, as real ones do — but never today.
            if !isToday && rng.chance(0.05) { continue }

            // Water through the day.
            var hour = 7
            while hour < 22 {
                if happened(hour) {
                    let amount = [250.0, 330, 500, 500, 750].randomElement(using: &rng)!
                    _ = try hydration.log(HydrationLogDraft(amount: Milliliters(amount),
                                                            loggedAt: at(hour, rng.int(0...55))))
                }
                hour += rng.int(1...3)
            }

            // Meals.
            for meal in Self.meals(using: &rng) where happened(meal.hour) {
                for item in meal.items {
                    guard let ref = foods[item.ref] else { continue }
                    _ = try nutrition.record(NutritionLogDraft(
                        foodRef: ref, grams: (item.grams * rng.double(0.85...1.15)).rounded(),
                        eatenAt: instant(at(meal.hour, rng.int(0...40))),
                        mealType: meal.type))
                }
            }

            // Training: push Monday, pull Tuesday, legs Thursday, run Saturday.
            let training: TrainingDay? = switch weekday {
            case 2: .push
            case 3: .pull
            case 5: .legs
            case 7: .run
            default: nil
            }
            if let training, happened(18), rng.chance(0.9) {
                let start = at(17, rng.int(30...59))
                let minutes = training == .run ? rng.int(28...45) : rng.int(50...75)
                let rpe = rng.int(6...9)
                let sessionId = try sessions.log(WorkoutSessionDraft(
                    date: day.value, startTimestamp: start,
                    endTimestamp: start.addingTimeInterval(Double(minutes) * 60),
                    durationMinutes: minutes, rpe: rpe,
                    notes: rpe >= 9 ? "Tough one" : nil,
                    sessionType: training == .run ? "running" : "strength"))
                for (index, lift) in training.lifts.enumerated() {
                    guard let id = exercises[lift.exerciseId] else { continue }
                    var draft = WorkoutBoutDraft(sessionId: sessionId, exerciseCatalogId: id,
                                                 sequenceIndex: index, prescriptionType: lift.type,
                                                 rpe: rng.int(6...9))
                    switch lift.type {
                    case "distance":
                        let metres = (rng.double(4.5...7.5) * 1000).rounded()
                        draft.actualDistanceMeters = metres
                        draft.elapsedSeconds = (metres / 1000 * rng.double(320...360)).rounded()
                        draft.avgHeartRate = rng.int(142...162)
                    case "time_under_load":
                        draft.actualSets = 3
                        draft.actualDurationSeconds = Double(rng.int(4...6) * 10 + Int(progress * 20))
                    default:
                        // Linear progress over the window, rounded to the plates a gym has.
                        let load = lift.startKg + (lift.endKg - lift.startKg) * progress
                        draft.prescribedSets = lift.sets
                        draft.prescribedReps = lift.reps
                        draft.actualSets = lift.sets
                        draft.actualReps = lift.reps - (rng.chance(0.15) ? 1 : 0)
                        draft.actualLoadKg = lift.startKg > 0 ? (load / 2.5).rounded() * 2.5 : nil
                    }
                    _ = try bouts.log(draft)
                }
            }

            // How the day felt.
            if happened(21) || (isToday && happened(9)) {
                let score = Int(rng.normal(mean: 6.6 + Double((outcome.score ?? 60) - 60) / 25, sd: 1.1))
                    .clamped(2, 10)
                _ = try mood.log(MoodLogDraft(score: score, timestamp: at(isToday ? 9 : 21),
                                              notes: score <= 4 ? "Low energy" : nil,
                                              timezoneOffset: offset, timezoneID: zone.identifier),
                                 logicalDay: day.value)
            }

            // Weigh-ins most mornings, a full scan on Sundays.
            if rng.chance(0.75) || weekday == 1 {
                let weight = rng.normal(mean: 84.5 - 3.8 * progress, sd: 0.35)
                _ = try body.log(BodyCompositionMeasurementDraft(
                    metric: BodyMetric.weight.id, value: (weight * 10).rounded() / 10,
                    unit: BodyMetric.weight.unit, timestamp: at(7, 15), source: "manual",
                    conditions: "fasted", timezoneOffset: offset, timezoneIdentifier: zone.identifier),
                    logicalDay: day.value)
                if weekday == 1 {
                    let fat = rng.normal(mean: 21.5 - 3 * progress, sd: 0.3)
                    _ = try body.log(BodyCompositionMeasurementDraft(
                        metric: BodyMetric.bodyFatPercent.id, value: (fat * 10).rounded() / 10,
                        unit: BodyMetric.bodyFatPercent.unit, timestamp: at(7, 20), source: "manual",
                        conditions: "fasted", timezoneOffset: offset, timezoneIdentifier: zone.identifier),
                        logicalDay: day.value)
                    let muscle = rng.normal(mean: 36.2 + 0.8 * progress, sd: 0.15)
                    _ = try body.log(BodyCompositionMeasurementDraft(
                        metric: BodyMetric.skeletalMuscleKg.id, value: (muscle * 10).rounded() / 10,
                        unit: BodyMetric.skeletalMuscleKg.unit, timestamp: at(7, 20), source: "manual",
                        conditions: "fasted", timezoneOffset: offset, timezoneIdentifier: zone.identifier),
                        logicalDay: day.value)
                }
            }

            // Tape measurements every other Sunday.
            if weekday == 1 && (k / 7) % 2 == 0 {
                let tape: [(BodyMeasurementType, Double)] = [
                    (.waist, 91 - 4.5 * progress), (.chest, 104 - 1 * progress),
                    (.hips, 101 - 2 * progress), (.arm, 36 + 0.8 * progress),
                    (.thigh, 59 - 0.5 * progress),
                ]
                // No side: a side is refused unless the profile tracks sides.
                for (type, value) in tape {
                    _ = try circumferences.log(BodyMeasurementDraft(
                        measuredAt: at(7, 30), measurementType: type,
                        valueCm: (rng.normal(mean: value, sd: 0.3) * 10).rounded() / 10))
                }
            }

            // Digestion.
            if happened(8) && rng.chance(0.85) {
                let bristol = [3, 4, 4, 4, 4, 5, 3, 6].randomElement(using: &rng)!
                _ = try bowel.log(BowelMovementDraft(timestamp: at(8, rng.int(0...50)),
                                                     bristolType: BristolType(rawValue: bristol) ?? .type4),
                                  logicalDay: day.value)
            }
            for hour in [9, 13, 17] where happened(hour) && rng.chance(0.6) {
                let grade = [2, 2, 3, 3, 3, 4].randomElement(using: &rng)!
                _ = try urination.log(UrinationDraft(timestamp: at(hour, rng.int(0...50)),
                                                     colorGrade: UrinationColorGrade(rawValue: grade) ?? .grade3),
                                      logicalDay: day.value)
            }

            // Supplements, usually remembered.
            if happened(8) && rng.chance(0.9) {
                _ = try supplementLogs.log(SupplementLogDraft(planId: creatine, timestamp: at(8, 10)),
                                           logicalDay: day.value)
            }
            if happened(8) && rng.chance(0.8) {
                _ = try supplementLogs.log(SupplementLogDraft(planId: vitaminD, timestamp: at(8, 10)),
                                           logicalDay: day.value)
            }
        }
        return count
    }

    // MARK: - Content

    private enum TrainingDay {
        case push, pull, legs, run

        var lifts: [Lift] {
            switch self {
            case .push: [
                Lift("exercise-bench-press", sets: 4, reps: 6, from: 70, to: 82.5),
                Lift("exercise-overhead-press", sets: 3, reps: 8, from: 40, to: 47.5),
                Lift("exercise-incline-bench-press", sets: 3, reps: 10, from: 55, to: 62.5),
                Lift("exercise-close-grip-bench-press", sets: 3, reps: 10, from: 50, to: 57.5),
            ]
            case .pull: [
                Lift("exercise-deadlift", sets: 3, reps: 5, from: 120, to: 142.5),
                Lift("exercise-pull-up", type: "reps_bodyweight", sets: 4, reps: 8, from: 0, to: 0),
                Lift("exercise-barbell-row", sets: 4, reps: 8, from: 60, to: 70),
                Lift("exercise-bicep-curl", sets: 3, reps: 12, from: 12.5, to: 15),
            ]
            case .legs: [
                Lift("exercise-squat", sets: 4, reps: 6, from: 95, to: 115),
                Lift("exercise-romanian-deadlift", sets: 3, reps: 8, from: 80, to: 92.5),
                Lift("exercise-bulgarian-split-squat", sets: 3, reps: 10, from: 16, to: 22.5),
                Lift("exercise-leg-curl", sets: 3, reps: 12, from: 35, to: 42.5),
                Lift("exercise-plank", type: "time_under_load", sets: 3, reps: 0, from: 0, to: 0),
            ]
            case .run: [
                Lift("exercise-running", type: "distance", sets: 0, reps: 0, from: 0, to: 0),
            ]
            }
        }
    }

    private struct Lift {
        let exerciseId: String
        let type: String
        let sets: Int
        let reps: Int
        let startKg: Double
        let endKg: Double

        init(_ exerciseId: String, type: String = "reps_load", sets: Int, reps: Int,
             from startKg: Double, to endKg: Double) {
            self.exerciseId = exerciseId
            self.type = type
            self.sets = sets
            self.reps = reps
            self.startKg = startKg
            self.endKg = endKg
        }
    }

    private struct Meal {
        let type: NutritionMealType
        let hour: Int
        let items: [(ref: String, grams: Double)]
    }

    private static let breakfasts: [[(ref: String, grams: Double)]] = [
        [("usda:2346396", 60), ("usda:170894", 170), ("usda:173944", 120)],
        [("usda:172187", 150), ("usda:172689", 70), ("usda:171705", 70)],
        [("usda:170894", 200), ("usda:2346396", 45), ("usda:168191", 30)],
    ]
    private static let lunches: [[(ref: String, grams: Double)]] = [
        [("usda:171477", 160), ("usda:169753", 200), ("usda:169967", 120)],
        [("usda:172421", 200), ("usda:172688", 60), ("usda:170457", 120)],
        [("usda:174289", 90), ("usda:172688", 80), ("usda:171477", 120)],
    ]
    private static let dinners: [[(ref: String, grams: Double)]] = [
        [("usda:174034", 150), ("usda:169737", 220), ("usda:170457", 100)],
        [("usda:171477", 180), ("usda:170093", 250), ("usda:169967", 150)],
        [("usda:174034", 130), ("usda:169753", 220), ("usda:171705", 60)],
    ]
    private static let snacks: [[(ref: String, grams: Double)]] = [
        [("usda:171688", 180)],
        [("cofid:14-896", 30)],
        [("usda:174294", 32), ("usda:173944", 110)],
        [("usda:168191", 48)],
    ]

    private static func meals(using rng: inout SeededGenerator) -> [Meal] {
        var meals = [
            Meal(type: .breakfast, hour: 8, items: breakfasts.randomElement(using: &rng)!),
            Meal(type: .lunch, hour: 13, items: lunches.randomElement(using: &rng)!),
            Meal(type: .dinner, hour: 19, items: dinners.randomElement(using: &rng)!),
        ]
        if rng.chance(0.7) {
            meals.insert(Meal(type: .snack, hour: 16, items: snacks.randomElement(using: &rng)!), at: 2)
        }
        return meals
    }

    private static func availableFoods(in db: Database) throws -> [String: SourceIdentifier] {
        let wanted = Set((breakfasts + lunches + dinners + snacks).flatMap { $0.map(\.ref) })
        let placeholders = Array(repeating: "?", count: wanted.count).joined(separator: ",")
        let rows = try db.query("SELECT food_ref FROM nutrition_food WHERE food_ref IN (\(placeholders));",
                                wanted.sorted().map { .text($0) })
        var found: [String: SourceIdentifier] = [:]
        for row in rows {
            if let text = row.string("food_ref"), let ref = SourceIdentifier(parsing: text) {
                found[text] = ref
            }
        }
        return found
    }

    private static func exercises(in catalog: ExerciseCatalogStore) throws -> [String: Int64] {
        let ids = [TrainingDay.push, .pull, .legs, .run].flatMap { $0.lifts.map(\.exerciseId) }
        var found: [String: Int64] = [:]
        for id in ids {
            if let entry = try catalog.exercise(sourceId: "workout-guide", exerciseId: id) {
                found[id] = entry.id
            }
        }
        return found
    }
}

/// SplitMix64: deterministic, so the same plan plants the same history.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func chance(_ p: Double) -> Bool { Double.random(in: 0..<1, using: &self) < p }
    mutating func int(_ range: ClosedRange<Int>) -> Int { Int.random(in: range, using: &self) }
    mutating func double(_ range: ClosedRange<Double>) -> Double { Double.random(in: range, using: &self) }

    /// Box–Muller.
    mutating func normal(mean: Double, sd: Double) -> Double {
        let u1 = max(Double.random(in: 0..<1, using: &self), .leastNonzeroMagnitude)
        let u2 = Double.random(in: 0..<1, using: &self)
        return mean + sd * (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}

private extension Int {
    func clamped(_ low: Int, _ high: Int) -> Int { Swift.min(Swift.max(self, low), high) }
}
