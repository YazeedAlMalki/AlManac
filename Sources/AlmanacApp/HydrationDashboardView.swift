import SwiftUI
import AlmanacCore

struct HydrationDashboardView: View {
    @ObservedObject var viewModel: HydrationViewModel
    @ObservedObject var healthKitManager: HealthKitManager
    @State private var autoRefreshTimer: Timer?

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    DashboardHeaderView()
                        .padding()

                    if viewModel.isLoading {
                        ProgressView()
                            .frame(maxHeight: .infinity, alignment: .center)
                    } else if let metrics = viewModel.todayMetrics {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 24) {
                                if healthKitManager.isExerciseActive {
                                    ExerciseContextCardView(
                                        workoutType: healthKitManager.activeWorkoutType,
                                        heartRate: healthKitManager.currentHeartRate
                                    )
                                }

                                HydrationCircleProgressView(
                                    current: Double(metrics.totalVolumeMilliliters),
                                    goal: viewModel.recommendedVolume
                                )
                                .padding()

                                MetricsGridView(
                                    consumed: metrics.totalVolumeMilliliters,
                                    goal: Int(viewModel.recommendedVolume),
                                    remaining: max(0, Int(viewModel.recommendedVolume) - metrics.totalVolumeMilliliters)
                                )

                                DrinkTimelineView(
                                    drinkHistory: viewModel.drinkHistory,
                                    isEmpty: viewModel.drinkHistory.isEmpty
                                )

                                if let errorMessage = viewModel.errorMessage {
                                    ErrorBannerView(message: errorMessage)
                                }
                            }
                            .padding()
                        }
                    } else {
                        ContentUnavailableView(
                            "No Data",
                            systemImage: "drop",
                            description: Text("Unable to load today's metrics")
                        )
                    }
                }

                VStack {
                    HStack {
                        Spacer()
                        Button(action: {
                            Task {
                                try await viewModel.loadTodayMetrics()
                                try await viewModel.loadDrinkHistory()
                            }
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.blue)
                                .padding()
                        }
                    }
                    Spacer()
                }
                .padding()
            }
            .onAppear {
                Task {
                    try await viewModel.loadTodayMetrics()
                    try await viewModel.loadDrinkHistory()
                }
                startAutoRefresh()
            }
            .onDisappear {
                stopAutoRefresh()
            }
        }
    }

    private func startAutoRefresh() {
        autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task {
                try await viewModel.loadTodayMetrics()
            }
        }
    }

    private func stopAutoRefresh() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = nil
    }
}

struct DashboardHeaderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Today's Progress")
                .font(.title2)
                .fontWeight(.bold)
            Text(Date().formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HydrationCircleProgressView: View {
    let current: Double
    let goal: Double

    var progress: Double {
        min(current / goal, 1.0)
    }

    var statusMessage: String {
        let percentage = Int(progress * 100)
        if percentage >= 100 {
            return "Goal achieved! 🎉"
        } else if percentage >= 75 {
            return "Almost there!"
        } else if percentage >= 50 {
            return "Halfway there"
        } else {
            return "Keep going"
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 12)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [.blue, .cyan]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotation(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: progress)

                VStack(spacing: 4) {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 36, weight: .bold, design: .default))
                    Text("Hydrated")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(height: 200)

            VStack(spacing: 4) {
                Text(statusMessage)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text("\(Int(current))ml of \(Int(goal))ml")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct MetricsGridView: View {
    let consumed: Int
    let goal: Int
    let remaining: Int

    var body: some View {
        HStack(spacing: 12) {
            StatCard(
                title: "Consumed",
                value: "\(consumed)ml",
                icon: "drop.fill",
                color: .blue
            )

            StatCard(
                title: "Goal",
                value: "\(goal)ml",
                icon: "target",
                color: .green
            )

            StatCard(
                title: "Remaining",
                value: "\(remaining)ml",
                icon: "hourglass",
                color: .orange
            )
        }
        .padding(.horizontal)
    }
}

struct DrinkTimelineView: View {
    let drinkHistory: [HydrationSample]
    let isEmpty: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Drink Timeline")
                .font(.headline)
                .padding(.horizontal)

            if isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "drop")
                        .font(.title)
                        .foregroundColor(.gray)
                    Text("No drinks logged yet")
                        .foregroundColor(.secondary)
                    Text("Start logging your hydration")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
                .padding(.horizontal)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(drinkHistory.reversed().enumerated()), id: \.element.id) { _, sample in
                        TimelineEntryView(sample: sample)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct ErrorBannerView: View {
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("Error")
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(message)
                    .font(.caption)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .border(Color.red.opacity(0.3), width: 1)
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

struct ExerciseContextCardView: View {
    let workoutType: String?
    let heartRate: Int?

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "figure.walk")
                    .font(.title2)
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Active Exercise")
                        .font(.headline)
                    if let workoutType = workoutType {
                        Text(workoutType)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if let heartRate = heartRate {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(heartRate)")
                            .font(.headline)
                            .foregroundColor(.orange)
                        Text("BPM")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Text("You're exercising! Increase your hydration intake to compensate for fluid loss. The app will suggest larger drink volumes.")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(3)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .border(Color.orange.opacity(0.3), width: 1)
        .cornerRadius(8)
        .padding(.horizontal)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

struct TimelineEntryView: View {
    let sample: HydrationSample

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(liquidTypeName(sample.liquidType))
                    .font(.headline)

                Text(sample.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text("\(sample.volumeMilliliters)ml")
                .font(.headline)
                .foregroundColor(.blue)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    private func liquidTypeName(_ type: LiquidType) -> String {
        switch type {
        case .water:
            return "💧 Water"
        case .sportsDrink:
            return "⚡ Sports Drink"
        case .electrolyteSolution:
            return "🧂 Electrolyte"
        case .coconutWater:
            return "🥥 Coconut Water"
        case .juice:
            return "🧃 Juice"
        case .tea:
            return "🍵 Tea"
        case .coffee:
            return "☕ Coffee"
        case .milk:
            return "🥛 Milk"
        case .other:
            return "🥤 Other"
        }
    }
}

#Preview {
    let store = HydrationStore(databasePath: ":memory:")
    let calculator = HydrationCalculator()
    let loggingService = HydrationLoggingService(store: store, calculator: calculator)
    let reminderService = HydrationReminderService(store: store, calculator: calculator)
    let viewModel = HydrationViewModel(
        store: store,
        calculator: calculator,
        loggingService: loggingService,
        reminderService: reminderService
    )
    let healthKitManager = HealthKitManager()

    HydrationDashboardView(viewModel: viewModel, healthKitManager: healthKitManager)
}
