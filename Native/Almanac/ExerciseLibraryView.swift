import SwiftUI
import AlmanacCore

/// The exercise library, browsable as **muscle group → method of training**.
///
/// Asked for 2026-09-26. Both halves of the grouping were already in the data
/// — `exerciseCatalog.category` is a muscle (Chest, Quads, Lats, Rear Delts,
/// …) and `exerciseCatalog.equipment` is the method (17 distinct values across
/// the shipped catalogue) — so this is a browse view over existing rows rather
/// than a new classification.
///
/// An exercise is listed under **every** muscle in `exerciseMuscle`, so a
/// movement that works two groups appears in both, and `Migration042` made
/// that many-to-many real. Only the primary muscle is populated today:
/// naming the secondary movers of 300-odd movements is a claim about
/// physiology, and this repo's rule is that a guessed value written into user
/// data is worse than an absent one. Adding secondaries is a data import
/// (`addMuscle(to:muscle:)`); nothing here has to change when it arrives.
struct ExerciseLibraryView: View {
    @ObservedObject var model: TrainingModel
    var onPick: ((ExerciseCatalogEntry) -> Void)?

    @State private var groups: [MuscleGroup] = []
    @State private var loaded = false
    @State private var collapsed: Set<String> = []
    @State private var historyFor: ExerciseCatalogEntry?

    var body: some View {
        List {
            if !loaded {
                Section { ProgressView("Loading catalogue").frame(maxWidth: .infinity) }
            } else if groups.isEmpty {
                Section {
                    Text("No exercises in the catalogue yet.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(groups) { group in
                    muscleSection(group)
                }
            }
        }
        .navigationTitle("Exercises")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $historyFor) { exercise in
            ExerciseProgressView(model: model, exercise: exercise)
        }
        .task {
            groups = model.muscleGroups()
            loaded = true
        }
    }

    // MARK: - Muscle group

    private func muscleSection(_ group: MuscleGroup) -> some View {
        let isCollapsed = collapsed.contains(group.muscle)
        return Section {
            if isCollapsed {
                // Collapsed still shows the count, so a collapsed group is a
                // deliberate skip rather than a group that looks empty.
                Text("\(count(in: group)) exercises")
                    .font(AlmanacTypography.font(.caption))
                    .foregroundStyle(AlmanacPalette.textSecondary)
            } else {
                ForEach(group.byEquipment) { equipment in
                    equipmentSection(equipment, in: group)
                }
            }
        } header: {
            Button {
                toggle(group.muscle)
            } label: {
                HStack {
                    Text(group.muscle)
                    if group.hasSecondaryOnly {
                        // Listed here only because the movement also works this
                        // group. Saying so is the difference between a main entry
                        // and an "also".
                        Text("also works")
                            .font(AlmanacTypography.font(.caption))
                            .foregroundStyle(AlmanacPalette.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Text(isCollapsed ? "\(count(in: group))" : "−")
                        .font(AlmanacTypography.font(.caption))
                        .foregroundStyle(AlmanacPalette.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(group.muscle), \(count(in: group)) exercises")
            .accessibilityHint(isCollapsed ? "Expands the group" : "Collapses the group")
        }
    }

    // MARK: - Method of training

    private func equipmentSection(_ equipment: EquipmentGroup, in group: MuscleGroup) -> some View {
        Section {
            ForEach(equipment.exercises) { exercise in
                row(exercise)
            }
        } header: {
            Text(equipment.equipment)
        }
    }

    // MARK: - Row

    private func row(_ exercise: ExerciseCatalogEntry) -> some View {
        HStack(spacing: 12) {
            Button {
                onPick?(exercise)
            } label: {
                HStack(spacing: 12) {
                    Text(exercise.name)
                        .foregroundStyle(AlmanacPalette.textPrimary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onPick == nil)
            .accessibilityIdentifier("exercise-row-\(exercise.id)")

            // A second, separate action: the graph is a look-back, not part of
            // choosing an exercise, so it gets its own target rather than
            // turning every row into a two-in-one control.
            Button {
                historyFor = exercise
            } label: {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(AlmanacPalette.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("History for \(exercise.name)")
            .accessibilityIdentifier("exercise-history-\(exercise.id)")
        }
    }

    // MARK: - Helpers

    private func count(in group: MuscleGroup) -> Int {
        group.byEquipment.reduce(0) { $0 + $1.exercises.count }
    }

    private func toggle(_ muscle: String) {
        if collapsed.contains(muscle) { collapsed.remove(muscle) } else { collapsed.insert(muscle) }
    }
}
