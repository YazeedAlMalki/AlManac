import SwiftUI
import AlmanacCore

/// Which synced source wins, per domain, when two disagree.
///
/// Asked for by the owner on 2026-09-26 and reachable from Settings → HealthKit →
/// "Which source wins", which is the "and can change it later from settings" half
/// of the request. There is no first-run prompt yet: profile setup is a display
/// name and a few fields, and grafting a seven-domain arbitration question onto
/// it would be the wrong place. The link in Settings is the whole surface for
/// now, and the store is the same either way.
///
/// Read the footnote before reading the pickers. **Apple Health is currently the
/// only synced source** — the Whoop and Fitbit integrations do not exist, and
/// this screen is the arbitration layer waiting for them, not evidence they are
/// on the way. Every row below therefore has exactly one real choice today. It
/// is still worth setting now, because a preference recorded after a second
/// provider starts writing is a preference recorded against data the user has
/// already seen and formed an opinion about.
struct SyncSourcePreferenceView: View {
    let db: Database?

    @State private var choices: [SyncDomain: SyncSource] = [:]
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                ForEach(SyncDomain.allCases, id: \.self) { domain in
                    row(domain)
                }
            } footer: {
                Text("Apple Health is the only source Almanac can read from today. These settings decide what happens when a second one is added and the two disagree — most visibly about sleep, where a watch and a ring will not agree on staging.")
            }

            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Which source wins")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let db else { loaded = true; return }
            choices = (try? SyncSourcePreferenceStore(db: db).allPreferences()) ?? [:]
            loaded = true
        }
    }

    private func row(_ domain: SyncDomain) -> some View {
        Picker(selection: binding(for: domain)) {
            Text("Not decided").tag(String?.none)
            ForEach(SyncSource.builtIn) { source in
                Text(source.title).tag(String?.some(source.id))
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(domain.title)
                if loaded && choices[domain] == nil {
                    Text("Undecided")
                        .font(AlmanacTypography.font(.caption))
                        .foregroundStyle(AlmanacPalette.textSecondary)
                }
            }
        }
        .accessibilityIdentifier("sync-source-\(domain.rawValue)")
    }

    /// Writing goes through the store rather than being kept only in local
    /// state, so the choice survives relaunch and so a second provider reads the
    /// same row this screen writes.
    private func binding(for domain: SyncDomain) -> Binding<String?> {
        Binding(
            get: { choices[domain]?.id },
            set: { newValue in
                do {
                    guard let db else { return }
                    let store = SyncSourcePreferenceStore(db: db)
                    if let newValue {
                        let source = SyncSource.builtIn.first { $0.id == newValue }
                            ?? SyncSource(id: newValue, title: newValue)
                        try store.setPreferredSource(source, for: domain)
                        choices[domain] = source
                    } else {
                        try store.clearPreference(for: domain)
                        choices[domain] = nil
                    }
                } catch {
                    self.error = String(describing: error)
                }
            })
    }
}
