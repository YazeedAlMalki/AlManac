import SwiftUI
import AlmanacCore
import Foundation

/// Workout templates — the reusable containers from §3 of the prescription
/// model.
///
/// `PrescribedWorkoutStore` has been in `AlmanacCore` since the schema pass and
/// unreachable from the app. This is the surface for it.
///
/// **A template is exercises, but editable** (owner, 2026-10-06). Since
/// Migration 055 a template holds the exercises it prescribes, with sets, reps
/// and load where it has them, and the Training screen's "Start from a
/// template" copies them onto today's session (`TemplateApplier`). Copied, not
/// referenced: editing a template here never rewrites a session it was applied
/// to.
///
/// **Discontinuing keeps the template.** It is soft-deleted so a past session
/// can still name the one it was done from, which is why a review screen reads
/// discontinued templates on purpose. Hiding it from here while its history still
/// refers to it would make the record unreadable.
@MainActor
struct TrainingTemplateView: View {
    let db: Database?
    /// For the exercise catalogue the editor picks from.
    @ObservedObject var model: TrainingModel

    @State private var templates: [PrescribedWorkoutEntry] = []
    @State private var adding = false
    @State private var editing: PrescribedWorkoutEntry?
    @State private var error: String?
    @State private var readProblem: String?

    var body: some View {
        List {
            if let readProblem {
                Section { AlmanacProblemNote(text: readProblem) }
            }

            Section {
                if templates.isEmpty {
                    Text("No templates yet. A template is a reusable session: its exercises, with sets and reps where you give them, and a shape — straight sets, a circuit, a ladder.")
                        .font(AlmanacTypography.font(.body))
                        .foregroundStyle(AlmanacPalette.textSecondary)
                } else {
                    ForEach(templates) { template in
                        row(template)
                    }
                }
                Button("Add template", systemImage: AlmanacIcon.quickAdd) { adding = true }
                    .disabled(db == nil)
            } header: {
                AlmanacSectionHeader(title: "Templates")
            } footer: {
                Text("Deleting a template keeps it, so a past session can still say which one it came from.")
            }
        }
        .listStyle(.insetGrouped)
        .almanacModuleSurface()
        .navigationTitle("Templates")
        .task { reload() }
        .sheet(isPresented: $adding) {
            TemplateEditor(db: db, model: model, template: nil) { reload() }
        }
        .sheet(item: $editing) { template in
            TemplateEditor(db: db, model: model, template: template) { reload() }
        }
        .editorError($error)
    }

    private func row(_ template: PrescribedWorkoutEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(template.name)
                    .font(AlmanacTypography.font(.body))
                    .foregroundStyle(AlmanacPalette.textPrimary)
                Spacer(minLength: 10)
                Text(TrainingContainer(rawValue: template.containerType)?.displayName
                    ?? readable(template.containerType))
                    .font(AlmanacTypography.font(.caption))
                    .foregroundStyle(AlmanacPalette.textSecondary)
                    .multilineTextAlignment(.trailing)
            }
            if let notes = template.notes, !notes.isEmpty {
                Text(notes)
                    .font(AlmanacTypography.font(.caption))
                    .foregroundStyle(AlmanacPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minHeight: AlmanacMetrics.minimumControl)
        .contentShape(Rectangle())
        .onTapGesture { editing = template }
        .swipeActions(edge: .trailing) {
            Button("Edit") { editing = template }
            Button("Delete", role: .destructive) { delete(template) }
        }
        .contextMenu {
            Button("Edit") { editing = template }
            Button("Delete", role: .destructive) { delete(template) }
        }
    }

    private func delete(_ template: PrescribedWorkoutEntry) {
        guard let db else { return }
        do {
            try PrescribedWorkoutStore(db: db).delete(id: template.id)
            reload()
        } catch {
            self.error = String(describing: error)
        }
    }

    private func reload() {
        guard let db else { return }
        do {
            templates = try PrescribedWorkoutStore(db: db).templates()
            readProblem = nil
        } catch {
            self.error = String(describing: error)
            readProblem = "Could not read your templates."
            templates = []
        }
    }
}

/// Create or edit a template.
///
/// The container is a closed `TrainingContainer` picker, not a free string, so
/// the value can only ever be one of the model's ten. The store validates it
/// too — a typed control the user cannot get wrong and a store that refuses
/// anyway, because the other callers are not this screen.
@MainActor
private struct TemplateEditor: View {
    let db: Database?
    @ObservedObject var model: TrainingModel
    let template: PrescribedWorkoutEntry?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var container: TrainingContainer = .straightSets
    @State private var notes = ""
    @State private var items: [TemplateItemRow] = []
    @State private var pickingExercise = false
    @State private var editingItem: TemplateItemRow?
    @State private var error: String?

    private var isEditing: Bool { template != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Template") {
                    TextField("Name", text: $name)
                    Picker("Container", selection: $container) {
                        ForEach(TrainingContainer.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .accessibilityIdentifier("template-container")
                }
                Section {
                    ForEach(items) { item in
                        Button { editingItem = item } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).foregroundStyle(AlmanacPalette.textPrimary)
                                Text(item.summary)
                                    .font(AlmanacTypography.font(.caption))
                                    .foregroundStyle(AlmanacPalette.textSecondary)
                            }
                        }
                        .accessibilityIdentifier("template-item-\(item.draft.exerciseCatalogId)")
                    }
                    .onDelete { items.remove(atOffsets: $0) }
                    .onMove { items.move(fromOffsets: $0, toOffset: $1) }
                    Button("Add exercise", systemImage: "plus") { pickingExercise = true }
                        .accessibilityIdentifier("template-add-exercise")
                } header: {
                    Text("Exercises")
                } footer: {
                    Text("Starting a session from this template copies these into it. The session is yours to change afterwards, and editing the template later does not change a session already started from it.")
                }
                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .almanacModuleSurface()
            .navigationTitle(isEditing ? "Edit template" : "New template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(db == nil)
                }
            }
            .editorError($error)
            .onAppear(perform: load)
            .sheet(isPresented: $pickingExercise) {
                NavigationStack {
                    ExercisePickerView(model: model, exercises: model.exercises) { exercise in
                        editingItem = TemplateItemRow(
                            name: exercise.name,
                            draft: PrescribedWorkoutItemDraft(exerciseCatalogId: exercise.id,
                                                              prescriptionType: exercise.prescriptionType),
                            isNew: true)
                    }
                }
            }
            .sheet(item: $editingItem) { item in
                TemplateItemEditor(item: item) { saved in
                    if let index = items.firstIndex(where: { $0.id == saved.id }) {
                        items[index] = saved
                    } else {
                        items.append(saved)
                    }
                }
            }
        }
    }

    private func load() {
        guard let template else { return }
        name = template.name
        container = TrainingContainer(rawValue: template.containerType) ?? .straightSets
        notes = template.notes ?? ""
        guard let db else { return }
        do {
            items = try PrescribedWorkoutStore(db: db).items(of: template.id).map {
                TemplateItemRow(name: model.exerciseName(for: $0.exerciseCatalogId), draft: $0.draft, isNew: false)
            }
        } catch {
            self.error = String(describing: error)
        }
    }

    private func save() {
        guard let db else { return }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else {
            error = "Give the template a name."
            return
        }
        let cleanNotes = optionalText(notes.trimmingCharacters(in: .whitespacesAndNewlines))
        do {
            let store = PrescribedWorkoutStore(db: db)
            if let template {
                // Returns whether a live template was changed, so a save against
                // one that was deleted elsewhere says so instead of appearing
                // to have worked.
                guard try store.update(id: template.id, name: cleanName,
                                       containerType: container.rawValue, notes: cleanNotes) else {
                    error = "That template no longer exists — it may have been deleted on another screen."
                    return
                }
                try store.setItems(items.map(\.draft), for: template.id)
            } else {
                let id = try store.create(name: cleanName, containerType: container.rawValue, notes: cleanNotes)
                try store.setItems(items.map(\.draft), for: id)
            }
            onSaved()
            dismiss()
        } catch {
            self.error = String(describing: error)
        }
    }
}

/// One exercise in the template editor's list, before it is saved.
private struct TemplateItemRow: Identifiable, Hashable {
    let id = UUID()
    let name: String
    var draft: PrescribedWorkoutItemDraft
    /// True until it has been added to the list once, so the editor says
    /// "Add" rather than "Save".
    var isNew: Bool

    /// "3 × 8 · 60 kg", "30 s", or "No numbers set".
    var summary: String {
        var parts: [String] = []
        if let sets = draft.prescribedSets, let reps = draft.prescribedReps {
            parts.append("\(sets) × \(reps)")
        } else if let sets = draft.prescribedSets {
            parts.append("\(sets) sets")
        } else if let reps = draft.prescribedReps {
            parts.append("\(reps) reps")
        }
        if let load = draft.prescribedLoadKg { parts.append("\(AlmanacNumber.compact(load)) kg") }
        if let seconds = draft.prescribedDurationSeconds { parts.append("\(AlmanacNumber.compact(seconds)) s") }
        if let meters = draft.prescribedDistanceMeters { parts.append("\(AlmanacNumber.compact(meters)) m") }
        if let rounds = draft.prescribedRounds { parts.append("\(rounds) rounds") }
        return parts.isEmpty ? "No numbers set" : parts.joined(separator: " · ")
    }
}

/// The planned numbers for one template exercise. Only the fields the
/// exercise's prescription type records are offered; every one is optional,
/// and a blank is stored as nothing, never as zero.
@MainActor
private struct TemplateItemEditor: View {
    let item: TemplateItemRow
    let onSave: (TemplateItemRow) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sets = ""
    @State private var reps = ""
    @State private var loadKg = ""
    @State private var durationSeconds = ""
    @State private var distanceMeters = ""
    @State private var rounds = ""
    @State private var error: String?

    private var kind: PrescriptionKind? { PrescriptionKind(rawValue: item.draft.prescriptionType) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let kind {
                        if kind.recordsReps {
                            field("Sets", text: $sets, id: "template-item-sets")
                            field("Reps", text: $reps, id: "template-item-reps")
                        }
                        if kind.recordsLoad && kind.recordsReps {
                            field("Load (kg)", text: $loadKg, id: "template-item-load")
                        }
                        if kind.recordsDuration {
                            field("Duration (seconds)", text: $durationSeconds, id: "template-item-duration")
                        }
                        if kind.recordsDistance {
                            field("Distance (metres)", text: $distanceMeters, id: "template-item-distance")
                        }
                        if kind.recordsRounds {
                            field("Rounds", text: $rounds, id: "template-item-rounds")
                        }
                    }
                } header: {
                    Text(item.name)
                } footer: {
                    Text("All optional. Leave a field blank and the session starts without that number.")
                }
            }
            .almanacModuleSurface()
            .navigationTitle(item.isNew ? "Add exercise" : "Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(item.isNew ? "Add" : "Save", action: save)
                        .accessibilityIdentifier("template-item-save")
                }
            }
            .editorError($error)
            .onAppear(perform: load)
        }
    }

    private func field(_ title: String, text: Binding<String>, id: String) -> some View {
        TextField(title, text: text)
            .keyboardType(.decimalPad)
            .accessibilityIdentifier(id)
    }

    private func load() {
        let draft = item.draft
        sets = draft.prescribedSets.map(String.init) ?? ""
        reps = draft.prescribedReps.map(String.init) ?? ""
        loadKg = draft.prescribedLoadKg.map { AlmanacNumber.compact($0) } ?? ""
        durationSeconds = draft.prescribedDurationSeconds.map { AlmanacNumber.compact($0) } ?? ""
        distanceMeters = draft.prescribedDistanceMeters.map { AlmanacNumber.compact($0) } ?? ""
        rounds = draft.prescribedRounds.map(String.init) ?? ""
    }

    private func save() {
        // Validated before anything changes: a mistyped number must not become
        // a silent blank.
        func count(_ text: String, _ name: String) throws -> Int? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            guard let value = Int(trimmed), value > 0 else {
                throw EditorFailure(message: "\(name) must be a whole number above zero, or blank.")
            }
            return value
        }
        func measure(_ text: String, _ name: String) throws -> Double? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            guard let value = Double(trimmed), value.isFinite, value > 0 else {
                throw EditorFailure(message: "\(name) must be a number above zero, or blank.")
            }
            return value
        }
        do {
            var saved = item
            saved.draft.prescribedSets = try count(sets, "Sets")
            saved.draft.prescribedReps = try count(reps, "Reps")
            saved.draft.prescribedLoadKg = try measure(loadKg, "Load")
            saved.draft.prescribedDurationSeconds = try measure(durationSeconds, "Duration")
            saved.draft.prescribedDistanceMeters = try measure(distanceMeters, "Distance")
            saved.draft.prescribedRounds = try count(rounds, "Rounds")
            saved.isNew = false
            onSave(saved)
            dismiss()
        } catch let failure as EditorFailure {
            error = failure.message
        } catch {
            self.error = String(describing: error)
        }
    }
}
