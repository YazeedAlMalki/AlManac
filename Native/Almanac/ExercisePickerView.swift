import SwiftUI
import AlmanacCore

/// A searchable list of catalog exercises. Pushed from `LogBoutView`; pops
/// itself on selection via `onSelect` rather than owning navigation state
/// itself.
struct ExercisePickerView: View {
    let exercises: [ExerciseCatalogEntry]
    let onSelect: (ExerciseCatalogEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [ExerciseCatalogEntry] {
        guard !query.isEmpty else { return exercises }
        return exercises.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List {
            if exercises.isEmpty {
                Text("No exercises in the catalog yet.").foregroundStyle(.secondary)
            }
            ForEach(filtered) { exercise in
                Button {
                    onSelect(exercise)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.name).foregroundStyle(.primary)
                        Text(readable(exercise.prescriptionType))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Search exercises")
        .navigationTitle("Choose Exercise")
        .navigationBarTitleDisplayMode(.inline)
    }
}
