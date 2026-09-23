import SwiftUI
import AlmanacCore
import Darwin

/// Create, share and restore whole-app backups.
///
/// Backups are `*.almanac-backup` files: one SQLite container holding the
/// live database and every laboratory document, written by `BackupService`.
/// The list is read from the backups folder, not from `backup_manifest`,
/// because that table lives inside the database a restore replaces — files
/// created after the snapshot point would otherwise vanish from the list the
/// moment a restore completed.
@MainActor
struct BackupView: View {
    let db: Database

    @State private var bundles: [BackupBundleInfo] = []
    @State private var latest: BackupBundleInfo?
    @State private var pendingRestore: BackupBundleInfo?
    @State private var error: String?
    @State private var isWorking = false

    private var fileManager: FileManager { .default }
    private var supportRoot: URL {
        (try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                              appropriateFor: nil, create: true))?.appendingPathComponent("Almanac", isDirectory: true)
            ?? fileManager.temporaryDirectory
    }
    private var backupsDirectory: URL {
        supportRoot.appendingPathComponent("Backups", isDirectory: true)
    }
    private var documentsDirectory: URL {
        supportRoot.appendingPathComponent("Documents", isDirectory: true)
    }
    private var service: BackupService { BackupService(db: db) }

    private var currentSchemaVersion: Int64 {
        (try? db.query("SELECT COALESCE(MAX(version), 0) AS v FROM schema_migrations;").first?.int("v")) ?? 0
    }

    var body: some View {
        Form {
            Section {
                Button {
                    createBackup()
                } label: {
                    Label("Create backup", systemImage: "externaldrive.badge.plus")
                }
                .disabled(isWorking)
                Text("Saves the database and every laboratory document into one file on this device.")
                    .font(.caption).foregroundStyle(.secondary)
                if let latest {
                    ShareLink(item: URL(fileURLWithPath: latest.filePath)) {
                        Label("Share latest backup", systemImage: "square.and.arrow.up")
                    }
                }
            }

            Section("Backups on this device") {
                if bundles.isEmpty {
                    Text("No backups yet.").foregroundStyle(.secondary)
                }
                ForEach(bundles) { bundle in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(bundle.fileName).font(.subheadline)
                            Text(summary(for: bundle)).font(.caption).foregroundStyle(.secondary)
                            if bundle.schemaVersion != currentSchemaVersion {
                                Text("Made by an older version of Almanac — restore is not available.")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        if bundle.schemaVersion == currentSchemaVersion {
                            Button("Restore", role: .destructive) { pendingRestore = bundle }
                        }
                    }
                }
            }
        }
        .navigationTitle("Backup & restore")
        .editorError($error)
        .confirmationDialog("Replace your records?", isPresented: restorePresented, titleVisibility: .visible) {
            Button("Restore and restart", role: .destructive) { performRestore() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your current records are replaced with the backup. The app restarts when the restore finishes.")
        }
        .task { reload() }
    }

    private var restorePresented: Binding<Bool> {
        Binding(
            get: { pendingRestore != nil },
            set: { if !$0 { pendingRestore = nil } }
        )
    }

    private func reload() {
        do {
            try fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
            bundles = try service.listBundles(in: backupsDirectory.path)
        } catch {
            self.error = String(describing: error)
        }
    }

    private func createBackup() {
        isWorking = true
        defer { isWorking = false }
        do {
            try fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let target = backupsDirectory.appendingPathComponent("almanac-\(stamp).almanac-backup")
            let info = try service.writeBundle(to: target.path, documentsRoot: documentsDirectory, note: nil)
            latest = info
            reload()
        } catch {
            self.error = String(describing: error)
        }
    }

    private func performRestore() {
        guard let pendingRestore else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try service.restoreBundle(at: pendingRestore.filePath, documentsRoot: documentsDirectory)
            // The whole database was replaced on disk. In-memory state no
            // longer matches; restarting is the honest way to reload it.
            exit(0)
        } catch {
            self.error = String(describing: error)
        }
    }

    private func summary(for bundle: BackupBundleInfo) -> String {
        var parts = [dateText(bundle.createdAt)]
        if bundle.documentCount > 0 {
            parts.append("\(bundle.documentCount) document\(bundle.documentCount == 1 ? "" : "s")")
        }
        parts.append(ByteCountFormatter.string(fromByteCount: bundle.byteCount, countStyle: .file))
        if let note = bundle.note { parts.append(note) }
        return parts.joined(separator: " · ")
    }

    private func dateText(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return iso }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}