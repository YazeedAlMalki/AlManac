import SwiftUI
import AlmanacCore
import Foundation

/// Workout templates — the reusable containers from §3 of the prescription
/// model.
///
/// `PrescribedWorkoutStore` has been in `AlmanacCore` since the schema pass and
/// unreachable from the app. This is the surface for it.
///
/// **A template is deliberately thin and this screen says so.** A template is a
/// name plus a container shape; the bouts inside it are `workoutBout` rows a
/// session logs against it, not rows this screen would own. So there is nothing
/// here to add exercises to, and pretending otherwise would imply an editing
/// model the store does not have and that would rewrite history if it did.
///
/// **Discontinuing keeps the template.** It is soft-deleted so a past session
/// can still name the one it was done from, which is why a review screen reads
/// discontinued templates on purpose. Hiding it from here while its history still
/// refers to it would make the record unreadable.
@MainActor
struct TrainingTemplateView: View {
    let db: Database?

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
                    Text("No templates yet. A template is a reusable shape for a session — straight sets, a circuit, a ladder.")
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
                AlmanacSectionHeader(title: String(localized: "Templates"))
            } footer: {
                Text("Deleting a template keeps it, so a past session can still say which one it came from.")
            }
        }
        .listStyle(.insetGrouped)
        .almanacModuleSurface()
        .navigationTitle("Templates")
        .task { reload() }
        .sheet(isPresented: $adding) {
            TemplateEditor(db: db, template: nil) { reload() }
        }
        .sheet(item: $editing) { template in
            TemplateEditor(db: db, template: template) { reload() }
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
    let template: PrescribedWorkoutEntry?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var container: TrainingContainer = .straightSets
    @State private var notes = ""
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
                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .almanacModuleSurface()
            .navigationTitle(isEditing ? String(localized: "Edit template") : String(localized: "New template"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(db == nil)
                }
            }
            .editorError($error)
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let template else { return }
        name = template.name
        container = TrainingContainer(rawValue: template.containerType) ?? .straightSets
        notes = template.notes ?? ""
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
            } else {
                _ = try store.create(name: cleanName, containerType: container.rawValue, notes: cleanNotes)
            }
            onSaved()
            dismiss()
        } catch {
            self.error = String(describing: error)
        }
    }
}
