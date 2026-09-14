import Foundation

/// Store for persisting and retrieving hydration data.
///
/// Uses `Database.run`/`Database.query` directly — the same seam every other
/// module in this package goes through. There is no ORM layer here.
public final class HydrationStore: Sendable {
    public let db: Database  // Public so CalorieIntegration/HydrationLoggingService share one connection.

    public init(database: Database) {
        self.db = database
    }

    private var iso: ISO8601DateFormatter { ISO8601DateFormatter() }

    // MARK: - Sample Operations

    public func save(_ sample: HydrationSample) throws {
        try db.run("""
        INSERT INTO hydration_sample (
            id, user_id, timestamp, volume_ml, liquid_type, sodium_mg, calories_kcal, source_name
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            timestamp     = excluded.timestamp,
            volume_ml     = excluded.volume_ml,
            liquid_type   = excluded.liquid_type,
            sodium_mg     = excluded.sodium_mg,
            calories_kcal = excluded.calories_kcal,
            source_name   = excluded.source_name;
        """, [
            .text(sample.id),
            .text(sample.userId),
            .text(iso.string(from: sample.timestamp)),
            .real(sample.volumeMilliliters),
            .text(sample.liquidType.rawValue),
            sample.sodiumMilligrams.map { SQLValue.real($0) } ?? .null,
            sample.caloriesKcal.map { SQLValue.real($0) } ?? .null,
            sample.sourceName.map { SQLValue.text($0) } ?? .null
        ])
    }

    public func fetchSamples(userId: String, from startDate: Date, to endDate: Date) throws -> [HydrationSample] {
        let rows = try db.query("""
        SELECT id, user_id, timestamp, volume_ml, liquid_type, sodium_mg, calories_kcal, source_name
        FROM hydration_sample
        WHERE user_id = ? AND timestamp >= ? AND timestamp <= ?
        ORDER BY timestamp DESC
        """, [.text(userId), .text(iso.string(from: startDate)), .text(iso.string(from: endDate))])

        return rows.compactMap { row in
            guard let id = row.string("id"),
                  let userId = row.string("user_id"),
                  let timestampStr = row.string("timestamp"),
                  let timestamp = iso.date(from: timestampStr),
                  let volumeMl = row.double("volume_ml"),
                  let liquidTypeStr = row.string("liquid_type"),
                  let liquidType = LiquidType(rawValue: liquidTypeStr)
            else { return nil }

            return HydrationSample(
                id: id,
                userId: userId,
                timestamp: timestamp,
                volumeMilliliters: volumeMl,
                liquidType: liquidType,
                sodiumMilligrams: row.double("sodium_mg"),
                caloriesKcal: row.double("calories_kcal"),
                sourceName: row.string("source_name")
            )
        }
    }

    public func deleteSample(_ id: String) throws {
        try db.run("DELETE FROM hydration_sample WHERE id = ?", [.text(id)])
    }

    // MARK: - Metrics Operations

    public func save(_ metrics: HydrationMetrics) throws {
        try db.run("""
        INSERT INTO hydration_metrics (
            date, total_volume_ml, total_sodium_mg, exercise_minutes,
            recommended_intake_ml, hydration_percentage, sample_count
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(date) DO UPDATE SET
            total_volume_ml        = excluded.total_volume_ml,
            total_sodium_mg        = excluded.total_sodium_mg,
            exercise_minutes       = excluded.exercise_minutes,
            recommended_intake_ml  = excluded.recommended_intake_ml,
            hydration_percentage   = excluded.hydration_percentage,
            sample_count           = excluded.sample_count;
        """, [
            .text(dayKey(metrics.date)),
            .real(metrics.totalVolumeMilliliters),
            .real(metrics.totalSodiumMilligrams),
            metrics.exerciseMinutes.map { SQLValue.real($0) } ?? .null,
            .real(metrics.recommendedIntakeMilliliters),
            .real(metrics.hydrationPercentage),
            .integer(Int64(metrics.sampleCount))
        ])
    }

    public func fetchMetrics(for date: Date) throws -> HydrationMetrics? {
        let rows = try db.query("""
        SELECT * FROM hydration_metrics WHERE date = ?
        """, [.text(dayKey(date))])

        guard let row = rows.first else { return nil }
        return parseMetrics(row, fallbackDate: date)
    }

    public func fetchMetrics(from startDate: Date, to endDate: Date) throws -> [HydrationMetrics] {
        let rows = try db.query("""
        SELECT * FROM hydration_metrics
        WHERE date >= ? AND date <= ?
        ORDER BY date DESC
        """, [.text(dayKey(startDate)), .text(dayKey(endDate))])

        return rows.compactMap { row -> HydrationMetrics? in
            guard let dateStr = row.string("date") else { return nil }
            let date = dayDate(from: dateStr) ?? startDate
            return parseMetrics(row, fallbackDate: date)
        }
    }

    private func parseMetrics(_ row: Row, fallbackDate: Date) -> HydrationMetrics? {
        guard let totalVolume = row.double("total_volume_ml"),
              let totalSodium = row.double("total_sodium_mg"),
              let recommendedIntake = row.double("recommended_intake_ml"),
              let sampleCount = row.int("sample_count")
        else { return nil }

        return HydrationMetrics(
            date: fallbackDate,
            totalVolumeMilliliters: totalVolume,
            totalSodiumMilligrams: totalSodium,
            exerciseMinutes: row.double("exercise_minutes"),
            recommendedIntakeMilliliters: recommendedIntake,
            sampleCount: Int(sampleCount)
        )
    }

    // MARK: - Profile Operations

    public func save(_ profile: HydrationProfile) throws {
        try db.run("""
        INSERT INTO hydration_profile (
            user_id, baseline_intake_ml, body_weight_kg, activity_level, updated_at
        ) VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(user_id) DO UPDATE SET
            baseline_intake_ml = excluded.baseline_intake_ml,
            body_weight_kg     = excluded.body_weight_kg,
            activity_level     = excluded.activity_level,
            updated_at         = excluded.updated_at;
        """, [
            .text(profile.userId),
            .real(profile.baselineIntakeMilliliters),
            profile.bodyWeightKg.map { SQLValue.real($0) } ?? .null,
            .text(profile.activityLevel.rawValue),
            .text(iso.string(from: profile.updatedAt))
        ])
    }

    public func fetchProfile(for userId: String) throws -> HydrationProfile? {
        let rows = try db.query("SELECT * FROM hydration_profile WHERE user_id = ?", [.text(userId)])

        guard let row = rows.first,
              let baselineIntake = row.double("baseline_intake_ml"),
              let activityLevelStr = row.string("activity_level"),
              let activityLevel = ActivityLevel(rawValue: activityLevelStr),
              let updatedAtStr = row.string("updated_at"),
              let updatedAt = iso.date(from: updatedAtStr)
        else { return nil }

        return HydrationProfile(
            userId: userId,
            baselineIntakeMilliliters: baselineIntake,
            bodyWeightKg: row.double("body_weight_kg"),
            activityLevel: activityLevel,
            updatedAt: updatedAt
        )
    }

    // MARK: - Reminder Operations

    public func save(_ reminder: HydrationReminder) throws {
        try db.run("""
        INSERT INTO hydration_reminder (
            id, interval_minutes, start_hour, end_hour, is_enabled, created_at
        ) VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            interval_minutes = excluded.interval_minutes,
            start_hour       = excluded.start_hour,
            end_hour         = excluded.end_hour,
            is_enabled       = excluded.is_enabled;
        """, [
            .text(reminder.id),
            .integer(Int64(reminder.intervalMinutes)),
            .integer(Int64(reminder.startHour)),
            .integer(Int64(reminder.endHour)),
            .integer(reminder.isEnabled ? 1 : 0),
            .text(iso.string(from: reminder.createdAt))
        ])
    }

    public func fetchReminders() throws -> [HydrationReminder] {
        let rows = try db.query("SELECT * FROM hydration_reminder ORDER BY created_at DESC")

        return rows.compactMap { row in
            guard let id = row.string("id"),
                  let intervalMinutes = row.int("interval_minutes"),
                  let startHour = row.int("start_hour"),
                  let endHour = row.int("end_hour"),
                  let isEnabledInt = row.int("is_enabled"),
                  let createdAtStr = row.string("created_at"),
                  let createdAt = iso.date(from: createdAtStr)
            else { return nil }

            return HydrationReminder(
                id: id,
                intervalMinutes: Int(intervalMinutes),
                startHour: Int(startHour),
                endHour: Int(endHour),
                isEnabled: isEnabledInt != 0,
                createdAt: createdAt
            )
        }
    }

    public func deleteReminder(_ id: String) throws {
        try db.run("DELETE FROM hydration_reminder WHERE id = ?", [.text(id)])
    }

    // MARK: - Convenience Methods

    /// Computes today's hydration metrics.
    /// - Parameter healthBridge: Optional bridge into `health_sample` to pull
    ///   today's workout minutes. Pass `nil` to compute without exercise data
    ///   (the exercise boost is then simply not applied).
    public func calculateTodayMetrics(
        calculator: HydrationCalculator,
        profile: HydrationProfile,
        healthBridge: HydrationHealthBridge? = nil
    ) throws -> HydrationMetrics {
        let now = Date()
        let today = Calendar.current.startOfDay(for: now)
        let samples = try fetchSamples(from: today, to: now)

        let totalVolume = samples.reduce(0) { $0 + $1.volumeMilliliters }
        let totalSodium = samples.reduce(0) { $0 + ($1.sodiumMilligrams ?? 0) }

        let exerciseMinutes = try healthBridge?.exerciseMinutes(on: today)

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

    // MARK: - Private Helpers

    /// `hydration_metrics.date` is a logical-day key, not an instant — stored
    /// as `yyyy-MM-dd` so equality and range comparisons are exact regardless
    /// of what time of day the row was written.
    private func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func dayDate(from key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key)
    }
}
