import Foundation

/// Store for persisting and retrieving hydration data
public final class HydrationStore: Sendable {
    private let db: Database

    public init(database: Database) {
        self.db = database
    }

    // MARK: - Sample Operations

    public func save(_ sample: HydrationSample) throws {
        try db.execute("""
        INSERT OR REPLACE INTO hydration_sample (
            id, timestamp, volume_ml, liquid_type, sodium_mg, calories_kcal, source_name
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
        """, [
            sample.id,
            ISO8601DateFormatter().string(from: sample.timestamp),
            sample.volumeMilliliters,
            sample.liquidType.rawValue,
            sample.sodiumMilligrams as Any,
            sample.caloriesKcal as Any,
            sample.sourceName as Any
        ])
    }

    public func fetchSamples(
        from startDate: Date,
        to endDate: Date
    ) throws -> [HydrationSample] {
        let startISO = ISO8601DateFormatter().string(from: startDate)
        let endISO = ISO8601DateFormatter().string(from: endDate)

        let rows = try db.query("""
        SELECT id, timestamp, volume_ml, liquid_type, sodium_mg, calories_kcal, source_name
        FROM hydration_sample
        WHERE timestamp >= ? AND timestamp <= ?
        ORDER BY timestamp DESC
        """, [startISO, endISO])

        return rows.compactMap { row in
            guard let id = row["id"] as? String,
                  let timestampStr = row["timestamp"] as? String,
                  let volumeMl = row["volume_ml"] as? Double,
                  let liquidTypeStr = row["liquid_type"] as? String,
                  let liquidType = LiquidType(rawValue: liquidTypeStr),
                  let timestamp = ISO8601DateFormatter().date(from: timestampStr)
            else { return nil }

            return HydrationSample(
                id: id,
                timestamp: timestamp,
                volumeMilliliters: volumeMl,
                liquidType: liquidType,
                sodiumMilligrams: row["sodium_mg"] as? Double,
                caloriesKcal: row["calories_kcal"] as? Double,
                sourceName: row["source_name"] as? String
            )
        }
    }

    public func deleteSample(_ id: String) throws {
        try db.execute("DELETE FROM hydration_sample WHERE id = ?", [id])
    }

    // MARK: - Metrics Operations

    public func save(_ metrics: HydrationMetrics) throws {
        let dateStr = ISO8601DateFormatter().string(from: metrics.date)
        try db.execute("""
        INSERT OR REPLACE INTO hydration_metrics (
            date, total_volume_ml, total_sodium_mg, exercise_minutes,
            recommended_intake_ml, hydration_percentage, sample_count
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
        """, [
            dateStr,
            metrics.totalVolumeMilliliters,
            metrics.totalSodiumMilligrams,
            metrics.exerciseMinutes as Any,
            metrics.recommendedIntakeMilliliters,
            metrics.hydrationPercentage,
            metrics.sampleCount
        ])
    }

    public func fetchMetrics(for date: Date) throws -> HydrationMetrics? {
        let dateStr = ISO8601DateFormatter().string(from: date)
        let rows = try db.query("""
        SELECT * FROM hydration_metrics
        WHERE date = ?
        """, [dateStr])

        guard let row = rows.first,
              let totalVolume = row["total_volume_ml"] as? Double,
              let totalSodium = row["total_sodium_mg"] as? Double,
              let recommendedIntake = row["recommended_intake_ml"] as? Double,
              let sampleCount = row["sample_count"] as? Int
        else { return nil }

        return HydrationMetrics(
            date: date,
            totalVolumeMilliliters: totalVolume,
            totalSodiumMilligrams: totalSodium,
            exerciseMinutes: row["exercise_minutes"] as? Double,
            recommendedIntakeMilliliters: recommendedIntake,
            sampleCount: sampleCount
        )
    }

    public func fetchMetrics(
        from startDate: Date,
        to endDate: Date
    ) throws -> [HydrationMetrics] {
        let startISO = ISO8601DateFormatter().string(from: startDate)
        let endISO = ISO8601DateFormatter().string(from: endDate)

        let rows = try db.query("""
        SELECT * FROM hydration_metrics
        WHERE date >= ? AND date <= ?
        ORDER BY date DESC
        """, [startISO, endISO])

        return rows.compactMap { row in
            guard let dateStr = row["date"] as? String,
                  let date = ISO8601DateFormatter().date(from: dateStr),
                  let totalVolume = row["total_volume_ml"] as? Double,
                  let totalSodium = row["total_sodium_mg"] as? Double,
                  let recommendedIntake = row["recommended_intake_ml"] as? Double,
                  let sampleCount = row["sample_count"] as? Int
            else { return nil }

            return HydrationMetrics(
                date: date,
                totalVolumeMilliliters: totalVolume,
                totalSodiumMilligrams: totalSodium,
                exerciseMinutes: row["exercise_minutes"] as? Double,
                recommendedIntakeMilliliters: recommendedIntake,
                sampleCount: sampleCount
            )
        }
    }

    // MARK: - Profile Operations

    public func save(_ profile: HydrationProfile) throws {
        try db.execute("""
        INSERT OR REPLACE INTO hydration_profile (
            user_id, baseline_intake_ml, body_weight_kg, activity_level, updated_at
        ) VALUES (?, ?, ?, ?, ?)
        """, [
            profile.userId,
            profile.baselineIntakeMilliliters,
            profile.bodyWeightKg as Any,
            profile.activityLevel.rawValue,
            ISO8601DateFormatter().string(from: profile.updatedAt)
        ])
    }

    public func fetchProfile(for userId: String) throws -> HydrationProfile? {
        let rows = try db.query("""
        SELECT * FROM hydration_profile
        WHERE user_id = ?
        """, [userId])

        guard let row = rows.first,
              let baselineIntake = row["baseline_intake_ml"] as? Double,
              let activityLevelStr = row["activity_level"] as? String,
              let activityLevel = ActivityLevel(rawValue: activityLevelStr),
              let updatedAtStr = row["updated_at"] as? String,
              let updatedAt = ISO8601DateFormatter().date(from: updatedAtStr)
        else { return nil }

        return HydrationProfile(
            userId: userId,
            baselineIntakeMilliliters: baselineIntake,
            bodyWeightKg: row["body_weight_kg"] as? Double,
            activityLevel: activityLevel,
            updatedAt: updatedAt
        )
    }

    // MARK: - Reminder Operations

    public func save(_ reminder: HydrationReminder) throws {
        try db.execute("""
        INSERT OR REPLACE INTO hydration_reminder (
            id, interval_minutes, start_hour, end_hour, is_enabled, created_at
        ) VALUES (?, ?, ?, ?, ?, ?)
        """, [
            reminder.id,
            reminder.intervalMinutes,
            reminder.startHour,
            reminder.endHour,
            reminder.isEnabled ? 1 : 0,
            ISO8601DateFormatter().string(from: reminder.createdAt)
        ])
    }

    public func fetchReminders() throws -> [HydrationReminder] {
        let rows = try db.query("""
        SELECT * FROM hydration_reminder
        ORDER BY created_at DESC
        """, [])

        return rows.compactMap { row in
            guard let id = row["id"] as? String,
                  let intervalMinutes = row["interval_minutes"] as? Int,
                  let startHour = row["start_hour"] as? Int,
                  let endHour = row["end_hour"] as? Int,
                  let isEnabledInt = row["is_enabled"] as? Int,
                  let createdAtStr = row["created_at"] as? String,
                  let createdAt = ISO8601DateFormatter().date(from: createdAtStr)
            else { return nil }

            return HydrationReminder(
                id: id,
                intervalMinutes: intervalMinutes,
                startHour: startHour,
                endHour: endHour,
                isEnabled: isEnabledInt != 0,
                createdAt: createdAt
            )
        }
    }

    public func deleteReminder(_ id: String) throws {
        try db.execute("DELETE FROM hydration_reminder WHERE id = ?", [id])
    }

    // MARK: - Convenience Methods

    public func calculateTodayMetrics(
        calculator: HydrationCalculator,
        profile: HydrationProfile
    ) throws -> HydrationMetrics {
        let today = Calendar.current.startOfDay(for: Date())
        let samples = try fetchSamples(from: today, to: Date())

        let totalVolume = samples.reduce(0) { $0 + $1.volumeMilliliters }
        let totalSodium = samples.reduce(0) { $0 + ($1.sodiumMilligrams ?? 0) }

        // Fetch exercise minutes from health data (assumes integration with Health module)
        let exerciseMinutes: Double? = nil  // Will be populated from Health module integration

        let recommendedIntake = calculator.recommendedDailyIntake(
            profile: profile,
            exerciseMinutes: exerciseMinutes ?? 0
        )

        return HydrationMetrics(
            date: today,
            totalVolumeMilliliters: totalVolume,
            totalSodiumMilligrams: totalSodium,
            exerciseMinutes: exerciseMinutes,
            recommendedIntakeMilliliters: recommendedIntake,
            sampleCount: samples.count
        )
    }
}
