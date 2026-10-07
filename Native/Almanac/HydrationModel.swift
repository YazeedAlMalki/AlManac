import SwiftUI
import AlmanacCore

/// Owns hydration logging state for the app, the same way `LaboratoryModel`
/// owns Laboratory state — but shares its `Database` connection rather than
/// opening a second one (see `AlmanacApp.swift`).
@MainActor
final class HydrationModel: ObservableObject {
    @Published private(set) var store: HydrationStore?
    @Published private(set) var todayTotal: Milliliters = .zero
    @Published private(set) var todaysEntries: [HydrationEntry] = []
    /// Set when a read from the database failed, cleared the moment one
    /// succeeds. Distinct from an empty result: "nothing logged yet" and "could
    /// not read the log" are different claims, and a screen that shows the
    /// first when the second is true is as wrong as one that renders a missing
    /// reading as zero.
    @Published private(set) var readProblem: String?
    /// Set when pulling from Apple Health failed. Distinct from `readProblem`:
    /// the log was readable, the figures are just going stale, and the fix is
    /// different. Shown on the dashboard.
    @Published private(set) var syncProblem: String?
    /// Reminder settings, persisted in `hydration_settings` — the single
    /// source of truth `SettingsView`'s reminder controls read from and
    /// write to, replacing the `@AppStorage` copy that used to drift
    /// independently of it.
    @Published private(set) var hydrationSettings: HydrationSettings?

    private var healthProvider: (any HealthProvider)?
    private var healthWriter: (any HealthWriter)?
    private var db: Database?
    private var settingsStore: HydrationSettingsStore?
    private let timeModel = TimeModel(timeZone: .current)

    func configure(db: Database?) {
        guard let db, self.db == nil else { return } // already configured
        self.db = db
        store = HydrationStore(db: db)
        settingsStore = HydrationSettingsStore(db: db)
        refresh()
        loadSettings()
    }

    func loadSettings() {
        guard let settingsStore else { return }
        hydrationSettings = try? settingsStore.getOrCreate()
    }

    /// Persists the reminder half of `hydration_settings`, leaving the
    /// other fields (calorie tracking, sodium/sugar tracking, daily goal)
    /// untouched.
    func saveReminderSettings(enabled: Bool, intervalMinutes: Int, startHour: Int, endHour: Int) throws {
        guard let settingsStore else { throw EditorFailure(message: String(localized: "The database is unavailable.")) }
        let base = hydrationSettings ?? (try? settingsStore.getOrCreate()) ?? HydrationSettings()
        let updated = HydrationSettings(
            isCalorieTrackingEnabled: base.isCalorieTrackingEnabled,
            isDoubleTrackWarningEnabled: base.isDoubleTrackWarningEnabled,
            remindersEnabled: enabled,
            reminderIntervalMinutes: intervalMinutes,
            reminderStartHour: startHour,
            reminderEndHour: endHour,
            dailyGoalMilliliters: base.dailyGoalMilliliters,
            trackSodium: base.trackSodium,
            trackSugar: base.trackSugar,
            updatedAt: Date()
        )
        try settingsStore.save(updated)
        hydrationSettings = updated
    }

    /// Persists the daily goal half of `hydration_settings`, leaving the
    /// other fields untouched. Mirrors `saveReminderSettings` so the goal
    /// lives in the single source of truth instead of `@AppStorage`.
    func saveDailyGoal(milliliters: Double) throws {
        guard let settingsStore else { throw EditorFailure(message: String(localized: "The database is unavailable.")) }
        let base = hydrationSettings ?? (try? settingsStore.getOrCreate()) ?? HydrationSettings()
        guard base.dailyGoalMilliliters != milliliters else { return }
        let updated = HydrationSettings(
            isCalorieTrackingEnabled: base.isCalorieTrackingEnabled,
            isDoubleTrackWarningEnabled: base.isDoubleTrackWarningEnabled,
            remindersEnabled: base.remindersEnabled,
            reminderIntervalMinutes: base.reminderIntervalMinutes,
            reminderStartHour: base.reminderStartHour,
            reminderEndHour: base.reminderEndHour,
            dailyGoalMilliliters: milliliters,
            trackSodium: base.trackSodium,
            trackSugar: base.trackSugar,
            updatedAt: Date()
        )
        try settingsStore.save(updated)
        hydrationSettings = updated
    }

    /// Wires the concrete iOS `HealthKitProvider` in. Left unconfigured, sync
    /// methods below are no-ops — hydration logging itself never depends on
    /// HealthKit being authorised.
    func configureHealthKit(provider: any HealthProvider, writer: any HealthWriter) {
        healthProvider = provider
        healthWriter = writer
    }

    func refresh() {
        guard let store else { return }
        let today = timeModel.logicalDay(Date())
        guard let bounds = timeModel.bounds(of: today) else { return }
        do {
            let range = (start: isoDay(bounds.start), end: isoDay(bounds.end))
            todayTotal = try store.total(from: range.start, to: range.end)
            todaysEntries = try store.logs(from: range.start, to: range.end)
            readProblem = nil
        } catch {
            // Do not crash the dashboard — but do not pretend either. This used
            // to carry only a comment saying it "will simply show stale figures
            // until the next refresh() succeeds", which described a self-heal
            // with no mechanism behind it: the next `refresh()` fails the same
            // way, and the user is left looking at a screen that is
            // indistinguishable from one that genuinely has nothing logged.
            // Read the failure, say it, and let the note clear itself the moment
            // a read does succeed.
            readProblem = "Could not read today's hydration log."
        }
    }

    private func isoDay(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    func log(amount: Milliliters, note: String?) throws {
        guard let store, let db else { throw EditorFailure(message: String(localized: "The database is unavailable.")) }
        let loggedAt = Date()
        let id = try store.log(HydrationLogDraft(amount: amount, loggedAt: loggedAt, note: note))
        // §7.2: water is the second half of the night window's contents. A dry
        // fast is opened by a drink, so iftar's water is in scope for this even
        // though no food was.
        try NightNutritionWindowAssigner(db: db).assign(hydrationLogID: id, loggedAt: loggedAt)
        refresh()
        syncAfterChange()
    }

    // MARK: - Drinks

    /// The logging service behind drink logging. `HydrationLoggingService` and
    /// `DrinkCatalog` have been fully built and tested in `AlmanacCore` since
    /// Migration013 — volume scaling, the `catalogUnsourcedEstimate` vs
    /// `userEntered` qualifier, duplicate-tap detection, and the high-sugar /
    /// high-sodium warnings — with nothing in the app reaching any of it. These
    /// are the seam that makes it reachable.
    private func loggingService() throws -> HydrationLoggingService {
        guard let db, let settingsStore else {
            throw EditorFailure(message: String(localized: "The database is unavailable."))
        }
        return HydrationLoggingService(store: HydrationStore(db: db), settingsStore: settingsStore)
    }

    /// Every drink available to log: the built-in catalog first, then the
    /// user's own saved drinks.
    func allDrinks() -> [Drink] {
        (try? loggingService().allDrinks()) ?? CatalogDrinks.all
    }

    /// Logs a catalog or custom drink, returning the service's warnings so the
    /// caller can show them. The warnings are the service's decision, not the
    /// UI's — a duplicate tap or a 40g sugar load is a fact about the entry,
    /// and re-deriving it here would let the two drift.
    @discardableResult
    func logDrink(_ drink: Drink, volume: Milliliters?, note: String?) throws -> [DrinkLoggingWarning] {
        let loggedAt = Date()
        let result = try loggingService().logDrink(drink, volume: volume, at: loggedAt, note: note)
        // Same §7.2 window assignment as a plain water entry — a drink logged at
        // iftar is inside the night window on exactly the same terms.
        if let db {
            try NightNutritionWindowAssigner(db: db)
                .assign(hydrationLogID: result.hydrationLogID, loggedAt: loggedAt)
        }
        refresh()
        syncAfterChange()
        return result.warnings
    }

    /// Saves a user-authored drink. The service tags it `.userEntered`
    /// itself, so a custom drink can never be presented as a catalog estimate.
    @discardableResult
    func saveCustomDrink(name: String, liquidType: LiquidType, volumeMilliliters: Double,
                         caloriesKcal: Double, sodiumMilligrams: Double,
                         sugarGrams: Double?) throws -> Drink {
        let drink = try loggingService().saveCustomDrink(
            name: name, liquidType: liquidType, volumeMilliliters: volumeMilliliters,
            caloriesKcal: caloriesKcal, sodiumMilligrams: sodiumMilligrams, sugarGrams: sugarGrams)
        objectWillChange.send()
        return drink
    }

    /// Each logged drink's calories today, in log order. Empty when no drink
    /// carried a figure.
    ///
    /// Returned per drink rather than pre-summed because the day total needs
    /// the count as well as the sum: `DayEnergy` names the composition in
    /// words, and a count that was computed somewhere else could disagree with
    /// this total without anything failing.
    ///
    /// These figures are added into the day's single energy total alongside
    /// food. That is a presentation choice and not a claim that a catalog drink
    /// is a cited figure like food — the qualifier is still written per row to
    /// `hydration_log.value_qualifier`, which is what `Migration013` exists to
    /// protect, and `DayEnergy` sums without touching it. The distinction is
    /// preserved by being sayable out loud, not by being a second number.
    var todaysDrinkEnergy: [Double] {
        todaysEntries.compactMap { $0.drink?.caloriesKcal }
    }

    func delete(id: String) throws {
        guard let store else { throw EditorFailure(message: String(localized: "The database is unavailable.")) }
        try store.delete(id: id)
        refresh()
        syncAfterChange()
    }

    /// Kicks the full inbound/outbound HealthKit sync (the same pair the
    /// connect flow runs) without any auth sheet. Called when the scene
    /// becomes active, so water logged in Health while Almanac was
    /// backgrounded appears without re-tapping Connect. A no-op until
    /// HealthKit has been configured via `configureHealthKit`.
    func syncOnForeground() async {
        await syncInbound()
        await drainOutbound()
    }

    /// After any local change, pull new HealthKit water samples in and then
    /// push pending manual entries back out — the documented "sync after each
    /// manual log" behaviour (Native/README.md).
    private func syncAfterChange() {
        runHealthSync()
    }

    /// The shared sync driver: inbound goes through `HealthSyncService`
    /// (rows and the anchor commit atomically), outbound through
    /// `HydrationWriteback`'s pending queue. Both halves guard on their own
    /// configuration, and a failure in either retries on the next run because
    /// neither half leaves anything half-written. They differ in whether the
    /// user is told: an inbound failure means the figures on screen have quietly
    /// stopped updating, so it is surfaced, while an outbound failure changes
    /// nothing they can see — the entry is already saved here — so it is
    /// deliberately silent. See `drainOutbound`.
    private func runHealthSync() {
        guard healthProvider != nil || healthWriter != nil else { return }
        Task { [weak self] in
            await self?.syncInbound()
            await self?.drainOutbound()
        }
    }

    /// Pulls new HealthKit water samples in. A no-op until HealthKit has
    /// been authorised via `configureHealthKit`.
    func syncInbound() async {
        guard let db, let store, let healthProvider else { return }
        do {
            _ = try await HealthSyncService(db: db, provider: healthProvider, writer: store,
                                            healthDomain: .water).syncOnce()
            syncProblem = nil
            refresh()
        } catch {
            // `HealthSyncService` does preserve the last good anchor, so nothing
            // is corrupted and the next run does retry — that part of the old
            // comment was true. What it missed is the user: a sync that keeps
            // failing leaves the dashboard showing figures that quietly stop
            // updating, which is the same silence as an unreadable log even
            // though the cause and the fix differ. Said out loud, and cleared
            // by the first sync that works.
            syncProblem = "Apple Health sync is not going through. The figures below may be out of date."
        }
    }

    /// Pushes manually-logged entries out to HealthKit. A no-op until
    /// HealthKit has been authorised via `configureHealthKit`.
    func drainOutbound() async {
        guard let db, let healthWriter else { return }
        defer { refresh() }
        // Silence here is the correct answer, and it is the one place in this
        // file where a swallowed error is not a defect. A push to HealthKit
        // failing changes nothing the user can see: the entry is already saved
        // in Almanac, which is the log of record, and `HydrationWriteback`'s
        // queue retries it. A note here would report a problem they cannot see
        // and cannot fix, which is how a dashboard teaches people to ignore the
        // notes that matter. Deliberately not recorded on the model either —
        // a published property nothing reads is a channel that looks handled
        // while telling nobody anything.
        _ = try? await HydrationWriteback(db: db, writer: healthWriter).drainOnce()
    }
}
