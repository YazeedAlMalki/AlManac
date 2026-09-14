import Foundation

/// Unified service for logging drinks with optional calorie tracking
/// Handles double-tracking prevention and settings integration
public final class HydrationLoggingService: Sendable {
    private let hydrationStore: HydrationStore
    private let calorieIntegration: CalorieIntegration
    private let settingsStore: HydrationSettingsStore

    public init(
        hydrationStore: HydrationStore,
        calorieIntegration: CalorieIntegration,
        settingsStore: HydrationSettingsStore
    ) {
        self.hydrationStore = hydrationStore
        self.calorieIntegration = calorieIntegration
        self.settingsStore = settingsStore
    }

    /// Log a drink with automatic calorie tracking if enabled
    /// - Parameters:
    ///   - drink: The drink being logged
    ///   - customVolume: Optional custom volume (otherwise use drink default)
    ///   - userId: User ID for settings lookup
    /// - Returns: Result with sample ID and any warnings
    public func logDrink(
        drink: Drink,
        customVolume: Double? = nil,
        userId: String
    ) async throws -> DrinkLoggingResult {
        let volume = customVolume ?? drink.volumeMilliliters
        // Every per-serving figure (sodium, calories, sugar) scales with a
        // custom volume — logging half a can must not credit a full can's
        // nutrition, and must not silently skip a full can's warnings either.
        let scale = drink.volumeMilliliters > 0 ? volume / drink.volumeMilliliters : 1
        let scaledSodium = drink.sodiumMilligrams * scale
        let scaledCalories = drink.caloriesKcal * scale
        let scaledSugar = drink.sugarGrams.map { $0 * scale }

        var warnings: [DrinkLoggingWarning] = []

        // Create hydration sample
        let sample = HydrationSample(
            id: UUID().uuidString,
            timestamp: Date(),
            volumeMilliliters: volume,
            liquidType: drink.liquidType,
            sodiumMilligrams: scaledSodium,
            caloriesKcal: scaledCalories,
            sourceName: "manual"
        )

        try hydrationStore.save(sample)

        // Get settings
        let settings = try settingsStore.getOrCreate(for: userId)

        // Handle calorie tracking if enabled
        var calorieEntryId: String?
        if settings.isCalorieTrackingEnabled && scaledCalories > 0 {
            calorieEntryId = try calorieIntegration.logCalories(
                hydrationSampleId: sample.id,
                drink: drink,
                calorieAmount: scaledCalories,
                sugarAmount: scaledSugar
            )

            // Check for double-tracking if warnings enabled
            if settings.isDoubleTrackWarningEnabled {
                let suspicions = try calorieIntegration.detectDoubleTracking(
                    userId: userId,
                    entryId: calorieEntryId!,
                    timeWindowMinutes: 5
                )

                if !suspicions.isEmpty {
                    warnings.append(
                        DrinkLoggingWarning(
                            type: .possibleDoubleTrack,
                            message: "⚠️ Similar drink logged \(suspicions.first!.timeDifferenceSeconds)s ago. Did you mean to log this drink?"
                        )
                    )
                }
            }
        }

        // Add warning if high sugar
        if settings.trackSugar, let sugar = scaledSugar, sugar > 35 {
            warnings.append(
                DrinkLoggingWarning(
                    type: .highSugar,
                    message: "⚠️ This drink has \(Int(sugar))g sugar (high)"
                )
            )
        }

        // Add warning if high sodium and not exercise time
        if settings.trackSodium && scaledSodium > 300 {
            warnings.append(
                DrinkLoggingWarning(
                    type: .highSodium,
                    message: "ℹ️ This drink has high sodium. Ideal during/after exercise"
                )
            )
        }

        return DrinkLoggingResult(
            hydrationSampleId: sample.id,
            calorieEntryId: calorieEntryId,
            warnings: warnings,
            calorieAmount: settings.isCalorieTrackingEnabled ? scaledCalories : nil
        )
    }

    /// Log a custom drink
    /// - Parameters:
    ///   - name: Drink name
    ///   - liquidType: Type of liquid
    ///   - volume: Volume in milliliters
    ///   - calories: Calories in kcal
    ///   - sodium: Sodium in mg
    ///   - sugar: Sugar in grams
    ///   - userId: User ID (to save as custom drink)
    public func logCustomDrink(
        name: String,
        liquidType: LiquidType,
        volume: Double,
        calories: Double,
        sodium: Double,
        sugar: Double?,
        userId: String
    ) async throws -> DrinkLoggingResult {
        let drink = Drink(
            id: UUID().uuidString,
            name: name,
            liquidType: liquidType,
            volumeMilliliters: volume,
            caloriesKcal: calories,
            sodiumMilligrams: sodium,
            sugarGrams: sugar,
            isCustom: true,
            userId: userId
        )

        // Save as custom drink first
        try saveCustomDrink(drink)

        // Log it
        return try await logDrink(drink: drink, userId: userId)
    }

    /// Save a custom drink for future use
    public func saveCustomDrink(_ drink: Drink) throws {
        guard drink.isCustom else {
            throw DrinkLoggingError.notACustomDrink
        }
        guard let userId = drink.userId else {
            throw DrinkLoggingError.missingUserId
        }

        try hydrationStore.db.run("""
        INSERT INTO hydration_custom_drink (
            id, user_id, name, liquid_type, volume_ml, calories_kcal,
            sodium_mg, sugar_grams, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            name          = excluded.name,
            liquid_type   = excluded.liquid_type,
            volume_ml     = excluded.volume_ml,
            calories_kcal = excluded.calories_kcal,
            sodium_mg     = excluded.sodium_mg,
            sugar_grams   = excluded.sugar_grams;
        """, [
            .text(drink.id),
            .text(userId),
            .text(drink.name),
            .text(drink.liquidType.rawValue),
            .real(drink.volumeMilliliters),
            .real(drink.caloriesKcal),
            .real(drink.sodiumMilligrams),
            drink.sugarGrams.map { SQLValue.real($0) } ?? .null,
            .text(ISO8601DateFormatter().string(from: drink.createdAt))
        ])
    }

    /// Get user's custom drinks
    public func getCustomDrinks(for userId: String) throws -> [Drink] {
        let iso = ISO8601DateFormatter()
        let rows = try hydrationStore.db.query("""
        SELECT * FROM hydration_custom_drink
        WHERE user_id = ?
        ORDER BY created_at DESC
        """, [.text(userId)])

        return rows.compactMap { row in
            guard let id = row.string("id"),
                  let name = row.string("name"),
                  let liquidTypeStr = row.string("liquid_type"),
                  let liquidType = LiquidType(rawValue: liquidTypeStr),
                  let volume = row.double("volume_ml"),
                  let calories = row.double("calories_kcal"),
                  let sodium = row.double("sodium_mg"),
                  let userIdStr = row.string("user_id"),
                  let createdAtStr = row.string("created_at"),
                  let createdAt = iso.date(from: createdAtStr)
            else { return nil }

            return Drink(
                id: id,
                name: name,
                liquidType: liquidType,
                volumeMilliliters: volume,
                caloriesKcal: calories,
                sodiumMilligrams: sodium,
                sugarGrams: row.double("sugar_grams"),
                isCustom: true,
                userId: userIdStr,
                createdAt: createdAt
            )
        }
    }

    /// Delete a logged drink
    public func deleteLoggedDrink(_ sampleId: String) throws {
        // Delete hydration sample
        try hydrationStore.deleteSample(sampleId)

        // Delete associated calorie entry if exists
        try hydrationStore.db.run(
            "DELETE FROM hydration_calorie_entry WHERE hydration_sample_id = ?",
            [.text(sampleId)]
        )
    }

    /// Get summary for today
    public func getTodaySummary(userId: String) async throws -> DrinkLoggingSummary {
        let settings = try settingsStore.getOrCreate(for: userId)
        let today = Calendar.current.startOfDay(for: Date())
        let samples = try hydrationStore.fetchSamples(userId: userId, from: today, to: Date())

        var totalCalories = 0.0
        var totalSugar = 0.0
        if settings.isCalorieTrackingEnabled {
            let entries = try calorieIntegration.fetchCalories(from: today, to: Date())
            totalCalories = entries.reduce(0) { $0 + $1.caloriesKcal }
            totalSugar = entries.reduce(0) { $0 + ($1.sugarGrams ?? 0) }
        }

        let totalSodium = samples.reduce(0) { $0 + ($1.sodiumMilligrams ?? 0) }

        return DrinkLoggingSummary(
            date: today,
            drinkCount: samples.count,
            totalVolumeMl: samples.reduce(0) { $0 + $1.volumeMilliliters },
            totalCaloriesKcal: totalCalories,
            totalSugarGrams: totalSugar,
            totalSodiumMg: totalSodium,
            isCalorieTrackingEnabled: settings.isCalorieTrackingEnabled
        )
    }

    /// Undo last drink log
    public func undoLastDrink(userId: String) throws -> String? {
        let today = Calendar.current.startOfDay(for: Date())
        let samples = try hydrationStore.fetchSamples(userId: userId, from: today, to: Date())

        guard let lastSample = samples.first else {
            return nil
        }

        try deleteLoggedDrink(lastSample.id)
        return lastSample.id
    }
}

// MARK: - Data Models

public struct DrinkLoggingResult: Sendable, Hashable {
    public let hydrationSampleId: String
    public let calorieEntryId: String?
    public let warnings: [DrinkLoggingWarning]
    public let calorieAmount: Double?  // Logged calorie amount (if tracking enabled)

    public var hasWarnings: Bool { !warnings.isEmpty }
    public var warningMessage: String? {
        warnings.map { $0.message }.joined(separator: "\n")
    }

    public init(
        hydrationSampleId: String,
        calorieEntryId: String? = nil,
        warnings: [DrinkLoggingWarning] = [],
        calorieAmount: Double? = nil
    ) {
        self.hydrationSampleId = hydrationSampleId
        self.calorieEntryId = calorieEntryId
        self.warnings = warnings
        self.calorieAmount = calorieAmount
    }
}

public struct DrinkLoggingWarning: Sendable, Hashable {
    public enum WarningType: String, Sendable, Hashable {
        case possibleDoubleTrack = "double_track"
        case highSugar = "high_sugar"
        case highSodium = "high_sodium"
        case highCalories = "high_calories"
    }

    public let type: WarningType
    public let message: String

    public init(type: WarningType, message: String) {
        self.type = type
        self.message = message
    }
}

public struct DrinkLoggingSummary: Sendable, Hashable {
    public let date: Date
    public let drinkCount: Int
    public let totalVolumeMl: Double
    public let totalCaloriesKcal: Double
    public let totalSugarGrams: Double
    public let totalSodiumMg: Double
    public let isCalorieTrackingEnabled: Bool

    public init(
        date: Date,
        drinkCount: Int,
        totalVolumeMl: Double,
        totalCaloriesKcal: Double = 0,
        totalSugarGrams: Double = 0,
        totalSodiumMg: Double = 0,
        isCalorieTrackingEnabled: Bool = false
    ) {
        self.date = date
        self.drinkCount = drinkCount
        self.totalVolumeMl = totalVolumeMl
        self.totalCaloriesKcal = totalCaloriesKcal
        self.totalSugarGrams = totalSugarGrams
        self.totalSodiumMg = totalSodiumMg
        self.isCalorieTrackingEnabled = isCalorieTrackingEnabled
    }
}

public enum DrinkLoggingError: Error, Sendable {
    case notACustomDrink
    case missingUserId
    case databaseError(String)
}
