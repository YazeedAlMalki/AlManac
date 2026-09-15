import Foundation

/// Logs a drink (catalog or custom) as a hydration entry, scaling its
/// nutrition figures to the amount actually drunk and attaching them to the
/// log row — see `Migration013`. Single-user: no `userId` anywhere, unlike
/// `claude/app-hydration-tracking-mpwsyv`'s `HydrationLoggingService`, which
/// this supersedes rather than wraps (that branch's `hydrationStore`,
/// `calorieIntegration` and `settingsStore` types don't exist in this tree).
public struct HydrationLoggingService: Sendable {
    private let store: HydrationStore
    private let settingsStore: HydrationSettingsStore

    public init(store: HydrationStore, settingsStore: HydrationSettingsStore) {
        self.store = store
        self.settingsStore = settingsStore
    }

    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    /// Logs `drink`. `volume` overrides the drink's default serving size —
    /// every scalable figure (sodium, calories, sugar) is scaled to match,
    /// so logging half a can never credits a full can's nutrition.
    @discardableResult
    public func logDrink(_ drink: Drink, volume: Milliliters? = nil, at date: Date = Date(),
                          note: String? = nil) throws -> DrinkLoggingResult {
        let amount = volume ?? Milliliters(drink.volumeMilliliters)
        let scale = drink.volumeMilliliters > 0 ? amount.value / drink.volumeMilliliters : 1
        let scaledSodium = drink.sodiumMilligrams * scale
        let scaledCalories = drink.caloriesKcal * scale
        let scaledSugar = drink.sugarGrams.map { $0 * scale }

        let attachment = DrinkAttachment(drinkID: drink.id, drinkName: drink.name,
                                          caloriesKcal: scaledCalories, sodiumMg: scaledSodium,
                                          sugarG: scaledSugar, qualifier: drink.valueQualifier)
        let id = try store.log(HydrationLogDraft(amount: amount, loggedAt: date, note: note, drink: attachment))

        let settings = try settingsStore.getOrCreate()
        var warnings: [DrinkLoggingWarning] = []

        if settings.isDoubleTrackWarningEnabled,
           let secondsAgo = try possibleDoubleTrack(excluding: id, drinkID: drink.id, at: date) {
            warnings.append(DrinkLoggingWarning(
                type: .possibleDoubleTrack,
                message: "Similar drink logged \(secondsAgo)s ago. Did you mean to log this drink?"))
        }
        if settings.trackSugar, let sugar = scaledSugar, sugar > 35 {
            warnings.append(DrinkLoggingWarning(type: .highSugar, message: "This drink has \(Int(sugar))g sugar (high)"))
        }
        if settings.trackSodium && scaledSodium > 300 {
            warnings.append(DrinkLoggingWarning(type: .highSodium,
                message: "This drink has high sodium. Ideal during/after exercise"))
        }

        return DrinkLoggingResult(hydrationLogID: id, warnings: warnings,
                                   caloriesLogged: settings.isCalorieTrackingEnabled ? scaledCalories : nil)
    }

    /// Logs a plain amount with no drink attached — unchanged from before
    /// Migration013, still the right call for "just water, no catalog entry".
    @discardableResult
    public func logAmount(_ amount: Milliliters, at date: Date = Date(), note: String? = nil) throws -> String {
        try store.log(HydrationLogDraft(amount: amount, loggedAt: date, note: note))
    }

    /// Saves a user-authored drink to `hydration_drink`, tagged
    /// `.userEntered` regardless of what the caller passes — a custom drink
    /// is definitionally the user's own figures, never a catalog estimate.
    @discardableResult
    public func saveCustomDrink(name: String, liquidType: LiquidType, volumeMilliliters: Double,
                                 caloriesKcal: Double, sodiumMilligrams: Double,
                                 sugarGrams: Double? = nil) throws -> Drink {
        let drink = Drink(name: name, liquidType: liquidType, volumeMilliliters: volumeMilliliters,
                           caloriesKcal: caloriesKcal, sodiumMilligrams: sodiumMilligrams,
                           sugarGrams: sugarGrams, isCustom: true, valueQualifier: .userEntered)
        try store.db.run("""
        INSERT INTO hydration_drink (id, name, liquid_type, volume_ml, calories_kcal, sodium_mg, sugar_g, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            name          = excluded.name,
            liquid_type   = excluded.liquid_type,
            volume_ml     = excluded.volume_ml,
            calories_kcal = excluded.calories_kcal,
            sodium_mg     = excluded.sodium_mg,
            sugar_g       = excluded.sugar_g;
        """, [
            .text(drink.id), .text(drink.name), .text(drink.liquidType.rawValue),
            .real(drink.volumeMilliliters), .real(drink.caloriesKcal), .real(drink.sodiumMilligrams),
            drink.sugarGrams.map { SQLValue.real($0) } ?? .null, .text(iso(drink.createdAt))
        ])
        return drink
    }

    public func customDrinks() throws -> [Drink] {
        try store.db.query("SELECT * FROM hydration_drink ORDER BY created_at DESC;").compactMap { row in
            guard let id = row.string("id"), let name = row.string("name"),
                  let liquidTypeRaw = row.string("liquid_type"), let liquidType = LiquidType(rawValue: liquidTypeRaw),
                  let volume = row.double("volume_ml"), let calories = row.double("calories_kcal"),
                  let sodium = row.double("sodium_mg"), let createdAtText = row.string("created_at"),
                  let createdAt = ISO8601DateFormatter().date(from: createdAtText)
            else { return nil }
            return Drink(id: id, name: name, liquidType: liquidType, volumeMilliliters: volume,
                         caloriesKcal: calories, sodiumMilligrams: sodium, sugarGrams: row.double("sugar_g"),
                         isCustom: true, valueQualifier: .userEntered, createdAt: createdAt)
        }
    }

    /// Every drink this app knows about: the built-in catalog plus whatever
    /// custom drinks the user has saved.
    public func allDrinks() throws -> [Drink] {
        try CatalogDrinks.all + customDrinks()
    }

    /// Looks a short window back for another entry of the *same* drink, to
    /// flag an accidental duplicate tap. Recomputed at read time from
    /// existing rows every call — nothing is persisted or mutated for this,
    /// unlike the branch's `double_track_warning` column. See Migration013.
    private func possibleDoubleTrack(excluding id: String, drinkID: String, at date: Date,
                                      windowMinutes: Int = 5) throws -> Int? {
        let windowStart = date.addingTimeInterval(-Double(windowMinutes) * 60)
        let recent = try store.logs(from: iso(windowStart), to: iso(date))
        guard let match = recent.first(where: { $0.id != id && $0.drink?.drinkID == drinkID }),
              let matchStart = match.loggedAt.span?.start
        else { return nil }
        return Int(date.timeIntervalSince(matchStart))
    }
}

public struct DrinkLoggingResult: Sendable, Hashable {
    public let hydrationLogID: String
    public let warnings: [DrinkLoggingWarning]
    /// Calories actually recorded against this entry — `nil` when calorie
    /// tracking is off in settings, even though the row itself always
    /// carries the scaled figure (settings govern presentation, not storage;
    /// nothing here is thrown away because a toggle happened to be off).
    public let caloriesLogged: Double?

    public var hasWarnings: Bool { !warnings.isEmpty }

    public init(hydrationLogID: String, warnings: [DrinkLoggingWarning] = [], caloriesLogged: Double? = nil) {
        self.hydrationLogID = hydrationLogID
        self.warnings = warnings
        self.caloriesLogged = caloriesLogged
    }
}

public struct DrinkLoggingWarning: Sendable, Hashable {
    public enum WarningType: String, Sendable, Hashable {
        case possibleDoubleTrack = "double_track"
        case highSugar = "high_sugar"
        case highSodium = "high_sodium"
    }

    public let type: WarningType
    public let message: String

    public init(type: WarningType, message: String) {
        self.type = type
        self.message = message
    }
}
