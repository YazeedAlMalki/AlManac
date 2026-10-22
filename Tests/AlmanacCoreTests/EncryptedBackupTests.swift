import Foundation
import Testing
@testable import AlmanacCore

/// A stand-in for the app's `CryptoKitBackupCipher`, so the **envelope** (header
/// layout, limits, what is authenticated, error reporting, the file round trip) is
/// tested on Linux, where CryptoKit does not exist.
///
/// It is deliberately NOT secure and must never be used outside tests: the key is a
/// simple mix of the inputs and the "cipher" is an XOR keystream with a keyed
/// checksum for a tag. What it does model faithfully is the contract: `open` throws
/// when the key, nonce, header or ciphertext differ from what `seal` saw.
struct StandInCipher: BackupCipher {
    struct Failure: Error {}

    func randomBytes(_ count: Int) throws -> [UInt8] {
        var generator = SystemRandomNumberGenerator()
        return (0 ..< count).map { _ in UInt8.random(in: 0...255, using: &generator) }
    }

    func deriveKey(passphrase: String, salt: [UInt8], iterations: Int) throws -> [UInt8] {
        var state: UInt64 = 1469598103934665603
        func mix(_ byte: UInt8) { state = (state ^ UInt64(byte)) &* 1099511628211 }
        Array(passphrase.utf8).forEach(mix)
        salt.forEach(mix)
        withUnsafeBytes(of: UInt64(iterations).bigEndian) { $0.forEach(mix) }
        return (0 ..< 32).map { index in
            mix(UInt8(index))
            return UInt8(truncatingIfNeeded: state >> UInt64((index % 8) * 8))
        }
    }

    private func keystream(key: [UInt8], nonce: [UInt8], count: Int) -> [UInt8] {
        (0 ..< count).map { i in key[i % key.count] ^ nonce[i % nonce.count] ^ UInt8(truncatingIfNeeded: i &* 31) }
    }

    private func tag(key: [UInt8], nonce: [UInt8], header: [UInt8], ciphertext: [UInt8]) -> [UInt8] {
        var state: UInt64 = 1469598103934665603
        for byte in key + nonce + header + ciphertext { state = (state ^ UInt64(byte)) &* 1099511628211 }
        return (0 ..< 16).map { index in
            state = (state ^ UInt64(index)) &* 1099511628211
            return UInt8(truncatingIfNeeded: state >> 24)
        }
    }

    func seal(_ plaintext: [UInt8], key: [UInt8], nonce: [UInt8], authenticating header: [UInt8]) throws -> [UInt8] {
        let stream = keystream(key: key, nonce: nonce, count: plaintext.count)
        let ciphertext = zip(plaintext, stream).map { $0 ^ $1 }
        return ciphertext + tag(key: key, nonce: nonce, header: header, ciphertext: ciphertext)
    }

    func open(_ sealed: [UInt8], key: [UInt8], nonce: [UInt8], authenticating header: [UInt8]) throws -> [UInt8] {
        guard sealed.count >= 16 else { throw Failure() }
        let ciphertext = Array(sealed.dropLast(16))
        guard Array(sealed.suffix(16)) == tag(key: key, nonce: nonce, header: header, ciphertext: ciphertext) else {
            throw Failure()
        }
        let stream = keystream(key: key, nonce: nonce, count: ciphertext.count)
        return zip(ciphertext, stream).map { $0 ^ $1 }
    }
}

@Suite("Encrypted backup envelope (P1-3)")
struct EncryptedBackupTests {
    private let cipher = StandInCipher()
    private let passphrase = "correct horse battery"
    // The real default (600,000) is for the real cipher; the stand-in is not slow.
    private let iterations = 2_000
    private let plaintext = Array("SQLite format 3\0 pretend this is a health record".utf8)

    private func sealed() throws -> [UInt8] {
        try EncryptedBackup.encrypt(plaintext, passphrase: passphrase, using: cipher, iterations: iterations)
    }

    @Test("A backup round-trips with the right passphrase")
    func roundTrip() throws {
        let file = try sealed()
        #expect(try EncryptedBackup.decrypt(file, passphrase: passphrase, using: cipher) == plaintext)
    }

    @Test("The envelope starts with its magic and does not contain the plaintext")
    func shapeOfTheFile() throws {
        let file = try sealed()
        #expect(EncryptedBackup.isEncrypted(file))
        #expect(!EncryptedBackup.isEncrypted(plaintext))
        #expect(!EncryptedBackup.isEncrypted([]))
        #expect(file.count == EncryptedBackup.magic.count + 3 + 4 + 1 + 16 + 1 + 12 + plaintext.count + 16)
        let needle = Array("health record".utf8)
        let contains = (0 ... file.count - needle.count).contains { Array(file[$0 ..< $0 + needle.count]) == needle }
        #expect(!contains, "plaintext appears in the encrypted file")
    }

    @Test("Encrypting the same backup twice never gives the same bytes")
    func freshSaltAndNonce() throws {
        #expect(try sealed() != sealed())
    }

    @Test("A wrong passphrase is reported, not returned as garbage")
    func wrongPassphrase() throws {
        let file = try sealed()
        #expect(throws: EncryptedBackupError.wrongPassphraseOrDamaged) {
            try EncryptedBackup.decrypt(file, passphrase: "not the passphrase", using: cipher)
        }
    }

    @Test("Altering any byte after the magic is detected")
    func tamperingIsDetected() throws {
        let file = try sealed()
        for index in EncryptedBackup.magic.count ..< file.count {
            var altered = file
            altered[index] ^= 0x01
            #expect(throws: (any Error).self, "byte \(index) was changed and nothing noticed") {
                try EncryptedBackup.decrypt(altered, passphrase: passphrase, using: cipher)
            }
        }
    }

    @Test("A lowered iteration count in the header is not silently accepted")
    func iterationCountIsAuthenticated() throws {
        var file = try sealed()
        let at = EncryptedBackup.magic.count + 3        // low byte of the big-endian count
        file[at + 3] ^= 0x01                             // 2,000 -> 2,001: still inside the limits
        #expect(throws: EncryptedBackupError.wrongPassphraseOrDamaged) {
            try EncryptedBackup.decrypt(file, passphrase: passphrase, using: cipher)
        }
    }

    @Test("Absurd iteration counts are refused before any key derivation")
    func iterationLimits() throws {
        for count in [0, 999, 10_000_001, Int(UInt32.max)] {
            var file = try sealed()
            let at = EncryptedBackup.magic.count + 3
            let n = UInt32(truncatingIfNeeded: count)
            file.replaceSubrange(at ..< at + 4, with: [UInt8(n >> 24), UInt8((n >> 16) & 0xFF), UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)])
            #expect(throws: EncryptedBackupError.unsupportedFormat) {
                try EncryptedBackup.decrypt(file, passphrase: passphrase, using: cipher)
            }
        }
        #expect(throws: EncryptedBackupError.unsupportedFormat) {
            try EncryptedBackup.encrypt(plaintext, passphrase: passphrase, using: cipher, iterations: 10_000_001)
        }
    }

    @Test("Truncated and foreign files are refused without trapping")
    func truncation() throws {
        let file = try sealed()
        for length in 0 ..< file.count where length != file.count {
            let cut = Array(file.prefix(length))
            if length < EncryptedBackup.magic.count {
                #expect(throws: EncryptedBackupError.notEncrypted) {
                    try EncryptedBackup.decrypt(cut, passphrase: passphrase, using: cipher)
                }
            } else {
                #expect(throws: (any Error).self, "a file cut to \(length) bytes decrypted") {
                    try EncryptedBackup.decrypt(cut, passphrase: passphrase, using: cipher)
                }
            }
        }
        #expect(throws: EncryptedBackupError.notEncrypted) {
            try EncryptedBackup.decrypt(plaintext, passphrase: passphrase, using: cipher)
        }
    }

    @Test("Another format version is reported as unsupported")
    func futureVersion() throws {
        var file = try sealed()
        file[EncryptedBackup.magic.count] = 2
        #expect(throws: EncryptedBackupError.unsupportedFormat) {
            try EncryptedBackup.decrypt(file, passphrase: passphrase, using: cipher)
        }
    }

    @Test("A short passphrase is refused, a long one is not")
    func passphraseLength() {
        #expect(!EncryptedBackup.isAcceptable(passphrase: "1234567"))
        #expect(EncryptedBackup.isAcceptable(passphrase: "12345678"))
        #expect(throws: EncryptedBackupError.passphraseTooShort(minimum: 8)) {
            try EncryptedBackup.encrypt(plaintext, passphrase: "short", using: cipher, iterations: iterations)
        }
    }

    @Test("The same passphrase typed in a different Unicode form still opens the file")
    func unicodeNormalization() throws {
        let composed = "pässword-ünïcode"
        let decomposed = composed.decomposedStringWithCanonicalMapping
        // Swift compares Strings by canonical equivalence, so compare the bytes.
        #expect(Array(composed.utf8) != Array(decomposed.utf8))
        let file = try EncryptedBackup.encrypt(plaintext, passphrase: composed, using: cipher, iterations: iterations)
        #expect(try EncryptedBackup.decrypt(file, passphrase: decomposed, using: cipher) == plaintext)
    }

    @Test("A real backup survives encrypt → decrypt → restore, and the shared file holds no SQLite header")
    func realBundleRoundTrip() throws {
        let dir = NSTemporaryDirectory() + "almanac-enc-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let source = try Database(path: dir + "/src.sqlite")
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(source)
        try SyncAnchorStore(db: source).save(domain: "hrv", token: [4, 2])
        let bundle = dir + "/snapshot.almanac-backup"
        try BackupService(db: source).writeBundle(to: bundle, documentsRoot: nil, note: nil)

        let shared = dir + "/snapshot.almanac-backup.enc"
        try EncryptedBackup.encryptFile(at: bundle, to: shared, passphrase: passphrase, using: cipher, iterations: iterations)
        #expect(EncryptedBackup.isEncrypted(fileAt: shared))
        let head = [UInt8](try Data(contentsOf: URL(fileURLWithPath: shared)).prefix(16))
        #expect(head != Array("SQLite format 3\0".utf8), "the shared file starts like a plain SQLite database")

        let opened = dir + "/opened.almanac-backup"
        try EncryptedBackup.decryptFile(at: shared, to: opened, passphrase: passphrase, using: cipher)
        #expect(!EncryptedBackup.isEncrypted(fileAt: opened))

        let target = try Database(path: dir + "/tgt.sqlite")
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(target)
        try BackupService(db: target).restoreBundle(at: opened)
        #expect(try SyncAnchorStore(db: target).load("hrv")?.token == [4, 2])
    }

    @Test("Decrypting with the wrong passphrase writes nothing usable")
    func wrongPassphraseOnAFile() throws {
        let dir = NSTemporaryDirectory() + "almanac-enc-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let plain = dir + "/p.bin", shared = dir + "/p.enc", out = dir + "/out.bin"
        try Data(plaintext).write(to: URL(fileURLWithPath: plain))
        try EncryptedBackup.encryptFile(at: plain, to: shared, passphrase: passphrase, using: cipher, iterations: iterations)
        #expect(throws: EncryptedBackupError.wrongPassphraseOrDamaged) {
            try EncryptedBackup.decryptFile(at: shared, to: out, passphrase: "wrong passphrase", using: cipher)
        }
        #expect(!FileManager.default.fileExists(atPath: out))
    }
}
