import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(CommonCrypto)
import CommonCrypto
#endif

/// Passphrase encryption for a backup that leaves the phone (owner,
/// 2026-10-22; BRD §6.18/§8 "export encryption").
///
/// **What is encrypted, and what is not.** The copy that is shared — the
/// `.zip` a person mails, AirDrops or saves to Files — holds an encrypted
/// container, and nothing about it can be read without the passphrase. The
/// containers in the app's own backups folder stay as they are: they sit in
/// the app's sandbox under iOS file protection, beside the live database,
/// which is no more encrypted than they are. A key for them would have to live
/// on the same phone, and protect nothing the phone's lock does not already.
///
/// **The passphrase is never stored.** Not in the database, not in the
/// Keychain, not in the file. Forgetting it loses that file, and the screen
/// says so before anything is encrypted.
///
/// **Format, version 1.** One file, so the zip wrapper and the import path see
/// a single entry exactly as before:
///
/// ```
/// offset  size  field
///      0     8  magic "ALMANAC\0"
///      8     1  format version (1)
///      9     1  key derivation (1 = PBKDF2-HMAC-SHA256)
///     10     4  iterations, big-endian
///     14    16  salt
///     30    12  nonce
///     42     n  ciphertext of the whole `.almanac-backup` container
///   42+n    16  Poly1305 tag
/// ```
///
/// Sealed with ChaCha20-Poly1305 (RFC 8439), with the 42-byte header as
/// associated data, so an edited iteration count or salt fails the tag rather
/// than decrypting to something else. The key is PBKDF2-HMAC-SHA256 over the
/// passphrase's UTF-8 in Unicode canonical composition, so an Arabic
/// passphrase typed on a different keyboard still matches.
public enum BackupEncryption {
    static let magic: [UInt8] = Array("ALMANAC".utf8) + [0]
    static let formatVersion: UInt8 = 1
    static let pbkdf2SHA256: UInt8 = 1
    static let headerLength = 42
    static let tagLength = 16

    /// OWASP's 2023 floor for PBKDF2-HMAC-SHA256.
    public static let defaultIterations = 600_000
    /// A file asking for more is refused before any work: an iteration count
    /// read from a file is a number a stranger chose.
    static let maximumIterations = 10_000_000
    public static let minimumPassphraseLength = 8

    public enum EncryptionError: Error, Equatable, Sendable, CustomStringConvertible {
        case passphraseTooShort(minimum: Int)
        case wrongPassphraseOrDamaged
        case unsupportedFormat
        case notEncrypted

        public var description: String {
            switch self {
            case .passphraseTooShort(let minimum):
                return localized("The passphrase needs at least %@ characters.", String(minimum))
            case .wrongPassphraseOrDamaged:
                return localized("The passphrase is wrong, or the file was changed after it was encrypted.")
            case .unsupportedFormat:
                return localized("This backup was encrypted by a newer version of Almanac.")
            case .notEncrypted:
                return localized("This backup is not encrypted.")
            }
        }
    }

    /// Whether the file starts with this format's magic. Reads eight bytes,
    /// so it is cheap enough to ask of anything a person imports.
    public static func isEncrypted(fileAt path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: magic.count)) ?? Data()
        return [UInt8](head) == magic
    }

    /// Encrypts the file at `source` into `destination`, replacing it.
    public static func encrypt(fileAt source: String, to destination: String, passphrase: String,
                               iterations: Int = defaultIterations) throws {
        guard passphrase.count >= minimumPassphraseLength else {
            throw EncryptionError.passphraseTooShort(minimum: minimumPassphraseLength)
        }
        precondition((1...maximumIterations).contains(iterations), "iterations out of range")
        let plaintext = [UInt8](try Data(contentsOf: URL(fileURLWithPath: source)))
        let salt = randomBytes(16)
        let nonce = randomBytes(12)
        var header = magic
        header.append(formatVersion)
        header.append(pbkdf2SHA256)
        let count = UInt32(iterations)
        header += [UInt8(count >> 24), UInt8((count >> 16) & 0xff), UInt8((count >> 8) & 0xff), UInt8(count & 0xff)]
        header += salt
        header += nonce
        let key = deriveKey(passphrase: passphrase, salt: salt, iterations: iterations)
        let sealed = try seal(plaintext, key: key, nonce: nonce, aad: header)
        try Data(header + sealed.ciphertext + sealed.tag)
            .write(to: URL(fileURLWithPath: destination), options: .atomic)
    }

    /// Decrypts the file at `source` into `destination`, replacing it. Nothing
    /// is written unless the passphrase opens the file and its tag matches.
    public static func decrypt(fileAt source: String, to destination: String, passphrase: String) throws {
        let bytes = [UInt8](try Data(contentsOf: URL(fileURLWithPath: source)))
        guard bytes.count >= magic.count, Array(bytes[0..<magic.count]) == magic else {
            throw EncryptionError.notEncrypted
        }
        guard bytes.count >= headerLength + tagLength else { throw EncryptionError.wrongPassphraseOrDamaged }
        guard bytes[8] == formatVersion, bytes[9] == pbkdf2SHA256 else { throw EncryptionError.unsupportedFormat }
        let iterations = Int(UInt32(bytes[10]) << 24 | UInt32(bytes[11]) << 16
                             | UInt32(bytes[12]) << 8 | UInt32(bytes[13]))
        guard (1...maximumIterations).contains(iterations) else { throw EncryptionError.wrongPassphraseOrDamaged }
        let header = Array(bytes[0..<headerLength])
        let salt = Array(bytes[14..<30])
        let nonce = Array(bytes[30..<headerLength])
        let ciphertext = Array(bytes[headerLength..<(bytes.count - tagLength)])
        let tag = Array(bytes[(bytes.count - tagLength)...])
        let key = deriveKey(passphrase: passphrase, salt: salt, iterations: iterations)
        guard let plaintext = open(ciphertext: ciphertext, tag: tag, key: key, nonce: nonce, aad: header) else {
            throw EncryptionError.wrongPassphraseOrDamaged
        }
        try Data(plaintext).write(to: URL(fileURLWithPath: destination), options: .atomic)
    }

    // MARK: - Primitives

    static func deriveKey(passphrase: String, salt: [UInt8], iterations: Int) -> [UInt8] {
        let password = Array(passphrase.precomposedStringWithCanonicalMapping.utf8)
        #if canImport(CommonCrypto)
        var derived = [UInt8](repeating: 0, count: 32)
        let status = password.withUnsafeBytes { passwordBytes in
            salt.withUnsafeBufferPointer { saltBytes in
                derived.withUnsafeMutableBufferPointer { out in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                         passwordBytes.baseAddress?.assumingMemoryBound(to: CChar.self),
                                         passwordBytes.count,
                                         saltBytes.baseAddress, saltBytes.count,
                                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                                         UInt32(iterations),
                                         out.baseAddress, out.count)
                }
            }
        }
        if status == Int32(kCCSuccess) { return derived }
        #endif
        return PortableCrypto.pbkdf2SHA256(password: password, salt: salt, iterations: iterations, keyLength: 32)
    }

    static func seal(_ plaintext: [UInt8], key: [UInt8], nonce: [UInt8],
                     aad: [UInt8]) throws -> (ciphertext: [UInt8], tag: [UInt8]) {
        #if canImport(CryptoKit)
        let box = try ChaChaPoly.seal(plaintext, using: SymmetricKey(data: key),
                                      nonce: try ChaChaPoly.Nonce(data: nonce), authenticating: aad)
        return ([UInt8](box.ciphertext), [UInt8](box.tag))
        #else
        return PortableCrypto.seal(plaintext, key: key, nonce: nonce, aad: aad)
        #endif
    }

    static func open(ciphertext: [UInt8], tag: [UInt8], key: [UInt8], nonce: [UInt8],
                     aad: [UInt8]) -> [UInt8]? {
        #if canImport(CryptoKit)
        guard let box = try? ChaChaPoly.SealedBox(nonce: ChaChaPoly.Nonce(data: nonce),
                                                  ciphertext: ciphertext, tag: tag),
              let plaintext = try? ChaChaPoly.open(box, using: SymmetricKey(data: key), authenticating: aad)
        else { return nil }
        return [UInt8](plaintext)
        #else
        return PortableCrypto.open(ciphertext: ciphertext, tag: tag, key: key, nonce: nonce, aad: aad)
        #endif
    }

    private static func randomBytes(_ count: Int) -> [UInt8] {
        var generator = SystemRandomNumberGenerator()
        return (0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
    }
}
