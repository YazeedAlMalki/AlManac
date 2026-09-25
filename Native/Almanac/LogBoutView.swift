import SwiftUI
import AlmanacCore

/// Quick-add a bout of work against today's ad-hoc session. Which fields
/// are shown is driven entirely by the picked exercise's own
/// `prescriptionType` (§2 of `docs/features/training.md`) — the twelve
/// types disagree about which numbers mean anything, so this never shows a
/// field a type doesn't use.
@MainActor
struct LogBoutView: View {
    @ObservedObject var model: TrainingModel
    @Environment(\.dismiss) private var dismiss
    private let onSaved: () -> Void

    @State private var selectedExercise: ExerciseCatalogEntry?
    @State private var setsText = ""
    @State private var repsText = ""
    @State private var loadText = ""
    @State private var durationText = ""
    @State private var distanceText = ""
    @State private var roundsText = ""
    @State private var rpe = 5
    @State private var notes = ""
    @State private var error: String?

    init(model: TrainingModel, onSaved: @escaping () -> Void = {}) {
        self.model = model
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise") {
                    NavigationLink {
                        ExercisePickerView(exercises: model.exercises) { exercise in
                            selectedExercise = exercise
                        }
                    } label: {
                        if let selectedExercise {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(selectedExercise.name)
                                Text(readable(selectedExercise.prescriptionType))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Choose an exercise").foregroundStyle(.secondary)
                        }
                    }
                }

                if let selectedExercise {
                    Section("Details") {
                        detailFields(for: selectedExercise.prescriptionType)
                    }
                }

                Section("How did it feel?") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("RPE")
                            Spacer()
                            Text("\(rpe)/10").font(.headline).monospacedDigit()
                        }
                        Slider(value: Binding(get: { Double(rpe) }, set: { rpe = Int($0.rounded()) }),
                               in: 1...10, step: 1)
                    }
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle("Log Training")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(selectedExercise == nil)
                }
            }
            .editorError($error)
        }
    }

    @ViewBuilder
    private func detailFields(for prescriptionType: String) -> some View {
        switch prescriptionType {
        case "reps_load":
            TextField("Sets", text: $setsText).keyboardType(.numberPad)
            TextField("Reps", text: $repsText).keyboardType(.numberPad)
            TextField("Load (kg)", text: $loadText).keyboardType(.decimalPad)
        case "reps_bodyweight":
            TextField("Sets", text: $setsText).keyboardType(.numberPad)
            TextField("Reps", text: $repsText).keyboardType(.numberPad)
        case "distance":
            TextField("Distance (m)", text: $distanceText).keyboardType(.decimalPad)
            TextField("Sets (optional)", text: $setsText).keyboardType(.numberPad)
        case "duration", "time_under_load", "hold_stretch":
            TextField("Duration (seconds)", text: $durationText).keyboardType(.decimalPad)
            TextField("Sets (optional)", text: $setsText).keyboardType(.numberPad)
        case "work_in_time", "rounds_for_time":
            TextField("Rounds completed", text: $roundsText).keyboardType(.numberPad)
        default:
            Text("Logged as notes and RPE only — \(readable(prescriptionType)) has no numeric fields yet.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func save() {
        guard let selectedExercise else { return }
        do {
            try model.logBout(
                exercise: selectedExercise,
                sets: Int(setsText), reps: Int(repsText), loadKg: Double(loadText),
                durationSeconds: Double(durationText), distanceMeters: Double(distanceText),
                rounds: Int(roundsText), rpe: rpe, notes: optionalText(notes))
            onSaved()
            dismiss()
        } catch { self.error = String(describing: error) }
    }
}
