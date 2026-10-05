import Testing
import Foundation
@testable import AlmanacCore

/// `NotificationPlanner` end to end against real stores: the trigger rules,
/// the per-type switches, and Appendix B's suppression — all three arriving at
/// one plan. The assemblers beneath it are covered on their own; what is
/// untested anywhere else is that the wiring between them does the right thing.
@Suite("NotificationPlanner Tests")
struct NotificationPlannerTests {
    let db: Database
    let timeModel = TimeModel(timeZone: TimeZone(identifier: "Asia/Riyadh")!)
    let day = LogicalDay("2025-09-18")

    /// 2025-09-18 06:00:00 Riyadh. Before the day's Fajr, so a dry fast started
    /// at Fajr is not yet active at `now` — the suhoor case depends on that.
    let now = Date(timeIntervalSince1970: 1_758_164_400)

    init() throws {
        db = try TestDatabase()
    }

    private var planner: NotificationPlanner {
        NotificationPlanner(db: db, timeModel: timeModel, clock: FixedClock(now))
    }

    private var rules: NotificationRuleStore { NotificationRuleStore(db: db) }

    // MARK: - Helpers

    private func riyadh(_ hour: Int, _ minute: Int = 0, day dateString: String = "2025-09-18") -> Date {
        let bits = dateString.split(separator: "-").compactMap { Int($0) }
        var comps = DateComponents()
        comps.year = bits[0]; comps.month = bits[1]; comps.day = bits[2]
        comps.hour = hour; comps.minute = minute
        comps.timeZone = timeModel.timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeModel.timeZone
        return calendar.date(from: comps)!
    }

    private func allSixTimes(fajr: Date, maghrib: Date) -> [PrayerTime] {
        [
            PrayerTime(name: "fajr", timestamp: fajr),
            PrayerTime(name: "sunrise", timestamp: fajr.addingTimeInterval(3600)),
            PrayerTime(name: "dhuhr", timestamp: fajr.addingTimeInterval(7 * 3600)),
            PrayerTime(name: "asr", timestamp: fajr.addingTimeInterval(10 * 3600)),
            PrayerTime(name: "maghrib", timestamp: maghrib),
            PrayerTime(name: "isha", timestamp: maghrib.addingTimeInterval(3600))
        ]
    }

    @discardableResult
    private func logDayShift(wake: Date, sleepStart: Date, type: ShiftType = .day) throws -> Int64 {
        let id = try ShiftScheduleStore(db: db).createSchedule(ShiftScheduleDraft(name: "Schedule"))
        try ShiftScheduleStore(db: db).logOccurrence(ShiftOccurrenceDraft(
            scheduleId: id, date: day.value, shiftType: type,
            expectedSleepWindowStart: sleepStart, expectedWakeTime: wake))
        return id
    }

    private func planned(_ plan: NotificationPlan, _ type: NotificationType) -> [PlannedNotification] {
        plan.notifications.filter { $0.type == type }
    }

    /// The same, narrowed to the anchor day. Several types legitimately fire on
    /// every day the 48-hour horizon touches, so a count assertion about "the
    /// meal notification" means this day's one. Matched on the day being one of
    /// the identifier's dot-separated components rather than a suffix, because
    /// water carries an extra per-fire-time component after the day.
    private func planned(_ plan: NotificationPlan, _ type: NotificationType, on target: LogicalDay) -> [PlannedNotification] {
        planned(plan, type).filter {
            $0.identifier.split(separator: ".").map(String.init).contains(target.value)
        }
    }

    // MARK: - Per-type wiring

    @Test("A day shift's wake and sleep window produce water, bedtime and readiness")
    func dayShiftProducesItsThreeTypes() throws {
        try logDayShift(wake: riyadh(7), sleepStart: riyadh(23))
        try MealReminderSettingsStore(db: db).setReminder(for: .breakfast, enabled: true,
                                                            reminderMinuteOfDay: 7 * 60 + 30)
        try rules.setEnabled(true, for: .meal)
        try rules.setEnabled(true, for: .bedtime)

        let plan = try planner.plan()
        #expect(planned(plan, .readiness, on: day).map(\.fireAt) == [riyadh(7)])
        #expect(planned(plan, .bedtime, on: day).map(\.fireAt) == [riyadh(22, 30)])
        #expect(planned(plan, .meal, on: day).map(\.fireAt) == [riyadh(7, 30)])
        // 07:00 wake to 21:00 (23:00 minus two hours), every 90 minutes.
        #expect(planned(plan, .water, on: day).map(\.fireAt)
                == [riyadh(8, 30), riyadh(10), riyadh(11, 30), riyadh(13), riyadh(14, 30),
                    riyadh(16), riyadh(17, 30), riyadh(19), riyadh(20, 30)])
    }

    @Test("A fast day with cached prayer times produces suhoor and iftar, and nothing else fasting-shaped")
    func fastDayProducesSuhoorAndIftar() throws {
        let fajr = riyadh(4, 30)
        let maghrib = riyadh(18, 5)
        try PrayerTimeCacheStore(db: db).upsert(
            date: day.value, times: allSixTimes(fajr: fajr, maghrib: maghrib),
            latitude: 24.7136, longitude: 46.6753, calculationMethod: "umm_al_qura")
        try ReligiousFastScheduleStore(db: db).createSchedule(
            scheduleType: "ramadan", startGregorianDate: day.value, endGregorianDate: day.value)

        let plan = try planner.plan()
        let suhoor = planned(plan, .suhoor)
        #expect(suhoor.count == 1)
        #expect(suhoor.first?.fireAt == fajr.addingTimeInterval(-20 * 60))
        // Rendered the way the planner renders it — in the device's locale, so
        // "4:30 AM" in English and "٤:٣٠ ص" in Arabic. Only the day key is pinned.
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeModel.timeZone
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let fajrText = formatter.string(from: fajr)
        #expect(suhoor.first?.body.contains(fajrText) == true, "the body names Fajr's time")

        let iftar = planned(plan, .iftar)
        #expect(iftar.map(\.fireAt) == [maghrib])
    }

    @Test("No fast schedule means no suhoor and no iftar even with cached prayer times")
    func noFastScheduleNoSuhoorOrIftar() throws {
        try PrayerTimeCacheStore(db: db).upsert(
            date: day.value, times: allSixTimes(fajr: riyadh(4, 30), maghrib: riyadh(18)),
            latitude: 24.7136, longitude: 46.6753, calculationMethod: "umm_al_qura")

        let plan = try planner.plan()
        #expect(planned(plan, .suhoor).isEmpty)
        #expect(planned(plan, .iftar).isEmpty)
    }

    @Test("Each meal type gets its own notification, and only the ones with a time set")
    func oneNotificationPerMealType() throws {
        for mealType in NutritionMealType.allCases {
            try MealReminderSettingsStore(db: db).setReminder(for: mealType, enabled: true,
                                                                reminderMinuteOfDay: 9 * 60)
        }
        try rules.setEnabled(true, for: .meal)

        let meals = planned(try planner.plan(), .meal, on: day)
        #expect(meals.count == 4, "one per meal type")
        #expect(Set(meals.map(\.identifier)).count == 4, "each with its own identifier, not one shared")
        #expect(meals.allSatisfy { $0.fireAt == riyadh(9) })
    }

    @Test("A meal type with no time set contributes no notification of its own")
    func unsetMealTypeContributesNothing() throws {
        try MealReminderSettingsStore(db: db).setReminder(for: .breakfast, enabled: true,
                                                            reminderMinuteOfDay: 9 * 60)
        try rules.setEnabled(true, for: .meal)

        let meals = planned(try planner.plan(), .meal, on: day)
        #expect(meals.map(\.identifier) == ["almanac.meal.breakfast.\(day.value)"])
    }

    @Test("An active supplement plan contributes one notification named after it")
    func supplementNamedAfterPlan() throws {
        let planStore = SupplementPlanStore(db: db)
        let id = try planStore.create(SupplementPlanDraft(name: "Vitamin D", doseAmount: 2000,
                                                          doseUnit: "iu", frequency: "daily"))
        try planStore.setReminder(id: id, enabled: true, reminderMinuteOfDay: 8 * 60)
        try rules.setEnabled(true, for: .supplement)

        let supplements = planned(try planner.plan(), .supplement, on: day)
        #expect(supplements.count == 1)
        #expect(supplements.first?.fireAt == riyadh(8))
        #expect(supplements.first?.title == "Time for Vitamin D")
    }

    @Test("Contextual hydration fires before a meal type the user actually eats")
    func contextualHydrationFromLoggedHistory() throws {
        let food = SourceIdentifier(namespace: .almanac, localID: "test-food")
        let log = NutritionLogStore(db: db, clock: FixedClock(riyadh(10, day: "2025-09-12")),
                                    zone: ZoneContext(timeModel.timeZone))
        for (dateString, text) in [("2025-09-12", "2025-09-12T12:00:00+03:00"),
                                   ("2025-09-13", "2025-09-13T12:00:00+03:00")] {
            _ = dateString
            try log.record(NutritionLogDraft(
                foodRef: food,
                eatenAt: PartialDateTime(text: text, precision: .instant,
                                         zone: ZoneContext(offsetMinutes: 180)),
                mealType: .lunch))
        }
        try rules.setEnabled(true, for: .contextualHydration)

        let hydration = planned(try planner.plan(), .contextualHydration, on: day)
        #expect(hydration.count == 1)
        #expect(hydration.first?.fireAt == riyadh(11))
    }

    // MARK: - Per-type switches

    @Test("A type whose rule is off contributes nothing, whatever its trigger would have been")
    func offTypesContributeNothing() throws {
        try logDayShift(wake: riyadh(7), sleepStart: riyadh(23))
        try MealReminderSettingsStore(db: db).setReminder(for: .breakfast, enabled: true,
                                                            reminderMinuteOfDay: 7 * 60 + 30)

        let plan = try planner.plan()
        // §5.25 defaults: meal, bedtime and supplement all start off.
        #expect(planned(plan, .meal).isEmpty)
        #expect(planned(plan, .bedtime).isEmpty)
        #expect(planned(plan, .supplement).isEmpty)
        // Water and readiness are on by default and do come through.
        #expect(!planned(plan, .water).isEmpty)
        #expect(planned(plan, .readiness).count == 1)
    }

    @Test("Turning water off in hydration settings silences it even though the notification rule is on")
    func hydrationSettingsSilenceWater() throws {
        try logDayShift(wake: riyadh(7), sleepStart: riyadh(23))
        #expect(try rules.isEnabled(.water))

        var settings = try HydrationSettingsStore(db: db).getOrCreate()
        settings = HydrationSettings(isCalorieTrackingEnabled: settings.isCalorieTrackingEnabled,
                                    isDoubleTrackWarningEnabled: settings.isDoubleTrackWarningEnabled,
                                    remindersEnabled: false,
                                    reminderIntervalMinutes: settings.reminderIntervalMinutes,
                                    reminderStartHour: settings.reminderStartHour,
                                    reminderEndHour: settings.reminderEndHour,
                                    dailyGoalMilliliters: settings.dailyGoalMilliliters,
                                    trackSodium: settings.trackSodium, trackSugar: settings.trackSugar,
                                    updatedAt: settings.updatedAt)
        try HydrationSettingsStore(db: db).save(settings)

        #expect(try planner.plan().notifications.filter { $0.type == .water }.isEmpty)
    }

    private func saveHydrationReminders(enabled: Bool, intervalMinutes: Int) throws {
        let settings = try HydrationSettingsStore(db: db).getOrCreate()
        try HydrationSettingsStore(db: db).save(HydrationSettings(
            isCalorieTrackingEnabled: settings.isCalorieTrackingEnabled,
            isDoubleTrackWarningEnabled: settings.isDoubleTrackWarningEnabled,
            remindersEnabled: enabled, reminderIntervalMinutes: intervalMinutes,
            reminderStartHour: settings.reminderStartHour, reminderEndHour: settings.reminderEndHour,
            dailyGoalMilliliters: settings.dailyGoalMilliliters,
            trackSodium: settings.trackSodium, trackSugar: settings.trackSugar,
            updatedAt: settings.updatedAt))
    }

    private func waterTimes(asOf now: Date? = nil) throws -> [Date] {
        try planner.plan(asOf: now).notifications.filter { $0.type == .water }.map(\.fireAt)
    }

    @Test("The notification rule's own interval wins over the hydration reminder's")
    func ruleIntervalWins() throws {
        try logDayShift(wake: riyadh(7), sleepStart: riyadh(23))
        try saveHydrationReminders(enabled: true, intervalMinutes: 120)
        try rules.setRule(NotificationRule(type: .water, isEnabled: true, intervalMinutes: 60))

        #expect(try waterTimes() == [riyadh(8), riyadh(9), riyadh(10), riyadh(11), riyadh(12),
                                     riyadh(13), riyadh(14), riyadh(15), riyadh(16), riyadh(17),
                                     riyadh(18), riyadh(19), riyadh(20), riyadh(21)])
    }

    @Test("The hydration reminder's interval is used when the notification rule names none")
    func hydrationIntervalUsedWhenRuleSilent() throws {
        try logDayShift(wake: riyadh(7), sleepStart: riyadh(23))
        try saveHydrationReminders(enabled: true, intervalMinutes: 120)

        #expect(try waterTimes().first == riyadh(9), "07:00 wake plus two hours")
    }

    @Test("The spec's 90-minute default applies only when neither source names an interval")
    func specDefaultIsTheLastResort() throws {
        try logDayShift(wake: riyadh(7), sleepStart: riyadh(23))
        // No hydration_settings row at all, so `fetch()` is nil and the spec's
        // own default is what is left.
        #expect(try HydrationSettingsStore(db: db).fetch() == nil)
        #expect(try waterTimes().first == riyadh(8, 30))
    }

    // MARK: - Suppression, per fire instant

    @Test("An active dry fast suppresses today's water reminders")
    func dryFastSuppressesWater() throws {
        try logDayShift(wake: riyadh(7), sleepStart: riyadh(23))
        try FastingSessionStore(db: db).start(
            FastingSessionDraft(startTimestamp: now.addingTimeInterval(-3600), sessionType: .religious,
                                 isDryFast: true), logicalDay: day.value)

        #expect(try planner.plan().notifications.filter { $0.type == .water }.isEmpty)
    }

    @Test("A confirmed IF session suppresses meal and snack reminders but not water or bedtime")
    func confirmedIFSuppressesMeals() throws {
        try logDayShift(wake: riyadh(7), sleepStart: riyadh(23), type: .evening)
        try MealReminderSettingsStore(db: db).setReminder(for: .breakfast, enabled: true,
                                                            reminderMinuteOfDay: 7 * 60 + 30)
        try rules.setEnabled(true, for: .meal)
        try FastingSessionStore(db: db).start(
            FastingSessionDraft(startTimestamp: now.addingTimeInterval(-3600), sessionType: .ifPlanned,
                                 isDryFast: false), logicalDay: day.value)

        try rules.setEnabled(true, for: .bedtime)
        let plan = try planner.plan()
        #expect(planned(plan, .meal, on: day).isEmpty, "Appendix B: meal is suppressed during confirmed IF")
        #expect(planned(plan, .bedtime, on: day).count == 1, "Appendix B: bedtime is sent during confirmed IF")
        #expect(!planned(plan, .water).isEmpty, "Appendix B: water is sent during confirmed IF")
    }

    @Test("A night shift suppresses bedtime but not readiness or water")
    func nightShiftSuppressesBedtimeOnly() throws {
        let scheduleId = try ShiftScheduleStore(db: db).createSchedule(ShiftScheduleDraft(name: "Nights"))
        try ShiftScheduleStore(db: db).logOccurrence(ShiftOccurrenceDraft(
            scheduleId: scheduleId, date: day.value, shiftType: .night,
            shiftStartTime: riyadh(19), shiftEndTime: riyadh(23, 30),
            expectedSleepWindowStart: riyadh(23), expectedWakeTime: riyadh(7)))
        try rules.setEnabled(true, for: .bedtime)

        let plan = try planner.plan()
        #expect(planned(plan, .bedtime, on: day).isEmpty, "Appendix B: bedtime is suppressed on a night shift")
        #expect(planned(plan, .readiness, on: day).count == 1, "Appendix B: readiness is sent on a night shift")
        #expect(!planned(plan, .water, on: day).isEmpty)
    }

    @Test("Suppression is evaluated at each notification's own fire instant, not once for the pass")
    func suppressionIsPerFireInstant() throws {
        // The night shift runs 19:00–23:30 today, so tonight's 22:30 bedtime is
        // inside it and tomorrow's is not. A pass-wide suppression decision
        // would get one of those two wrong; asking per fire instant gets both.
        let scheduleId = try ShiftScheduleStore(db: db).createSchedule(ShiftScheduleDraft(name: "Nights"))
        try ShiftScheduleStore(db: db).logOccurrence(ShiftOccurrenceDraft(
            scheduleId: scheduleId, date: day.value, shiftType: .night,
            shiftStartTime: riyadh(19), shiftEndTime: riyadh(23, 30),
            expectedSleepWindowStart: riyadh(23), expectedWakeTime: riyadh(7)))
        let tomorrow = LogicalDay("2025-09-19")
        try ShiftScheduleStore(db: db).logOccurrence(ShiftOccurrenceDraft(
            scheduleId: scheduleId, date: tomorrow.value, shiftType: .day,
            expectedSleepWindowStart: riyadh(23, day: tomorrow.value),
            expectedWakeTime: riyadh(7, day: tomorrow.value)))
        try rules.setEnabled(true, for: .bedtime)

        let plan = try planner.plan()
        #expect(planned(plan, .bedtime, on: day).isEmpty, "22:30 tonight is inside the night shift")
        #expect(planned(plan, .bedtime, on: tomorrow).map(\.fireAt) == [riyadh(22, 30, day: tomorrow.value)],
                "22:30 tomorrow is a day shift, so it is sent")
    }

    @Test("Post-shift sleep suppresses readiness, water, meal, bedtime and supplements")
    func postShiftSleepSuppressesNearlyEverything() throws {
        try logDayShift(wake: riyadh(7), sleepStart: riyadh(23), type: .night)
        try MealReminderSettingsStore(db: db).setReminder(for: .breakfast, enabled: true,
                                                            reminderMinuteOfDay: 7 * 60 + 30)
        try rules.setEnabled(true, for: .meal)
        try rules.setEnabled(true, for: .supplement)
        let planStore = SupplementPlanStore(db: db)
        let id = try planStore.create(SupplementPlanDraft(name: "Iron", doseAmount: 1,
                                                          doseUnit: "capsule", frequency: "daily"))
        try planStore.setReminder(id: id, enabled: true, reminderMinuteOfDay: 8 * 60)

        // An episode that spans the whole of today's plan window, so every one
        // of today's candidate fire instants falls inside it.
        try SleepEpisodeStore(db: db).upsert(
            SleepEpisode(start: now.addingTimeInterval(-3600), end: riyadh(23, 59),
                         type: .postShift, source: .healthkit, asleepMinutes: 600),
            timezoneOffset: 180, logicalDay: day.value)

        let plan = try planner.plan()
        for type in [NotificationType.readiness, .water, .meal, .bedtime, .supplement] {
            #expect(planned(plan, type, on: day).isEmpty,
                    "\(type) should be suppressed during post-shift sleep")
        }
    }

    @Test("A final readiness record suppresses the readiness notification")
    func finalReadinessSuppressesReadiness() throws {
        try logDayShift(wake: riyadh(7), sleepStart: riyadh(23))
        let cycleId = try ReadinessCycleStore(db: db).createCycle(anchorDate: day.value)
        let outcome = ReadinessOutcome(state: .final, score: 72, color: .green, textDescription: nil,
                                       confidence: .high, missingInputs: [], formulaVersion: "1.0",
                                       inputSnapshot: "{}", recommendation: nil, precedenceApplied: [],
                                       baselineContext: .general)
        try ReadinessRecordStore(db: db).record(outcome, cycleId: cycleId, anchorDate: day.value)

        let plan = try planner.plan()
        #expect(planned(plan, .readiness, on: day).isEmpty)
        #expect(!planned(plan, .water, on: day).isEmpty, "and nothing else")
    }

    // MARK: - Horizon and shape

    @Test("Nothing already in the past is planned")
    func pastTriggersAreDropped() throws {
        // Yesterday's shift, so both its fire instants are behind `now`.
        let yesterday = "2025-09-17"
        let scheduleId = try ShiftScheduleStore(db: db).createSchedule(ShiftScheduleDraft(name: "Schedule"))
        try ShiftScheduleStore(db: db).logOccurrence(ShiftOccurrenceDraft(
            scheduleId: scheduleId, date: yesterday, shiftType: .day,
            expectedSleepWindowStart: riyadh(23, day: yesterday),
            expectedWakeTime: riyadh(7, day: yesterday)))

        let plan = try planner.plan()
        for notification in plan.notifications {
            #expect(notification.fireAt >= now, "\(notification.identifier) is in the past")
        }
    }

    @Test("Two runs over unchanged state produce the same plan")
    func planIsStable() throws {
        try logDayShift(wake: riyadh(7), sleepStart: riyadh(23))
        let first = try planner.plan()
        let second = try planner.plan()
        #expect(first == second)
    }

    @Test("Identifiers are unique, and every one is namespaced to the app")
    func identifiersAreUniqueAndNamespaced() throws {
        try logDayShift(wake: riyadh(7), sleepStart: riyadh(23))
        try MealReminderSettingsStore(db: db).setReminder(for: .breakfast, enabled: true,
                                                            reminderMinuteOfDay: 7 * 60 + 30)
        try rules.setEnabled(true, for: .meal)

        let identifiers = try planner.plan().notifications.map(\.identifier)
        #expect(Set(identifiers).count == identifiers.count)
        #expect(identifiers.allSatisfy { $0.hasPrefix("almanac.") })
    }

    @Test("The plan is empty, not broken, on a database with nothing logged at all")
    func emptyDatabasePlansNothing() throws {
        let plan = try planner.plan()
        #expect(plan.notifications.isEmpty)
        #expect(plan.computedAt == now)
    }

    @Test("A 48-hour horizon covers three logical days and never a fourth")
    func horizonIsBounded() throws {
        // Shifts on the 17th through the 21st, so the pass has more days
        // available than it is allowed to reach.
        for offset in 0...4 {
            let future = LogicalDay(String(format: "2025-09-%02d", 17 + offset))
            let scheduleId = try ShiftScheduleStore(db: db).createSchedule(ShiftScheduleDraft(name: "S\(offset)"))
            try ShiftScheduleStore(db: db).logOccurrence(ShiftOccurrenceDraft(
                scheduleId: scheduleId, date: future.value, shiftType: .day,
                expectedSleepWindowStart: riyadh(23, day: future.value),
                expectedWakeTime: riyadh(7, day: future.value)))
        }

        let days = readinessDays(in: try planner.plan())
        // 06:00 on the 18th plus 48 hours is 06:00 on the 20th, which is inside
        // the 20th's own logical day. Three days is therefore the true maximum,
        // and the three-day bound in `daysCovered` is exactly that rather than
        // an arbitrary truncation.
        #expect(days == ["2025-09-18", "2025-09-19", "2025-09-20"])
    }

    @Test("A shorter horizon covers fewer days")
    func horizonIsRespected() throws {
        for offset in 0...2 {
            let future = LogicalDay(String(format: "2025-09-%02d", 18 + offset))
            let scheduleId = try ShiftScheduleStore(db: db).createSchedule(ShiftScheduleDraft(name: "S\(offset)"))
            try ShiftScheduleStore(db: db).logOccurrence(ShiftOccurrenceDraft(
                scheduleId: scheduleId, date: future.value, shiftType: .day,
                expectedSleepWindowStart: riyadh(23, day: future.value),
                expectedWakeTime: riyadh(7, day: future.value)))
        }

        // Six hours from 06:00 reaches 12:00, so only today qualifies.
        #expect(readinessDays(in: try planner.plan(horizon: 6 * 3600)) == ["2025-09-18"])
    }

    private func readinessDays(in plan: NotificationPlan) -> [String] {
        plan.notifications.filter { $0.type == .readiness }
            .compactMap { $0.identifier.split(separator: ".").last.map(String.init) }
            .sorted()
    }

    // MARK: - Immediate suggestion

    @Test("The pre-workout snack suggestion is delivered now, not scheduled ahead")
    func snackSuggestionIsImmediate() throws {
        let food = SourceIdentifier(namespace: .almanac, localID: "test-food")
        let log = NutritionLogStore(db: db, clock: FixedClock(now), zone: ZoneContext(timeModel.timeZone))
        try log.record(NutritionLogDraft(
            foodRef: food,
            eatenAt: PartialDateTime(text: "2025-09-18T04:00:00+03:00", precision: .instant,
                                     zone: ZoneContext(offsetMinutes: 180)),
            mealType: .lunch))
        try PlannedWorkoutStore(db: db).create(PlannedWorkoutDraft(scheduledAt: riyadh(13)))
        try rules.setEnabled(true, for: .contextualSnack)

        let suggestion = try planner.immediateSnackSuggestion()
        #expect(suggestion?.type == .contextualSnack)
        #expect(suggestion?.fireAt == now)
        #expect(suggestion?.body.contains("7.0 hours") == true)
    }

    @Test("The snack suggestion is nil while its rule is off, even when the gap is large")
    func snackSuggestionRespectsItsRule() throws {
        let food = SourceIdentifier(namespace: .almanac, localID: "test-food")
        let log = NutritionLogStore(db: db, clock: FixedClock(now), zone: ZoneContext(timeModel.timeZone))
        try log.record(NutritionLogDraft(
            foodRef: food,
            eatenAt: PartialDateTime(text: "2025-09-18T04:00:00+03:00", precision: .instant,
                                     zone: ZoneContext(offsetMinutes: 180)),
            mealType: .lunch))
        try PlannedWorkoutStore(db: db).create(PlannedWorkoutDraft(scheduledAt: riyadh(13)))
        #expect(try planner.immediateSnackSuggestion() == nil, "§5.25 seeds contextual_snack off")
    }

    @Test("The snack suggestion is suppressed during a confirmed fast")
    func snackSuggestionSuppressedDuringFast() throws {
        let food = SourceIdentifier(namespace: .almanac, localID: "test-food")
        let log = NutritionLogStore(db: db, clock: FixedClock(now), zone: ZoneContext(timeModel.timeZone))
        try log.record(NutritionLogDraft(
            foodRef: food,
            eatenAt: PartialDateTime(text: "2025-09-18T04:00:00+03:00", precision: .instant,
                                     zone: ZoneContext(offsetMinutes: 180)),
            mealType: .lunch))
        try PlannedWorkoutStore(db: db).create(PlannedWorkoutDraft(scheduledAt: riyadh(13)))
        try rules.setEnabled(true, for: .contextualSnack)
        try FastingSessionStore(db: db).start(
            FastingSessionDraft(startTimestamp: now.addingTimeInterval(-3600), sessionType: .ifConfirmedSuggestion,
                                 isDryFast: false), logicalDay: day.value)

        #expect(try planner.immediateSnackSuggestion() == nil)
    }

    @Test("A short gap to the workout does not produce a suggestion")
    func snackSuggestionNeedsTheGap() throws {
        let food = SourceIdentifier(namespace: .almanac, localID: "test-food")
        let log = NutritionLogStore(db: db, clock: FixedClock(now), zone: ZoneContext(timeModel.timeZone))
        try log.record(NutritionLogDraft(
            foodRef: food,
            eatenAt: PartialDateTime(text: "2025-09-18T04:00:00+03:00", precision: .instant,
                                     zone: ZoneContext(offsetMinutes: 180)),
            mealType: .lunch))
        // Meal at 04:00, workout at 06:30 — a two-and-a-half hour gap, inside
        // the three-hour threshold.
        try PlannedWorkoutStore(db: db).create(PlannedWorkoutDraft(scheduledAt: riyadh(6, 30)))
        try rules.setEnabled(true, for: .contextualSnack)

        #expect(try planner.immediateSnackSuggestion() == nil)
    }
}
