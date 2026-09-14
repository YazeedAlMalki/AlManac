import Foundation

/// Manages calorie tracking integration with hydration logging
public final class CalorieIntegration: Sendable {
    private let db: Database
    private var iso: ISO8601DateFormatter { ISO8601DateFormatter() }

    public init(database: Database) {
        self.db = database
    }

    // MARK: - Calorie Entry

    /// Log calories from a drink
    /// - Parameters:
    ///   - hydrationSampleId: The hydration sample that generated the calories
    ///   - drink: The drink that was consumed
    ///   - calorieAmount: Calculated calories (may differ from drink default if custom volume)
    ///   - sugarAmount: Calculated sugar (may differ from drink default if custom volume)
    /// - Returns: Calorie entry ID
    @discardableResult
    public func logCalories(
        hydrationSampleId: String,
        drink: Drink,
        calorieAmount: Double,
        sugarAmount: Double?
    ) throws -> String {
        let entryId = UUID().uuidString

        try db.run("""
        INSERT INTO hydration_calorie_entry (
            id, hydration_sample_id, drink_id, drink_name, calories_kcal,
            sugar_grams, timestamp, double_track_warning
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, [
            .text(entryId),
            .text(hydrationSampleId),
            .text(drink.id),
            .text(drink.name),
            .real(calorieAmount),
            sugarAmount.map { SQLValue.real($0) } ?? .null,
            .text(iso.string(from: Date())),
            .integer(0)  // Set by a later detectDoubleTracking pass if suspicious.
        ])

        return entryId
    }

    /// Fetch calorie entries for a date range
    public func fetchCalories(from startDate: Date, to endDate: Date) throws -> [CalorieEntry] {
        let rows = try db.query("""
        SELECT id, hydration_sample_id, drink_id, drink_name, calories_kcal,
               sugar_grams, timestamp, double_track_warning
        FROM hydration_calorie_entry
        WHERE timestamp >= ? AND timestamp <= ?
        ORDER BY timestamp DESC
        """, [.text(iso.string(from: startDate)), .text(iso.string(from: endDate))])

        return rows.compactMap { row in
            guard let id = row.string("id"),
                  let sampleId = row.string("hydration_sample_id"),
                  let drinkId = row.string("drink_id"),
                  let drinkName = row.string("drink_name"),
                  let calories = row.double("calories_kcal"),
                  let timestampStr = row.string("timestamp"),
                  let timestamp = iso.date(from: timestampStr),
                  let doubleTrackWarning = row.int("double_track_warning")
            else { return nil }

            return CalorieEntry(
                id: id,
                hydrationSampleId: sampleId,
                drinkId: drinkId,
                drinkName: drinkName,
                caloriesKcal: calories,
                sugarGrams: row.double("sugar_grams"),
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

    /// Detect potential double-tracking for a specific entry among recent entries.
    /// Only returns suspicions involving the given entryId.
    /// - Parameters:
    ///   - userId: User ID (for context, though not strictly needed for detection)
    ///   - entryId: The newly logged entry ID to check for duplicates
    ///   - timeWindowMinutes: Minutes to look back for duplicates
    /// - Returns: List of suspicious entries with confidence scores involving this entry
    @discardableResult
    public func detectDoubleTracking(
        userId: String,
        entryId: String,
        timeWindowMinutes: Int = 5
    ) throws -> [DoubleTrackingSuspicion] {
        let rows = try db.query("""
        SELECT id, drink_id, timestamp FROM hydration_calorie_entry
        ORDER BY timestamp DESC
        LIMIT 100
        """)

        struct Entry { let id: String; let drinkId: String; let timestamp: Date }
        let entries: [Entry] = rows.compactMap { row in
            guard let id = row.string("id"),
                  let drinkId = row.string("drink_id"),
                  let timestampStr = row.string("timestamp"),
                  let timestamp = iso.date(from: timestampStr)
            else { return nil }
            return Entry(id: id, drinkId: drinkId, timestamp: timestamp)
        }

        guard let newEntry = entries.first(where: { $0.id == entryId }) else {
            return []
        }

        var suspicions: [DoubleTrackingSuspicion] = []
        let windowSeconds = Double(timeWindowMinutes) * 60

        for entry in entries where entry.id != newEntry.id {
            // Same drink only — a Pepsi and a coffee three minutes apart
            // are two real drinks, not a duplicate.
            guard entry.drinkId == newEntry.drinkId else { continue }

            let diffSeconds = abs(newEntry.timestamp.timeIntervalSince(entry.timestamp))
            guard diffSeconds <= windowSeconds else { continue }

            let confidence = 1.0 - (diffSeconds / windowSeconds)
            suspicions.append(
                DoubleTrackingSuspicion(
                    entryId: newEntry.id,
                    suspiciousWithId: entry.id,
                    timeDifferenceSeconds: Int(diffSeconds),
                    confidence: confidence
                )
            )
        }

        if !suspicions.isEmpty {
            let flaggedIds = Set(suspicions.flatMap { [$0.entryId, $0.suspiciousWithId] })
            try db.transaction {
                for id in flaggedIds {
                    try db.run(
                        "UPDATE hydration_calorie_entry SET double_track_warning = 1 WHERE id = ?",
                        [.text(id)]
                    )
                }
            }
        }

        return suspicions
    }

    /// Delete a calorie entry
    public func deleteEntry(_ id: String) throws {
        try db.run("DELETE FROM hydration_calorie_entry WHERE id = ?", [.text(id)])
    }

    /// Mark an entry as reviewed (double-track warning acknowledged)
    public func markAsReviewed(_ id: String) throws {
        try db.run(
            "UPDATE hydration_calorie_entry SET double_track_warning = 0 WHERE id = ?",
            [.text(id)]
        )
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
