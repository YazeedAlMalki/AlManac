import SwiftUI
import AlmanacCore

struct HydrationDashboardView: View {
    @ObservedObject var viewModel: HydrationViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Today's Progress")
                    .font(.title2)
                    .fontWeight(.bold)

                if viewModel.isLoading {
                    ProgressView()
                } else if let metrics = viewModel.todayMetrics {
                    VStack(spacing: 24) {
                        HydrationCircleProgressView(
                            current: Double(metrics.totalVolumeMilliliters),
                            goal: viewModel.recommendedVolume
                        )

                        HStack(spacing: 16) {
                            StatCard(
                                title: "Consumed",
                                value: "\(metrics.totalVolumeMilliliters)ml",
                                icon: "drop.fill",
                                color: .blue
                            )

                            StatCard(
                                title: "Goal",
                                value: "\(Int(viewModel.recommendedVolume))ml",
                                icon: "target",
                                color: .green
                            )

                            StatCard(
                                title: "Remaining",
                                value: "\(max(0, Int(viewModel.recommendedVolume) - metrics.totalVolumeMilliliters))ml",
                                icon: "hourglass",
                                color: .orange
                            )
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Drink Timeline")
                                .font(.headline)

                            if viewModel.drinkHistory.isEmpty {
                                Text("No drinks logged yet")
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding()
                            } else {
                                ScrollView(.vertical, showsIndicators: false) {
                                    VStack(spacing: 8) {
                                        ForEach(Array(viewModel.drinkHistory.reversed().enumerated()), id: \.element.id) { index, sample in
                                            TimelineEntryView(sample: sample)
                                        }
                                    }
                                }
                            }
                        }

                        if let errorMessage = viewModel.errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(.red)
                                Text(errorMessage)
                                    .font(.caption)
                            }
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    .padding()
                } else {
                    Text("Unable to load metrics")
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding()
            .onAppear {
                Task {
                    try await viewModel.loadTodayMetrics()
                    try await viewModel.loadDrinkHistory()
                }
            }
        }
    }
}

struct HydrationCircleProgressView: View {
    let current: Double
    let goal: Double

    var progress: Double {
        min(current / goal, 1.0)
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

            Text("\(Int(current))ml of \(Int(goal))ml")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
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

    HydrationDashboardView(viewModel: viewModel)
}
