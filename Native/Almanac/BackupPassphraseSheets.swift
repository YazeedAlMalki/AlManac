import SwiftUI
import AlmanacCore

/// An encrypted backup picked from Files, copied into a private staging folder
/// while access to the picked file was still open, and waiting for its passphrase.
struct EncryptedImport: Identifiable {
    let file: URL
    let staging: URL
    var id: URL { file }
}

/// Where a shared backup's encrypted copy lives while the share sheet is open:
/// the temporary directory, never the backups folder, so it is not kept after
/// sharing and is not part of a device backup.
enum BackupShareFiles {
    static let prefix = "AlmanacShare-"

    static func newDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(prefix + UUID().uuidString, isDirectory: true)
    }

    /// Removes every encrypted copy this app has left in the temporary directory.
    static func removeAll() {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(at: fm.temporaryDirectory, includingPropertiesForKeys: nil)) ?? []
        for url in entries where url.lastPathComponent.hasPrefix(prefix) { try? fm.removeItem(at: url) }
    }
}

/// Asks for a passphrase, encrypts a **copy** of the chosen backup with it, and
/// only then offers that copy for sharing. The plaintext container never leaves
/// the app (audit finding S-02).
@MainActor
struct BackupShareSheet: View {
    let bundle: BackupBundleInfo

    @Environment(\.dismiss) private var dismiss
    @State private var passphrase = ""
    @State private var confirmation = ""
    @State private var isEncrypting = false
    @State private var directory: URL?
    @State private var sharedFile: URL?
    @State private var error: String?

    private var lengthOK: Bool { EncryptedBackup.isAcceptable(passphrase: passphrase) }
    private var mismatch: Bool { !confirmation.isEmpty && passphrase != confirmation }
    private var canEncrypt: Bool { lengthOK && passphrase == confirmation && !isEncrypting }

    var body: some View {
        NavigationStack {
            Form {
                if let sharedFile {
                    Section {
                        ShareLink(item: sharedFile) {
                            Label("Share encrypted backup", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityIdentifier("backup-share-encrypted")
                    } footer: {
                        Text("Keep the passphrase somewhere safe. Without it this file cannot be opened.")
                    }
                } else {
                    Section {
                        SecureField("Passphrase", text: $passphrase)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("backup-passphrase")
                        SecureField("Repeat passphrase", text: $confirmation)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("backup-passphrase-repeat")
                    } header: {
                        Text("Choose a passphrase")
                    } footer: {
                        Text("Anyone who has this file and the passphrase can read your health records. Almanac cannot recover a lost passphrase.")
                    }
                    if !passphrase.isEmpty && !lengthOK {
                        Text("Use at least \(EncryptedBackup.minimumPassphraseLength) characters.")
                            .font(.caption).foregroundStyle(AlmanacPalette.warning)
                    }
                    if mismatch {
                        Text("The passphrases do not match.")
                            .font(.caption).foregroundStyle(AlmanacPalette.warning)
                    }
                    Section {
                        Button {
                            encrypt()
                        } label: {
                            if isEncrypting { ProgressView() } else { Text("Encrypt") }
                        }
                        .disabled(!canEncrypt)
                        .accessibilityIdentifier("backup-encrypt")
                    }
                }
                if let error {
                    Text(error).font(.caption).foregroundStyle(AlmanacPalette.warning)
                }
            }
            .navigationTitle("Share backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .onDisappear { if let directory { try? FileManager.default.removeItem(at: directory) } }
    }

    private func encrypt() {
        isEncrypting = true
        error = nil
        let source = bundle.filePath
        let secret = passphrase
        let folder = BackupShareFiles.newDirectory()
        let destination = folder.appendingPathComponent((source as NSString).lastPathComponent + ".enc")
        Task {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                directory = folder
                // Key derivation is deliberately slow (600,000 rounds); keep it off the main actor.
                try await Task.detached(priority: .userInitiated) {
                    try EncryptedBackup.encryptFile(at: source, to: destination.path,
                                                    passphrase: secret, using: CryptoKitBackupCipher())
                }.value
                sharedFile = destination
            } catch {
                try? FileManager.default.removeItem(at: folder)
                directory = nil
                self.error = String(describing: error)
            }
            isEncrypting = false
            // The secret is not needed again; do not leave it in view state.
            passphrase = ""
            confirmation = ""
        }
    }
}

/// Asks for the passphrase of an encrypted backup picked for import.
/// `attempt` returns an error message to show here, or `nil` once the backup has
/// been decrypted, validated and adopted.
@MainActor
struct BackupImportPassphraseSheet: View {
    let attempt: (String) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var passphrase = ""
    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Passphrase", text: $passphrase)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("backup-import-passphrase")
                } header: {
                    Text("This backup is encrypted")
                } footer: {
                    Text("Enter the passphrase you chose when you shared it.")
                }
                if let message {
                    Text(message).font(.caption).foregroundStyle(AlmanacPalette.warning)
                }
                Section {
                    Button {
                        submit()
                    } label: {
                        if isWorking { ProgressView() } else { Text("Import") }
                    }
                    .disabled(passphrase.isEmpty || isWorking)
                    .accessibilityIdentifier("backup-import-submit")
                }
            }
            .navigationTitle("Encrypted backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func submit() {
        isWorking = true
        message = nil
        let secret = passphrase
        Task {
            let result = await attempt(secret)
            isWorking = false
            if let result {
                message = result
            } else {
                passphrase = ""
                dismiss()
            }
        }
    }
}
