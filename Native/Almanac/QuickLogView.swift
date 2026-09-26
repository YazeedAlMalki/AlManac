import SwiftUI
import AlmanacCore

/// The icon every section on this sheet wears. It exists because the four
/// section headers are the same kind of thing and had drifted: Water's was
/// 22pt with no chip while the other three were 21pt in a 44pt `surfaceMuted`
/// well, so the first header on the screen read as a different kind of thing
/// from the three below it. One definition means the next edit cannot break
/// only one of them.
private struct QuickLogSectionIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 21, weight: .medium))
            .foregroundStyle(AlmanacPalette.accent)
            .frame(width: 44, height: 44)
            .background(AlmanacPalette.surfaceMuted)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

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
    @ObservedObject var fastingModel: FastingModel

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
                        AlmanacEyebrow(text: "Log without sorting first")
                        Text("Quick log")
                            .font(AlmanacTypography.font(.screenTitle))
                            .foregroundStyle(AlmanacPalette.textPrimary)
                        Text("Record the small things as they happen. Almanac keeps each one precise on its own.")
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
            // No navigation title. It and the Fraunces heading above said the
            // same two words about 24pt apart, in two different faces, and the
            // sheet was visibly repeating itself before the user had read
            // anything. The heading is the one that belongs: it is the screen's
            // voice, and the bar's only job here is the Close action.
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
                    QuickBodyLogView(db: db, trackingModel: trackingModel,
                                      isFastDay: fastingModel.isFastDay, onSaved: finishFlow)
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
                HStack(spacing: 14) {
                    QuickLogSectionIcon(systemName: AlmanacIcon.hydration)
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
                    QuickLogSectionIcon(systemName: icon)
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
    let isFastDay: Bool?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var metric = "weight"
    @State private var value = ""
    @State private var conditions = "unknown"
    @State private var error: String?

    /// Set from the real fasting state when FastingView already knows it, so
    /// the user is not asked to re-declare in two places what the Fasting
    /// module records. Left `unknown` when there is no session today — the
    /// measurement is still valid, just not comparable, and saying so beats
    /// guessing.
    func seedConditions(fromFasting isFastDay: Bool?) {
        guard conditions == "unknown" else { return }
        switch isFastDay {
        case true: conditions = "fasted"
        case false: conditions = "non_fasted"
        case nil: break
        }
    }

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
                }
                // Its own section, not a third field of the measurement. The
                // owner asked (2026-09-26) that fasting state stop being
                // lumped in with logging a body number: the two are different
                // facts about different things, and a reader scanning this form
                // should not see "conditions" as part of what was measured.
                Section {
                    Picker("Fasting state", selection: $conditions) {
                        Text("Unknown").tag("unknown")
                        Text("Fasted").tag("fasted")
                        Text("Not fasted").tag("non_fasted")
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Conditions")
                } footer: {
                    Text("Body composition is only comparable between measurements taken in the same state. This is recorded separately from the measurement, and is not a fasting session — Fasting keeps that.")
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
        .task { seedConditions(fromFasting: isFastDay) }
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
