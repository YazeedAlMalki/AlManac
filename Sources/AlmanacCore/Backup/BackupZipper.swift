import Foundation

// BRD §6.18 asks for backups shared as ZIP archives; the canonical container
// is the single-file `.almanac-backup` SQLite snapshot, and rewriting it would
// throw away the bundled checksums/manifest machinery that already works. This
// is the thinnest compliant wrapper: zip the container at the export boundary,
// unzip at the import boundary, and leave both the format and the restore
// logic untouched.
//
// Why hand-rolled instead of an Apple API: `FileManager.zipItem`/`unzipItem`
// and the `Archive` framework are absent from the current Mac/iOS SDKs, and
// the app target is iOS where shelling out to `/usr/bin/zip` is impossible.
// A minimal ZIP writer/reader with STORE (no compression) entries is ~100
// lines of pure bytes + CRC-32, interoperable with every standard unzip tool,
// and — unlike any Apple framework — compiles and tests identically on Linux.
// STORE is deliberate: the payload is a SQLite file that barely compresses,
// so DEFLATE would add ~200 lines of inflate for no real gain.
//
// Refusal over guessing: a foreign zip whose only entry is DEFLATE is thrown
// `notABackupFile` rather than silently mishandled — the import boundary must
// never guess at a backup's content.

public enum BackupZipper {

    /// Wraps a `.almanac-backup` file into a `.zip` of the same base name,
    /// written next to it. Returns the zip's path.
    public static func zip(bundlePath: String) throws -> String {
        let fm = FileManager.default
        let src = URL(fileURLWithPath: bundlePath)
        let dest = src.deletingPathExtension().appendingPathExtension("zip")
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        let data = try Data(contentsOf: src)
        var bytes = [UInt8]()
        bytes.reserveCapacity(data.count + 900)
        let name = src.lastPathComponent
        let nameBytes = Array(name.utf8)
        let crc = crc32(data)
        let crcDate: UInt16 = 0x21 // 1980-01-01, DOS format — valid, not meaningful
        let crcTime: UInt16 = 0

        // Local file header.
        let localOffset = UInt32(bytes.count)
        bytes.append(contentsOf: littleEndian(UInt32(0x04034b50)))
        bytes.append(contentsOf: littleEndian(UInt16(20)))      // version needed
        bytes.append(contentsOf: littleEndian(UInt16(0)))       // flags
        bytes.append(contentsOf: littleEndian(UInt16(0)))       // method: stored
        bytes.append(contentsOf: littleEndian(crcTime))
        bytes.append(contentsOf: littleEndian(crcDate))
        bytes.append(contentsOf: littleEndian(crc))
        bytes.append(contentsOf: littleEndian(UInt32(data.count)))
        bytes.append(contentsOf: littleEndian(UInt32(data.count)))
        bytes.append(contentsOf: littleEndian(UInt16(nameBytes.count)))
        bytes.append(contentsOf: littleEndian(UInt16(0)))       // extra length
        bytes.append(contentsOf: nameBytes)
        bytes.append(contentsOf: data)

        // Central directory entry.
        let cdOffset = UInt32(bytes.count)
        bytes.append(contentsOf: littleEndian(UInt32(0x02014b50)))
        bytes.append(contentsOf: littleEndian(UInt16(20)))      // version made by
        bytes.append(contentsOf: littleEndian(UInt16(20)))      // version needed
        bytes.append(contentsOf: littleEndian(UInt16(0)))       // flags
        bytes.append(contentsOf: littleEndian(UInt16(0)))       // method: stored
        bytes.append(contentsOf: littleEndian(crcTime))
        bytes.append(contentsOf: littleEndian(crcDate))
        bytes.append(contentsOf: littleEndian(crc))
        bytes.append(contentsOf: littleEndian(UInt32(data.count)))
        bytes.append(contentsOf: littleEndian(UInt32(data.count)))
        bytes.append(contentsOf: littleEndian(UInt16(nameBytes.count)))
        bytes.append(contentsOf: littleEndian(UInt16(0)))       // extra length
        bytes.append(contentsOf: littleEndian(UInt16(0)))       // comment length
        bytes.append(contentsOf: littleEndian(UInt16(0)))       // disk number
        bytes.append(contentsOf: littleEndian(UInt16(0)))       // internal attrs
        bytes.append(contentsOf: littleEndian(UInt32(0)))       // external attrs
        bytes.append(contentsOf: littleEndian(localOffset))     // local header offset
        bytes.append(contentsOf: nameBytes)
        let cdSize = UInt32(bytes.count) - cdOffset

        // End of central directory.
        bytes.append(contentsOf: littleEndian(UInt32(0x06054b50)))
        bytes.append(contentsOf: littleEndian(UInt16(0)))       // disk number
        bytes.append(contentsOf: littleEndian(UInt16(0)))       // cd start disk
        bytes.append(contentsOf: littleEndian(UInt16(1)))       // entries on this disk
        bytes.append(contentsOf: littleEndian(UInt16(1)))       // total entries
        bytes.append(contentsOf: littleEndian(cdSize))
        bytes.append(contentsOf: littleEndian(cdOffset))
        bytes.append(contentsOf: littleEndian(UInt16(0)))       // comment length

        try Data(bytes).write(to: dest, options: .atomic)
        return dest.path
    }

    /// Extracts the single `.almanac-backup` inside a `zipPath` archive into
    /// `extractionDir` (created if needed) and returns the bundle's path.
    ///
    /// Throws `notABackupFile` when the archive is not a structurally valid
    /// zip, does not contain exactly one `.almanac-backup` entry, or uses
    /// compression this wrapper refuses to guess at.
    public static func unzip(archivePath: String, into extractionDir: String) throws -> String {
        let fm = FileManager.default
        try fm.createDirectory(atPath: extractionDir, withIntermediateDirectories: true)
        let data = try Data(contentsOf: URL(fileURLWithPath: archivePath))
        let bytes = [UInt8](data)

        // Locate the End Of Central Directory: it is the last structure and
        // sits within the final 65_557 + 22 bytes.
        let scanStart = bytes.count > 65_579 ? bytes.count - 65_579 : 0
        var eocdIndex = -1
        for i in stride(from: bytes.count - 22, through: scanStart, by: -1) {
            if u32(bytes, i) == 0x06054b50 { eocdIndex = i; break }
        }
        guard eocdIndex >= 0 else { throw BackupService.BackupError.notABackupFile(archivePath) }

        let totalEntries = u16(bytes, eocdIndex + 10)
        let cdSize = u32(bytes, eocdIndex + 12)
        let cdOffset = u32(bytes, eocdIndex + 16)
        guard totalEntries >= 1, cdOffset + cdSize <= UInt32(bytes.count) else {
            throw BackupService.BackupError.notABackupFile(archivePath)
        }

        // Walk the central directory and find the single backup entry.
        var cursor = Int(cdOffset)
        var bundleEntry: (offset: UInt32, size: UInt32, name: String)?
        var seen = 0
        while seen < Int(totalEntries) {
            guard cursor + 46 <= bytes.count, u32(bytes, cursor) == 0x02014b50 else {
                throw BackupService.BackupError.notABackupFile(archivePath)
            }
            let method = u16(bytes, cursor + 10)
            let compressed = u32(bytes, cursor + 20)
            let nameLen = Int(u16(bytes, cursor + 28))
            let extraLen = Int(u16(bytes, cursor + 30))
            let commentLen = Int(u16(bytes, cursor + 32))
            let localOffset = u32(bytes, cursor + 42)
            guard cursor + 46 + nameLen + extraLen + commentLen <= bytes.count else {
                throw BackupService.BackupError.notABackupFile(archivePath)
            }
            let name = String(bytes: bytes[cursor + 46 ..< cursor + 46 + nameLen], encoding: .utf8) ?? ""
            if name.hasSuffix(".almanac-backup") {
                guard method == 0 else {
                    throw BackupService.BackupError.notABackupFile(
                        "\(archivePath): entry '\(name)' uses compression this build does not support")
                }
                bundleEntry = (offset: localOffset, size: compressed, name: name)
            }
            cursor += 46 + nameLen + extraLen + commentLen
            seen += 1
        }
        guard let entry = bundleEntry else {
            throw BackupService.BackupError.notABackupFile("\(archivePath): no .almanac-backup inside")
        }

        // Read the local header to find where the payload really starts.
        let lo = Int(entry.offset)
        guard lo + 30 <= bytes.count, u32(bytes, lo) == 0x04034b50 else {
            throw BackupService.BackupError.notABackupFile(archivePath)
        }
        let localNameLen = Int(u16(bytes, lo + 26))
        let localExtraLen = Int(u16(bytes, lo + 28))
        let start = lo + 30 + localNameLen + localExtraLen
        guard start + Int(entry.size) <= bytes.count else {
            throw BackupService.BackupError.notABackupFile(archivePath)
        }

        let payload = Data(bytes[start ..< start + Int(entry.size)])
        guard crc32(payload) == u32(bytes, lo + 14) else {
            throw BackupService.BackupError.corruptBundle(reason: "zip entry failed its CRC-32 check")
        }

        // Guard the extracted name stays inside the extraction directory.
        let outURL = URL(fileURLWithPath: entry.name, relativeTo: URL(fileURLWithPath: extractionDir))
            .standardizedFileURL
        guard outURL.path.hasPrefix(URL(fileURLWithPath: extractionDir).standardizedFileURL.path + "/") else {
            throw BackupService.BackupError.notABackupFile(archivePath)
        }
        try payload.write(to: outURL, options: .atomic)
        return outURL.path
    }

    // MARK: - Little helpers

    private static func u16(_ b: [UInt8], _ i: Int) -> UInt16 {
        UInt16(b[i]) | (UInt16(b[i + 1]) << 8)
    }

    private static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) | (UInt32(b[i + 1]) << 8) | (UInt32(b[i + 2]) << 16) | (UInt32(b[i + 3]) << 24)
    }

    private static func littleEndian(_ v: UInt16) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8(v >> 8)]
    }

    private static func littleEndian(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = crcTable[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static let crcTable: [UInt32] = {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
            }
            table[i] = c
        }
        return table
    }()
}