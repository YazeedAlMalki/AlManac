import SwiftUI
import UserNotifications
import WidgetKit
import AlmanacCore
import Darwin

/// Settings → About → Privacy: what Almanac keeps, where, and what the person can
/// do about it. Every statement here is one the code makes true today; the same
/// facts, in more detail, are in `docs/PRIVACY.md`. If a feature changes one of
/// them (a server, an SDK, a new permission), change this screen, that document
/// and `PrivacyInfo.xcprivacy` in the same commit.
///
/// Draft wording: it has not been reviewed by a lawyer or, in Arabic, a native
/// speaker. It describes behaviour; it is not a legal opinion.
struct PrivacyNoticeView: View {
    var body: some View {
        Form {
            Section("Where your data lives") {
                Text("Everything you record stays on this phone. Almanac has no account, no server and no analytics, and it makes no network requests of its own. A link to a source opens in your browser only when you tap it.")
            }
            Section("What Almanac keeps") {
                Text("The records you enter, or choose to bring in from Apple Health: meals, water, training, body measurements, sleep, laboratory results, mood, digestion, fasting and prayer settings, and the profile details you give it.")
            }
            Section("Permissions") {
                Text("Apple Health: Almanac reads and writes only the kinds of data you allow. Location: used once, when you ask for it, to work out prayer times; the coordinates are kept on this phone. Notifications: reminders are scheduled on this phone.")
            }
            Section("Sharing") {
                Text("Nothing leaves your phone unless you share it. A backup you share is encrypted with a passphrase you choose. An export of your data is a readable file and is not encrypted, so share it only with people and apps you trust.")
            }
            Section("Your choices") {
                Text("You can export your data, or erase everything, from Settings. You can change permissions in iOS Settings, or delete the app. Data already in Apple Health stays there until you remove it in the Health app.")
            }
            Section("Sources") {
                Text("Food, exercise and laboratory reference data comes from public datasets credited under Attributions.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AlmanacPalette.canvas)
        .navigationTitle("Privacy")
        .toolbarBackground(AlmanacPalette.canvas, for: .navigationBar)
    }
}

struct ExportedFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// "Export my data" and "Erase all data", the person's access and deletion rights
/// (remediation P1-5), as two rows for Settings → Data.
@MainActor
struct DataRightsRows: View {
    let db: Database?

    @State private var exportedFile: ExportedFile?
    @State private var isExporting = false
    @State private var confirmErase = false
    @State private var error: String?

    var body: some View {
        Group {
            if let db {
                Button {
                    export(db)
                } label: {
                    if isExporting {
                        ProgressView()
                    } else {
                        Label("Export my data…", systemImage: "square.and.arrow.up.on.square")
                    }
                }
                .disabled(isExporting)
                .accessibilityIdentifier("settings-export-data")
            }
            Button(role: .destructive) {
                confirmErase = true
            } label: {
                Label("Erase all data…", systemImage: "trash")
            }
            .accessibilityIdentifier("settings-erase-data")
            // An alert rather than a confirmation dialog: its Cancel button is
            // reliably in the accessibility tree, which the UI test relies on.
            .alert("Erase everything?", isPresented: $confirmErase) {
                Button("Erase everything and restart", role: .destructive) { erase() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All your records, backups and settings on this phone are deleted and cannot be recovered. Data already in Apple Health stays there; remove it in the Health app. Backups you shared with others are not affected.")
            }
        }
        .sheet(item: $exportedFile, onDismiss: { DataExportFiles.removeAll() }) { exported in
            DataExportSheet(file: exported.url)
        }
        .editorError($error)
    }

    private func export(_ db: Database) {
        isExporting = true
        let file = DataExportFiles.newDirectory().appendingPathComponent(
            "almanac-export-" + ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-") + ".json")
        Task {
            do {
                // Reads every table of the person's records; keep it off the main actor.
                try await Task.detached(priority: .userInitiated) {
                    try DataExport(db: db).write(to: file.path)
                }.value
                exportedFile = ExportedFile(url: file)
            } catch {
                try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
                self.error = String(describing: error)
            }
            isExporting = false
        }
    }

    private func erase() {
        do {
            try AppDataEraser.eraseEverything()
        } catch {
            self.error = String(describing: error)
        }
    }
}

/// Where an export lives while its share sheet is open: the temporary directory,
/// removed when the sheet closes.
enum DataExportFiles {
    static let prefix = "AlmanacExport-"

    static func newDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(prefix + UUID().uuidString, isDirectory: true)
    }

    static func removeAll() {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(at: fm.temporaryDirectory, includingPropertiesForKeys: nil)) ?? []
        for url in entries where url.lastPathComponent.hasPrefix(prefix) { try? fm.removeItem(at: url) }
    }
}

@MainActor
struct DataExportSheet: View {
    let file: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ShareLink(item: file) {
                        Label("Share export", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("settings-share-export")
                } footer: {
                    Text("This file is a readable copy of your records. It is not encrypted. Share it only with people and apps you trust.")
                }
            }
            .navigationTitle("Export my data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

/// Everything "Erase all data" does that only the app can do. The database and
/// folders go through `LocalDataEraser` (core, tested); this adds the reminders
/// already scheduled with iOS, preferences, temporary copies and widgets, then
/// quits, because every screen and model still holds state read from what was
/// just deleted. The next launch is a first launch.
///
/// Data in Apple Health is not Almanac's to erase and is left alone; the
/// confirmation says so.
@MainActor
enum AppDataEraser {
    static func eraseEverything() throws {
        // Reminders first, so nothing fires about records that no longer exist.
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()

        BackupShareFiles.removeAll()
        DataExportFiles.removeAll()

        var databaseFiles = [try AppGroupDatabase.legacyFileURL().path]
        if let group = AppGroupDatabase.groupContainer {
            databaseFiles.append(group.appendingPathComponent("almanac.sqlite").path)
        }
        // Application Support/Almanac holds the legacy database, Backups/ and Documents/.
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: false)
            .appendingPathComponent("Almanac", isDirectory: true)
        try LocalDataEraser.erase(databaseFiles: databaseFiles, directories: [support.path])

        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        WidgetCenter.shared.reloadAllTimelines()
        exit(0)
    }
}
