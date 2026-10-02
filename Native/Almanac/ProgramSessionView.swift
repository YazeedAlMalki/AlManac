import SwiftUI
import AlmanacCore

/// One line on the generated sheet: what `RotationEngine.plan` put in a slot,
/// and everything the user has said about it since.
private struct SessionSlot {
    let slot: Int
    let entry: RotationEntry
    var log: ProgramSessionLog

    /// Non-nil when this exercise is standing in for one the user held. The
    /// engine decides that; this screen never works it out.
    var isSubstitute: Bool { entry.substitutesForSlot != nil }
}

/// An active session generated from a program's day — the handoff's UX flow, from
/// the generated list to Finish.
///
/// **Nothing here writes until Finish.** `RotationEngine.nextRotationIndex`
/// counts live `workoutSession` rows, so a row created when this sheet opened
/// would consume a rotation pass for a session the user then put down, and
/// Decision 2 counts *completed* sessions. The plan is a value in `@State` for as
/// long as the sheet is up, and one call to `ProgramModel.finishSession` writes
/// the whole thing at once.
///
/// **The rotation is the engine's, not this screen's.** A skip moves nothing
/// here: the slot index goes back into `plan(skipping:)`, and the engine holds
/// the item, fills the slot with the next unused one, and reports both in
/// `RotationPlan.skipped`. The one pool write this screen makes is permanent
/// removal, because that is the only one of Decision 3's two mechanisms that
/// touches the pool at all.
///
/// **The prescription shown is this session's, not the pool's.**
/// `ReadinessAdjustment.prescription` is pure, so scaling for a band produces a
/// copy. The pool is never edited, and every field that moved is named — an
/// unexplained smaller number is a prescription the user has to decide whether to
/// trust.
struct ProgramSessionView: View {
    @ObservedObject var model: ProgramModel
    @ObservedObject var trainingModel: TrainingModel
    let day: ProgramDayEntry
    let onFinish: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var startedAt = Date()
    @State private var readinessAdjusted = false
    @State private var rotationIndex = 0
    @State private var slots: [SessionSlot] = []
    /// The slots the user has held for this session. Indices only, because the
    /// engine owns what "holding slot 2" means: it returns the held item in
    /// `RotationPlan.skipped`, and the view reads the answer rather than
    /// re-deriving it.
    @State private var skippedSlots: Set<Int> = []
    /// What the engine held back this pass, straight off the plan.
    @State private var held: [SkippedSlot] = []
    @State private var suggestions: [Int64: ProgressionSuggestion] = [:]
    @State private var promptingSkipForSlot: Int?
    @State private var rpe = 7
    @State private var notes = ""
    @State private var planProblem: String?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if let planProblem {
                    Section {
                        AlmanacProblemNote(text: planProblem, action: "Nothing has been recorded for this session.")
                    }
                } else if isRestDay {
                    restDaySection
                } else {
                    readinessSection
                    prescriptionSection
                    heldSection
                }

                Section("How did it feel?") {
                    HStack(alignment: .firstTextBaseline) {
                        Text("RPE")
                        Spacer(minLength: 12)
                        Text("\(rpe)/10").font(AlmanacTypography.font(.data).monospacedDigit())
                    }
                    .frame(minHeight: AlmanacMetrics.minimumControl / 2)
                    Slider(value: Binding(get: { Double(rpe) }, set: { rpe = Int($0.rounded()) }),
                           in: 1...10, step: 1)
                        .accessibilityLabel("Session RPE")
                        .accessibilityValue("\(rpe) out of 10")
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section {
                    Button(action: finish) {
                        Label("Finish session", systemImage: AlmanacIcon.check)
                    }
                    .buttonStyle(AlmanacPrimaryButtonStyle())
                    .disabled(slots.isEmpty || isRestDay)
                    .accessibilityIdentifier("finish-program-session")
                } footer: {
                    Text("Finishing records this session and moves the rotation on by one place. Putting it down records nothing.")
                }
            }
            .listStyle(.insetGrouped)
            .almanacModuleSurface()
            .navigationTitle(day.label)
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("program-session-screen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Put down") { dismiss() }
                        .accessibilityIdentifier("abandon-program-session")
                }
            }
            .confirmationDialog(skipDialogTitle,
                                isPresented: Binding(get: { promptingSkipForSlot != nil },
                                                     set: { if !$0 { promptingSkipForSlot = nil } }),
                                titleVisibility: .visible) {
                Button("Skip just for today") { skip(promptingSkipForSlot, .perSession) }
                Button("Remove from rotation", role: .destructive) {
                    skip(promptingSkipForSlot, .permanent)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Skipping keeps this exercise in the rotation and offers it again the next time you train \(day.label). Removing takes it out until you put it back.")
            }
            .editorError($error)
            .task { rebuild() }
        }
    }

    // MARK: - Readiness

    /// A switch rather than the handoff's modal, because the answer only ever
    /// scales this session's copy of the prescription: there is no destructive
    /// branch to confirm and no effect deferred past the screen, so a dialog for
    /// it would be a dialog about nothing. The question was *asked* at the moment
    /// the day was started (`ProgramDayView`); this is where the answer takes
    /// effect, and it stays changeable for as long as the sheet is up.
    private var readinessSection: some View {
        Section {
            Toggle("Factor in today's readiness",
                   isOn: Binding(get: { readinessAdjusted }, set: { rebuild(readinessAdjusted: $0) }))
                .disabled(model.todayReadinessScore == nil)
                .accessibilityIdentifier("readiness-toggle")
            if let score = model.todayReadinessScore {
                HStack(alignment: .firstTextBaseline) {
                    Text(readinessAdjusted ? bandName(score) : "Your plan as written")
                    Spacer(minLength: 12)
                    Text(readinessAdjusted ? "scaled from \(score)" : "not scaled")
                        .foregroundStyle(AlmanacPalette.textSecondary)
                }
                .font(AlmanacTypography.font(.body))
            } else {
                Text("No readiness score for today, so there is nothing to scale by. The day runs as written.")
                    .font(AlmanacTypography.font(.caption))
                    .foregroundStyle(AlmanacPalette.textSecondary)
            }
        } header: {
            Text("Readiness")
        } footer: {
            Text(readinessAdjusted
                 ? "A bad day scales this session's prescription. Your plan is not edited, so the next good day is the one you wrote."
                 : "Your plan, exactly as written.")
        }
    }

    /// §9's rest day is a different thing from a very light one — it has no
    /// prescription at all rather than a small one, and `AdjustedPrescription.isRestDay`
    /// is the difference. It appears only when the user said yes *and* every
    /// exercise on the sheet resolved to a rest policy.
    private var restDaySection: some View {
        Section {
            AlmanacCard(prominent: true) {
                VStack(alignment: .leading, spacing: 10) {
                    AlmanacEyebrow(text: "Readiness \(model.todayReadinessScore ?? 0) · \(bandName(model.todayReadinessScore ?? 0))")
                    Text("Today is a rest day")
                        .font(AlmanacTypography.font(.screenTitle))
                        .foregroundStyle(AlmanacPalette.textPrimary)
                    Text("This is too low a reading to scale work against. Your \(day.label) plan is kept exactly as written — nothing has been changed — and you can still train it if you want to.")
                        .font(AlmanacTypography.font(.body))
                        .foregroundStyle(AlmanacPalette.textSecondary)
                    Button("Train as written anyway") { rebuild(readinessAdjusted: false) }
                        .buttonStyle(AlmanacSecondaryButtonStyle())
                        .accessibilityIdentifier("train-as-written-anyway")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var isRestDay: Bool {
        readinessAdjusted && !slots.isEmpty && slots.allSatisfy { $0.log.prescription.isRestDay }
    }

    // MARK: - The generated list

    private var prescriptionSection: some View {
        Section {
            if slots.isEmpty {
                Text("Nothing to do on this pass of the rotation.")
                    .font(AlmanacTypography.font(.body))
                    .foregroundStyle(AlmanacPalette.textSecondary)
            }
            ForEach(slots, id: \.entry.item.id) { slot in
                slotRow(slot)
            }
        } header: {
            AlmanacSectionHeader(title: "\(day.label) today", detail: "Pass \(rotationIndex + 1)")
        } footer: {
            Text("These are the prescribed numbers. What you actually do is recorded separately when you finish, so a session never rewrites your plan.")
        }
    }

    private func slotRow(_ slot: SessionSlot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(name(slot.entry.item))
                    .font(AlmanacTypography.font(.bodyMedium))
                    .foregroundStyle(AlmanacPalette.textPrimary)
                Spacer(minLength: 12)
                if slot.isSubstitute {
                    AlmanacStatusMark(text: "Standing in", tone: .neutral)
                }
            }
            Text(prescribedText(slot))
                .font(AlmanacTypography.font(.data).monospacedDigit())
                .foregroundStyle(AlmanacPalette.textSecondary)
            changeLines(slot)
            variantPicker(slot)
            actualsEditor(slot)
            Button("Not today") { promptingSkipForSlot = slot.slot }
                .font(AlmanacTypography.font(.label))
                .frame(maxWidth: .infinity, minHeight: AlmanacMetrics.minimumControl)
                .accessibilityIdentifier("skip-slot-\(slot.slot)")
        }
        .padding(.vertical, 8)
        .accessibilityIdentifier("session-slot-\(slot.slot)")
    }

    /// The fields that moved, named. `AdjustedPrescription.changes` is recorded
    /// from what actually differed rather than from the policy, so a good morning
    /// produces nothing here instead of "100 kg → 100 kg" — a panel that fires
    /// every single day is a panel nobody reads.
    @ViewBuilder
    private func changeLines(_ slot: SessionSlot) -> some View {
        let moves = ProgramPrescriptionText.changes(slot.log.prescription.changes)
        if !moves.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(moves, id: \.field) { move in
                    HStack(alignment: .firstTextBaseline) {
                        Text(move.field)
                        Spacer(minLength: 12)
                        Text(move.text).monospacedDigit()
                    }
                    .font(AlmanacTypography.font(.caption))
                    .foregroundStyle(AlmanacPalette.textSecondary)
                }
            }
        }
        if let suggestion = suggestions[slot.entry.item.id] {
            suggestionLine(suggestion)
        }
    }

    /// Decision 4. A **suggestion, never a write**: nothing on this screen touches
    /// the pool item, and the suggestion is stated in the user's own terms so the
    /// number is traceable to a rule they set rather than to the app's opinion.
    @ViewBuilder
    private func suggestionLine(_ suggestion: ProgressionSuggestion) -> some View {
        switch suggestion.outcome {
        case .increase(let toKg):
            Text("Your rule suggests \(AlmanacNumber.compact(toKg)) kg, up from \(AlmanacNumber.compact(suggestion.currentLoadKg ?? 0)) kg. It is not applied until you change the prescription.")
                .font(AlmanacTypography.font(.caption))
                .foregroundStyle(AlmanacPalette.textSecondary)
        case .hold(let atKg):
            Text("Your rule holds \(AlmanacNumber.compact(atKg)) kg — the condition was not met.")
                .font(AlmanacTypography.font(.caption))
                .foregroundStyle(AlmanacPalette.textSecondary)
        case .nothingLogged:
            Text("Nothing logged for this exercise yet, so there is no weight to progress from.")
                .font(AlmanacTypography.font(.caption))
                .foregroundStyle(AlmanacPalette.textSecondary)
        }
    }

    /// Decision 1: the variant is chosen per exercise at write time and is a
    /// closed set, so a session cannot record "DB", "Dumbbells" and "dumbbell" in
    /// one column and draw three lines where the graph should show one. "Not
    /// recorded" is offered because it is a real answer — a bodyweight movement
    /// has no variant — and it is a name on the graph, not a blank.
    private func variantPicker(_ slot: SessionSlot) -> some View {
        Picker("Equipment",
               selection: Binding(get: { slot.log.equipmentVariant },
                                  set: { newValue in update(slot.slot) { $0.equipmentVariant = newValue } })) {
            Text("Not recorded").tag(EquipmentVariant?.none)
            ForEach(EquipmentVariant.allCases, id: \.self) { variant in
                Text(variant.displayName).tag(EquipmentVariant?.some(variant))
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("variant-picker-\(slot.entry.item.id)")
        .frame(minHeight: AlmanacMetrics.minimumControl / 2)
    }

    /// The log. `workoutBout` records a bout as one row carrying sets, reps and
    /// load rather than a row per set, so this is the numbers themselves — and it
    /// is deliberately a different thing from the prescription line above it,
    /// because that is what was planned and this is what happened
    /// (`docs/features/training.md` §2).
    ///
    /// Only the fields the prescription actually uses are offered, because the
    /// twelve types disagree about which numbers mean anything.
    private func actualsEditor(_ slot: SessionSlot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AlmanacRule()
            HStack(alignment: .firstTextBaseline) {
                Text("Did")
                Spacer(minLength: 12)
                Text(actualsText(slot.log))
                    .font(AlmanacTypography.font(.data).monospacedDigit())
                    .foregroundStyle(isDone(slot.log) ? AlmanacPalette.textPrimary
                                                      : AlmanacPalette.textSecondary)
            }
            .font(AlmanacTypography.font(.body))
            .frame(minHeight: AlmanacMetrics.minimumControl / 2)

            if slot.log.prescription.sets != nil {
                countStepper("Sets", slot: slot, keyPath: \.actualSets, range: 1...20)
            }
            if slot.log.prescription.reps != nil {
                countStepper("Reps", slot: slot, keyPath: \.actualReps, range: 1...999)
            }
            if slot.log.prescription.loadKg != nil {
                loadStepper(slot)
            }
            if slot.log.prescription.durationSeconds != nil {
                durationStepper(slot)
            }

            Button("Mark done") { markDone(slot.slot) }
                .font(AlmanacTypography.font(.bodyMedium))
                .frame(maxWidth: .infinity, minHeight: AlmanacMetrics.minimumControl)
                .background(isDone(slot.log) ? AlmanacPalette.surfaceMuted : AlmanacPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: AlmanacMetrics.controlRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AlmanacMetrics.controlRadius, style: .continuous)
                        .inset(by: AlmanacMetrics.ruleWeight / 2)
                        .stroke(AlmanacPalette.divider, lineWidth: AlmanacMetrics.ruleWeight)
                }
                .foregroundStyle(AlmanacPalette.textPrimary)
                .disabled(isDone(slot.log))
                .accessibilityIdentifier("mark-done-\(slot.entry.item.id)")
        }
    }

    private func countStepper(_ title: String, slot: SessionSlot,
                              keyPath: WritableKeyPath<ProgramSessionLog, Int?>,
                              range: ClosedRange<Int>) -> some View {
        HStack {
            Text(title).font(AlmanacTypography.font(.body))
            Spacer(minLength: 12)
            Stepper(value: Binding(
                get: { slot.log[keyPath: keyPath] ?? 0 },
                set: { value in update(slot.slot) { $0[keyPath: keyPath] = value } }),
                in: range) {
                Text((slot.log[keyPath: keyPath] ?? 0).description)
                    .font(AlmanacTypography.font(.data).monospacedDigit())
            }
            .labelsHidden()
            .accessibilityLabel(title)
            .accessibilityValue((slot.log[keyPath: keyPath] ?? 0).description)
        }
        .frame(minHeight: AlmanacMetrics.minimumControl / 2)
    }

    private func loadStepper(_ slot: SessionSlot) -> some View {
        HStack {
            Text("Load").font(AlmanacTypography.font(.body))
            Spacer(minLength: 12)
            Stepper(value: Binding(
                get: { slot.log.actualLoadKg ?? 0 },
                set: { value in update(slot.slot) { $0.actualLoadKg = value } }),
                in: 0...500, step: 1) {
                Text(loadText(slot.log.actualLoadKg))
                    .font(AlmanacTypography.font(.data).monospacedDigit())
            }
            .labelsHidden()
            .accessibilityLabel("Load")
            .accessibilityValue(slot.log.actualLoadKg.map { "\(AlmanacNumber.compact($0)) kilograms" } ?? "Not set")
        }
        .frame(minHeight: AlmanacMetrics.minimumControl / 2)
    }

    private func durationStepper(_ slot: SessionSlot) -> some View {
        HStack {
            Text("Duration").font(AlmanacTypography.font(.body))
            Spacer(minLength: 12)
            Stepper(value: Binding(
                get: { slot.log.actualDurationSeconds ?? 0 },
                set: { value in update(slot.slot) { $0.actualDurationSeconds = value } }),
                in: 0...1800, step: 5) {
                Text(slot.log.actualDurationSeconds.map { "\(Int($0)) s" } ?? "—")
                    .font(AlmanacTypography.font(.data).monospacedDigit())
            }
            .labelsHidden()
            .accessibilityLabel("Duration")
            .accessibilityValue(slot.log.actualDurationSeconds.map { "\(Int($0)) seconds" } ?? "Not set")
        }
        .frame(minHeight: AlmanacMetrics.minimumControl / 2)
    }

    // MARK: - Held

    /// What the engine held back. A per-session skip writes nothing to the pool —
    /// holding its rotation position *is* the absence of a write — so this list is
    /// the only trace of it until the session is finished, when it becomes a bout
    /// with `wasSkippedForSession` set.
    @ViewBuilder
    private var heldSection: some View {
        if !skippedSlots.isEmpty {
            Section {
                ForEach(Array(skippedSlots).sorted(), id: \.self) { slot in
                    Button {
                        unskip(slot)
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(heldItem(for: slot).map(name) ?? "Slot \(slot + 1)")
                                .font(AlmanacTypography.font(.body))
                                .foregroundStyle(AlmanacPalette.textPrimary)
                            Spacer(minLength: 12)
                            Text("Undo").foregroundStyle(AlmanacPalette.accent)
                        }
                        .frame(minHeight: AlmanacMetrics.minimumControl)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("undo-skip-slot-\(slot)")
                }
            } header: {
                Text("Held this session")
            } footer: {
                Text(skippedSlots.count == 1
                     ? "This keeps its place in the cycle and is offered again the next time you train \(day.label)."
                     : "These keep their places in the cycle and are offered again the next time you train \(day.label).")
            }
        }
    }

    /// The item the engine held for a slot, if the slot was inside this pass's
    /// window. Nil for a slot the engine clamped away — it kept nothing, so there
    /// is nothing to name.
    private func heldItem(for slot: Int) -> PoolItemEntry? {
        held.first { $0.slot == slot }?.item
    }

    // MARK: - Building the plan

    /// Regenerates the sheet — on appear and whenever the readiness toggle moves.
    ///
    /// A **full** rebuild rather than an in-place rescale, because the window
    /// depends on which slots are held: a rescale that kept the old entries could
    /// leave a substitute standing in for a slot that no longer exists.
    ///
    /// Actuals and equipment already entered survive, keyed by pool item, because
    /// toggling readiness is a change of plan for the *same* slot rather than a new
    /// session — and throwing away what someone had already typed in order to
    /// compare two prescriptions would be worse than the rebuild itself.
    private func rebuild(readinessAdjusted: Bool? = nil) {
        if let readinessAdjusted { self.readinessAdjusted = readinessAdjusted }
        model.loadItems(programDayId: day.id)
        guard let plan = model.plan(programDayId: day.id, skipping: skippedSlots) else {
            planProblem = "Almanac could not work out this session's exercises."
            slots = []
            held = []
            suggestions = [:]
            return
        }
        planProblem = nil
        rotationIndex = plan.rotationIndex
        let previous = Dictionary(slots.map { ($0.entry.item.id, $0.log) }, uniquingKeysWith: { first, _ in first })
        slots = plan.entries.map { entry in
            let fresh = ProgramSessionLog(
                item: entry.item,
                prescription: model.prescription(for: entry.item, readinessAdjusted: self.readinessAdjusted))
            return SessionSlot(slot: entry.slot, entry: entry, log: previous[entry.item.id] ?? fresh)
        }
        held = plan.skipped
        suggestions = model.suggestions(for: plan.exercises)
    }

    // MARK: - Actions

    /// Decision 3's two mechanisms, from one prompt with both answers on it.
    ///
    /// **Per-session** changes nothing outside this screen: the slot index goes
    /// back into `plan(skipping:)`, and the engine holds the item and refills the
    /// slot from the cycle. **Permanent** is the only mechanism of the two that
    /// writes to the pool, so the pool is written in that branch and nowhere else.
    private func skip(_ slot: Int?, _ availability: ExerciseAvailability) {
        guard let slot, let entry = slots.first(where: { $0.slot == slot }) else {
            promptingSkipForSlot = nil
            return
        }
        promptingSkipForSlot = nil
        if availability.mutatesPool {
            do {
                try model.setAvailability(availability, item: entry.entry.item.id, programDayId: day.id)
            } catch {
                self.error = String(describing: error)
                return
            }
        } else {
            // Recorded as an index and handed straight back to the engine on the
            // rebuild below. There is no pool write in this branch — Decision 3's
            // per-session mechanism has no database effect at all, and holding the
            // item's rotation position *is* the absence of one.
            skippedSlots.insert(slot)
        }
        rebuild()
    }

    private func unskip(_ slot: Int) {
        skippedSlots.remove(slot)
        rebuild()
    }

    private func markDone(_ slot: Int) {
        update(slot) { log in
            // Actuals start from the prescription because "mark done" means "I did
            // what the sheet said" — the common case, and otherwise eight taps of
            // typing numbers that are already on screen. The prescription line
            // above is unchanged and still says what was planned; this says what
            // happened, which is the only reason the two are different columns.
            if log.actualSets == nil { log.actualSets = log.prescription.sets }
            if log.actualReps == nil { log.actualReps = log.prescription.reps }
            if log.actualLoadKg == nil { log.actualLoadKg = log.prescription.loadKg }
            if log.actualDurationSeconds == nil { log.actualDurationSeconds = log.prescription.durationSeconds }
            log.rpe = rpe
        }
    }

    private func isDone(_ log: ProgramSessionLog) -> Bool {
        log.actualSets != nil || log.actualReps != nil || log.actualLoadKg != nil
            || log.actualDurationSeconds != nil
    }

    private func finish() {
        do {
            // A held slot is written as a skipped bout of its own, so the record
            // says what happened rather than quietly omitting an exercise the user
            // deliberately did not do — and so `ExerciseProgression` can leave it
            // off both graphs without a filter of its own.
            let logs = slots.map(\.log) + held.map { heldSlot in
                ProgramSessionLog(item: heldSlot.item,
                                  prescription: model.prescription(for: heldSlot.item,
                                                                   readinessAdjusted: readinessAdjusted),
                                  skippedForSession: true)
            }
            try model.finishSession(programDayId: day.id,
                                    readinessAdjusted: readinessAdjusted,
                                    logs: logs,
                                    durationMinutes: max(1, Int(Date().timeIntervalSince(startedAt) / 60)),
                                    rpe: rpe,
                                    notes: optionalText(notes.trimmingCharacters(in: .whitespacesAndNewlines)))
            onFinish()
            dismiss()
        } catch {
            self.error = String(describing: error)
        }
    }

    private func update(_ slot: Int, _ change: (inout ProgramSessionLog) -> Void) {
        guard let index = slots.firstIndex(where: { $0.slot == slot }) else { return }
        change(&slots[index].log)
    }

    // MARK: - Text

    /// The handoff's copy discipline: the question is how long the unavailability
    /// lasts, never whether the user likes the exercise. Dislike and missing
    /// equipment both resolve to permanent removal, so a prompt asking "do you
    /// enjoy this?" would route both to the same wrong answer.
    private var skipDialogTitle: String {
        guard let slot = promptingSkipForSlot,
              let entry = slots.first(where: { $0.slot == slot }) else { return "Not today" }
        return "\(name(entry.entry.item)) — how long?"
    }

    private func name(_ item: PoolItemEntry) -> String {
        model.exerciseName(for: item.exerciseCatalogId, in: trainingModel.exercises)
    }

    private func prescribedText(_ slot: SessionSlot) -> String {
        ProgramPrescriptionText.adjusted(slot.log.prescription,
                                         kind: PrescriptionKind(rawValue: slot.entry.item.prescriptionType))
    }

    private func actualsText(_ log: ProgramSessionLog) -> String {
        var parts: [String] = []
        if let sets = log.actualSets, let reps = log.actualReps {
            parts.append("\(sets) × \(reps)")
        } else if let sets = log.actualSets {
            parts.append("\(sets) sets")
        }
        if let load = log.actualLoadKg, load > 0 { parts.append("@ \(AlmanacNumber.compact(load)) kg") }
        if let duration = log.actualDurationSeconds, duration > 0 { parts.append("\(Int(duration)) s") }
        return parts.isEmpty ? "Not recorded" : parts.joined(separator: " ")
    }

    private func loadText(_ value: Double?) -> String {
        guard let value, value > 0 else { return "—" }
        return "\(AlmanacNumber.compact(value)) kg"
    }

    private func bandName(_ score: Int) -> String {
        switch ReadinessBand.band(for: score) {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .moderate: return "Moderate"
        case .belowBaseline: return "Below baseline"
        case .poor: return "Poor"
        case .veryLow: return "Very low"
        }
    }
}