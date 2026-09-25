import SwiftUI
import AlmanacCore

@MainActor
struct QuickLogView: View {
    private enum Destination: String, Identifiable {
        case water
        case food
        case training
        case body

        var id: String { rawValue }
    }

    let db: Database?
    @ObservedObject var hydrationModel: HydrationModel
    @ObservedObject var nutritionModel: NutritionModel
    @ObservedObject var trainingModel: TrainingModel
    @ObservedObject var trackingModel: TrackingCalendarModel

    @Environment(\.dismiss) private var dismiss
    @State private var destination: Destination?
    @State private var waterConfirmation: String?
    @State private var feedbackTrigger = 0
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AlmanacMetrics.sectionGap) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("FAST ENTRY")
                            .font(AlmanacTypography.font(.label))
                            .tracking(1.2)
                            .foregroundStyle(AlmanacPalette.textSecondary)
                        Text("Quick log")
                            .font(AlmanacTypography.font(.screenTitle))
                            .foregroundStyle(AlmanacPalette.textPrimary)
                        Text("Add the small things now. Almanac keeps the record precise without making you stop and sort it first.")
                            .font(AlmanacTypography.font(.body))
                            .foregroundStyle(AlmanacPalette.textSecondary)
                    }

                    waterCard
                    destinationCard(
                        icon: AlmanacIcon.nutrition,
                        title: "Food",
                        detail: "Search the catalogue and record a meal.",
                        destination: .food
                    )
                    destinationCard(
                        icon: AlmanacIcon.training,
                        title: "Training",
                        detail: "Record a bout without leaving Today.",
                        destination: .training
                    )
                    destinationCard(
                        icon: AlmanacIcon.body,
                        title: "Body",
                        detail: "Add weight or another body measurement.",
                        destination: .body
                    )
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, AlmanacMetrics.screenInset)
                .padding(.top, 22)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Quick log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $destination, onDismiss: { destination = nil }) { destination in
                switch destination {
                case .water:
                    HydrationLoggingView(model: hydrationModel, onSaved: finishFlow)
                case .food:
                    NutritionQuickEntryView(model: nutritionModel, onSaved: finishFlow)
                case .training:
                    LogBoutView(model: trainingModel, onSaved: finishFlow)
                case .body:
                    QuickBodyLogView(db: db, trackingModel: trackingModel, onSaved: finishFlow)
                }
            }
            .sensoryFeedback(.success, trigger: feedbackTrigger)
            .editorError($error)
            .almanacScreen()
        }
    }

    private var waterCard: some View {
        AlmanacCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: AlmanacIcon.hydration)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(AlmanacPalette.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Water")
                            .font(AlmanacTypography.font(.sectionTitle))
                            .foregroundStyle(AlmanacPalette.textPrimary)
                        Text("One tap logs a usual amount.")
                            .font(AlmanacTypography.font(.caption))
                            .foregroundStyle(AlmanacPalette.textSecondary)
                    }
                }

                HStack(spacing: 10) {
                    ForEach([250.0, 500.0, 750.0], id: \.self) { amount in
                        Button("+\(Int(amount))") { logWater(amount) }
                            .buttonStyle(AlmanacSecondaryButtonStyle())
                    }
                }

                Button {
                    destination = .water
                } label: {
                    Label("Custom amount", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AlmanacSecondaryButtonStyle())

                if let waterConfirmation {
                    AlmanacStatusMark(text: waterConfirmation, tone: .good)
                }
            }
        }
    }

    private func destinationCard(icon: String, title: String, detail: String, destination: Destination) -> some View {
        Button {
            self.destination = destination
        } label: {
            AlmanacCard {
                HStack(spacing: 14) {
                    Image(systemName: icon)
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(AlmanacPalette.accent)
                        .frame(width: 44, height: 44)
                        .background(AlmanacPalette.surfaceMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(AlmanacTypography.font(.sectionTitle))
                            .foregroundStyle(AlmanacPalette.textPrimary)
                        Text(detail)
                            .font(AlmanacTypography.font(.body))
                            .foregroundStyle(AlmanacPalette.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 10)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AlmanacPalette.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the \(title.lowercased()) logger")
    }

    private func logWater(_ amount: Double) {
        do {
            try hydrationModel.log(amount: Milliliters(amount), note: nil)
            trackingModel.refresh()
            waterConfirmation = "\(Int(amount)) mL added"
            feedbackTrigger += 1
        } catch {
            self.error = String(describing: error)
        }
    }

    private func finishFlow() {
        // The child logger dismisses itself after saving. Keep the quick-log
        // sheet open so a second entry is one tap away, and just clear the
        // child presentation so a cancelled child cannot reopen immediately.
        trackingModel.refresh()
        destination = nil
    }
}

@MainActor
private struct QuickBodyLogView: View {
    let db: Database?
    @ObservedObject var trackingModel: TrackingCalendarModel
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var metric = "weight"
    @State private var value = ""
    @State private var conditions = "unknown"
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Measurement") {
                    Picker("Metric", selection: $metric) {
                        ForEach(bodyMetricOptions) { option in
                            Text(option.title).tag(option.id)
                        }
                    }
                    TextField("Value", text: $value)
                        .keyboardType(.decimalPad)
                    Picker("Conditions", selection: $conditions) {
                        Text("Unknown").tag("unknown")
                        Text("Fasted").tag("fasted")
                        Text("Not fasted").tag("non_fasted")
                    }
                }
            }
            .almanacModuleSurface()
            .navigationTitle("Log body")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
            .editorError($error)
        }
    }

    private func save() {
        guard let db,
              let number = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)),
              number.isFinite,
              number > 0,
              let option = bodyMetricOptions.first(where: { $0.id == metric }) else {
            error = "Enter a positive measurement value."
            return
        }
        do {
            let now = Date()
            let day = TimeModel(timeZone: .current).logicalDay(now).value
            _ = try BodyCompositionMeasurementStore(db: db).log(
                BodyCompositionMeasurementDraft(
                    metric: option.id,
                    value: number,
                    unit: option.unit,
                    timestamp: now,
                    source: "manual",
                    conditions: conditions,
                    timezoneOffset: TimeZone.current.secondsFromGMT(for: now) / 60,
                    timezoneIdentifier: TimeZone.current.identifier
                ),
                logicalDay: day
            )
            trackingModel.refresh()
            onSaved()
            dismiss()
        } catch {
            self.error = String(describing: error)
        }
    }
}
