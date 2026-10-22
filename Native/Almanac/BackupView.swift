import SwiftUI
import UniformTypeIdentifiers
import AlmanacCore
import Darwin

/// Create, share and restore whole-app backups.
///
/// Backups are `*.almanac-backup` files: one SQLite container holding the
/// live database and every laboratory document, written by `BackupService`.
/// Sharing encrypts the container with a passphrase the person chooses
/// (`BackupEncryption`, owner 2026-10-22) and wraps it in a `.zip` (BRD §6.18)
/// so any mail client, OS or archive tool accepts it. Import accepts the raw
/// container, an encrypted one, and either inside a `.zip`; an encrypted one
/// asks for its passphrase before anything is validated or adopted.
/// The list is read from the backups folder, not from `backup_manifest`,
/// because that table lives inside the database a restore replaces — files
/// created after the snapshot point would otherwise vanish from the list the
/// moment a restore completed.
@MainActor
struct BackupView: View {
    let db: Database

    @State private var bundles: [BackupBundleInfo] = []
    /// The bundle the passphrase sheet is encrypting for sharing.
    @State private var sharing: BackupBundleInfo?
    /// An imported file that turned out to be encrypted, held in its own
    /// temporary folder until its passphrase is given or the sheet is closed.
    @State private var lockedImport: URL?
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
                if let newest = bundles.first {
                    Button {
                        sharing = newest
                    } label: {
                        Label("Share latest backup", systemImage: "square.and.arrow.up")
                    }
                    .disabled(isWorking)
                    Text("A shared backup is encrypted with a passphrase you choose.")
                        .font(.caption).foregroundStyle(.secondary)
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
        .sheet(item: $sharing) { bundle in
            EncryptedShareSheet(bundle: bundle)
        }
        .sheet(item: lockedImportItem) { item in
            UnlockBackupSheet(file: item.url) { opened in
                try adopt(opened)
            }
        }
        .task { reload() }
    }

    private var lockedImportItem: Binding<LockedImport?> {
        Binding(
            get: { lockedImport.map { LockedImport(url: $0) } },
            // Closing the sheet, by Cancel, a swipe or a successful unlock,
            // deletes the held copy: an encrypted file left in temp is still
            // the person's records, just locked.
            set: { if $0 == nil { discardLockedImport() } }
        )
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
            removeUnencryptedZipTwins()
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
            try service.writeBundle(to: target.path, documentsRoot: documentsDirectory, note: nil)
            reload()
        } catch {
            self.error = String(describing: error)
        }
    }

    /// Earlier versions wrote an unencrypted `.zip` beside each new backup for
    /// sharing. Nothing reads them now, and an unencrypted copy is exactly what
    /// sharing no longer makes, so they go.
    private func removeUnencryptedZipTwins() {
        let entries = (try? fileManager.contentsOfDirectory(at: backupsDirectory, includingPropertiesForKeys: nil)) ?? []
        for url in entries where url.pathExtension.lowercased() == "zip" {
            try? fileManager.removeItem(at: url)
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
        defer { try? fileManager.removeItem(at: tmp) }
        do {
            try fileManager.createDirectory(at: tmp, withIntermediateDirectories: true)
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
            if BackupEncryption.isEncrypted(fileAt: bundleURL.path) {
                // Held outside `tmp`, which goes when this returns, until the
                // passphrase sheet opens it or is closed.
                let holding = fileManager.temporaryDirectory
                    .appendingPathComponent("AlmanacLockedImport-\(UUID().uuidString)", isDirectory: true)
                try fileManager.createDirectory(at: holding, withIntermediateDirectories: true)
                let held = holding.appendingPathComponent("locked.almanac-backup")
                try fileManager.moveItem(at: bundleURL, to: held)
                lockedImport = held
                return
            }
            try adopt(bundleURL)
        } catch {
            self.error = String(describing: error)
        }
    }

    /// Validates a plain container and moves it into the backups folder.
    /// Validate before adopting: a non-bundle (or a foreign zip that unzipped
    /// but still is not one) must not land in the folder.
    private func adopt(_ bundleURL: URL) throws {
        try fileManager.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        _ = try service.readBundleInfo(at: bundleURL.path)
        for suffix in ["-wal", "-shm"] { try? fileManager.removeItem(atPath: bundleURL.path + suffix) }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let target = backupsDirectory.appendingPathComponent("imported-\(stamp).almanac-backup")
        try fileManager.moveItem(at: bundleURL, to: target)
        reload()
    }

    private func discardLockedImport() {
        if let lockedImport { try? fileManager.removeItem(at: lockedImport.deletingLastPathComponent()) }
        lockedImport = nil
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

private struct LockedImport: Identifiable {
    let url: URL
    var id: URL { url }
}

/// Asks for a passphrase twice, then encrypts the bundle and zips it in a
/// temporary folder, and only then offers it to the share sheet. The folder
/// goes when the sheet closes; the passphrase is never written anywhere.
@MainActor
private struct EncryptedShareSheet: View {
    let bundle: BackupBundleInfo

    @Environment(\.dismiss) private var dismiss
    @State private var passphrase = ""
    @State private var confirmation = ""
    @State private var isEncrypting = false
    @State private var sharedFile: URL?
    @State private var work = ShareWork()
    @State private var error: String?

    private var canEncrypt: Bool {
        passphrase.count >= BackupEncryption.minimumPassphraseLength && confirmation == passphrase
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Locked while encrypting: the job seals with the passphrase
                    // it started with, so an edit now would show one passphrase
                    // beside a file made with another.
                    SecureField("Passphrase", text: $passphrase)
                        .disabled(isEncrypting)
                        .accessibilityIdentifier("backup-passphrase")
                    SecureField("Repeat passphrase", text: $confirmation)
                        .disabled(isEncrypting)
                        .accessibilityIdentifier("backup-passphrase-repeat")
                } footer: {
                    Text("Use at least 8 characters. Almanac does not keep the passphrase: without it, this backup cannot be restored.")
                }
                if !confirmation.isEmpty, confirmation != passphrase {
                    Text("The two passphrases do not match.")
                        .font(.caption).foregroundStyle(AlmanacPalette.warning)
                        .accessibilityIdentifier("backup-passphrase-mismatch")
                }
                Section {
                    if let sharedFile {
                        ShareLink(item: sharedFile) {
                            Label("Share encrypted backup", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityIdentifier("share-encrypted-backup")
                    } else {
                        Button {
                            encrypt()
                        } label: {
                            if isEncrypting { ProgressView() } else { Text("Encrypt") }
                        }
                        .disabled(!canEncrypt || isEncrypting)
                        .accessibilityIdentifier("encrypt-backup")
                    }
                }
                if let error {
                    Text(error).font(.caption).foregroundStyle(AlmanacPalette.warning)
                }
            }
            .navigationTitle("Encrypt backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            // A changed passphrase makes the file already built the wrong one.
            .onChange(of: passphrase) { _, _ in discardSharedFile() }
            .onChange(of: confirmation) { _, _ in discardSharedFile() }
        }
        // Leaving the sheet, by Done or a swipe, cancels any encryption still
        // running; the job removes what it made once it finishes.
        .onDisappear {
            work.cancel()
            discardSharedFile()
        }
    }

    private func encrypt() {
        guard canEncrypt else { return }
        isEncrypting = true
        error = nil
        let source = bundle.filePath
        let secret = passphrase
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AlmanacShare-\(UUID().uuidString)", isDirectory: true)
        // Recorded before the job starts, so leaving the sheet mid-way knows
        // which folder is the job's.
        work.directory = directory
        work.task = Task {
            do {
                // Key derivation is deliberately slow; it runs off the main
                // thread so the sheet keeps drawing its progress.
                let zip = try await Task.detached(priority: .userInitiated) { () throws -> String in
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let sealed = directory.appendingPathComponent((source as NSString).lastPathComponent)
                    try BackupEncryption.encrypt(fileAt: source, to: sealed.path, passphrase: secret)
                    defer { try? FileManager.default.removeItem(at: sealed) }
                    return try BackupZipper.zip(bundlePath: sealed.path)
                }.value
                if work.isCancelled {
                    // The sheet closed while this ran: nothing may be shared.
                    try? FileManager.default.removeItem(at: directory)
                } else {
                    sharedFile = URL(fileURLWithPath: zip)
                }
            } catch {
                try? FileManager.default.removeItem(at: directory)
                if !work.isCancelled { self.error = String(describing: error) }
            }
            isEncrypting = false
        }
    }

    private func discardSharedFile() {
        if let directory = work.directory { try? FileManager.default.removeItem(at: directory) }
        work.directory = nil
        sharedFile = nil
    }
}

/// The share sheet's running encryption, held by reference so the job can see
/// that the sheet has closed by the time it finishes. Only ever touched on the
/// main actor.
@MainActor
private final class ShareWork {
    var directory: URL?
    var task: Task<Void, Never>?
    private(set) var isCancelled = false

    /// Stops the job from publishing its file, and deletes the folder it has
    /// already made. A job still encrypting cleans up when it finishes.
    func cancel() {
        isCancelled = true
        task?.cancel()
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
    }
}

/// Asks for an encrypted import's passphrase, decrypts it beside the locked
/// copy, and hands the plain container to `onUnlocked`, which validates and
/// adopts it. A wrong passphrase leaves the sheet open to try again.
@MainActor
private struct UnlockBackupSheet: View {
    let file: URL
    let onUnlocked: (URL) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var passphrase = ""
    @State private var isUnlocking = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Passphrase", text: $passphrase)
                        .accessibilityIdentifier("unlock-backup-passphrase")
                } footer: {
                    Text("This backup is encrypted. Enter the passphrase it was shared with.")
                }
                if let error {
                    Text(error).font(.caption).foregroundStyle(AlmanacPalette.warning)
                }
                Section {
                    Button {
                        unlock()
                    } label: {
                        if isUnlocking { ProgressView() } else { Text("Unlock") }
                    }
                    .disabled(passphrase.isEmpty || isUnlocking)
                    .accessibilityIdentifier("unlock-backup")
                }
            }
            .navigationTitle("Encrypted backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func unlock() {
        isUnlocking = true
        error = nil
        let source = file.path
        let opened = file.deletingLastPathComponent().appendingPathComponent("opened.almanac-backup")
        let secret = passphrase
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try BackupEncryption.decrypt(fileAt: source, to: opened.path, passphrase: secret)
                }.value
                try onUnlocked(opened)
                dismiss()
            } catch {
                self.error = String(describing: error)
            }
            isUnlocking = false
        }
    }
}
