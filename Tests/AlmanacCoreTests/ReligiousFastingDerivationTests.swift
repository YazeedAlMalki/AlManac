import Testing
import Foundation
@testable import AlmanacCore

/// The religious fast as a *derived* fact: schedule + corrections + prayer
/// times + the intake log + the time → the session. Every test here drives the
/// real stores through `FastingCoordinator`, the one entry point the app calls,
/// because the bugs this replaces were all wiring bugs — the rules were right
/// and nothing reached them.
@Suite("Religious fasting, derived")
struct ReligiousFastingDerivationTests {
    let db: Database
    let riyadh = TimeZone(identifier: "Asia/Riyadh")!
    /// 2026-09-17 is a Thursday.
    let day = "2026-09-17"

    init() throws {
        db = try TestDatabase()
    }

    // MARK: - Fixtures

    private func at(_ hour: Int, _ minute: Int = 0, on date: String = "2026-09-17") -> Date {
        let bits = date.split(separator: "-").compactMap { Int($0) }
        var comps = DateComponents()
        comps.year = bits[0]; comps.month = bits[1]; comps.day = bits[2]
        comps.hour = hour; comps.minute = minute
        comps.timeZone = riyadh
        return Calendar(identifier: .gregorian).date(from: comps)!
    }

    private var fajr: Date { at(4, 30) }
    private var maghrib: Date { at(18, 0) }

    private func coordinator(at now: Date) -> FastingCoordinator {
        FastingCoordinator(db: db, clock: FixedClock(now), timeZone: riyadh)
    }

    private var schedules: ReligiousFastScheduleStore { ReligiousFastScheduleStore(db: db) }
    private var sessions: FastingSessionStore { FastingSessionStore(db: db) }

    private func cachePrayerTimes(_ date: String, fajr: Date? = nil, maghrib: Date? = nil) throws {
        let f = fajr ?? at(4, 30, on: date)
        let m = maghrib ?? at(18, 0, on: date)
        try PrayerTimeCacheStore(db: db).upsert(date: date, times: [
            PrayerTime(name: "fajr", timestamp: f),
            PrayerTime(name: "sunrise", timestamp: f.addingTimeInterval(80 * 60)),
            PrayerTime(name: "dhuhr", timestamp: f.addingTimeInterval(7 * 3600)),
            PrayerTime(name: "asr", timestamp: f.addingTimeInterval(10 * 3600)),
            PrayerTime(name: "maghrib", timestamp: m),
            PrayerTime(name: "isha", timestamp: m.addingTimeInterval(90 * 60))
        ], latitude: 24.7136, longitude: 46.6753, calculationMethod: "umm_al_qura")
    }

    /// Thursday the 17th a fast day, with the 16th–18th cached.
    private func thursdayFast() throws {
        try schedules.setRecurringEnabled(ReligiousFastScheduleStore.monThu, enabled: true)
        for date in ["2026-09-16", "2026-09-17", "2026-09-18"] { try cachePrayerTimes(date) }
    }

    @discardableResult
    private func drink(at instant: Date, ml: Double = 250) throws -> String {
        try HydrationStore(db: db, zone: ZoneContext(riyadh)).log(HydrationLogDraft(amount: Milliliters(ml), loggedAt: instant))
    }

    @discardableResult
    private func eat(at instant: Date, grams: Double? = 100) throws -> String {
        try NutritionLogStore(db: db, zone: ZoneContext(riyadh)).record(NutritionLogDraft(
            foodRef: SourceIdentifier(namespace: .usda, localID: "dates"), grams: grams,
            eatenAt: PartialDateTime(instant: instant, zone: ZoneContext(riyadh)),
            foodNameText: "Dates")).logID
    }

    private func religiousSession(_ date: String = "2026-09-17") throws -> FastingSession? {
        try sessions.sessions(for: date).first { $0.sessionType == .religious }
    }

    // MARK: - The calendar exists without anyone setting it up

    @Test("Ramadan's schedule is created on the first refresh, for this year and next")
    func ramadanIsCreatedAutomatically() throws {
        try coordinator(at: at(12)).refresh()
        let ramadan = try schedules.schedules(activeOnly: false).filter { $0.scheduleType == "ramadan" }
        let thisYear = try #require(HijriDate(gregorian: day)).year
        #expect(Set(ramadan.compactMap(\.hijriYear)).isSuperset(of: [thisYear + 1]))
        #expect(ramadan.allSatisfy { $0.isActive })

        // Idempotent: a second refresh creates nothing more.
        try coordinator(at: at(13)).refresh()
        #expect(try schedules.schedules(activeOnly: false).filter { $0.scheduleType == "ramadan" }.count
                == ramadan.count)
    }

    @Test("A Ramadan day really is a fast day once the schedule exists")
    func ramadanDayIsAFastDay() throws {
        let range = try #require(ReligiousFastScheduleStore.ramadanRange(hijriYear: 1448))
        try schedules.ensureRamadanSchedules(around: day)
        let status = try schedules.status(range.start)
        #expect(status.isFastDay)
        #expect(status.kinds == [.ramadan])
        #expect(status.hijri?.month == 9)
        #expect(status.hijri?.day == 1)
    }

    @Test("Turning Ramadan off is remembered by the year that has not been created yet")
    func ramadanOffCarriesForward() throws {
        try schedules.setRamadanEnabled(false, asOf: day)
        let range = try #require(ReligiousFastScheduleStore.ramadanRange(hijriYear: 1448))
        #expect(try !schedules.isFastDay(range.start))
        #expect(try !schedules.isRamadanEnabled())

        // A year later the next Ramadan row is created — off, as the user left it.
        let nextYear = try #require(ReligiousFastScheduleStore.ramadanRange(hijriYear: 1449))
        try schedules.ensureRamadanSchedules(around: nextYear.start)
        #expect(try !schedules.isFastDay(nextYear.start))

        try schedules.setRamadanEnabled(true, asOf: day)
        #expect(try schedules.isFastDay(range.start))
    }

    @Test("Mondays and Thursdays and White Days are switched on and off")
    func recurringRulesToggle() throws {
        #expect(try !schedules.isFastDay(day))
        try schedules.setRecurringEnabled(ReligiousFastScheduleStore.monThu, enabled: true)
        #expect(try schedules.status(day).kinds == [.thursday])
        try schedules.setRecurringEnabled(ReligiousFastScheduleStore.monThu, enabled: false)
        #expect(try !schedules.isFastDay(day))
        // Switching on again reuses the row rather than piling up new ones.
        try schedules.setRecurringEnabled(ReligiousFastScheduleStore.monThu, enabled: true)
        #expect(try schedules.schedules(activeOnly: false).filter { $0.scheduleType == "mon_thu" }.count == 1)
    }

    @Test("Eid and the days of Tashreeq are never a voluntary fast day")
    func prohibitedDaysAreExcluded() throws {
        try schedules.setRecurringEnabled(ReligiousFastScheduleStore.whiteDays, enabled: true)
        try schedules.setRecurringEnabled(ReligiousFastScheduleStore.monThu, enabled: true)
        // 13 Dhu al-Hijjah 1447 — a White Day by number, a day of Tashreeq by law.
        let statuses = try schedules.statuses(from: "2026-05-01", days: 60)
        let tashreeq = try #require(statuses.first { $0.hijri?.month == 12 && $0.hijri?.day == 13 })
        #expect(!tashreeq.isFastDay)
        let eidAlAdha = try #require(statuses.first { $0.hijri?.month == 12 && $0.hijri?.day == 10 })
        #expect(!eidAlAdha.isFastDay)
        // The 14th is an ordinary White Day.
        let fourteenth = try #require(statuses.first { $0.hijri?.month == 12 && $0.hijri?.day == 14 })
        #expect(fourteenth.kinds.contains(.whiteDay))
    }

    @Test("A manual correction wins, the latest one wins, and clearing returns the calculation")
    func manualCorrections() throws {
        try schedules.setRecurringEnabled(ReligiousFastScheduleStore.monThu, enabled: true)
        let tuesday = "2026-09-15"

        try schedules.setManualFastDay(day, isFast: false, reason: "travelling")
        #expect(try !schedules.isFastDay(day))
        #expect(try schedules.status(day).isCorrected)

        try schedules.setManualFastDay(tuesday, isFast: true)
        #expect(try schedules.isFastDay(tuesday))

        try schedules.setManualFastDay(day, isFast: true)
        #expect(try schedules.isFastDay(day))
        #expect(try !schedules.status(day).isCorrected, "agreeing with the calculation is not a correction")

        try schedules.setManualFastDay(tuesday, isFast: nil)
        #expect(try !schedules.isFastDay(tuesday))
        // Logged, never overwritten.
        let manual = try #require(try schedules.schedules().first { $0.scheduleType == "manual" })
        #expect(manual.manualCorrections.count == 4)
    }

    // MARK: - Before Fajr is suhoor

    @Test("No session exists before Fajr, and suhoor touches nothing")
    func beforeFajrIsSuhoor() throws {
        try thursdayFast()
        try eat(at: at(4, 0))
        try drink(at: at(4, 10))

        let outcome = try coordinator(at: at(4, 15)).ensureDay(day, at: at(4, 15))

        #expect(outcome == .notStartedYet)
        #expect(try religiousSession() == nil)
        #expect(try coordinator(at: at(4, 15)).today().phase(at: at(4, 15)) == .beforeFajr(fajr: fajr, maghrib: maghrib))
    }

    @Test("Suhoor eaten before Fajr does not break the fast once it begins")
    func suhoorDoesNotBreakTheFast() throws {
        try thursdayFast()
        try eat(at: at(4, 0))
        try drink(at: at(4, 20))

        try coordinator(at: at(9)).refresh()

        let session = try #require(try religiousSession())
        #expect(session.isActive)
        #expect(!session.isInvalidated)
        #expect(session.startTimestamp == fajr)
    }

    @Test("A session an older build created before Fajr is removed until Fajr comes")
    func preFajrSessionFromOlderBuildIsRemoved() throws {
        try thursdayFast()
        try sessions.start(FastingSessionDraft(startTimestamp: fajr, sessionType: .religious, isDryFast: true),
                           logicalDay: day)
        #expect(try coordinator(at: at(4, 10)).ensureDay(day, at: at(4, 10)) == .notStartedYet)
        #expect(try religiousSession() == nil)
    }

    // MARK: - Fajr to Maghrib

    @Test("Water drunk after Fajr breaks the dry fast at that moment")
    func waterAfterFajrBreaks() throws {
        try thursdayFast()
        try coordinator(at: at(9)).refresh()
        try drink(at: at(13, 5))

        let outcome = try coordinator(at: at(14)).ensureDay(day, at: at(14))

        let session = try #require(try religiousSession())
        #expect(outcome == .sessionBroken(sessionId: session.id, at: at(13, 5)))
        #expect(session.endTimestamp == at(13, 5))
        #expect(session.finalDurationMinutes == 8 * 60 + 35)
        #expect(try coordinator(at: at(14)).today().phase(at: at(14)) == .broken(at: at(13, 5), maghrib: maghrib))
    }

    @Test("Deleting the drink that broke the fast gives the day its fast back")
    func deletingTheBreakingIntakeRestores() throws {
        try thursdayFast()
        try coordinator(at: at(9)).refresh()
        let id = try drink(at: at(13, 5))
        try coordinator(at: at(14)).refresh()
        #expect(try religiousSession()?.isActive == false)

        try HydrationStore(db: db).delete(id: id)
        try coordinator(at: at(15)).refresh()
        #expect(try religiousSession()?.isActive == true)

        // …and after Maghrib it is a kept fast, not a broken one.
        try coordinator(at: at(19)).refresh()
        let kept = try #require(try religiousSession())
        #expect(kept.endTimestamp == maghrib)
        #expect(try coordinator(at: at(19)).today().phase(at: at(19)) == .kept(maghrib: maghrib))
    }

    @Test("Opened for the first time after Maghrib, the day is recorded as kept at Maghrib")
    func firstOpenAfterMaghribRecordsAKeptFast() throws {
        try thursdayFast()
        try drink(at: at(18, 5)) // iftar
        try coordinator(at: at(21)).refresh()

        let session = try #require(try religiousSession())
        #expect(session.isActive == false)
        #expect(session.endTimestamp == maghrib)
        #expect(session.finalDurationMinutes == 13 * 60 + 30)
    }

    @Test("Yesterday's fast still open past midnight is closed at its Maghrib, not when the app opens")
    func yesterdayIsClosedAtItsOwnMaghrib() throws {
        try schedules.setRecurringEnabled(ReligiousFastScheduleStore.monThu, enabled: true)
        try schedules.setManualFastDay("2026-09-18", isFast: false)
        for date in ["2026-09-16", "2026-09-17", "2026-09-18"] { try cachePrayerTimes(date) }
        try coordinator(at: at(12)).refresh()
        #expect(try religiousSession()?.isActive == true)

        try coordinator(at: at(1, 30, on: "2026-09-18")).refresh()

        #expect(try religiousSession()?.endTimestamp == maghrib)
    }

    @Test("Recalculated prayer times move the session's start")
    func movedFajrMovesTheStart() throws {
        try thursdayFast()
        try coordinator(at: at(9)).refresh()
        try cachePrayerTimes(day, fajr: at(4, 33))
        try coordinator(at: at(10)).refresh()
        #expect(try religiousSession()?.startTimestamp == at(4, 33))
    }

    @Test("A religious session an older build invalidated is repaired")
    func invalidatedReligiousSessionIsRepaired() throws {
        try thursdayFast()
        try coordinator(at: at(9)).refresh()
        let id = try #require(try religiousSession()?.id)
        try db.run("UPDATE fasting_session SET isActive = 0, isInvalidated = 1 WHERE id = ?;", [.integer(id)])

        try coordinator(at: at(10)).refresh()

        let repaired = try #require(try religiousSession())
        #expect(repaired.isActive)
        #expect(!repaired.isInvalidated)
    }

    @Test("An intermittent fast running at Fajr yields to the religious one, keeping its hours")
    func intermittentYieldsAtFajr() throws {
        try thursdayFast()
        let ifID = try sessions.start(FastingSessionDraft(startTimestamp: at(20, 0, on: "2026-09-16"),
                                                          sessionType: .ifPlanned),
                                      logicalDay: "2026-09-16")

        try coordinator(at: at(9)).refresh()

        let intermittent = try #require(try sessions.session(id: ifID))
        #expect(intermittent.isActive == false)
        #expect(intermittent.endTimestamp == fajr)
        #expect(try religiousSession()?.isActive == true)
    }

    @Test("Un-marking the day removes its session and its night window")
    func unmarkingRemovesSessionAndWindow() throws {
        try thursdayFast()
        try coordinator(at: at(9)).refresh()
        #expect(try religiousSession() != nil)
        #expect(try NutritionWindowStore(db: db).window(date: day, windowType: .nightNutritionWindow) != nil)

        try coordinator(at: at(10)).setManualFastDay(day, isFast: false, reason: "unwell")

        #expect(try religiousSession() == nil)
        #expect(try NutritionWindowStore(db: db).window(date: day, windowType: .nightNutritionWindow) == nil)
        #expect(try coordinator(at: at(10)).today().phase(at: at(10)) == .notAFastDay)
    }

    @Test("A fast day with no prayer times says so and invents nothing")
    func noPrayerTimesIsSaidPlainly() throws {
        try schedules.setRecurringEnabled(ReligiousFastScheduleStore.monThu, enabled: true)
        #expect(try coordinator(at: at(9)).ensureDay(day, at: at(9)) == .prayerTimesUnavailable)
        #expect(try religiousSession() == nil)
        #expect(try coordinator(at: at(9)).today().phase(at: at(9)) == .prayerTimesUnavailable)
    }

    // MARK: - The logging wrappers reach the rules

    @Test("Logging lunch through the app's nutrition path breaks the religious fast")
    func nutritionWrapperBreaksReligiousFast() throws {
        try thursdayFast()
        try coordinator(at: at(9)).refresh()
        let clock = FixedClock(at(13))
        let log = FastingAwareNutritionLog(db: db, clock: clock, zone: ZoneContext(riyadh))

        // No stated amount, so zero calories by §11.1 — and still an intake.
        let result = try log.record(NutritionLogDraft(
            foodRef: SourceIdentifier(namespace: .usda, localID: "coffee"), grams: nil,
            eatenAt: PartialDateTime(instant: at(13), zone: ZoneContext(riyadh))))

        let session = try #require(try religiousSession())
        #expect(result.fastingOutcome == .ended(sessionId: session.id, durationMinutes: 8 * 60 + 30))
        #expect(session.endTimestamp == at(13))
    }

    @Test("A meal logged before Fajr is suhoor, through the wrapper too")
    func nutritionWrapperLeavesSuhoorAlone() throws {
        try thursdayFast()
        try coordinator(at: at(9)).refresh()
        let log = FastingAwareNutritionLog(db: db, clock: FixedClock(at(9, 5)), zone: ZoneContext(riyadh))

        // Logged late, backdated to 04:00.
        let result = try log.record(NutritionLogDraft(
            foodRef: SourceIdentifier(namespace: .usda, localID: "dates"), grams: 50,
            eatenAt: PartialDateTime(instant: at(4), zone: ZoneContext(riyadh))))

        #expect(result.fastingOutcome == .noOp)
        let session = try #require(try religiousSession())
        #expect(session.isActive)
        #expect(!session.isInvalidated)
    }

    @Test("Iftar logged through the wrapper is claimed by the night window")
    func iftarIsAssignedToTheNightWindow() throws {
        try thursdayFast()
        try coordinator(at: at(9)).refresh()
        let log = FastingAwareHydrationLog(db: db, clock: FixedClock(at(18, 5)), zone: ZoneContext(riyadh))

        let result = try log.log(HydrationLogDraft(amount: Milliliters(300), loggedAt: at(18, 5)))

        #expect(result.fastingOutcome == .noOp, "iftar ends nothing — the fast was kept")
        let window = try #require(try NutritionWindowStore(db: db).window(date: day, windowType: .nightNutritionWindow))
        let assigned = try db.query("SELECT nutrition_window_id AS w FROM hydration_log WHERE id = ?;",
                                    [.text(result.hydrationLogID)]).first?.int("w")
        #expect(assigned == window.id)
        let contents = try coordinator(at: at(19)).contents(of: window)
        #expect(contents.map(\.id) == [result.hydrationLogID])
    }

    @Test("Deleting through the hydration wrapper restores the fast at once")
    func hydrationWrapperDeleteRestores() throws {
        try thursdayFast()
        try coordinator(at: at(9)).refresh()
        let log = FastingAwareHydrationLog(db: db, clock: FixedClock(at(12)), zone: ZoneContext(riyadh))
        let id = try log.log(HydrationLogDraft(amount: Milliliters(250), loggedAt: at(12))).hydrationLogID
        #expect(try religiousSession()?.isActive == false)

        try log.delete(id: id)

        #expect(try religiousSession()?.isActive == true)
    }

    @Test("A calorie-bearing drink ends an intermittent fast; plain water does not")
    func caloricDrinkBreaksIntermittentFast() throws {
        let clock = FixedClock(at(12))
        let ifID = try sessions.start(FastingSessionDraft(startTimestamp: at(8), sessionType: .ifPlanned),
                                      logicalDay: day)
        let log = FastingAwareHydrationLog(db: db, clock: clock, zone: ZoneContext(riyadh))

        #expect(try log.log(HydrationLogDraft(amount: Milliliters(250), loggedAt: at(10))).fastingOutcome == .noOp)

        let juice = DrinkAttachment(drinkID: "orange-juice", drinkName: "Orange juice", caloriesKcal: 110,
                                    sodiumMg: 2, sugarG: 20, qualifier: .catalogUnsourcedEstimate)
        let result = try log.log(HydrationLogDraft(amount: Milliliters(250), loggedAt: at(11), drink: juice))

        #expect(result.fastingOutcome == .ended(sessionId: ifID, durationMinutes: 180))
    }

    @Test("Deleting the meal that ended an intermittent fast reopens it")
    func deletingTheBreakingMealReopensIntermittentFast() throws {
        try db.execute("""
            INSERT INTO nutrition_source (namespace, dataset_id, name, release, licence, licence_group, attribution, url)
            VALUES ('usda', 'usda', 'USDA', '2026', 'CC0', 'A', '', '');
            INSERT INTO nutrition_nutrient (nutrient_id, infoods_tag, name, unit, description)
            VALUES ('energy_kcal', 'ENERC_KCAL', 'Energy', 'kcal', 'Energy');
            INSERT INTO nutrition_food (food_ref, namespace, local_id, licence_group, food_group_code, food_group_name, source_record)
            VALUES ('usda:bread', 'usda', 'bread', 'A', '', '', 'fixture');
            INSERT INTO nutrition_value (food_ref, nutrient_id, basis, amount, qualifier, confidence,
                                         source_value, source_nutrient_id, source_unit, licence_group)
            VALUES ('usda:bread', 'energy_kcal', 'per_100g', 250, 'measured', NULL, '250', 'ENERC_KCAL', 'kcal', 'A');
            """)
        let ifID = try sessions.start(FastingSessionDraft(startTimestamp: at(8), sessionType: .ifPlanned),
                                      logicalDay: day)
        let log = FastingAwareNutritionLog(db: db, clock: FixedClock(at(12)), zone: ZoneContext(riyadh))
        let recorded = try log.record(NutritionLogDraft(
            foodRef: SourceIdentifier(namespace: .usda, localID: "bread"), grams: 80,
            eatenAt: PartialDateTime(instant: at(11), zone: ZoneContext(riyadh))))
        #expect(try sessions.session(id: ifID)?.isActive == false)

        try log.delete(id: recorded.outcome.logID)

        #expect(try sessions.session(id: ifID)?.isActive == true)
    }

    @Test("§11.1's backdating rule does not reach a religious session")
    func intermittentRulesIgnoreReligiousSessions() throws {
        let id = try sessions.start(FastingSessionDraft(startTimestamp: fajr, sessionType: .religious, isDryFast: true),
                                    logicalDay: day)
        #expect(try sessions.recordNutritionEntry(calories: 400, at: at(4)) == .noOp)
        #expect(try sessions.recordIntake(at: at(4)) == .noOp, "an intake before Fajr is suhoor")
        let session = try #require(try sessions.session(id: id))
        #expect(session.isActive)
        #expect(!session.isInvalidated)
    }

    // MARK: - Reading

    @Test("The night window shown during the day is last night's, with what was eaten in it")
    func lastNightsWindowIsShownDuringTheDay() throws {
        try schedules.setRecurringEnabled(ReligiousFastScheduleStore.monThu, enabled: true)
        try schedules.setManualFastDay("2026-09-16", isFast: true)
        for date in ["2026-09-15", "2026-09-16", "2026-09-17", "2026-09-18"] { try cachePrayerTimes(date) }
        try coordinator(at: at(12, 0, on: "2026-09-16")).refresh()
        let iftar = try drink(at: at(18, 10, on: "2026-09-16"))
        let suhoor = try eat(at: at(4, 0))

        let reader = coordinator(at: at(12))
        try reader.refresh()
        let window = try #require(try reader.currentNightWindow())
        #expect(window.date == "2026-09-16")
        #expect(try reader.contents(of: window).map(\.id) == [iftar, suhoor])
    }

    @Test("The coming-up list names each fast day and why")
    func upcomingFastDays() throws {
        try schedules.setRecurringEnabled(ReligiousFastScheduleStore.monThu, enabled: true)
        let upcoming = try coordinator(at: at(12)).upcoming(days: 7)
        #expect(upcoming.map(\.date) == ["2026-09-21", "2026-09-24"])
        #expect(upcoming.map(\.kinds) == [[.monday], [.thursday]])
    }

    @Test("§11.1's suggestion: only after a real gap, never on a fast day, never during a fast")
    func intermittentSuggestion() throws {
        let reader = coordinator(at: at(23))
        #expect(try reader.intermittentSuggestionStart() == nil, "nothing logged is not a 14-hour gap")

        try eat(at: at(8))
        #expect(try reader.intermittentSuggestionStart() == at(8))
        #expect(try coordinator(at: at(20)).intermittentSuggestionStart() == nil, "12 hours is under the threshold")

        try schedules.setRecurringEnabled(ReligiousFastScheduleStore.monThu, enabled: true)
        #expect(try reader.intermittentSuggestionStart() == nil, "no IF suggestion on a religious fast day")
    }
}
