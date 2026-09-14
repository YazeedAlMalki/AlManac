// SwiftUI Components for Hydration Tracking
// Add these to your iOS app target

import SwiftUI

// MARK: - Progress Ring Component

struct ProgressRingView: View {
    let current: Int
    let goal: Int

    var percentage: Double {
        guard goal > 0 else { return 0 }
        return Double(current) / Double(goal)
    }

    var progressColor: Color {
        let percent = min(percentage, 1.0)
        if percent < 0.25 {
            return .red
        } else if percent < 0.5 {
            return .orange
        } else if percent < 1.0 {
            return .yellow
        } else {
            return .green
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                // Background circle
                Circle()
                    .stroke(.gray.opacity(0.2), lineWidth: 12)

                // Progress circle
                Circle()
                    .trim(from: 0, to: min(percentage, 1.0))
                    .stroke(progressColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: percentage)

                // Center text
                VStack(spacing: 4) {
                    Text("\(current)")
                        .font(.system(size: 40, weight: .bold))

                    Text("/ \(goal) ml")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("\(Int(percentage * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(hydrationStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var hydrationStatus: String {
        let percent = min(percentage, 1.0)
        if percent < 0.25 {
            return "🚨 Critical — drink now"
        } else if percent < 0.5 {
            return "⚠️ Low — time to drink"
        } else if percent < 1.0 {
            return "💧 Good progress"
        } else {
            return "✨ Hydration goal met!"
        }
    }
}

// MARK: - Stat Card Component

struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(icon)
                    .font(.title)

                Spacer()

                VStack(alignment: .trailing) {
                    Text(value)
                        .font(.headline)

                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.blue.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Search Bar Component

struct SearchBar: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.gray)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.gray)
                }
            }
        }
        .padding(8)
        .background(.gray.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - Warning Alert Component

struct WarningAlertView: View {
    let warning: DrinkLoggingWarning
    let onDismiss: () -> Void

    var warningColor: Color {
        switch warning.type {
        case .possibleDoubleTrack:
            return .orange
        case .highSugar:
            return .red
        case .highSodium:
            return .blue
        }
    }

    var warningIcon: String {
        switch warning.type {
        case .possibleDoubleTrack:
            return "⚠️"
        case .highSugar:
            return "🚨"
        case .highSodium:
            return "ℹ️"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(warningIcon)
                    .font(.title)

                VStack(alignment: .leading) {
                    Text("Warning")
                        .font(.headline)

                    Text(warning.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 12) {
                Button(action: onDismiss) {
                    Text("Dismiss")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: onDismiss) {
                    Text("Keep")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(warningColor)
            }
        }
        .padding()
        .background(warningColor.opacity(0.1))
        .cornerRadius(12)
        .border(warningColor.opacity(0.3), width: 1)
    }
}

// MARK: - Drink Type Emoji Helper

func liquidTypeEmoji(_ type: LiquidType) -> String {
    switch type {
    case .water:
        return "💧"
    case .sportsDrink:
        return "⚡"
    case .electrolyteSolution:
        return "🧂"
    case .coconutWater:
        return "🥥"
    case .juice:
        return "🧃"
    case .tea:
        return "🍵"
    case .coffee:
        return "☕"
    case .milk:
        return "🥛"
    case .other:
        return "🥤"
    }
}

func liquidTypeName(_ type: LiquidType) -> String {
    switch type {
    case .water:
        return "Water"
    case .sportsDrink:
        return "Sports Drink"
    case .electrolyteSolution:
        return "Electrolyte Solution"
    case .coconutWater:
        return "Coconut Water"
    case .juice:
        return "Juice"
    case .tea:
        return "Tea"
    case .coffee:
        return "Coffee"
    case .milk:
        return "Milk"
    case .other:
        return "Other"
    }
}

// MARK: - Weekly Chart Component

struct WeeklyTrendChart: View {
    let metrics: [HydrationMetrics]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly Trend")
                .font(.headline)

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(metrics.prefix(7), id: \.date) { metric in
                    VStack(spacing: 4) {
                        // Bar
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.blue)
                            .frame(
                                height: CGFloat(min(metric.hydrationPercentage / 100 * 80, 80))
                            )

                        // Day label
                        Text(dayOfWeekLabel(metric.date))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 120)
        }
        .padding()
        .background(.gray.opacity(0.05))
        .cornerRadius(12)
    }

    func dayOfWeekLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).prefix(1).uppercased()
    }
}

// MARK: - Drink Consumption Timeline

struct DrinkTimelineView: View {
    let samples: [HydrationSample]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's Drinks")
                .font(.headline)

            if samples.isEmpty {
                Text("No drinks logged yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                VStack(spacing: 8) {
                    ForEach(samples, id: \.id) { sample in
                        DrinkTimelineItemView(sample: sample)
                    }
                }
            }
        }
        .padding()
        .background(.gray.opacity(0.05))
        .cornerRadius(12)
    }
}

struct DrinkTimelineItemView: View {
    let sample: HydrationSample

    var timeAgo: String {
        let interval = Date().timeIntervalSince(sample.timestamp)
        let minutes = Int(interval / 60)

        if minutes < 1 {
            return "Just now"
        } else if minutes < 60 {
            return "\(minutes)m ago"
        } else {
            let hours = minutes / 60
            return "\(hours)h ago"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(liquidTypeEmoji(sample.liquidType))
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(liquidTypeName(sample.liquidType))
                    .font(.subheadline)

                Text(timeAgo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(Int(sample.volumeMilliliters))ml")
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .padding(8)
        .background(.blue.opacity(0.05))
        .cornerRadius(8)
    }
}

// MARK: - Nutrition Facts Popup

struct NutritionFactsView: View {
    let drink: Drink
    let volume: Double?
    @Environment(\.dismiss) var dismiss

    var scaledCalories: Double {
        let scale = drink.volumeMilliliters > 0 ? (volume ?? drink.volumeMilliliters) / drink.volumeMilliliters : 1
        return drink.caloriesKcal * scale
    }

    var scaledSodium: Double {
        let scale = drink.volumeMilliliters > 0 ? (volume ?? drink.volumeMilliliters) / drink.volumeMilliliters : 1
        return drink.sodiumMilligrams * scale
    }

    var scaledSugar: Double {
        let scale = drink.volumeMilliliters > 0 ? (volume ?? drink.volumeMilliliters) / drink.volumeMilliliters : 1
        return (drink.sugarGrams ?? 0) * scale
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text(drink.name)
                    .font(.headline)

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle")
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                NutritionRow(label: "Volume", value: "\(Int(volume ?? drink.volumeMilliliters))ml")
                NutritionRow(label: "Calories", value: "\(Int(scaledCalories)) kcal")
                NutritionRow(label: "Sodium", value: "\(Int(scaledSodium))mg")
                if scaledSugar > 0 {
                    NutritionRow(label: "Sugar", value: "\(Int(scaledSugar))g", warning: scaledSugar > 35)
                }
            }

            Spacer()
        }
        .padding()
    }
}

struct NutritionRow: View {
    let label: String
    let value: String
    var warning: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(warning ? .red : .primary)
        }
    }
}

// MARK: - Empty State View

struct HydrationEmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "drop.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue.opacity(0.5))

            Text("Stay Hydrated!")
                .font(.headline)

            Text("Log your first drink to get started")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(action: {}) {
                Label("Log Drink", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 16)
        }
        .padding(32)
        .multilineTextAlignment(.center)
    }
}
