import SwiftUI
import AlmanacCore

/// The programs you follow, and the days inside each one.
///
/// **Two jobs on one screen, because they are one list.** The 2026-10-01 handoff's
/// flow is "Start Workout → select a program → select a day type", and the
/// authoring of those same programs is not a different list — it is the same
/// names and the same days, with an editor attached. Splitting them would mean
/// building the picker out of one store and then teaching a second screen to
/// read it, and the day labels are the thing a user is most likely to want to fix
/// after using the picker.
///
/// **Days are in authoring order, never alphabetical.** `ProgramDayStore.days`
/// orders by `id`, so "Push, Pull, Legs" reads the way it was typed. A picker
/// that alphabetised them would turn a split into a set of unrelated labels, and
/// the order is the only thing in a program that is not an arbitrary choice.
struct ProgramListView: View {
    @ObservedObject var model: ProgramModel
    @ObservedObject var trainingModel: TrainingModel

    @State private var addingProgram = false
    @State private var editingProgram: TrainingProgramEntry?
    @State private var addingDayTo: TrainingProgramEntry?
    @State private var editingDay: ProgramDayEntry?
    @State private var starting: ProgramDayEntry?
    @State private var error: String?

    private var catalog: [ExerciseCatalogEntry] { trainingModel.exercises }

    var body: some View {
        List {
            if let problem = model.readProblem {
                Section { AlmanacProblemNote(text: problem) }
            }

            if model.programs.isEmpty {
                Section {
                    Text("No programs yet. A program is a split you follow — Push, Pull, Legs, or a mobility routine — and each day rotates through the exercises you put in it.")
                        .font(AlmanacTypography.font(.body))
                        .foregroundStyle(AlmanacPalette.textSecondary)
                    Button("Add program", systemImage: AlmanacIcon.quickAdd) { addingProgram = true }
                        .disabled(model.database == nil)
                        .accessibilityIdentifier("add-program")
                }
            }

            ForEach(model.programs) { program in
                Section {
                    ForEach(model.days(of: program.id)) { day in
                        dayRow(day, in: program)
                    }
                    Button("Add day", systemImage: AlmanacIcon.quickAdd) { addingDayTo = program }
                        .disabled(model.database == nil)
                        .accessibilityIdentifier("add-day-\(program.id)")
                } header: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(program.name)
                            .font(AlmanacTypography.font(.sectionTitle))
                            .foregroundStyle(AlmanacPalette.textPrimary)
                        Spacer(minLength: 12)
                        Menu {
                            Button("Rename program", systemImage: AlmanacIcon.edit) { editingProgram = program }
                            Button("Delete program", systemImage: "trash", role: .destructive) {
                                delete(program)
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AlmanacPalette.textSecondary)
                                .frame(width: AlmanacMetrics.minimumControl, height: AlmanacMetrics.minimumControl)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Options for \(program.name)")
                        .accessibilityIdentifier("program-options-\(program.id)")
                    }
                } footer: {
                    if let notes = program.notes, !notes.isEmpty {
                        Text(notes)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .almanacModuleSurface()
        .navigationTitle("Programs")
        .accessibilityIdentifier("program-list")
        .task { model.refresh() }
        .sheet(isPresented: $addingProgram) {
            ProgramEditor(model: model, program: nil)
        }
        .sheet(item: $editingProgram) { program in
            ProgramEditor(model: model, program: program)
        }
        .sheet(item: $addingDayTo) { program in
            DayEditor(model: model, programId: program.id, day: nil)
        }
        .sheet(item: $editingDay) { day in
            DayEditor(model: model, programId: day.programId, day: day)
        }
        .fullScreenCover(item: $starting) { day in
            ProgramSessionView(model: model, trainingModel: trainingModel, day: day) {
                model.loadItems(programDayId: day.id)
                trainingModel.refresh()
            }
        }
        .editorError($error)
    }

    /// A day: its label, how many exercises are in rotation, and a Start button.
    ///
    /// The count is `activeItems`, not the pool size, because a permanently
    /// removed exercise is still in the pool and "4 exercises, 3 in rotation" is
    /// the honest reading. Start is per-day rather than one button for the whole
    /// program because the rotation belongs to the day, not the split.
    private func dayRow(_ day: ProgramDayEntry, in program: TrainingProgramEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(day.label)
                    .font(AlmanacTypography.font(.bodyMedium))
                    .foregroundStyle(AlmanacPalette.textPrimary)
                Spacer(minLength: 12)
                Menu {
                    Button("Edit day", systemImage: AlmanacIcon.edit) { editingDay = day }
                    Button("Delete day", systemImage: "trash", role: .destructive) { delete(day) }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AlmanacPalette.textSecondary)
                        .frame(width: AlmanacMetrics.minimumControl, height: AlmanacMetrics.minimumControl)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Options for \(day.label)")
                .accessibilityIdentifier("day-options-\(day.id)")
            }

            NavigationLink {
                ProgramDayView(model: model, trainingModel: trainingModel, day: day,
                               programName: program.name) {
                    starting = day
                }
            } label: {
                Label("Exercises in \(day.label)", systemImage: "list.bullet")
                    .font(AlmanacTypography.font(.body))
                    .foregroundStyle(AlmanacPalette.textPrimary)
            }
            .accessibilityIdentifier("program-day-link-\(day.id)")

            Button {
                starting = day
            } label: {
                Label("Start \(day.label)", systemImage: AlmanacIcon.training)
            }
            .buttonStyle(AlmanacSecondaryButtonStyle())
            .disabled(model.database == nil)
            .accessibilityIdentifier("start-day-\(day.id)")
        }
        .padding(.vertical, 6)
    }

    private func delete(_ program: TrainingProgramEntry) {
        do { try model.deleteProgram(id: program.id) } catch { self.error = String(describing: error) }
    }

    private func delete(_ day: ProgramDayEntry) {
        do { try model.deleteDay(id: day.id) } catch { self.error = String(describing: error) }
    }
}

/// Create or rename a program.
@MainActor
private struct ProgramEditor: View {
    @ObservedObject var model: ProgramModel
    let program: TrainingProgramEntry?

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var notes = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Program") {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("program-name-field")
                }
                Section {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                } header: {
                    Text("Notes")
                } footer: {
                    Text("What this split is for. Optional.")
                }
            }
            .almanacModuleSurface()
            .navigationTitle(program == nil ? "New program" : "Rename program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(model.database == nil)
                        .accessibilityIdentifier("save-program")
                }
            }
            .editorError($error)
            .onAppear {
                name = program?.name ?? ""
                notes = program?.notes ?? ""
            }
        }
    }

    private func save() {
        do {
            let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanNotes = optionalText(notes.trimmingCharacters(in: .whitespacesAndNewlines))
            if let program {
                try model.updateProgram(id: program.id, name: cleanName, notes: cleanNotes)
            } else {
                try model.createProgram(name: cleanName, notes: cleanNotes)
            }
            dismiss()
        } catch {
            self.error = String(describing: error)
        }
    }
}

/// Create or rename one part of a split.
@MainActor
private struct DayEditor: View {
    @ObservedObject var model: ProgramModel
    let programId: Int64
    let day: ProgramDayEntry?

    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Push", text: $label)
                        .accessibilityIdentifier("day-label-field")
                } header: {
                    Text("Day")
                } footer: {
                    Text("Your own word for this part of the split. Days appear in the order you add them.")
                }
            }
            .almanacModuleSurface()
            .navigationTitle(day == nil ? "New day" : "Rename day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(model.database == nil)
                        .accessibilityIdentifier("save-day")
                }
            }
            .editorError($error)
            .onAppear { label = day?.label ?? "" }
        }
    }

    private func save() {
        do {
            if let day {
                try model.updateDay(id: day.id, label: label)
            } else {
                try model.createDay(programId: programId, label: label)
            }
            dismiss()
        } catch {
            self.error = String(describing: error)
        }
    }
}