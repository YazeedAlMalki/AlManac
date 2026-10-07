import SwiftUI
import AlmanacCore

struct HydrationLoggingView: View {
    @ObservedObject var viewModel: HydrationViewModel
    @State private var selectedVolume: Int = 250
    @State private var selectedLiquid: LiquidType = .water
    @State private var isLoggingInProgress: Bool = false
    @State private var showSuccessMessage: Bool = false

    private let drinkCategories: [(category: String, drinks: [(name: String, liquid: LiquidType, volume: Int)])] = [
        ("Water", [
            ("Water", .water, 250),
            ("Water (Large)", .water, 500)
        ]),
        ("Sports & Energy", [
            ("Sports Drink", .sportsDrink, 250),
            ("Electrolyte", .electrolyteSolution, 250)
        ]),
        ("Natural", [
            ("Coconut Water", .coconutWater, 200),
            ("Juice", .juice, 200)
        ]),
        ("Hot Drinks", [
            ("Tea", .tea, 200),
            ("Coffee", .coffee, 150)
        ]),
        ("Dairy", [
            ("Milk", .milk, 200)
        ])
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                HeaderView()

                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxHeight: .infinity, alignment: .center)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 20) {
                            DrinkCategoryGridView(
                                categories: drinkCategories,
                                selectedLiquid: $selectedLiquid,
                                selectedVolume: $selectedVolume
                            )

                            VolumeCustomizerView(
                                selectedVolume: $selectedVolume
                            )

                            LoggingActionView(
                                selectedVolume: selectedVolume,
                                selectedLiquid: selectedLiquid,
                                isLoggingInProgress: isLoggingInProgress,
                                showUndoButton: viewModel.showUndoButton,
                                showSuccess: showSuccessMessage,
                                onLog: {
                                    Task {
                                        isLoggingInProgress = true
                                        await viewModel.logDrink(
                                            volumeMilliliters: selectedVolume,
                                            liquidType: selectedLiquid
                                        )
                                        isLoggingInProgress = false
                                        withAnimation {
                                            showSuccessMessage = true
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                            withAnimation {
                                                showSuccessMessage = false
                                            }
                                        }
                                    }
                                },
                                onUndo: {
                                    Task {
                                        await viewModel.undoLastDrink()
                                    }
                                }
                            )

                            if let errorMessage = viewModel.errorMessage {
                                ErrorMessageView(message: errorMessage)
                            }
                        }
                        .padding()
                    }
                }
            }
        }
    }
}

struct HeaderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Log Hydration")
                .font(.title2)
                .fontWeight(.bold)
            Text("Track your daily water intake")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DrinkCategoryGridView: View {
    let categories: [(category: String, drinks: [(name: String, liquid: LiquidType, volume: Int)])]
    @Binding var selectedLiquid: LiquidType
    @Binding var selectedVolume: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Select Drinks")
                .font(.headline)

            ForEach(categories, id: \.category) { category in
                VStack(alignment: .leading, spacing: 8) {
                    Text(category.category)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(category.drinks, id: \.liquid) { drink in
                            DrinkButtonView(
                                name: drink.name,
                                volume: drink.volume,
                                isSelected: selectedLiquid == drink.liquid,
                                action: {
                                    withAnimation {
                                        selectedVolume = drink.volume
                                        selectedLiquid = drink.liquid
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}

struct DrinkButtonView: View {
    let name: String
    let volume: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                Text("\(volume)ml")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                isSelected
                    ? Color.blue.opacity(0.15)
                    : Color.gray.opacity(0.08)
            )
            .border(
                isSelected ? Color.blue : Color.clear,
                width: 2
            )
            .cornerRadius(8)
        }
    }
}

struct VolumeCustomizerView: View {
    @Binding var selectedVolume: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom Volume")
                .font(.headline)

            HStack(spacing: 16) {
                Slider(value: Double($selectedVolume), in: 100...500, step: 10)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(selectedVolume)ml")
                        .font(.headline)
                    Text("Selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(width: 60, alignment: .trailing)
            }

            HStack(spacing: 12) {
                ForEach([100, 200, 300, 500], id: \.self) { volume in
                    Button(action: {
                        withAnimation {
                            selectedVolume = volume
                        }
                    }) {
                        Text("\(volume)ml")
                            .font(.caption)
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(selectedVolume == volume ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                            .cornerRadius(6)
                            .foregroundColor(.primary)
                    }
                }
            }
        }
    }
}

struct LoggingActionView: View {
    let selectedVolume: Int
    let selectedLiquid: LiquidType
    let isLoggingInProgress: Bool
    let showUndoButton: Bool
    let showSuccess: Bool
    let onLog: () -> Void
    let onUndo: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Button(action: onLog) {
                if isLoggingInProgress {
                    ProgressView()
                        .tint(.white)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "drop.fill")
                        Text("Log \(selectedVolume)ml")
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
            .disabled(isLoggingInProgress)

            if showUndoButton {
                Button(action: onUndo) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.uturn.left")
                        Text("Undo Last Drink")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .foregroundColor(.primary)
                    .cornerRadius(8)
                }
            }

            if showSuccess {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Logged successfully!")
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
                .transition(.scale.combined(with: .opacity))
            }
        }
    }
}

struct ErrorMessageView: View {
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
            }
            Spacer()
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .border(Color.red.opacity(0.3), width: 1)
        .cornerRadius(8)
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

    HydrationLoggingView(viewModel: viewModel)
}
