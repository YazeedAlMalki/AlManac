import SwiftUI
import AlmanacCore

/// The exercise library as pages inside pages: muscle → method → exercises.
///
/// The first version was one long list of collapsible sections, which the owner
/// rejected (2026-09-26): with 16 muscles and up to 17 methods each it read as a
/// wall. Each level is now its own pushed screen, so a screen only ever answers
/// one question — which muscle, then which method, then which exercise.
///
/// The data is `ExerciseCatalogStore.groupedByMuscleThenEquipment()`, loaded
/// once at the top and passed down, so drilling in never re-queries. An exercise
/// with several muscles in `exerciseMuscle` appears under each of them.
struct ExerciseLibraryView: View {
    @ObservedObject var model: TrainingModel
    var onPick: ((ExerciseCatalogEntry) -> Void)?

    @State private var groups: [MuscleGroup] = []
    @State private var loaded = false

    var body: some View {
        List {
            if !loaded {
                ProgressView("Loading exercises").frame(maxWidth: .infinity)
            } else if groups.isEmpty {
                Text("No exercises in the catalogue yet.")
                    .foregroundStyle(AlmanacPalette.textSecondary)
            } else {
                ForEach(groups) { group in
                    NavigationLink {
                        MuscleMethodsView(model: model, group: group, onPick: onPick)
                    } label: {
                        LibraryRow(title: group.muscle,
                                   detail: group.hasSecondaryOnly
                                       ? "Nothing here is primarily this muscle"
                                       : nil,
                                   count: group.byEquipment.reduce(0) { $0 + $1.exercises.count })
                    }
                    .accessibilityIdentifier("muscle-\(group.muscle)")
                }
            }
        }
        .navigationTitle("Muscle groups")
        .navigationBarTitleDisplayMode(.inline)
        .almanacModuleSurface()
        .task {
            guard !loaded else { return }
            groups = model.muscleGroups()
            loaded = true
        }
    }
}

/// Second page: the methods of training for one muscle.
private struct MuscleMethodsView: View {
    @ObservedObject var model: TrainingModel
    let group: MuscleGroup
    var onPick: ((ExerciseCatalogEntry) -> Void)?

    var body: some View {
        List {
            ForEach(group.byEquipment) { method in
                NavigationLink {
                    MethodExercisesView(model: model, muscle: group.muscle,
                                        method: method, onPick: onPick)
                } label: {
                    LibraryRow(title: method.equipment, detail: nil,
                               count: method.exercises.count)
                }
                .accessibilityIdentifier("method-\(method.equipment)")
            }
        }
        .navigationTitle(group.muscle)
        .navigationBarTitleDisplayMode(.inline)
        .almanacModuleSurface()
    }
}

/// Third page: the exercises for one muscle and one method.
private struct MethodExercisesView: View {
    @ObservedObject var model: TrainingModel
    let muscle: String
    let method: EquipmentGroup
    var onPick: ((ExerciseCatalogEntry) -> Void)?

    var body: some View {
        List {
            ForEach(method.exercises) { exercise in
                NavigationLink {
                    ExerciseDetailPage(model: model, exercise: exercise, onPick: onPick)
                } label: {
                    Text(exercise.name)
                        .foregroundStyle(AlmanacPalette.textPrimary)
                }
                .accessibilityIdentifier("exercise-row-\(exercise.id)")
            }
        }
        .navigationTitle("\(muscle) · \(method.equipment)")
        .navigationBarTitleDisplayMode(.inline)
        .almanacModuleSurface()
    }
}

/// Last page: one exercise — its history and graph, and the way to log it.
/// Putting "Log this" here rather than on the row means a tap on an exercise
/// always does the same thing (open it), and logging is a deliberate second tap.
private struct ExerciseDetailPage: View {
    @ObservedObject var model: TrainingModel
    let exercise: ExerciseCatalogEntry
    var onPick: ((ExerciseCatalogEntry) -> Void)?

    var body: some View {
        ExerciseProgressView(model: model, exercise: exercise)
            .safeAreaInset(edge: .bottom) {
                if let onPick {
                    Button("Log this exercise") { onPick(exercise) }
                        .buttonStyle(AlmanacPrimaryButtonStyle())
                        .padding(.horizontal, AlmanacMetrics.screenInset)
                        .padding(.vertical, 12)
                        .background(AlmanacPalette.canvas)
                        .accessibilityIdentifier("log-this-exercise")
                }
            }
    }
}

/// One row at any level: a name and how many exercises are underneath it.
private struct LibraryRow: View {
    let title: String
    let detail: String?
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AlmanacTypography.font(.body))
                    .foregroundStyle(AlmanacPalette.textPrimary)
                if let detail {
                    Text(detail)
                        .font(AlmanacTypography.font(.caption))
                        .foregroundStyle(AlmanacPalette.textSecondary)
                }
            }
            Spacer(minLength: 12)
            Text("\(count)")
                .font(AlmanacTypography.font(.data).monospacedDigit())
                .foregroundStyle(AlmanacPalette.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(count) exercises")
    }
}
