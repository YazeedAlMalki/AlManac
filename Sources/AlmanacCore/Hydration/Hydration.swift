import Foundation

/// Public API for Hydration tracking module
///
/// The hydration module provides comprehensive tracking of fluid intake with:
/// - Personalized recommendations based on activity and user profile
/// - Adaptive metrics that learn from user behavior
/// - Configurable reminders with smart timing
/// - Multiple liquid types with electrolyte and sodium tracking
///
/// Usage:
/// ```swift
/// let calculator = HydrationCalculator()
/// let store = HydrationStore(database: db)
/// let reminder = HydrationReminderService(store: store, calculator: calculator)
///
/// // Create user profile
/// let profile = HydrationProfile(userId: "user123", bodyWeightKg: 70)
/// try store.save(profile)
///
/// // Log hydration
/// let sample = HydrationSample(
///     id: UUID().uuidString,
///     userId: "user123",
///     timestamp: Date(),
///     volumeMilliliters: 250,
///     liquidType: .water
/// )
/// try store.save(sample)
///
/// // Get recommendation
/// let metrics = try store.calculateTodayMetrics(
///     userId: "user123",
///     calculator: calculator,
///     profile: profile
/// )
/// let recommendation = calculator.currentRecommendation(
///     timeSinceLastDrinkMinutes: 30,
///     exerciseActive: false,
///     metrics: metrics,
///     profile: profile
/// )
/// ```
public enum HydrationModule {
    /// All public types exported by the hydration module
    public static let types: [Any.Type] = [
        HydrationSample.self,
        HydrationMetrics.self,
        HydrationReminder.self,
        HydrationProfile.self,
        HydrationRecommendation.self,
        HydrationCalculator.self,
        HydrationStore.self,
        HydrationReminderService.self,
        LiquidType.self,
        ActivityLevel.self,
        Urgency.self
    ]
}
