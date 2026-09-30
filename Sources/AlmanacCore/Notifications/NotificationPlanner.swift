import Foundation

/// §14.1's scheduling pass, as one pull-based, idempotent call.
///
/// Takes the real stores, produces the complete set of notifications that
/// should be pending, and returns it. It schedules nothing and reads nothing
/// from `UNUserNotificationCenter`: the app-side `NotificationScheduler`
/// reconciles the OS against what this returns, which is what makes the whole
/// pass testable on Linux and re-runnable without side effects.
///
/// **Why pull-based and not a call site per write path.** §14.1 lists four
/// things that should re-run this pass (app launch, any state-changing log
/// entry, a shift change, prayer times recalculating). Wiring that as four
/// call sites is the pattern `docs/features/fasting.md` records as this repo's
/// known multi-site failure mode: "the seventh path added later will be the
/// one that forgets". So the pass reads current state and is safe to call from
/// anywhere, including a place that has no idea notifications exist — the
/// reconciliation on foreground is then a backstop for state that changed
/// while the app was closed, not the mechanism that keeps the schedule right.
///
/// **Suppression is evaluated per notification, at that notification's own fire
/// instant, and this is not the same thing as evaluating it once for the pass.**
/// `isNightShift` and `isPostShiftSleep` carry their own start/end timestamps,
/// so asking at the fire instant gives the right answer for a notification 30
/// hours out. The other three axes — `isDryFastActive`,
/// `isConfirmedIFActive`, `isReadinessAlreadyFinal` — come from stores with no
/// point-in-time variant, exactly as `NotificationSuppressionContextAssembler`
/// documents, so their value in a 30-hours-out row is the value as of this
/// pass. That is a real limitation and it is not papered over: a fast that
/// starts at 04:00 tomorrow suppresses tomorrow's water reminders only from
/// the pass that observes it, which is the pass that runs when the user opens
/// the app or logs something after Fajr. The spec accepts this by making the
/// pass the unit of work rather than the notification.
public struct NotificationPlanner: @unchecked Sendable {
    /// §14.1 — "Scheduling horizon: Up to 48 hours ahead".
    public static let horizonSeconds: TimeInterval = 48 * 3600
    /// §14.2 — "Default interval: 90 minutes" for water, used when neither
    /// the notification rule nor the hydration settings name one.
    public static let defaultWaterIntervalMinutes = 90
    /// §14.2 — "~60 min before usual meal time".
    public static let contextualHydrationLeadMinutes: Double = 60

    private let db: Database
    private let timeModel: TimeModel
    private let clock: any Clock
    private let rules: NotificationRuleStore
    private let triggers: NotificationTriggerAssembler
    private let suppression: NotificationSuppressionContextAssembler
    private let shifts: ShiftScheduleStore
    private let hydrationSettings: HydrationSettingsStore

    public init(db: Database, timeModel: TimeModel, clock: any Clock = SystemClock()) {
        self.db = db
        self.timeModel = timeModel
        self.clock = clock
        self.rules = NotificationRuleStore(db: db, clock: clock)
        self.triggers = NotificationTriggerAssembler(db: db, timeModel: timeModel)
        self.suppression = NotificationSuppressionContextAssembler(db: db, timeModel: timeModel)
        self.shifts = ShiftScheduleStore(db: db)
        self.hydrationSettings = HydrationSettingsStore(db: db)
    }

    /// The notifications that should be pending as of `now`, for the next
    /// `horizon` seconds. Types whose `notification_rule` row is off
    /// contribute nothing; so does a notification whose type the suppression
    /// matrix suppresses at its own fire instant; so does one whose fire instant
    /// is in the past or beyond the horizon.
    public func plan(asOf now: Date? = nil,
                     horizon: TimeInterval = NotificationPlanner.horizonSeconds) throws -> NotificationPlan {
        let instant = now ?? clock.now
        var candidates: [PlannedNotification] = []

        let days = try daysCovered(from: instant, horizon: horizon)
        for day in days {
            try appendDaily(instant: instant, day: day, horizon: horizon, into: &candidates)
        }

        // Read the facts once for the whole pass rather than once per candidate.
        // Three of Appendix B's five axes cannot vary within a pass, and the two
        // that can are answered from rows already fetched. Without this the pass
        // issued ~7 queries per candidate — around 140 for a 48-hour window, on a
        // pass that runs on every foreground activation. See
        // `NotificationSuppressionContextAssembler.nowOnlyAxes()`.
        let nowOnly = try suppression.nowOnlyAxes()
        let occurrences = try suppression.nightOccurrences(around: instant)
        let postShiftEpisodes = try suppression.postShiftEpisodes(around: instant)

        let kept = candidates.filter { candidate in
            let context = nowOnly.with(
                isNightShift: suppression.isWithinNightShift(at: candidate.fireAt, occurrences: occurrences),
                isPostShiftSleep: suppression.isWithinPostShiftSleep(at: candidate.fireAt,
                                                                      episodes: postShiftEpisodes))
            return !NotificationSuppressionMatrix.shouldSuppress(candidate.type, in: context)
        }

        return NotificationPlan(computedAt: instant, notifications: kept)
    }

    /// §14.2's Contextual: Pre-workout Snack Suggestion, which is the one type
    /// with no scheduled form — the spec computes it "at log time and at app
    /// launch" and gives it no lead time, so it is delivered immediately when
    /// this returns non-nil rather than planned ahead. Nil when the rule is off,
    /// when the matrix suppresses it, or when no workout is far enough from the
    /// last meal.
    public func immediateSnackSuggestion(asOf now: Date? = nil,
                                         thresholdHours: Double = 3) throws -> PlannedNotification? {
        let instant = now ?? clock.now
        guard try rules.isEnabled(.contextualSnack) else { return nil }

        let context = try suppression.context(at: instant)
        guard !NotificationSuppressionMatrix.shouldSuppress(.contextualSnack, in: context) else { return nil }
        guard try triggers.shouldSuggestPreWorkoutSnack(now: instant, thresholdHours: thresholdHours),
              let workout = try PlannedWorkoutStore(db: db).nextUpcoming(after: instant) else { return nil }

        return PlannedNotification(
            identifier: "almanac.contextual_snack.immediate",
            type: .contextualSnack,
            fireAt: instant,
            title: NotificationText.contextualSnackTitle,
            body: NotificationText.contextualSnackBody(
                hoursUntilWorkout: workout.scheduledAt.timeIntervalSince(instant) / 3600))
    }

    // MARK: - Per-type assembly

    private func appendDaily(instant: Date, day: LogicalDay, horizon: TimeInterval,
                             into candidates: inout [PlannedNotification]) throws {
        try appendReadiness(day: day, into: &candidates)
        try appendWater(day: day, into: &candidates)
        try appendBedtime(day: day, into: &candidates)
        try appendSuhoor(day: day, into: &candidates)
        try appendIftar(day: day, into: &candidates)
        try appendMeals(day: day, into: &candidates)
        try appendSupplements(day: day, into: &candidates)
        try appendContextualHydration(day: day, into: &candidates)
    }

    private func appendReadiness(day: LogicalDay, into candidates: inout [PlannedNotification]) throws {
        guard try rules.isEnabled(.readiness), let fireAt = try triggers.readinessTrigger(for: day) else { return }
        candidates.append(PlannedNotification(
            identifier: "almanac.readiness.\(day.value)",
            type: .readiness, fireAt: fireAt,
            title: NotificationText.readinessTitle(shiftType: try shifts.occurrence(for: day.value)?.shiftType),
            body: NotificationText.readinessBody))
    }

    /// Water's on/off is the *conjunction* of two switches, and that is
    /// deliberate. `notification_rule.water` is the spec's own §5.25 default
    /// (on), and `hydration_settings.remindersEnabled` is the toggle the app
    /// already ships and the user already understands. Either one saying off
    /// means off — a user who has turned their water reminders off must not keep
    /// getting them because a schema default disagrees, and there is no third
    /// switch introduced here to arbitrate.
    private func appendWater(day: LogicalDay, into candidates: inout [PlannedNotification]) throws {
        guard try rules.isEnabled(.water) else { return }
        let settings = try hydrationSettings.fetch()
        guard settings?.remindersEnabled ?? true else { return }

        let interval = Double(try rules.rule(for: .water).intervalMinutes
            ?? settings?.reminderIntervalMinutes
            ?? Self.defaultWaterIntervalMinutes)
        for fireAt in try triggers.waterReminderTimes(for: day, intervalMinutes: interval) {
            candidates.append(PlannedNotification(
                identifier: "almanac.water.\(day.value).\(Int(fireAt.timeIntervalSince1970))",
                type: .water, fireAt: fireAt,
                title: NotificationText.waterTitle, body: NotificationText.waterBody))
        }
    }

    private func appendBedtime(day: LogicalDay, into candidates: inout [PlannedNotification]) throws {
        guard try rules.isEnabled(.bedtime), let fireAt = try triggers.bedtimeTrigger(for: day) else { return }
        candidates.append(PlannedNotification(
            identifier: "almanac.bedtime.\(day.value)", type: .bedtime, fireAt: fireAt,
            title: NotificationText.bedtimeTitle, body: NotificationText.bedtimeBody))
    }

    private func appendSuhoor(day: LogicalDay, into candidates: inout [PlannedNotification]) throws {
        guard try rules.isEnabled(.suhoor), let fireAt = try triggers.suhoorTrigger(for: day) else { return }
        // §14.2's body names Fajr's time, so it needs Fajr itself rather than
        // the 20-minutes-before instant the trigger already resolved.
        let fajr = fireAt.addingTimeInterval(20 * 60)
        candidates.append(PlannedNotification(
            identifier: "almanac.suhoor.\(day.value)", type: .suhoor, fireAt: fireAt,
            title: NotificationText.suhoorTitle(fajrText: timeText(fajr)),
            body: NotificationText.suhoorBody(fajrText: timeText(fajr))))
    }

    private func appendIftar(day: LogicalDay, into candidates: inout [PlannedNotification]) throws {
        guard try rules.isEnabled(.iftar), let fireAt = try triggers.iftarTrigger(for: day) else { return }
        candidates.append(PlannedNotification(
            identifier: "almanac.iftar.\(day.value)", type: .iftar, fireAt: fireAt,
            title: NotificationText.iftarTitle, body: NotificationText.iftarBody))
    }

    /// One notification per meal type, because `MealReminderSettingsStore` is
    /// per meal type (Migration029) and a user who sets 07:30 for breakfast has
    /// not thereby set a lunch reminder.
    private func appendMeals(day: LogicalDay, into candidates: inout [PlannedNotification]) throws {
        guard try rules.isEnabled(.meal) else { return }
        for mealType in NutritionMealType.allCases {
            guard let fireAt = try triggers.mealReminderTrigger(for: mealType, on: day) else { continue }
            candidates.append(PlannedNotification(
                identifier: "almanac.meal.\(mealType.rawValue).\(day.value)",
                type: .meal, fireAt: fireAt,
                title: NotificationText.mealTitle(mealType),
                body: NotificationText.mealBody(mealType)))
        }
    }

    private func appendSupplements(day: LogicalDay, into candidates: inout [PlannedNotification]) throws {
        guard try rules.isEnabled(.supplement) else { return }
        for reminder in try triggers.supplementReminderTriggers(on: day) {
            let name = try SupplementPlanStore(db: db).plan(id: reminder.planId)?.name ?? "your supplement"
            candidates.append(PlannedNotification(
                identifier: "almanac.supplement.\(reminder.planId).\(day.value)",
                type: .supplement, fireAt: reminder.time,
                title: NotificationText.supplementTitle(name),
                body: NotificationText.supplementBody))
        }
    }

    private func appendContextualHydration(day: LogicalDay,
                                           into candidates: inout [PlannedNotification]) throws {
        guard try rules.isEnabled(.contextualHydration) else { return }
        for mealType in NutritionMealType.allCases {
            guard let fireAt = try triggers.contextualHydrationTrigger(
                for: mealType, before: day, leadMinutes: Self.contextualHydrationLeadMinutes) else { continue }
            candidates.append(PlannedNotification(
                identifier: "almanac.contextual_hydration.\(mealType.rawValue).\(day.value)",
                type: .contextualHydration, fireAt: fireAt,
                title: NotificationText.contextualHydrationTitle,
                body: NotificationText.contextualHydrationBody(
                    mealType: mealType, leadMinutes: Self.contextualHydrationLeadMinutes)))
        }
    }

    // MARK: - Private

    /// The logical days the horizon touches: today's from `now`, then each
    /// following day. Bounded at three, because a 48-hour horizon from any
    /// instant spans at most three 04:00 boundaries and an unbounded loop over
    /// a `Date` arithmetic bug would otherwise be a hang rather than a wrong
    /// number.
    private func daysCovered(from instant: Date, horizon: TimeInterval) throws -> [LogicalDay] {
        var days: [LogicalDay] = []
        var cursor = timeModel.logicalDay(instant)
        let end = instant.addingTimeInterval(horizon)
        while days.count < 3 {
            days.append(cursor)
            guard let next = timeModel.day(after: cursor),
                  let nextStart = timeModel.start(of: next), nextStart <= end else { break }
            cursor = next
        }
        return days
    }

    private func timeText(_ instant: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeModel.timeZone
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: instant)
    }
}
