import SwiftUI
import UniformTypeIdentifiers
import AlmanacCore
import Darwin

/// Create, share and restore whole-app backups.
///
/// Backups are `*.almanac-backup` files: one SQLite container holding the
/// live database and every laboratory document, written by `BackupService`.
///
/// **What stays and what leaves.** A backup created here stays in the app's
/// backups folder, unencrypted, and that folder is excluded from iCloud and
/// computer backups. A backup that is *shared* is always an encrypted copy
/// (`EncryptedBackup`, passphrase chosen by the person), made on demand in the
/// temporary directory and removed when the share sheet closes. No plaintext
/// copy is ever handed to the share sheet (audit finding S-02).
///
/// Import accepts an encrypted backup (asking for its passphrase), the raw
/// container, and a plain `.zip` made by earlier versions of the app.
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
    @State private var importPresented = false
    /// The backup whose encrypted copy is being made for sharing.
    @State private var sharing: BackupBundleInfo?
    /// An encrypted backup picked for import, waiting for its passphrase, and the
    /// staging folder to remove when the sheet closes.
    @State private var encryptedImport: EncryptedImport?
    @State private var importStaging: URL?

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
                if let shareable = latest ?? bundles.first {
                    Button {
                        sharing = shareable
                    } label: {
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
            } footer: {
                Text("Backups kept on this device are not encrypted and are left out of iCloud and computer backups. A backup you share is always encrypted with a passphrase you choose.")
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
        .sheet(item: $sharing, onDismiss: { BackupShareFiles.removeAll() }) { bundle in
            BackupShareSheet(bundle: bundle)
        }
        .sheet(item: $encryptedImport, onDismiss: discardEncryptedImport) { pending in
            BackupImportPassphraseSheet { passphrase in
                await finishEncryptedImport(pending, passphrase: passphrase)
            }
        }
        .task {
            // A share that was interrupted (app killed) can leave its copy behind.
            BackupShareFiles.removeAll()
            reload()
        }
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
            keepOutOfDeviceBackups()
            removeLegacyZipTwins()
            bundles = try service.listBundles(in: backupsDirectory.path)
        } catch {
            self.error = String(describing: error)
        }
    }

    /// The backups folder holds the whole health record in clear. It is already
    /// inside the app's sandbox; this keeps it out of iCloud and computer backups too.
    private func keepOutOfDeviceBackups() {
        var url = backupsDirectory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    /// Earlier versions wrote a plaintext `.zip` twin next to every backup and
    /// never removed it (audit finding S-02). Nothing reads them, so they go.
    private func removeLegacyZipTwins() {
        let entries = (try? fileManager.contentsOfDirectory(at: backupsDirectory, includingPropertiesForKeys: nil)) ?? []
        for url in entries where url.pathExtension.lowercased() == "zip" {
            try? fileManager.removeItem(at: url)
        }
    }

    private func createBackup() {
        isWorking = true
        defer { isWorking = false }
        do {
            try fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let target = backupsDirectory.appendingPathComponent("almanac-\(stamp).almanac-backup")
            latest = try service.writeBundle(to: target.path, documentsRoot: documentsDirectory, note: nil)
            reload()
        } catch {
            self.error = String(describing: error)
        }
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
        var keepStaging = false
        defer { if !keepStaging { try? fileManager.removeItem(at: tmp) } }
        do {
            try fileManager.createDirectory(at: tmp, withIntermediateDirectories: true)
            if EncryptedBackup.isEncrypted(fileAt: url.path) {
                // Copied now, while access to the picked file is open: the
                // passphrase is asked for afterwards, outside that window.
                let copy = tmp.appendingPathComponent("candidate.enc")
                try fileManager.copyItem(at: url, to: copy)
                importStaging = tmp
                encryptedImport = EncryptedImport(file: copy, staging: tmp)
                keepStaging = true
                return
            }
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
            try adopt(bundleURL)
        } catch {
            self.error = String(describing: error)
        }
    }

    /// Validates a plain container before it is adopted: a non-bundle (or a
    /// foreign zip that unzipped but still is not one) must not land in the
    /// folder. Then moves it into the backups folder.
    private func adopt(_ bundleURL: URL) throws {
        try fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        _ = try service.readBundleInfo(at: bundleURL.path)
        for suffix in ["-wal", "-shm"] { try? fileManager.removeItem(atPath: bundleURL.path + suffix) }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let target = backupsDirectory.appendingPathComponent("imported-\(stamp).almanac-backup")
        try fileManager.moveItem(at: bundleURL, to: target)
        reload()
    }

    /// Decrypts the picked file with `passphrase` and adopts the result. Returns a
    /// message for the passphrase sheet to show, or `nil` on success.
    private func finishEncryptedImport(_ pending: EncryptedImport, passphrase: String) async -> String? {
        let opened = pending.staging.appendingPathComponent("candidate.almanac-backup")
        do {
            // Key derivation is deliberately slow; keep it off the main actor.
            try await Task.detached(priority: .userInitiated) {
                try EncryptedBackup.decryptFile(at: pending.file.path, to: opened.path,
                                                passphrase: passphrase, using: CryptoKitBackupCipher())
            }.value
            try adopt(opened)
            return nil
        } catch {
            try? fileManager.removeItem(at: opened)
            return String(describing: error)
        }
    }

    private func discardEncryptedImport() {
        if let importStaging { try? fileManager.removeItem(at: importStaging) }
        importStaging = nil
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
