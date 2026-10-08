import SwiftUI
import AlmanacCore

@MainActor
struct TrainingDashboardView: View {
    @ObservedObject var model: TrainingModel
    @ObservedObject var programModel: ProgramModel
    private let embedded: Bool
    @State private var logging = false
    @State private var pendingExercise: ExerciseCatalogEntry?
    @State private var choosingTemplate = false
    /// The template picked in the chooser, applied once the chooser has gone —
    /// so the "add after?" question is never raised over a closing sheet.
    @State private var chosenTemplate: PrescribedWorkoutEntry?
    /// A template whose exercises would be added after bouts already logged
    /// today — held while the person is asked.
    @State private var pendingTemplate: PendingTemplate?
    @State private var editingBout: WorkoutBoutEntry?
    @State private var error: String?

    private struct PendingTemplate: Identifiable {
        let template: PrescribedWorkoutEntry
        let loggedCount: Int
        var id: Int64 { template.id }
    }

    init(model: TrainingModel, programModel: ProgramModel, embedded: Bool = false) {
        self.model = model
        self.programModel = programModel
        self.embedded = embedded
    }

    var body: some View {
        dashboard.almanacNavigationHost(embedded)
    }

    private var dashboard: some View {
        List {
            if let summary = model.todaysSummary {
                Section("Today's Load") {
                    summaryRows(summary)
                }
            }
            Section("Today") {
                if let problem = model.readProblem {
                    AlmanacProblemNote(text: problem, action: String(localized: "Figures below may be out of date."))
                }
                if model.todaysBouts.isEmpty {
                    Text("Nothing logged yet today.").foregroundStyle(.secondary)
                }
                ForEach(model.todaysBouts) { bout in
                    // Tapping opens what was done for correction — which is how
                    // a session started from a template is filled in.
                    Button { editingBout = bout } label: { boutRow(bout) }
                        .foregroundStyle(.primary)
                        .accessibilityIdentifier("today-bout-\(bout.id)")
                }
                .onDelete(perform: delete)
            }
            Section {
                // The library is the way *into* logging without a search box, so
                // it belongs on the training screen rather than behind the log
                // button — a user browsing by muscle should not have to know
                // they have to open a form first.
                NavigationLink {
                    ExerciseLibraryView(model: model) { exercise in
                        pendingExercise = exercise
                    }
                } label: {
                    Label("Browse exercises", systemImage: "square.grid.2x2")
                }
                .accessibilityIdentifier("exercise-library-link")

                NavigationLink {
                    ProgramListView(model: programModel, trainingModel: model)
                } label: {
                    Label("Start workout", systemImage: AlmanacIcon.training)
                }
                .accessibilityIdentifier("training-programs-link")
                .disabled(model.database == nil)

                NavigationLink {
                    TrainingSessionReviewView(db: model.database, model: model)
                } label: {
                    Label("Training history", systemImage: AlmanacIcon.timeline)
                }
                .accessibilityIdentifier("training-history-link")
                .disabled(model.database == nil)

                Button {
                    choosingTemplate = true
                } label: {
                    Label("Start from a template", systemImage: AlmanacIcon.templates)
                }
                .accessibilityIdentifier("training-apply-template")
                .disabled(model.database == nil)

                NavigationLink {
                    TrainingTemplateView(db: model.database, model: model)
                } label: {
                    Label("Templates", systemImage: AlmanacIcon.templates)
                }
                .accessibilityIdentifier("training-templates-link")
                .disabled(model.database == nil)
            } footer: {
                Text("Grouped by muscle, then by how you train it — bar, cable, machine, bodyweight.")
            }
        }
        .navigationTitle("Training")
        .almanacModuleSurface()
        .toolbar { Button("Log training", systemImage: "plus") { logging = true } }
        .sheet(isPresented: $logging) {
            LogBoutView(model: model, preselected: pendingExercise) {
                pendingExercise = nil
            }
        }
        .sheet(isPresented: $choosingTemplate, onDismiss: {
            if let template = chosenTemplate {
                chosenTemplate = nil
                apply(template, appending: false)
            }
        }) {
            TemplateChooser(model: model) { template in chosenTemplate = template }
        }
        .sheet(item: $editingBout) { bout in
            BoutActualsEditor(db: model.database, bout: bout) { model.refresh() }
        }
        .confirmationDialog(
            pendingTemplate.map { "Add \($0.template.name)'s exercises after the \($0.loggedCount) already logged today?" } ?? "",
            isPresented: Binding(get: { pendingTemplate != nil }, set: { if !$0 { pendingTemplate = nil } }),
            titleVisibility: .visible,
            presenting: pendingTemplate
        ) { pending in
            Button("Add after them") { apply(pending.template, appending: true) }
            Button("Cancel", role: .cancel) { pendingTemplate = nil }
        } message: { _ in
            Text("Nothing already logged is changed or removed.")
        }
        .task { model.refresh() }
        .refreshable { model.refresh() }
        .editorError($error)
    }

    /// Applies a template to today's session. When today already holds logged
    /// bouts the first attempt is refused, and the person is asked before the
    /// template's exercises are added after them (unconfirmed — `CONTEXT.md`).
    private func apply(_ template: PrescribedWorkoutEntry, appending: Bool) {
        pendingTemplate = nil
        do {
            try model.applyTemplate(template, appendingAfterExisting: appending)
        } catch TemplateApplyError.sessionHasBouts(let count) {
            pendingTemplate = PendingTemplate(template: template, loggedCount: count)
        } catch TemplateApplyError.templateHasNoExercises(_) {
            self.error = "\(template.name) has no exercises yet. Add some under Templates first."
        } catch {
            self.error = String(describing: error)
        }
    }

    @ViewBuilder
    private func summaryRows(_ summary: WorkoutLoadSummary) -> some View {
        if let tonnage = summary.totalTonnageKg {
            summaryRow(String(localized: "Tonnage"), value: String(localized: "\(Int(tonnage.rounded())) kg"))
        }
        if let distance = summary.totalDistanceMeters {
            summaryRow(String(localized: "Distance"), value: String(localized: "\(Int(distance.rounded())) m"))
        }
        if let duration = summary.totalDurationSeconds {
            summaryRow(String(localized: "Time under load"), value: durationLabel(duration))
        }
        if let reps = summary.totalReps {
            summaryRow(String(localized: "Reps"), value: NumberDisplay.localized(String(reps)))
        }
        if let rounds = summary.totalRounds {
            summaryRow(String(localized: "Rounds"), value: NumberDisplay.localized(String(rounds)))
        }
        if let rpe = summary.averageRPE {
            summaryRow(String(localized: "Average RPE"), value: NumberDisplay.localized(String(format: "%.1f/10", rpe)))
        }
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }

    private func boutRow(_ bout: WorkoutBoutEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.exerciseName(for: bout.exerciseCatalogId))
            Text(isPlannedOnly(bout) ? "Planned · \(boutDetailLabel(bout))" : boutDetailLabel(bout))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// True for a bout a template planned and nothing has been recorded on yet,
    /// so the row does not read as done.
    private func isPlannedOnly(_ bout: WorkoutBoutEntry) -> Bool {
        let actuals: [Any?] = [bout.actualSets, bout.actualReps, bout.actualLoadKg,
                               bout.actualDurationSeconds, bout.actualDistanceMeters, bout.actualRounds]
        return bout.containerType != nil && actuals.allSatisfy { $0 == nil }
    }

    private func boutDetailLabel(_ bout: WorkoutBoutEntry) -> String {
        switch bout.prescriptionType {
        case "reps_load":
            let sets = bout.actualSets ?? bout.prescribedSets
            let reps = bout.actualReps ?? bout.prescribedReps
            let load = bout.actualLoadKg ?? bout.prescribedLoadKg
            let loadText = load.map { String(localized: "\(Int($0)) kg") } ?? "?"
            return String(localized: "\(count(sets)) x \(count(reps)) @ \(loadText)")
        case "reps_bodyweight":
            let sets = bout.actualSets ?? bout.prescribedSets
            let reps = bout.actualReps ?? bout.prescribedReps
            return String(localized: "\(count(sets)) x \(count(reps))")
        case "distance":
            let distance = bout.actualDistanceMeters ?? bout.prescribedDistanceMeters
            return distance.map { String(localized: "\(Int($0)) m") } ?? readable(bout.prescriptionType)
        case "duration", "time_under_load", "hold_stretch":
            let duration = bout.actualDurationSeconds ?? bout.prescribedDurationSeconds
            return duration.map(durationLabel) ?? readable(bout.prescriptionType)
        case "work_in_time", "rounds_for_time":
            let rounds = bout.actualRounds ?? bout.prescribedRounds
            return rounds.map { String(localized: "\($0) rounds") } ?? readable(bout.prescriptionType)
        default:
            return readable(bout.prescriptionType)
        }
    }

    /// A set or rep count in the app's digits, or "?" when it was not recorded.
    private func count(_ value: Int?) -> String {
        value.map { NumberDisplay.localized(String($0)) } ?? "?"
    }

    private func durationLabel(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let minutes = total / 60
        let secs = total % 60
        return minutes > 0 ? String(localized: "\(minutes)m \(secs)s") : String(localized: "\(secs)s")
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            do { try model.deleteBout(id: model.todaysBouts[index].id) }
            catch { self.error = String(describing: error) }
        }
    }
}

/// Picks a template to start today's session from.
@MainActor
private struct TemplateChooser: View {
    @ObservedObject var model: TrainingModel
    let onChoose: (PrescribedWorkoutEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var templates: [PrescribedWorkoutEntry] = []
    @State private var counts: [Int64: Int] = [:]
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if templates.isEmpty {
                    Text("No templates yet. Make one under Templates: its exercises, with sets and reps where you want them.")
                        .foregroundStyle(.secondary)
                }
                ForEach(templates) { template in
                    Button {
                        onChoose(template)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name).foregroundStyle(.primary)
                            let count = counts[template.id] ?? 0
                            Text(count == 1 ? "1 exercise" : "\(count) exercises")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("apply-template-\(template.id)")
                }
            }
            .navigationTitle("Start from a template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task { load() }
            .editorError($error)
        }
    }

    private func load() {
        do {
            templates = try model.templates()
            counts = model.exerciseCounts(of: templates)
        } catch {
            self.error = String(describing: error)
        }
    }
}
