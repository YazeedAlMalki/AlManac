import SwiftUI
import AlmanacCore
import UIKit

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
                    HStack(spacing: 12) {
                        ExerciseGraphicThumbnail(path: exercise.graphicPath)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name).foregroundStyle(.primary)
                            Text(readable(exercise.prescriptionType))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Search exercises")
        .navigationTitle("Choose Exercise")
        .navigationBarTitleDisplayMode(.inline)
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
                Color.secondary.opacity(0.12)
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
