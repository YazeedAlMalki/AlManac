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
    /// Pre-chosen when the user arrived by browsing the library rather than by
    /// opening this form cold. Kept in `@State` and applied in `.task` so the
    /// picker, the set/rep fields and the volume readout all agree from the
    /// first frame instead of flashing empty and filling in.
    @State private var preselect: ExerciseCatalogEntry?
    @State private var sets = 3
    @State private var reps = 6
    @State private var repeatSets: Int?
    @State private var load = 0.0
    @State private var durationText = ""
    @State private var distanceText = ""
    @State private var roundsText = ""
    @State private var rpe = 5
    @State private var notes = ""
    @State private var error: String?

    /// Sets is a choice from a fixed list, not a free number. No spec anywhere
    /// bounds it — `workoutBout.actualSets` is an unconstrained nullable
    /// INTEGER — so this list is the owner's decision (2026-09-26) and not a
    /// spec rule. A picker also removes the empty-by-default state the old
    /// free-text field had, where forgetting the field logged a silent NULL
    /// instead of a number.
    private static let setChoices = [1, 2, 3, 4, 5]

    /// Reps open at 6 because that is the common working-set default the owner
    /// asked for, and step down to 1. The upper bound is a UI affordance only:
    /// nothing in the spec caps reps, and a stepper needs a closed range, so
    /// this is set well above any real set rather than asserting a limit.
    private static let repRange = 1...999

    init(model: TrainingModel, preselected: ExerciseCatalogEntry? = nil,
         onSaved: @escaping () -> Void = {}) {
        self.model = model
        self.preselect = preselected
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise") {
                    NavigationLink {
                        ExercisePickerView(model: model, exercises: model.exercises) { exercise in
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
        .task { selectedExercise = preselect }
    }

    @ViewBuilder
    private func detailFields(for prescriptionType: String) -> some View {
        switch prescriptionType {
        case "reps_load":
            setPicker
            repStepper
            loadStepper
            volumeReadout
        case "reps_bodyweight":
            setPicker
            repStepper
            volumeReadout
        case "distance":
            TextField("Distance (m)", text: $distanceText).keyboardType(.decimalPad)
            optionalSetsField
        case "duration", "time_under_load", "hold_stretch":
            TextField("Duration (seconds)", text: $durationText).keyboardType(.decimalPad)
            optionalSetsField
        case "work_in_time", "rounds_for_time":
            TextField("Rounds completed", text: $roundsText).keyboardType(.numberPad)
        default:
            Text("Logged as notes and RPE only — \(readable(prescriptionType)) has no numeric fields yet.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var setPicker: some View {
        Picker("Sets", selection: $sets) {
            ForEach(Self.setChoices, id: \.self) { Text("\($0)").tag($0) }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Sets")
        .accessibilityValue("\(sets)")
    }

    private var repStepper: some View {
        Stepper(value: $reps, in: Self.repRange) {
            HStack {
                Text("Reps")
                Spacer()
                Text("\(reps)").font(.body).monospacedDigit()
            }
        }
        .accessibilityValue("\(reps)")
    }

    /// Load steps by 1 kg. The step is a UI affordance like the rep ceiling —
    /// nothing in the specs says what a plate increment is — but 1 kg rather
    /// than 2.5 because fractional plates are common enough that 2.5 would
    /// strand anyone who does not train in 5s. It is a `Stepper` rather than a
    /// field because tapping a weight in is faster than typing it, which was
    /// the point of the request.
    private var loadStepper: some View {
        Stepper(value: $load, in: 0...500, step: 1) {
            HStack {
                Text("Load")
                Spacer()
                Text(load == 0 ? "—" : "\(AlmanacNumber.compact(load)) kg")
                    .font(AlmanacTypography.font(.body).monospacedDigit())
            }
        }
        .accessibilityLabel("Load")
        .accessibilityValue(load == 0 ? "Not set" : "\(AlmanacNumber.compact(load)) kilograms")
    }

    /// The load the bout will add to today's total, shown while logging rather
    /// than only afterwards on the dashboard. Nil — not zero — when the
    /// numbers don't combine into a volume, so a bodyweight set never claims
    /// to be "0 kg" of work.
    @ViewBuilder
    private var volumeReadout: some View {
        if let tonnage = boutTonnageKg {
            Section {
                HStack {
                    Text("Volume")
                    Spacer()
                    Text("\(AlmanacNumber.compact(tonnage)) kg")
                        .font(AlmanacTypography.font(.data).monospacedDigit())
                }
            } header: {
                Text("This set")
            } footer: {
                Text("Sets × reps × load. This is the tonnage added to today's training total.")
            }
        }
    }

    private var boutTonnageKg: Double? {
        guard load > 0 else { return nil }
        return Double(sets * reps) * load
    }

    /// The repeat count for the types where sets multiply a duration or a
    /// distance (3×400m, 4×30s). Optional there, so the same fixed 1–5 list
    /// applies with a "not repeated" option rather than an empty text field.
    private var optionalSetsField: some View {
        Picker("Repeated", selection: $repeatSets) {
            Text("Not repeated").tag(Int?.none)
            ForEach(Self.setChoices, id: \.self) { Text("\($0)×").tag(Int?.some($0)) }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Sets")
        .accessibilityValue(repeatSets.map { "\($0)" } ?? "Not repeated")
    }

    private func save() {
        guard let selectedExercise else { return }
        // `reps_load` and `reps_bodyweight` always carry the chosen set count;
        // the repeat-multiplier types carry it only when one was chosen.
        let isRepsType = selectedExercise.prescriptionType == "reps_load"
            || selectedExercise.prescriptionType == "reps_bodyweight"
        do {
            try model.logBout(
                exercise: selectedExercise,
                sets: isRepsType ? sets : repeatSets,
                reps: isRepsType ? reps : nil,
                loadKg: selectedExercise.prescriptionType == "reps_load" && load > 0 ? load : nil,
                durationSeconds: Double(durationText), distanceMeters: Double(distanceText),
                rounds: Int(roundsText), rpe: rpe, notes: optionalText(notes))
            onSaved()
            dismiss()
        } catch { self.error = String(describing: error) }
    }
}
