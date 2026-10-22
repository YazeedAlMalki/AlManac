import Foundation
import CryptoKit
import CommonCrypto
import Security
import AlmanacCore

/// Apple's primitives behind AlmanacCore's `BackupCipher`: the random bytes come
/// from the system generator, the key from PBKDF2-HMAC-SHA256 (CommonCrypto), and
/// the sealing from AES-256-GCM (CryptoKit). Nothing here is hand-written
/// cryptography; this file only connects the framework calls to the envelope
/// format and policy in `EncryptedBackup.swift`, which is tested on Linux with a
/// stand-in cipher.
///
/// This type lives in the app target, not the core, because CryptoKit and
/// CommonCrypto do not exist on Linux, where the core is built and tested.
///
/// **Not exercised by an automated test** in this repository: the envelope tests
/// use a stand-in, and the UI test shares a real backup but cannot read the file
/// back. A reviewer who knows CryptoKit should read this file once.
struct CryptoKitBackupCipher: BackupCipher {
    enum Failure: Error, CustomStringConvertible {
        case randomSource(OSStatus)
        case keyDerivation(Int32)
        case sealedTooShort

        var description: String {
            switch self {
            case .randomSource(let status): return "the system random source failed (\(status))"
            case .keyDerivation(let status): return "key derivation failed (\(status))"
            case .sealedTooShort: return "the sealed data is shorter than its tag"
            }
        }
    }

    func randomBytes(_ count: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else { throw Failure.randomSource(status) }
        return bytes
    }

    func deriveKey(passphrase: String, salt: [UInt8], iterations: Int) throws -> [UInt8] {
        let keyLength = 32
        var derived = [UInt8](repeating: 0, count: keyLength)
        let status = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            passphrase, passphrase.utf8.count,
            salt, salt.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
            UInt32(iterations),
            &derived, keyLength)
        guard status == Int32(kCCSuccess) else { throw Failure.keyDerivation(status) }
        return derived
    }

    func seal(_ plaintext: [UInt8], key: [UInt8], nonce: [UInt8], authenticating header: [UInt8]) throws -> [UInt8] {
        let box = try AES.GCM.seal(Data(plaintext),
                                   using: SymmetricKey(data: key),
                                   nonce: try AES.GCM.Nonce(data: nonce),
                                   authenticating: Data(header))
        return Array(box.ciphertext) + Array(box.tag)
    }

    func open(_ sealed: [UInt8], key: [UInt8], nonce: [UInt8], authenticating header: [UInt8]) throws -> [UInt8] {
        let tagLength = 16
        guard sealed.count >= tagLength else { throw Failure.sealedTooShort }
        let split = sealed.count - tagLength
        let box = try AES.GCM.SealedBox(nonce: try AES.GCM.Nonce(data: nonce),
                                        ciphertext: Data(sealed[..<split]),
                                        tag: Data(sealed[split...]))
        // Throws `CryptoKitError.authenticationFailure` for a wrong key or any altered byte.
        return Array(try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: Data(header)))
    }
}
