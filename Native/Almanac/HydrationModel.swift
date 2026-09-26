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
        guard let settingsStore else { throw EditorFailure(message: "The database is unavailable.") }
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
        guard let settingsStore else { throw EditorFailure(message: "The database is unavailable.") }
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
        } catch {
            // A read failure here should not crash the dashboard; it will
            // simply show stale figures until the next refresh() succeeds.
        }
    }

    private func isoDay(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    func log(amount: Milliliters, note: String?) throws {
        guard let store else { throw EditorFailure(message: "The database is unavailable.") }
        try store.log(HydrationLogDraft(amount: amount, loggedAt: Date(), note: note))
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
            throw EditorFailure(message: "The database is unavailable.")
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
        let result = try loggingService().logDrink(drink, volume: volume, note: note)
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

    /// Calories from logged drinks today, summed separately from food.
    ///
    /// Deliberately NOT folded into `NutritionTotals.kcal`. A catalog drink is
    /// an uncited typical value (`DrinkValueQualifier.catalogUnsourcedEstimate`)
    /// and food is a cited composition figure; merging them would launder an
    /// estimate into a measurement, which is the exact distinction
    /// `Migration013` was written to protect. Two labelled numbers keep it.
    var todaysDrinkCalories: Double? {
        let withDrinks = todaysEntries.compactMap { $0.drink?.caloriesKcal }
        guard !withDrinks.isEmpty else { return nil }
        return withDrinks.reduce(0, +)
    }

    func delete(id: String) throws {
        guard let store else { throw EditorFailure(message: "The database is unavailable.") }
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
    /// configuration and swallow their own errors, so a failed push simply
    /// retries on the next run.
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
            refresh()
        } catch {
            // HealthSyncService already preserves the last good anchor on
            // failure; nothing further to do here but leave the dashboard as-is.
        }
    }

    /// Pushes manually-logged entries out to HealthKit. A no-op until
    /// HealthKit has been authorised via `configureHealthKit`.
    func drainOutbound() async {
        guard let db, let healthWriter else { return }
        _ = try? await HydrationWriteback(db: db, writer: healthWriter).drainOnce()
        refresh()
    }
}
