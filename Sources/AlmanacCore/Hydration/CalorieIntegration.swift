import Foundation

/// Manages calorie tracking integration with hydration logging
public final class CalorieIntegration: Sendable {
    private let db: Database

    public init(database: Database) {
        self.db = database
    }

    // MARK: - Calorie Entry

    /// Log calories from a drink
    /// - Parameters:
    ///   - hydrationSampleId: The hydration sample that generated the calories
    ///   - drink: The drink that was consumed
    ///   - calorieAmount: Calculated calories (may differ from drink default if custom volume)
    /// - Returns: Calorie entry ID
    public func logCalories(
        hydrationSampleId: String,
        drink: Drink,
        calorieAmount: Double
    ) throws -> String {
        let entryId = UUID().uuidString

        try db.execute("""
        INSERT INTO hydration_calorie_entry (
            id, hydration_sample_id, drink_id, drink_name, calories_kcal,
            sugar_grams, timestamp, double_track_warning
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, [
            entryId,
            hydrationSampleId,
            drink.id,
            drink.name,
            calorieAmount,
            drink.sugarGrams as Any,
            ISO8601DateFormatter().string(from: Date()),
            0  // Will be set if double-tracking detected
        ])

        return entryId
    }

    /// Fetch calorie entries for a date range
    public func fetchCalories(
        from startDate: Date,
        to endDate: Date
    ) throws -> [CalorieEntry] {
        let startISO = ISO8601DateFormatter().string(from: startDate)
        let endISO = ISO8601DateFormatter().string(from: endDate)

        let rows = try db.query("""
        SELECT id, hydration_sample_id, drink_id, drink_name, calories_kcal,
               sugar_grams, timestamp, double_track_warning
        FROM hydration_calorie_entry
        WHERE timestamp >= ? AND timestamp <= ?
        ORDER BY timestamp DESC
        """, [startISO, endISO])

        return rows.compactMap { row in
            guard let id = row["id"] as? String,
                  let sampleId = row["hydration_sample_id"] as? String,
                  let drinkId = row["drink_id"] as? String,
                  let drinkName = row["drink_name"] as? String,
                  let calories = row["calories_kcal"] as? Double,
                  let timestampStr = row["timestamp"] as? String,
                  let timestamp = ISO8601DateFormatter().date(from: timestampStr),
                  let doubleTrackWarning = row["double_track_warning"] as? Int
            else { return nil }

            return CalorieEntry(
                id: id,
                hydrationSampleId: sampleId,
                drinkId: drinkId,
                drinkName: drinkName,
                caloriesKcal: calories,
                sugarGrams: row["sugar_grams"] as? Double,
                timestamp: timestamp,
                hasDoubleTrackWarning: doubleTrackWarning != 0
            )
        }
    }

    /// Get daily calorie total from drinks
    public func getDailyTotal(for date: Date) throws -> DailyCalorieTotal {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let endOfDay = startOfDay.addingTimeInterval(86400)

        let entries = try fetchCalories(from: startOfDay, to: endOfDay)

        let totalCalories = entries.reduce(0) { $0 + $1.caloriesKcal }
        let totalSugar = entries.reduce(0) { $0 + ($1.sugarGrams ?? 0) }
        let warningCount = entries.filter { $0.hasDoubleTrackWarning }.count

        return DailyCalorieTotal(
            date: date,
            totalCaloriesKcal: totalCalories,
            totalSugarGrams: totalSugar,
            entryCount: entries.count,
            doubleTrackWarnings: warningCount
        )
    }

    // MARK: - Double-Track Detection

    /// Detect potential double-tracking
    /// - Returns: List of suspicious entries with warnings
    public func detectDoubleTracking(
        userId: String,
        timeWindowMinutes: Int = 5
    ) throws -> [DoubleTrackingSuspicion] {
        let rows = try db.query("""
        SELECT id, timestamp FROM hydration_calorie_entry
        ORDER BY timestamp DESC
        LIMIT 100
        """, [])

        var suspicions: [DoubleTrackingSuspicion] = []

        for (index, row) in rows.enumerated() {
            guard let id = row["id"] as? String,
                  let timestampStr = row["timestamp"] as? String,
                  let timestamp = ISO8601DateFormatter().date(from: timestampStr)
            else { continue }

            // Check against nearby entries
            for otherRow in rows.suffix(from: index + 1) {
                guard let otherId = otherRow["id"] as? String,
                      let otherTimestampStr = otherRow["timestamp"] as? String,
                      let otherTimestamp = ISO8601DateFormatter().date(from: otherTimestampStr)
                else { continue }

                let timeDiff = abs(timestamp.timeIntervalSince(otherTimestamp)) / 60

                // Flag if within time window and possibly same drink
                if timeDiff <= Double(timeWindowMinutes) {
                    suspicions.append(
                        DoubleTrackingSuspicion(
                            entryId: id,
                            suspiciousWithId: otherId,
                            timeDifferenceSeconds: Int(abs(timestamp.timeIntervalSince(otherTimestamp))),
                            confidence: confidenceScore(timeDiff: timeDiff, timeWindow: timeWindowMinutes)
                        )
                    )
                }
            }
        }

        return suspicions
    }

    /// Delete a calorie entry
    public func deleteEntry(_ id: String) throws {
        try db.execute("DELETE FROM hydration_calorie_entry WHERE id = ?", [id])
    }

    /// Mark an entry as reviewed (double-track warning acknowledged)
    public func markAsReviewed(_ id: String) throws {
        try db.execute(
            "UPDATE hydration_calorie_entry SET double_track_warning = 0 WHERE id = ?",
            [id]
        )
    }

    // MARK: - Private Helpers

    private func confidenceScore(timeDiff: Double, timeWindow: Int) -> Double {
        // Higher confidence if entries are very close in time
        let windowDouble = Double(timeWindow)
        return 1.0 - (timeDiff / windowDouble)
    }
}

// MARK: - Data Models

public struct CalorieEntry: Sendable, Hashable {
    public let id: String
    public let hydrationSampleId: String
    public let drinkId: String
    public let drinkName: String
    public let caloriesKcal: Double
    public let sugarGrams: Double?
    public let timestamp: Date
    public let hasDoubleTrackWarning: Bool

    public init(
        id: String,
        hydrationSampleId: String,
        drinkId: String,
        drinkName: String,
        caloriesKcal: Double,
        sugarGrams: Double? = nil,
        timestamp: Date = Date(),
        hasDoubleTrackWarning: Bool = false
    ) {
        self.id = id
        self.hydrationSampleId = hydrationSampleId
        self.drinkId = drinkId
        self.drinkName = drinkName
        self.caloriesKcal = caloriesKcal
        self.sugarGrams = sugarGrams
        self.timestamp = timestamp
        self.hasDoubleTrackWarning = hasDoubleTrackWarning
    }
}

public struct DailyCalorieTotal: Sendable, Hashable {
    public let date: Date
    public let totalCaloriesKcal: Double
    public let totalSugarGrams: Double
    public let entryCount: Int
    public let doubleTrackWarnings: Int

    public init(
        date: Date,
        totalCaloriesKcal: Double,
        totalSugarGrams: Double,
        entryCount: Int,
        doubleTrackWarnings: Int
    ) {
        self.date = date
        self.totalCaloriesKcal = totalCaloriesKcal
        self.totalSugarGrams = totalSugarGrams
        self.entryCount = entryCount
        self.doubleTrackWarnings = doubleTrackWarnings
    }
}

public struct DoubleTrackingSuspicion: Sendable, Hashable {
    public let entryId: String
    public let suspiciousWithId: String
    public let timeDifferenceSeconds: Int
    public let confidence: Double  // 0.0 to 1.0

    public var confidenceDescription: String {
        switch confidence {
        case 0.8...:
            return "Very High"
        case 0.6..<0.8:
            return "High"
        case 0.4..<0.6:
            return "Moderate"
        default:
            return "Low"
        }
    }

    public init(
        entryId: String,
        suspiciousWithId: String,
        timeDifferenceSeconds: Int,
        confidence: Double
    ) {
        self.entryId = entryId
        self.suspiciousWithId = suspiciousWithId
        self.timeDifferenceSeconds = timeDifferenceSeconds
        self.confidence = confidence
    }
}
