import SwiftUI
import AlmanacCore
import UIKit

/// A searchable list of catalog exercises. Pushed from `LogBoutView`; pops
/// itself on selection via `onSelect` rather than owning navigation state
/// itself.
///
/// Each row carries a second, separate action: a chevron that opens the
/// exercise's logged history rather than selecting it. Tapping the row still
/// means "log this", which is what the caller came here for, and the history
/// is a look-back rather than part of that choice — so it gets its own target
/// instead of turning every row into a two-in-one control.
struct ExercisePickerView: View {
    let model: TrainingModel
    let exercises: [ExerciseCatalogEntry]
    let onSelect: (ExerciseCatalogEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var historyFor: ExerciseCatalogEntry?

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
                HStack(spacing: 8) {
                    Button {
                        onSelect(exercise)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            ExerciseGraphicThumbnail(path: exercise.graphicPath)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.name).foregroundStyle(.primary)
                                Text(readable(exercise.prescriptionType))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("exercise-row-\(exercise.id)")

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
        }
        .accessibilityIdentifier("exercise-catalog")
        .searchable(text: $query, prompt: "Search exercises")
        .navigationTitle("Choose Exercise")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $historyFor) { exercise in
            ExerciseProgressView(model: model, exercise: exercise)
        }
    }
}

/// The exercise's demonstration graphic, from AlmanacCore's resource bundle.
/// Every shipped exercise has one (`ExerciseGraphicAudit`), so the empty
/// branch is a guard rather than an expected state.
private struct ExerciseGraphicThumbnail: View {
    let path: String?

    var body: some View {
        Group {
            if let image = ExerciseGraphicCache.image(for: path) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                // `ExerciseGraphicAudit` refuses to launch the app if any
                // exercise lacks a graphic, so this is a belt-and-braces
                // placeholder. It uses the palette rather than a system grey
                // so the "no raw colour outside DesignSystem.swift" rule has
                // no exceptions left.
                AlmanacPalette.surfaceMuted
            }
        }
        .frame(width: 44, height: 44)
    }
}

/// The graphics live in a resource bundle, not the app bundle, so `Image(_:)`
/// cannot find them; decode from the path and cache. 302 rows scroll through
/// this list, so without a cache the same PNGs would be re-decoded on every
/// row appearance.
private enum ExerciseGraphicCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 64
        return cache
    }()

    static func image(for path: String?) -> UIImage? {
        guard let path else { return nil }
        if let cached = cache.object(forKey: path as NSString) { return cached }
        guard let data = ExerciseGraphics.data(named: path),
              let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: path as NSString)
        return image
    }
}
