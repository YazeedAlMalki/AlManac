import SwiftUI
import AlmanacCore

/// Settings → About → Attributions.
///
/// The source entries come from `AttributionCatalog`, which is compiled into
/// the app, so the page needs no network. The per-author list is read from the
/// local `exerciseCatalog`, so it is offline too. If a source's entry is
/// missing the build would have failed (`AttributionAudit`), so this view never
/// has to decide what to do about an uncredited source.
struct AttributionsView: View {
    let db: Database?

    @State private var authors: [String: [ExerciseAuthorCredit]] = [:]

    var body: some View {
        List {
            Section("Sources") {
                ForEach(AttributionCatalog.entries, id: \.sourceId) { entry in
                    entryView(entry)
                }
            }

            ForEach(AttributionCatalog.entries, id: \.sourceId) { entry in
                if let credits = authors[entry.sourceId], !credits.isEmpty {
                    Section("\(entry.title) — exercise authors") {
                        ForEach(credits) { credit in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(credit.author)
                                if let license = credit.license {
                                    Text(license.name).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Attributions")
        .navigationBarTitleDisplayMode(.inline)
        .task { loadAuthors() }
    }

    @ViewBuilder
    private func entryView(_ entry: Attribution) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.title).font(.headline)
            Text(entry.author).font(.subheadline).foregroundStyle(.secondary)
            if let notice = entry.sourceNotice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
            }
            if let url = URL(string: entry.sourceURL) {
                Link(entry.sourceURL, destination: url).font(.footnote)
            }
            ForEach(entry.licenses, id: \.url) { license in
                if let url = URL(string: license.url) {
                    Link(license.name, destination: url).font(.footnote)
                }
            }
            if entry.isModified, let note = entry.modificationNote {
                Text("Modified: \(note)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    /// One row per distinct (author, licence) pair in the local catalog — an
    /// exercise source names an author per row, and listing them here satisfies
    /// the per-exercise attribution obligation without a per-row detail screen.
    /// The grouping itself lives in `ExerciseAuthorCredits` (core, tested).
    private func loadAuthors() {
        guard let db, let entries = try? ExerciseCatalogStore(db: db).all() else { return }
        authors = Dictionary(grouping: entries, by: \.sourceId).mapValues(ExerciseAuthorCredits.distinct(from:))
    }
}
