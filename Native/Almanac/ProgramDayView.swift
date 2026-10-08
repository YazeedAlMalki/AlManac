import SwiftUI
import AlmanacCore

/// One day's exercise pool — the prescription — and the door to starting it.
///
/// **The pool is shown whole, not just its live half.** `ProgramDayExercisePoolStore.items`
/// is the authoring read and includes permanently removed items, greyed out and
/// marked, because "why isn't this being offered" has to be answerable from this
/// screen. `activeItems` is what the rotation uses, and a day whose removals are
/// invisible here would look like a day with exercises missing from it.
struct ProgramDayView: View {
    @ObservedObject var model: ProgramModel
    let trainingModel: TrainingModel
    let day: ProgramDayEntry
    let programName: String
    /// Carries the answer, because the answer is what the session opens as.
    ///
    /// It used to be `onStart: () -> Void` with both buttons calling it, which
    /// made the question a formality: a person who said "Yes — today's score is
    /// 22" got a session identical to the one they got by saying no, and
    /// §7.10/§7.11 were unreachable for a second reason the checklist did not
    /// name — not only could the simulator produce no score, but a score would
    /// not have been acted on either. `true` scales this session's prescription;
    /// `false` runs the day as written.
    let onStart: (_ factorInReadiness: Bool) -> Void

    @State private var addingExercise = false
    @State private var editing: PoolEditTarget?
    @State private var promptReadiness = false
    @State private var error: String?

    var body: some View {
        List {
            if let problem = model.readProblem {
                Section { AlmanacProblemNote(text: problem) }
            }

            startSection

            Section {
                if pool.isEmpty {
                    Text("No exercises in \(day.label) yet. Add the movements you want to rotate through, in the order you want them offered.")
                        .font(AlmanacTypography.font(.body))
                        .foregroundStyle(AlmanacPalette.textSecondary)
                } else {
                    ForEach(pool) { item in
                        poolRow(item)
                    }
                }
                Button("Add exercise", systemImage: AlmanacIcon.quickAdd) { addingExercise = true }
                    .disabled(model.database == nil)
                    .accessibilityIdentifier("add-pool-exercise")
            } header: {
                AlmanacSectionHeader(title: String(localized: "Rotation"), detail: poolSummary)
            } footer: {
                Text("A session takes \(slotCount) exercises from the cycle, moving one place along each time you train this day. The order only changes when you change it here.")
            }
        }
        .listStyle(.insetGrouped)
        .almanacModuleSurface()
        .navigationTitle(day.label)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("program-day-screen")
        .task { model.loadItems(programDayId: day.id) }
        .sheet(isPresented: $addingExercise) {
            NavigationStack {
                ExercisePickerView(model: trainingModel, exercises: trainingModel.exercises) { exercise in
                    editing = .adding(exercise, programDayId: day.id, position: pool.count)
                }
            }
        }
        .sheet(item: $editing) { target in
            PoolItemEditor(model: model, catalog: trainingModel.exercises, target: target)
        }
        .editorError($error)
        .confirmationDialog("Factor in your readiness score?",
                            isPresented: $promptReadiness,
                            titleVisibility: .visible) {
            Button(yesLabel) { onStart(true) }
            Button("No, train as written") { onStart(false) }
        } message: {
            Text(readinessMessage)
        }
    }

    // MARK: - Pieces

    /// The one prominent thing on this screen: the day, and the action that
    /// starts it.
    private var startSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                AlmanacEyebrow(text: programName)
                Text(day.label)
                    .font(AlmanacTypography.font(.screenTitle))
                    .foregroundStyle(AlmanacPalette.textPrimary)
                Text("This is pass \(passNumber) through \(pool.count) exercises.")
                    .font(AlmanacTypography.font(.body))
                    .foregroundStyle(AlmanacPalette.textSecondary)
                Button {
                    promptReadiness = true
                } label: {
                    Label("Start \(day.label)", systemImage: AlmanacIcon.training)
                }
                .buttonStyle(AlmanacPrimaryButtonStyle())
                .disabled(pool.isEmpty)
                .accessibilityIdentifier("start-program-day")
                if pool.isEmpty {
                    Text("Add at least one exercise before starting this day.")
                        .font(AlmanacTypography.font(.caption))
                        .foregroundStyle(AlmanacPalette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func poolRow(_ item: PoolItemEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(name(item))
                    .font(AlmanacTypography.font(.bodyMedium))
                    .foregroundStyle(item.isActive ? AlmanacPalette.textPrimary : AlmanacPalette.textSecondary)
                Spacer(minLength: 12)
                Text("cycle \(item.rotationPosition) · slot \(item.positionWithinSession + 1)")
                    .font(AlmanacTypography.font(.caption).monospacedDigit())
                    .foregroundStyle(AlmanacPalette.textSecondary)
            }
            Text(prescriptionText(item))
                .font(AlmanacTypography.font(.caption).monospacedDigit())
                .foregroundStyle(AlmanacPalette.textSecondary)
            if item.isActive {
                progressionLine(item)
            } else {
                // Decision 3: removal is reversible and keeps the item's place in
                // the cycle, so putting it back is one tap and restores the
                // rotation exactly as it was — which is why this is a button and
                // not an "undo".
                HStack(spacing: 10) {
                    AlmanacStatusMark(text: String(localized: "Removed from rotation"), tone: .neutral)
                    Spacer(minLength: 8)
                    Button("Put back") { restore(item: item) }
                        .buttonStyle(.borderless)
                        .font(AlmanacTypography.font(.label))
                        .disabled(model.database == nil)
                        .accessibilityIdentifier("restore-pool-item-\(item.id)")
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .contentShape(Rectangle())
        .onTapGesture { editing = .editing(item) }
        .accessibilityIdentifier("pool-item-\(item.id)")
        .swipeActions(edge: .trailing) {
            Button("Delete", role: .destructive) {
                do { try model.deletePoolItem(id: item.id, programDayId: day.id) }
                catch { self.error = String(describing: error) }
            }
            Button(item.isActive ? String(localized: "Remove") : String(localized: "Put back")) {
                if item.isActive {
                    setAvailability(.permanent, item: item)
                } else {
                    restore(item: item)
                }
            }
                .tint(AlmanacPalette.surfaceMuted)
        }
    }

    /// Decision 4's rule, stated beside the prescription it modifies and never as
    /// a suggestion the app has already applied.
    @ViewBuilder
    private func progressionLine(_ item: PoolItemEntry) -> some View {
        if item.progressionEnabled, let increment = item.progressionIncrementKg {
            let condition = ProgressionCondition(rawValue: item.progressionCondition ?? "")
            Text("Progress by \(AlmanacNumber.compact(increment)) kg when \(condition?.displayName.lowercased() ?? "the condition is met").")
                .font(AlmanacTypography.font(.caption))
                .foregroundStyle(AlmanacPalette.textSecondary)
        } else {
            Text("No progression rule.")
                .font(AlmanacTypography.font(.caption))
                .foregroundStyle(AlmanacPalette.textSecondary)
        }
    }

    // MARK: - Derived

    private var pool: [PoolItemEntry] { model.items(programDayId: day.id) }

    /// `sessionSlotCount` counts live items *including* inactive ones, so a
    /// permanently removed exercise does not quietly shorten the day. Read off
    /// the pool the screen already has rather than through a second query; the
    /// arithmetic is the store's.
    private var slotCount: Int { (pool.map(\.positionWithinSession).max() ?? -1) + 1 }

    private var poolSummary: String {
        let active = pool.filter(\.isActive).count
        return active == pool.count ? "\(active) in rotation" : "\(active) of \(pool.count) in rotation"
    }

    private var passNumber: Int { (model.nextRotationIndex(programDayId: day.id) ?? 0) + 1 }

    private func name(_ item: PoolItemEntry) -> String {
        model.exerciseName(for: item.exerciseCatalogId, in: trainingModel.exercises)
    }

    private func prescriptionText(_ item: PoolItemEntry) -> String {
        ProgramPrescriptionText.summary(PrescriptionKind(rawValue: item.prescriptionType),
                                       sets: item.prescribedSets, reps: item.prescribedReps,
                                       loadKg: item.prescribedLoadKg,
                                       durationSeconds: item.prescribedDurationSeconds,
                                       restSeconds: item.prescribedRestSeconds)
    }

    // MARK: - Actions

    private func setAvailability(_ availability: ExerciseAvailability, item: PoolItemEntry) {
        do { try model.setAvailability(availability, item: item.id, programDayId: day.id) }
        catch { self.error = String(describing: error) }
    }

    private func restore(item: PoolItemEntry) {
        do { try model.restore(item: item.id, programDayId: day.id) }
        catch { self.error = String(describing: error) }
    }

    /// Decision 3's copy, in the handoff's own terms: the question is how long the
    /// unavailability lasts, never whether the user likes the exercise — dislike
    /// and lack of equipment both resolve to permanent removal, and a prompt
    /// asking "do you enjoy this?" would send both to the same wrong button.
    private var yesLabel: String {
        guard let score = model.todayReadinessScore else { return String(localized: "Yes — though there is no score today") }
        return String(localized: "Yes — today's score is \(score)")
    }

    private var readinessMessage: String {
        guard let score = model.todayReadinessScore else {
            return String(localized: "There is no readiness score for today yet, so there is nothing to scale by. The day runs as written either way.")
        }
        let band = ReadinessBand.band(for: score)
        if band == .veryLow {
            return String(localized: "Today scores \(score), which presents as a rest day rather than a lighter one. Your plan is kept exactly as written — a bad day never edits it.")
        }
        return String(localized: "Today scores \(score). The prescription will be scaled for that reading; your plan itself is not changed.")
    }
}

/// What the pool editor is editing: an existing row, or a blank prescription for
/// a newly picked exercise.
///
/// The not-yet-saved case is carried as an id and a position rather than as a
/// `PoolItemEntry`, because a row that does not exist yet has no id and no
/// timestamps, and minting stand-in ones would put a second, wrong answer to
/// "what is this item's id" on the screen that is supposed to be about the pool.
private struct PoolEditTarget: Identifiable {
    let id: Int64
    let programDayId: Int64
    let exerciseCatalogId: Int64
    let existing: PoolItemEntry?
    let position: Int

    static func adding(_ exercise: ExerciseCatalogEntry, programDayId: Int64, position: Int) -> PoolEditTarget {
        PoolEditTarget(id: -exercise.id, programDayId: programDayId,
                       exerciseCatalogId: exercise.id, existing: nil, position: position)
    }

    static func editing(_ item: PoolItemEntry) -> PoolEditTarget {
        PoolEditTarget(id: item.id, programDayId: item.programDayId,
                       exerciseCatalogId: item.exerciseCatalogId,
                       existing: item, position: item.positionWithinSession)
    }
}

/// The pool item's prescription, progression rule and cycle position.
///
/// **Progression is edited here and nowhere else.** `setProgression` is the only
/// writer and takes the increment and the condition together, so "turn progression
/// on" and "give it a rule" cannot drift apart into two ways of doing one thing.
@MainActor
private struct PoolItemEditor: View {
    @ObservedObject var model: ProgramModel
    let catalog: [ExerciseCatalogEntry]
    let target: PoolEditTarget

    private var existing: PoolItemEntry? { target.existing }
    private var isNew: Bool { existing == nil }

    @Environment(\.dismiss) private var dismiss
    @State private var kind: PrescriptionKind = .repsLoad
    @State private var sets = 3
    @State private var reps = 8
    @State private var loadKg = 0.0
    @State private var durationSeconds = 30.0
    @State private var restSeconds = 90.0
    @State private var rotationPosition = 0
    @State private var positionWithinSession = 0
    @State private var progressionOn = false
    @State private var incrementKg = 2.5
    @State private var condition: ProgressionCondition = .allRepsCompleted
    @State private var notes = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise") {
                    Text(model.exerciseName(for: target.exerciseCatalogId, in: catalog))
                        .font(AlmanacTypography.font(.bodyMedium))
                }

                Section("Prescription") {
                    Picker("Kind of work", selection: $kind) {
                        ForEach(PrescriptionKind.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .accessibilityIdentifier("pool-kind")

                    if showsReps {
                        Stepper(value: $sets, in: 1...20) { label(String(localized: "Sets"), NumberDisplay.localized(String(sets))) }
                        Stepper(value: $reps, in: 1...999) { label(String(localized: "Reps"), NumberDisplay.localized(String(reps))) }
                    }
                    if kind.recordsLoad {
                        Stepper(value: $loadKg, in: 0...500, step: 1) {
                            label(String(localized: "Load"), loadKg > 0 ? String(localized: "\(AlmanacNumber.compact(loadKg)) kg") : "—")
                        }
                    }
                    if showsDuration {
                        Stepper(value: $durationSeconds, in: 5...600, step: 5) {
                            label(String(localized: "Duration"), String(localized: "\(Int(durationSeconds)) s"))
                        }
                    }
                    Stepper(value: $restSeconds, in: 0...600, step: 5) {
                        label(String(localized: "Rest"), restSeconds > 0 ? String(localized: "\(Int(restSeconds)) s") : "—")
                    }
                }

                Section {
                    Stepper(value: $rotationPosition, in: 0...99) { label(String(localized: "Cycle position"), NumberDisplay.localized(String(rotationPosition))) }
                    Stepper(value: $positionWithinSession, in: 0...9) {
                        label(String(localized: "Slot in session"), NumberDisplay.localized(String(positionWithinSession + 1)))
                    }
                } header: {
                    Text("Where it sits")
                } footer: {
                    Text("The cycle position decides the order the exercises rotate in. The slot is which one it fills in a session.")
                }

                Section {
                    Toggle("Progress this exercise", isOn: $progressionOn)
                        .accessibilityIdentifier("progression-toggle")
                    if progressionOn {
                        Stepper(value: $incrementKg, in: 0.5...50, step: 0.5) {
                            label(String(localized: "Increase by"), String(localized: "\(AlmanacNumber.compact(incrementKg)) kg"))
                        }
                        Picker("When", selection: $condition) {
                            ForEach(ProgressionCondition.allCases, id: \.self) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                    }
                } header: {
                    Text("Progression")
                } footer: {
                    Text("Off by default, and set per exercise rather than once for everything. Almanac proposes the next load; it never changes your prescription by itself.")
                }

                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical).lineLimit(1...4)
                }
            }
            .almanacModuleSurface()
            .navigationTitle(isNew ? String(localized: "Add exercise") : String(localized: "Edit exercise"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(model.database == nil)
                        .accessibilityIdentifier("save-pool-item")
                }
            }
            .editorError($error)
            .onAppear(perform: load)
        }
    }

    private var showsReps: Bool {
        kind == .repsLoad || kind == .repsBodyweight || kind == .qualityReps || kind == .interval
    }

    private var showsDuration: Bool {
        kind == .duration || kind == .holdStretch || kind == .release || kind == .timeUnderLoad
    }

    private func label(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(AlmanacTypography.font(.body))
            Spacer(minLength: 12)
            Text(value).font(AlmanacTypography.font(.data).monospacedDigit())
        }
        .frame(minHeight: AlmanacMetrics.minimumControl / 2)
    }

    private func load() {
        guard let item = existing else {
            // A newly picked exercise opens on the kind of work the catalog says
            // it is, with the numbers left blank, so adding a hold does not open
            // pre-filled with three sets of eight.
            kind = catalog.first { $0.id == target.exerciseCatalogId }
                .flatMap { PrescriptionKind(rawValue: $0.prescriptionType) } ?? .repsLoad
            rotationPosition = target.position
            positionWithinSession = target.position
            return
        }
        kind = PrescriptionKind(rawValue: item.prescriptionType) ?? .repsLoad
        sets = item.prescribedSets ?? 3
        reps = item.prescribedReps ?? 8
        loadKg = item.prescribedLoadKg ?? 0
        durationSeconds = item.prescribedDurationSeconds ?? 30
        restSeconds = item.prescribedRestSeconds ?? 90
        rotationPosition = item.rotationPosition
        positionWithinSession = item.positionWithinSession
        progressionOn = item.progressionEnabled
        incrementKg = item.progressionIncrementKg ?? 2.5
        condition = item.progressionCondition.flatMap(ProgressionCondition.init(rawValue:))
            ?? .allRepsCompleted
        notes = item.notes ?? ""
    }

    private func save() {
        let draft = PoolItemDraft(
            programDayId: target.programDayId,
            exerciseCatalogId: target.exerciseCatalogId,
            rotationPosition: rotationPosition,
            positionWithinSession: positionWithinSession,
            prescriptionType: kind.rawValue,
            containerType: existing?.containerType,
            prescribedSets: showsReps ? sets : nil,
            prescribedReps: showsReps ? reps : nil,
            prescribedLoadKg: kind.recordsLoad && loadKg > 0 ? loadKg : nil,
            prescribedDurationSeconds: showsDuration ? durationSeconds : nil,
            prescribedRestSeconds: restSeconds > 0 ? restSeconds : nil,
            progressionEnabled: progressionOn,
            progressionIncrementKg: progressionOn ? incrementKg : nil,
            progressionCondition: progressionOn ? condition.rawValue : nil,
            notes: optionalText(notes.trimmingCharacters(in: .whitespacesAndNewlines)))
        do {
            if isNew {
                try model.addPoolItem(draft)
            } else if let item = existing {
                try model.updatePrescription(id: item.id, draft)
                // Positions and progression have their own writers, so "save"
                // cannot quietly become a second way of changing them.
                try model.setPositions(id: item.id, programDayId: item.programDayId,
                                       rotationPosition: rotationPosition,
                                       positionWithinSession: positionWithinSession)
                try model.setProgression(id: item.id, programDayId: item.programDayId,
                                         incrementKg: progressionOn ? incrementKg : nil,
                                         condition: progressionOn ? condition : nil)
            }
            dismiss()
        } catch {
            self.error = String(describing: error)
        }
    }
}

/// One prescription, as a line of text. Shared by the pool editor and the session
/// sheet so a prescription cannot read one way on one screen and another way on
/// the next.
enum ProgramPrescriptionText {
    static func summary(_ kind: PrescriptionKind?,
                        sets: Int?, reps: Int?, loadKg: Double?,
                        durationSeconds: Double?, restSeconds: Double?) -> String {
        guard let kind else { return String(localized: "No prescription set") }
        var parts: [String] = []
        if let sets, let reps {
            parts.append(String(localized: "\(sets) × \(reps)"))
        } else if let sets {
            parts.append(String(localized: "\(sets) sets"))
        }
        if let loadKg, loadKg > 0 { parts.append(String(localized: "@ \(AlmanacNumber.compact(loadKg)) kg")) }
        if let durationSeconds, durationSeconds > 0 { parts.append(String(localized: "\(Int(durationSeconds)) s")) }
        if parts.isEmpty { parts.append(kind.displayName) }
        if let restSeconds, restSeconds > 0 { parts.append(String(localized: "rest \(Int(restSeconds)) s")) }
        return parts.joined(separator: " · ")
    }

    /// The same prescription with the readiness-adjusted values in it. The kind
    /// is passed in because `AdjustedPrescription` carries the numbers and not the
    /// type it was derived from.
    static func adjusted(_ prescription: AdjustedPrescription, kind: PrescriptionKind?) -> String {
        summary(kind, sets: prescription.sets, reps: prescription.reps, loadKg: prescription.loadKg,
                durationSeconds: prescription.durationSeconds, restSeconds: prescription.restSeconds)
    }

    /// One "100 kg → 85 kg" line per field that actually moved. `changes` is
    /// recorded from what differed rather than from the policy, so a good morning
    /// produces no lines at all rather than "100 kg → 100 kg".
    static func changes(_ changes: [PrescriptionChange]) -> [(field: String, text: String)] {
        changes.map { change in
            let field: String
            switch change.field {
            case .sets: field = "Sets"
            case .reps: field = "Reps"
            case .loadKg: field = "Load"
            case .durationSeconds: field = "Duration"
            case .restSeconds: field = "Rest"
            }
            return (field, "\(number(change.was, field: change.field)) → \(number(change.now, field: change.field))")
        }
    }

    private static func number(_ value: Double?, field: PrescriptionChange.Field) -> String {
        guard let value else { return "—" }
        switch field {
        case .sets, .reps: return "\(Int(value))"
        case .loadKg: return "\(AlmanacNumber.compact(value)) kg"
        case .durationSeconds, .restSeconds: return "\(Int(value)) s"
        }
    }
}