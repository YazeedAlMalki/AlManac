import Foundation

/// Passphrase-encrypted backups (audit finding S-02 / remediation P1-3).
///
/// A backup that leaves the app is wrapped in this envelope, so the plaintext
/// `.almanac-backup` container (the whole health record) never travels in clear.
/// Backups that stay on the device are not wrapped; see `BackupView`.
///
/// ## What this file is, and is not
///
/// This is the **format and the policy**: header layout, parameter limits,
/// passphrase rules, what is authenticated, which errors are reported. It performs
/// no cryptography itself. The primitives sit behind `BackupCipher`, and the app
/// supplies Apple's (`CryptoKitBackupCipher`: AES-256-GCM, PBKDF2-HMAC-SHA256,
/// the system random generator). A hand-written cipher would be the wrong place to
/// save a dependency, and AlmanacCore must still build on Linux.
///
/// ## Layout (big-endian)
///
/// ```
/// magic "ALMBKENC"        8 bytes
/// format version          1 byte   (1)
/// cipher id               1 byte   (1 = AES-256-GCM)
/// KDF id                  1 byte   (1 = PBKDF2-HMAC-SHA256)
/// KDF iterations          4 bytes  (1,000 ... 10,000,000)
/// salt length, salt       1 + 16 bytes
/// nonce length, nonce     1 + 12 bytes
/// ciphertext || tag       n + 16 bytes
/// ```
///
/// The whole header is passed to the cipher as associated data, so changing any
/// parameter (a lower iteration count, a different salt) fails authentication
/// instead of silently weakening or redirecting the decryption. Salt and nonce are
/// fresh random values for every file, so the same backup encrypted twice never
/// produces the same bytes under one key.
///
/// ## Limits worth knowing
///
/// - Security rests on the passphrase. Eight characters is the floor enforced
///   here; nothing stops someone choosing a weak one above it.
/// - There is no recovery. A forgotten passphrase means the file cannot be read.
/// - The whole file is held in memory, as the rest of the backup code already does.
public protocol BackupCipher: Sendable {
    /// `count` bytes from a cryptographically secure source.
    func randomBytes(_ count: Int) throws -> [UInt8]
    /// A 32-byte key derived from the passphrase.
    func deriveKey(passphrase: String, salt: [UInt8], iterations: Int) throws -> [UInt8]
    /// Authenticated encryption. Returns the ciphertext followed by a 16-byte tag.
    func seal(_ plaintext: [UInt8], key: [UInt8], nonce: [UInt8], authenticating header: [UInt8]) throws -> [UInt8]
    /// The inverse of `seal`. **Must throw** when authentication fails.
    func open(_ sealed: [UInt8], key: [UInt8], nonce: [UInt8], authenticating header: [UInt8]) throws -> [UInt8]
}

public enum EncryptedBackupError: Error, Equatable, CustomStringConvertible, Sendable {
    /// The file does not start with the envelope's magic bytes.
    case notEncrypted
    /// An envelope this version cannot read: a newer format, other parameters, damage.
    case unsupportedFormat
    case passphraseTooShort(minimum: Int)
    /// Authentication failed. A wrong passphrase and a damaged or altered file are
    /// deliberately not told apart: the cipher cannot tell them apart either, and
    /// pretending otherwise would be a guess.
    case wrongPassphraseOrDamaged
    /// The cipher itself failed (for example no secure random source).
    case cipherFailed(String)

    public var description: String {
        switch self {
        case .notEncrypted:
            return localized("This file is not an encrypted Almanac backup.")
        case .unsupportedFormat:
            return localized("This encrypted backup uses a format this version of Almanac cannot read.")
        case .passphraseTooShort(let minimum):
            return localized("Use a passphrase of at least %@ characters.", String(minimum))
        case .wrongPassphraseOrDamaged:
            return localized("The passphrase is wrong, or the backup file is damaged.")
        case .cipherFailed(let detail):
            return localized("Encryption failed: %@", detail)
        }
    }
}

public enum EncryptedBackup {
    public static let minimumPassphraseLength = 8
    /// OWASP's 2023 floor for PBKDF2-HMAC-SHA256 is 600,000.
    public static let defaultIterations = 600_000

    static let magic: [UInt8] = Array("ALMBKENC".utf8)
    static let formatVersion: UInt8 = 1
    static let cipherAES256GCM: UInt8 = 1
    static let kdfPBKDF2SHA256: UInt8 = 1
    static let saltLength = 16
    static let nonceLength = 12
    static let tagLength = 16
    static let keyLength = 32
    /// A hostile file must not be able to demand hours of key derivation.
    static let iterationRange = 1_000...10_000_000

    // MARK: Detection

    public static func isEncrypted(_ leadingBytes: [UInt8]) -> Bool {
        leadingBytes.count >= magic.count && Array(leadingBytes.prefix(magic.count)) == magic
    }

    /// Whether the file at `path` starts with the envelope's magic bytes. Reads
    /// only those bytes. `false` for a missing or unreadable file.
    public static func isEncrypted(fileAt path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: magic.count) else { return false }
        return isEncrypted([UInt8](head))
    }

    // MARK: Passphrase

    /// NFKC, so the same passphrase typed on a different keyboard or after an OS
    /// text-normalisation change still derives the same key.
    static func normalized(_ passphrase: String) -> String {
        passphrase.precomposedStringWithCompatibilityMapping
    }

    /// Whether `passphrase` meets the length rule, for a form to check as the
    /// person types.
    public static func isAcceptable(passphrase: String) -> Bool {
        normalized(passphrase).count >= minimumPassphraseLength
    }

    // MARK: Encrypt / decrypt

    public static func encrypt(_ plaintext: [UInt8], passphrase: String, using cipher: any BackupCipher,
                               iterations: Int = defaultIterations) throws -> [UInt8] {
        let secret = normalized(passphrase)
        guard secret.count >= minimumPassphraseLength else {
            throw EncryptedBackupError.passphraseTooShort(minimum: minimumPassphraseLength)
        }
        guard iterationRange.contains(iterations) else { throw EncryptedBackupError.unsupportedFormat }
        do {
            let salt = try cipher.randomBytes(saltLength)
            let nonce = try cipher.randomBytes(nonceLength)
            guard salt.count == saltLength, nonce.count == nonceLength else {
                throw EncryptedBackupError.cipherFailed("random source returned the wrong length")
            }
            let head = header(iterations: iterations, salt: salt, nonce: nonce)
            let key = try cipher.deriveKey(passphrase: secret, salt: salt, iterations: iterations)
            guard key.count == keyLength else {
                throw EncryptedBackupError.cipherFailed("derived key has the wrong length")
            }
            let sealed = try cipher.seal(plaintext, key: key, nonce: nonce, authenticating: head)
            guard sealed.count == plaintext.count + tagLength else {
                throw EncryptedBackupError.cipherFailed("sealed output has the wrong length")
            }
            return head + sealed
        } catch let error as EncryptedBackupError {
            throw error
        } catch {
            throw EncryptedBackupError.cipherFailed(String(describing: error))
        }
    }

    public static func decrypt(_ file: [UInt8], passphrase: String, using cipher: any BackupCipher) throws -> [UInt8] {
        let parsed = try parseHeader(file)
        let key: [UInt8]
        do {
            key = try cipher.deriveKey(passphrase: normalized(passphrase), salt: parsed.salt,
                                       iterations: parsed.iterations)
        } catch {
            throw EncryptedBackupError.cipherFailed(String(describing: error))
        }
        guard key.count == keyLength else { throw EncryptedBackupError.cipherFailed("derived key has the wrong length") }
        let head = Array(file[0..<parsed.length])
        let sealed = Array(file[parsed.length...])
        do {
            return try cipher.open(sealed, key: key, nonce: parsed.nonce, authenticating: head)
        } catch {
            throw EncryptedBackupError.wrongPassphraseOrDamaged
        }
    }

    /// Encrypts the file at `source` into a new file at `destination` (replaced if
    /// it exists). The destination is written atomically.
    public static func encryptFile(at source: String, to destination: String, passphrase: String,
                                   using cipher: any BackupCipher,
                                   iterations: Int = defaultIterations) throws {
        let plain = [UInt8](try Data(contentsOf: URL(fileURLWithPath: source)))
        let sealed = try encrypt(plain, passphrase: passphrase, using: cipher, iterations: iterations)
        try Data(sealed).write(to: URL(fileURLWithPath: destination), options: .atomic)
    }

    public static func decryptFile(at source: String, to destination: String, passphrase: String,
                                   using cipher: any BackupCipher) throws {
        let file = [UInt8](try Data(contentsOf: URL(fileURLWithPath: source)))
        let plain = try decrypt(file, passphrase: passphrase, using: cipher)
        try Data(plain).write(to: URL(fileURLWithPath: destination), options: .atomic)
    }

    // MARK: Header

    struct ParsedHeader: Equatable {
        let iterations: Int
        let salt: [UInt8]
        let nonce: [UInt8]
        /// Bytes the header occupies; the sealed payload starts here.
        let length: Int
    }

    static func header(iterations: Int, salt: [UInt8], nonce: [UInt8]) -> [UInt8] {
        let n = UInt32(iterations)
        var bytes = magic
        bytes += [formatVersion, cipherAES256GCM, kdfPBKDF2SHA256]
        bytes += [UInt8((n >> 24) & 0xFF), UInt8((n >> 16) & 0xFF), UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)]
        bytes.append(UInt8(salt.count))
        bytes += salt
        bytes.append(UInt8(nonce.count))
        bytes += nonce
        return bytes
    }

    /// Reads and checks the header. Every read is preceded by a length check, so a
    /// truncated or hostile file is refused rather than trapped on.
    static func parseHeader(_ file: [UInt8]) throws -> ParsedHeader {
        guard isEncrypted(file) else { throw EncryptedBackupError.notEncrypted }
        var i = magic.count
        // version, cipher, kdf, 4 bytes of iterations, salt length
        guard file.count >= i + 3 + 4 + 1 else { throw EncryptedBackupError.unsupportedFormat }
        guard file[i] == formatVersion, file[i + 1] == cipherAES256GCM, file[i + 2] == kdfPBKDF2SHA256 else {
            throw EncryptedBackupError.unsupportedFormat
        }
        i += 3
        let iterations = (Int(file[i]) << 24) | (Int(file[i + 1]) << 16) | (Int(file[i + 2]) << 8) | Int(file[i + 3])
        i += 4
        guard iterationRange.contains(iterations) else { throw EncryptedBackupError.unsupportedFormat }
        let saltCount = Int(file[i])
        i += 1
        // salt, then the nonce length byte
        guard saltCount == saltLength, file.count >= i + saltCount + 1 else {
            throw EncryptedBackupError.unsupportedFormat
        }
        let salt = Array(file[i ..< i + saltCount])
        i += saltCount
        let nonceCount = Int(file[i])
        i += 1
        // nonce, then at least an (empty) ciphertext and its tag
        guard nonceCount == nonceLength, file.count >= i + nonceCount + tagLength else {
            throw EncryptedBackupError.unsupportedFormat
        }
        let nonce = Array(file[i ..< i + nonceCount])
        i += nonceCount
        return ParsedHeader(iterations: iterations, salt: salt, nonce: nonce, length: i)
    }
}
