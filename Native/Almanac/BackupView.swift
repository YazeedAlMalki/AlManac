import SwiftUI
import UniformTypeIdentifiers
import AlmanacCore
import Darwin

/// Create, share and restore whole-app backups.
///
/// Backups are `*.almanac-backup` files: one SQLite container holding the
/// live database and every laboratory document, written by `BackupService`.
/// Sharing wraps the container in a `.zip` (BRD §6.18) so any mail client,
/// OS or archive tool accepts it; import accepts both the raw container and a
/// `.zip` and unwraps the latter before adopting it.
/// The list is read from the backups folder, not from `backup_manifest`,
/// because that table lives inside the database a restore replaces — files
/// created after the snapshot point would otherwise vanish from the list the
/// moment a restore completed.
@MainActor
struct BackupView: View {
    let db: Database

    @State private var bundles: [BackupBundleInfo] = []
    @State private var latest: BackupBundleInfo?
    @State private var latestZipPath: String?
    @State private var pendingRestore: BackupBundleInfo?
    @State private var error: String?
    @State private var isWorking = false
    @State private var importPresented = false
    /// A backup needs a valid email on the profile (owner, 2026-10-20).
    /// Read on every visit, so an email saved in Profile counts at once.
    @State private var mayCreateBackup = false

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
                .disabled(isWorking || !mayCreateBackup)
                if mayCreateBackup {
                    Text("Saves the database and every laboratory document into one file on this device.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Add a valid email address in Profile to create backups. Restoring a backup does not need one.")
                        .font(.caption).foregroundStyle(AlmanacPalette.warning)
                        .accessibilityIdentifier("backup-needs-email")
                }
                if let latest {
                    ShareLink(item: shareItem(for: latest)) {
                        Label("Share latest backup", systemImage: "square.and.arrow.up")
                    }
                }
                Button {
                    importPresented = true
                } label: {
                    Label("Import backup…", systemImage: "square.and.arrow.down")
                }
                .fileImporter(
                    isPresented: $importPresented,
                    allowedContentTypes: [.zip, .data]
                ) { result in
                    switch result {
                    case .success(let url): importBackup(from: url)
                    case .failure(let e): error = String(describing: e)
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
                                    .font(.caption).foregroundStyle(AlmanacPalette.warning)
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
        mayCreateBackup = (try? ProfileStore(db: db).profile().mayCreateBackup) ?? false
        do {
            try fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
            bundles = try service.listBundles(in: backupsDirectory.path)
        } catch {
            self.error = String(describing: error)
        }
    }

    private func createBackup() {
        guard mayCreateBackup else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let target = backupsDirectory.appendingPathComponent("almanac-\(stamp).almanac-backup")
            let info = try service.writeBundle(to: target.path, documentsRoot: documentsDirectory, note: nil)
            latest = info
            // A `.zip` twin for sharing (BRD §6.18): the raw container stays in
            // the backups folder for restore; the zip is what leaves the app.
            latestZipPath = try BackupZipper.zip(bundlePath: info.filePath)
            reload()
        } catch {
            self.error = String(describing: error)
        }
    }

    /// What a share hands out: the `.zip` envelope (any mail client, OS or
    /// archive tool accepts it), falling back to the raw container if the twin
    /// is missing.
    private func shareItem(for bundle: BackupBundleInfo) -> URL {
        if let latestZipPath, latest?.filePath == bundle.filePath {
            return URL(fileURLWithPath: latestZipPath)
        }
        return URL(fileURLWithPath: bundle.filePath)
    }

    private func importBackup(from url: URL) {
        isWorking = true
        defer { isWorking = false }
        // A file picked from Files or iCloud is outside the sandbox and can
        // only be read inside a security-scoped access window.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let tmp = fileManager.temporaryDirectory
            .appendingPathComponent("AlmanacImport-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: tmp) }
        do {
            try fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: tmp, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let target = backupsDirectory.appendingPathComponent("imported-\(stamp).almanac-backup")
            let bundleURL: URL
            if url.pathExtension.lowercased() == "zip" {
                // Unzip to a temp dir first; the validated container then lands
                // in the backups folder like any locally-created one.
                let extracted = try BackupZipper.unzip(archivePath: url.path, into: tmp.path)
                bundleURL = URL(fileURLWithPath: extracted)
            } else {
                // Validated as a private copy: opening a SQLite file can write
                // to it (journal mode, sidecars), and the person's original in
                // Files must not change. The copy is also what gets adopted,
                // so what was validated is exactly what lands in the folder.
                bundleURL = tmp.appendingPathComponent("candidate.almanac-backup")
                try fileManager.copyItem(at: url, to: bundleURL)
            }
            // Validate before adopting: a non-bundle (or a foreign zip that
            // unzipped but still is not one) must not land in the folder.
            _ = try service.readBundleInfo(at: bundleURL.path)
            for suffix in ["-wal", "-shm"] { try? fileManager.removeItem(atPath: bundleURL.path + suffix) }
            try fileManager.moveItem(at: bundleURL, to: target)
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
            parts.append(String(localized: "\(bundle.documentCount) documents"))
        }
        parts.append(ByteCountFormatter.string(fromByteCount: bundle.byteCount, countStyle: .file))
        if let note = bundle.note { parts.append(note) }
        return parts.joined(separator: " · ")
    }

    private func dateText(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso) else { return iso }
        return date.almanacFormatted(date: .abbreviated, time: .shortened)
    }
}