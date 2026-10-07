import SwiftUI
import AlmanacCore

struct HydrationLoggingView: View {
    @ObservedObject var viewModel: HydrationViewModel
    @State private var selectedVolume: Int = 250
    @State private var selectedLiquid: LiquidType = .water

    private let drinkOptions: [(name: String, liquid: LiquidType, volume: Int)] = [
        ("Water", .water, 250),
        ("Sports Drink", .sportsDrink, 250),
        ("Electrolyte", .electrolyteSolution, 250),
        ("Coconut Water", .coconutWater, 200),
        ("Juice", .juice, 200),
        ("Tea", .tea, 200),
        ("Coffee", .coffee, 150),
        ("Milk", .milk, 200)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Log Hydration")
                    .font(.title2)
                    .fontWeight(.bold)

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Quick Select Drinks")
                        .font(.headline)

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(drinkOptions, id: \.liquid) { option in
                                Button(action: {
                                    selectedVolume = option.volume
                                    selectedLiquid = option.liquid
                                }) {
                                    HStack {
                                        Text(option.name)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        Text("\(option.volume)ml")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding()
                                    .background(
                                        selectedLiquid == option.liquid
                                            ? Color.blue.opacity(0.1)
                                            : Color.gray.opacity(0.05)
                                    )
                                    .cornerRadius(8)
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Custom Volume")
                        .font(.headline)

                    HStack {
                        Slider(value: Double($selectedVolume), in: 100...500, step: 10)
                        Text("\(selectedVolume)ml")
                            .font(.headline)
                            .frame(width: 50)
                    }
                }

                Spacer()

                VStack(spacing: 12) {
                    Button(action: {
                        Task {
                            await viewModel.logDrink(
                                volumeMilliliters: selectedVolume,
                                liquidType: selectedLiquid
                            )
                        }
                    }) {
                        HStack {
                            Image(systemName: "drop.fill")
                            Text("Log \(selectedVolume)ml of \(liquidTypeName(selectedLiquid))")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }

                    if viewModel.showUndoButton {
                        Button(action: {
                            Task {
                                await viewModel.undoLastDrink()
                            }
                        }) {
                            HStack {
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

                Spacer()
            }
            .padding()
        }
    }

    private func liquidTypeName(_ type: LiquidType) -> String {
        switch type {
        case .water:
            return "Water"
        case .sportsDrink:
            return "Sports Drink"
        case .electrolyteSolution:
            return "Electrolyte"
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
