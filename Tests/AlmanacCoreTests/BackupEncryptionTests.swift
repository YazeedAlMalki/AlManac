import XCTest
@testable import AlmanacCore

/// Passphrase encryption of a shared backup. The primitives are pinned to their
/// RFCs' own vectors, which is what lets a file sealed by CryptoKit on a phone
/// open with the portable code here, and the reverse; the envelope's tests pin
/// what it refuses. Iterations are kept low so the portable PBKDF2 stays fast;
/// the count is read from each file, so nothing else changes with it.
final class BackupEncryptionTests: XCTestCase {

    private func hex(_ text: String) -> [UInt8] {
        var bytes: [UInt8] = []
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            bytes.append(UInt8(text[index..<next], radix: 16)!)
            index = next
        }
        return bytes
    }

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    private func tempDir() throws -> String {
        let dir = NSTemporaryDirectory() + "almanac-encryption-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Primitives against their RFCs

    /// RFC 8439 §2.8.2.
    func testChaCha20Poly1305MatchesRFC8439() {
        let key = Array(UInt8(0x80)...UInt8(0x9f))
        let nonce = hex("070000004041424344454647")
        let aad = hex("50515253c0c1c2c3c4c5c6c7")
        let plaintext = Array("Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.".utf8)
        let expectedCiphertext = "d31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d63dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b3692ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc3ff4def08e4b7a9de576d26586cec64b6116"

        let portable = PortableCrypto.seal(plaintext, key: key, nonce: nonce, aad: aad)
        XCTAssertEqual(hex(portable.ciphertext), expectedCiphertext)
        XCTAssertEqual(hex(portable.tag), "1ae10b594f09e26a7e902ecbd0600691")

        // The platform's seal (CryptoKit where it exists) writes the same bytes.
        let platform = try? BackupEncryption.seal(plaintext, key: key, nonce: nonce, aad: aad)
        XCTAssertEqual(platform.map { hex($0.ciphertext) }, expectedCiphertext)
        XCTAssertEqual(platform.map { hex($0.tag) }, "1ae10b594f09e26a7e902ecbd0600691")

        XCTAssertEqual(PortableCrypto.open(ciphertext: portable.ciphertext, tag: portable.tag,
                                           key: key, nonce: nonce, aad: aad), plaintext)
        XCTAssertEqual(BackupEncryption.open(ciphertext: portable.ciphertext, tag: portable.tag,
                                             key: key, nonce: nonce, aad: aad), plaintext)
    }

    func testEmptyMessageAndAADStillCarryATag() {
        let sealed = PortableCrypto.seal([], key: [UInt8](repeating: 0, count: 32),
                                         nonce: [UInt8](repeating: 0, count: 12), aad: [])
        XCTAssertEqual(sealed.ciphertext, [])
        XCTAssertEqual(hex(sealed.tag), "4eb972c9a8fb3a1b382bb4d36f5ffad1")
    }

    /// RFC 8439 §2.5.2.
    func testPoly1305MatchesRFC8439() {
        let key = hex("85d6be7857556d337f4452fe42d506a80103808afb0db2fd4abff6af4149f51b")
        let tag = PortableCrypto.poly1305(key: key, message: Array("Cryptographic Forum Research Group".utf8))
        XCTAssertEqual(hex(tag), "a8061dc1305136c6c22b8baf0c0127a9")
    }

    /// RFC 4231 test case 6 (a key longer than a block) and a plain one.
    func testHMACSHA256() {
        XCTAssertEqual(hex(PortableCrypto.HMACSHA256(key: Array("key".utf8))
                            .mac(Array("The quick brown fox jumps over the lazy dog".utf8))),
                       "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8")
        XCTAssertEqual(hex(PortableCrypto.HMACSHA256(key: [UInt8](repeating: 0xaa, count: 131))
                            .mac(Array("Test Using Larger Than Block-Size Key - Hash Key First".utf8))),
                       "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54")
    }

    /// RFC 7914 §11 and the widely published 4,096-iteration vector.
    func testPBKDF2SHA256() {
        XCTAssertEqual(hex(PortableCrypto.pbkdf2SHA256(password: Array("passwd".utf8), salt: Array("salt".utf8),
                                                       iterations: 1, keyLength: 64)),
                       "55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc49ca9cccf179b645991664b39d77ef317c71b845b1e30bd509112041d3a19783")
        XCTAssertEqual(hex(PortableCrypto.pbkdf2SHA256(password: Array("password".utf8), salt: Array("salt".utf8),
                                                       iterations: 4096, keyLength: 32)),
                       "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a")
        // The platform's derivation (CommonCrypto where it exists) agrees.
        XCTAssertEqual(hex(BackupEncryption.deriveKey(passphrase: "password", salt: Array("salt".utf8),
                                                      iterations: 4096)),
                       "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a")
    }

    // MARK: - The envelope

    private let passphrase = "correct horse battery"

    private func writeSample(_ dir: String, bytes: [UInt8] = Array(0..<200).map { UInt8($0) }) throws -> String {
        let path = dir + "/plain.almanac-backup"
        try Data(bytes).write(to: URL(fileURLWithPath: path))
        return path
    }

    func testRoundTripRestoresTheExactBytes() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let plain = try writeSample(dir)
        let sealed = dir + "/sealed.almanac-backup"
        let opened = dir + "/opened.almanac-backup"

        try BackupEncryption.encrypt(fileAt: plain, to: sealed, passphrase: passphrase, iterations: 1_000)
        XCTAssertTrue(BackupEncryption.isEncrypted(fileAt: sealed))
        XCTAssertFalse(BackupEncryption.isEncrypted(fileAt: plain))
        let sealedBytes = [UInt8](try Data(contentsOf: URL(fileURLWithPath: sealed)))
        XCTAssertEqual(sealedBytes.count, 200 + BackupEncryption.headerLength + BackupEncryption.tagLength)
        XCTAssertNil(sealedBytes.firstRange(of: Array(0..<16).map { UInt8($0) }),
                     "the plaintext must not appear in the encrypted file")

        try BackupEncryption.decrypt(fileAt: sealed, to: opened, passphrase: passphrase)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: opened)),
                       try Data(contentsOf: URL(fileURLWithPath: plain)))
    }

    func testTwoEncryptionsOfOneFileDiffer() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let plain = try writeSample(dir)
        try BackupEncryption.encrypt(fileAt: plain, to: dir + "/a", passphrase: passphrase, iterations: 1_000)
        try BackupEncryption.encrypt(fileAt: plain, to: dir + "/b", passphrase: passphrase, iterations: 1_000)
        XCTAssertNotEqual(try Data(contentsOf: URL(fileURLWithPath: dir + "/a")),
                          try Data(contentsOf: URL(fileURLWithPath: dir + "/b")),
                          "a fresh salt and nonce each time")
    }

    func testWrongPassphraseWritesNothing() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let plain = try writeSample(dir)
        let sealed = dir + "/sealed.almanac-backup"
        let opened = dir + "/opened.almanac-backup"
        try BackupEncryption.encrypt(fileAt: plain, to: sealed, passphrase: passphrase, iterations: 1_000)

        XCTAssertThrowsError(try BackupEncryption.decrypt(fileAt: sealed, to: opened, passphrase: "correct horse battery!")) {
            XCTAssertEqual($0 as? BackupEncryption.EncryptionError, .wrongPassphraseOrDamaged)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: opened))
    }

    func testAnyChangedByteIsRefused() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let plain = try writeSample(dir)
        let sealed = dir + "/sealed.almanac-backup"
        try BackupEncryption.encrypt(fileAt: plain, to: sealed, passphrase: passphrase, iterations: 1_000)
        let original = [UInt8](try Data(contentsOf: URL(fileURLWithPath: sealed)))

        // The iteration count's low byte and the salt are header, and the
        // header is authenticated; then a ciphertext byte, then the tag.
        for index in [13, 20, 33, BackupEncryption.headerLength + 5, original.count - 1] {
            var tampered = original
            tampered[index] ^= 0x01
            let path = dir + "/tampered-\(index)"
            try Data(tampered).write(to: URL(fileURLWithPath: path))
            XCTAssertThrowsError(try BackupEncryption.decrypt(fileAt: path, to: dir + "/out", passphrase: passphrase),
                                 "byte \(index)") {
                XCTAssertEqual($0 as? BackupEncryption.EncryptionError, .wrongPassphraseOrDamaged, "byte \(index)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir + "/out"))
    }

    func testMalformedFilesAreRefusedBeforeAnyWork() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let plain = try writeSample(dir)
        let sealed = dir + "/sealed.almanac-backup"
        try BackupEncryption.encrypt(fileAt: plain, to: sealed, passphrase: passphrase, iterations: 1_000)
        let original = [UInt8](try Data(contentsOf: URL(fileURLWithPath: sealed)))

        func refuses(_ bytes: [UInt8], with expected: BackupEncryption.EncryptionError,
                     line: UInt = #line) throws {
            let path = dir + "/case"
            try Data(bytes).write(to: URL(fileURLWithPath: path))
            XCTAssertThrowsError(try BackupEncryption.decrypt(fileAt: path, to: dir + "/out", passphrase: passphrase),
                                 line: line) {
                XCTAssertEqual($0 as? BackupEncryption.EncryptionError, expected, line: line)
            }
        }

        try refuses(Array("SQLite format 3\0".utf8), with: .notEncrypted)
        try refuses(Array(original.prefix(50)), with: .wrongPassphraseOrDamaged)
        var newer = original
        newer[8] = 2
        try refuses(newer, with: .unsupportedFormat)
        // An iteration count a stranger chose is bounded before it is spent.
        var expensive = original
        expensive[10] = 0xff
        try refuses(expensive, with: .wrongPassphraseOrDamaged)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir + "/out"))
    }

    func testShortPassphraseIsRefused() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let plain = try writeSample(dir)
        XCTAssertThrowsError(try BackupEncryption.encrypt(fileAt: plain, to: dir + "/sealed",
                                                          passphrase: "seven77", iterations: 1_000)) {
            XCTAssertEqual($0 as? BackupEncryption.EncryptionError, .passphraseTooShort(minimum: 8))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir + "/sealed"))
    }

    /// The same passphrase typed as a composed or a decomposed accent opens
    /// the file: keyboards differ in which they produce.
    func testPassphraseIsComparedInCanonicalForm() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let plain = try writeSample(dir)
        let sealed = dir + "/sealed"
        try BackupEncryption.encrypt(fileAt: plain, to: sealed, passphrase: "caf\u{e9} au lait", iterations: 1_000)
        try BackupEncryption.decrypt(fileAt: sealed, to: dir + "/opened", passphrase: "cafe\u{301} au lait")
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: dir + "/opened")),
                       try Data(contentsOf: URL(fileURLWithPath: plain)))
    }

    // MARK: - The whole path a shared backup takes

    /// Bundle → encrypt → zip → unzip → decrypt → validate → restore: what the
    /// backup screen does on share and on import, end to end.
    func testEncryptedZipRestoresLikeAPlainOne() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let source = try Database(path: dir + "/src.sqlite")
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(source)
        try SyncAnchorStore(db: source).save(domain: "hrv", token: [4, 2])
        let bundle = dir + "/almanac.almanac-backup"
        try BackupService(db: source).writeBundle(to: bundle, documentsRoot: nil, note: nil)

        let shareDir = dir + "/share"
        try FileManager.default.createDirectory(atPath: shareDir, withIntermediateDirectories: true)
        let sealed = shareDir + "/almanac.almanac-backup"
        try BackupEncryption.encrypt(fileAt: bundle, to: sealed, passphrase: passphrase, iterations: 1_000)
        let zip = try BackupZipper.zip(bundlePath: sealed)

        // The zip's entry is the sealed container: no SQLite header, no rows.
        let zipBytes = [UInt8](try Data(contentsOf: URL(fileURLWithPath: zip)))
        XCTAssertNil(zipBytes.firstRange(of: Array("SQLite format 3".utf8)))

        let extracted = try BackupZipper.unzip(archivePath: zip, into: dir + "/import")
        XCTAssertTrue(BackupEncryption.isEncrypted(fileAt: extracted))
        let target = try Database(path: dir + "/tgt.sqlite")
        try MigrationRunner(migrations: AlmanacMigrations.all).migrate(target)
        XCTAssertThrowsError(try BackupService(db: target).readBundleInfo(at: extracted),
                             "an encrypted container is not readable as a bundle")

        let opened = dir + "/import/opened.almanac-backup"
        try BackupEncryption.decrypt(fileAt: extracted, to: opened, passphrase: passphrase)
        _ = try BackupService(db: target).readBundleInfo(at: opened)
        try BackupService(db: target).restoreBundle(at: opened)
        XCTAssertEqual(try SyncAnchorStore(db: target).load("hrv")?.token, [4, 2])
    }
}
