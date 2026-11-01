import Foundation

/// ChaCha20-Poly1305 (RFC 8439) and PBKDF2-HMAC-SHA256 (RFC 8018) in plain
/// Swift, for the platforms with no CryptoKit.
///
/// **Not what a phone runs.** On Apple platforms `BackupEncryption` seals with
/// CryptoKit's `ChaChaPoly` and derives keys with CommonCrypto, as the
/// technical specification's stack table asks ("CryptoKit … future archive
/// encryption"). This exists so the envelope — its header, its refusals, a
/// round trip — is tested on Linux, where the core is verified on every push,
/// the same reason `SHA256File` exists. Both are pinned to the RFCs' own test
/// vectors in `BackupEncryptionTests`, which is what makes a file sealed by one
/// open with the other.
///
/// Speed is not a goal here and neither is constant time: a Linux test run is
/// the only caller.
enum PortableCrypto {

    // MARK: - ChaCha20-Poly1305 (RFC 8439 §2.8)

    static func seal(_ plaintext: [UInt8], key: [UInt8], nonce: [UInt8],
                     aad: [UInt8]) -> (ciphertext: [UInt8], tag: [UInt8]) {
        precondition(key.count == 32 && nonce.count == 12)
        let oneTimeKey = Array(chacha20Block(key: key, counter: 0, nonce: nonce).prefix(32))
        let ciphertext = chacha20(key: key, nonce: nonce, counter: 1, plaintext)
        return (ciphertext, poly1305(key: oneTimeKey, message: macData(aad: aad, ciphertext: ciphertext)))
    }

    /// Nil when the tag does not match: a wrong key and a changed byte are the
    /// same answer, by design of the construction.
    static func open(ciphertext: [UInt8], tag: [UInt8], key: [UInt8], nonce: [UInt8],
                     aad: [UInt8]) -> [UInt8]? {
        guard key.count == 32, nonce.count == 12, tag.count == 16 else { return nil }
        let oneTimeKey = Array(chacha20Block(key: key, counter: 0, nonce: nonce).prefix(32))
        let expected = poly1305(key: oneTimeKey, message: macData(aad: aad, ciphertext: ciphertext))
        // Compared without an early exit, so the comparison takes the same time
        // however many leading bytes match.
        var difference: UInt8 = 0
        for i in 0..<16 { difference |= expected[i] ^ tag[i] }
        guard difference == 0 else { return nil }
        return chacha20(key: key, nonce: nonce, counter: 1, ciphertext)
    }

    private static func macData(aad: [UInt8], ciphertext: [UInt8]) -> [UInt8] {
        var data = aad
        data += [UInt8](repeating: 0, count: (16 - aad.count % 16) % 16)
        data += ciphertext
        data += [UInt8](repeating: 0, count: (16 - ciphertext.count % 16) % 16)
        data += littleEndian64(UInt64(aad.count))
        data += littleEndian64(UInt64(ciphertext.count))
        return data
    }

    // MARK: - ChaCha20 (RFC 8439 §2.3, §2.4)

    static func chacha20(key: [UInt8], nonce: [UInt8], counter: UInt32, _ input: [UInt8]) -> [UInt8] {
        var output = [UInt8]()
        output.reserveCapacity(input.count)
        var offset = 0
        var blockCounter = counter
        while offset < input.count {
            let keystream = chacha20Block(key: key, counter: blockCounter, nonce: nonce)
            let n = min(64, input.count - offset)
            for i in 0..<n { output.append(input[offset + i] ^ keystream[i]) }
            offset += 64
            blockCounter &+= 1
        }
        return output
    }

    static func chacha20Block(key: [UInt8], counter: UInt32, nonce: [UInt8]) -> [UInt8] {
        var state: [UInt32] = [0x6170_7865, 0x3320_646e, 0x7962_2d32, 0x6b20_6574]
        for i in 0..<8 { state.append(littleEndian32(key, 4 * i)) }
        state.append(counter)
        for i in 0..<3 { state.append(littleEndian32(nonce, 4 * i)) }
        var working = state
        for _ in 0..<10 {
            quarterRound(&working, 0, 4, 8, 12)
            quarterRound(&working, 1, 5, 9, 13)
            quarterRound(&working, 2, 6, 10, 14)
            quarterRound(&working, 3, 7, 11, 15)
            quarterRound(&working, 0, 5, 10, 15)
            quarterRound(&working, 1, 6, 11, 12)
            quarterRound(&working, 2, 7, 8, 13)
            quarterRound(&working, 3, 4, 9, 14)
        }
        var output = [UInt8]()
        output.reserveCapacity(64)
        for i in 0..<16 {
            let word = working[i] &+ state[i]
            output += [UInt8(word & 0xff), UInt8((word >> 8) & 0xff),
                       UInt8((word >> 16) & 0xff), UInt8(word >> 24)]
        }
        return output
    }

    private static func quarterRound(_ s: inout [UInt32], _ a: Int, _ b: Int, _ c: Int, _ d: Int) {
        s[a] = s[a] &+ s[b]; s[d] ^= s[a]; s[d] = rotateLeft(s[d], 16)
        s[c] = s[c] &+ s[d]; s[b] ^= s[c]; s[b] = rotateLeft(s[b], 12)
        s[a] = s[a] &+ s[b]; s[d] ^= s[a]; s[d] = rotateLeft(s[d], 8)
        s[c] = s[c] &+ s[d]; s[b] ^= s[c]; s[b] = rotateLeft(s[b], 7)
    }

    private static func rotateLeft(_ value: UInt32, _ count: UInt32) -> UInt32 {
        (value << count) | (value >> (32 - count))
    }

    // MARK: - Poly1305 (RFC 8439 §2.5)

    /// Five 26-bit limbs ("poly1305-donna"), so every product fits in 64 bits.
    static func poly1305(key: [UInt8], message: [UInt8]) -> [UInt8] {
        precondition(key.count == 32)
        let mask: UInt64 = 0x3ff_ffff
        let r0 = UInt64(littleEndian32(key, 0)) & 0x3ff_ffff
        let r1 = UInt64(littleEndian32(key, 3) >> 2) & 0x3ff_ff03
        let r2 = UInt64(littleEndian32(key, 6) >> 4) & 0x3ff_c0ff
        let r3 = UInt64(littleEndian32(key, 9) >> 6) & 0x3f0_3fff
        let r4 = UInt64(littleEndian32(key, 12) >> 8) & 0x00f_ffff
        let s1 = r1 * 5, s2 = r2 * 5, s3 = r3 * 5, s4 = r4 * 5
        var h0: UInt64 = 0, h1: UInt64 = 0, h2: UInt64 = 0, h3: UInt64 = 0, h4: UInt64 = 0

        var offset = 0
        while offset < message.count {
            // A block is its bytes followed by a 1; for a full block that 1 is
            // the 2^128 bit (byte 16), for a short one it lands inside it.
            let n = min(16, message.count - offset)
            var block = [UInt8](repeating: 0, count: 17)
            for i in 0..<n { block[i] = message[offset + i] }
            block[n] = 1
            h0 += UInt64(littleEndian32(block, 0)) & mask
            h1 += UInt64(littleEndian32(block, 3) >> 2) & mask
            h2 += UInt64(littleEndian32(block, 6) >> 4) & mask
            h3 += UInt64(littleEndian32(block, 9) >> 6) & mask
            h4 += UInt64(littleEndian32(block, 12) >> 8) | (UInt64(block[16]) << 24)

            let d0 = h0 * r0 + h1 * s4 + h2 * s3 + h3 * s2 + h4 * s1
            var d1 = h0 * r1 + h1 * r0 + h2 * s4 + h3 * s3 + h4 * s2
            var d2 = h0 * r2 + h1 * r1 + h2 * r0 + h3 * s4 + h4 * s3
            var d3 = h0 * r3 + h1 * r2 + h2 * r1 + h3 * r0 + h4 * s4
            var d4 = h0 * r4 + h1 * r3 + h2 * r2 + h3 * r1 + h4 * r0

            var carry = d0 >> 26; h0 = d0 & mask
            d1 += carry; carry = d1 >> 26; h1 = d1 & mask
            d2 += carry; carry = d2 >> 26; h2 = d2 & mask
            d3 += carry; carry = d3 >> 26; h3 = d3 & mask
            d4 += carry; carry = d4 >> 26; h4 = d4 & mask
            h0 += carry * 5; carry = h0 >> 26; h0 &= mask; h1 += carry
            offset += 16
        }

        // Fully carry, then subtract p = 2^130 - 5 if h >= p.
        var carry = h1 >> 26; h1 &= mask
        h2 += carry; carry = h2 >> 26; h2 &= mask
        h3 += carry; carry = h3 >> 26; h3 &= mask
        h4 += carry; carry = h4 >> 26; h4 &= mask
        h0 += carry * 5; carry = h0 >> 26; h0 &= mask
        h1 += carry

        var g0 = h0 &+ 5; carry = g0 >> 26; g0 &= mask
        var g1 = h1 &+ carry; carry = g1 >> 26; g1 &= mask
        var g2 = h2 &+ carry; carry = g2 >> 26; g2 &= mask
        var g3 = h3 &+ carry; carry = g3 >> 26; g3 &= mask
        let g4 = h4 &+ carry &- (1 << 26)
        // g4 wrapped (top bit set) means h < p: keep h. Otherwise take g.
        let takeG: UInt64 = (g4 >> 63) &- 1
        let keepH = ~takeG
        h0 = (h0 & keepH) | (g0 & takeG)
        h1 = (h1 & keepH) | (g1 & takeG)
        h2 = (h2 & keepH) | (g2 & takeG)
        h3 = (h3 & keepH) | (g3 & takeG)
        h4 = (h4 & keepH) | (g4 & takeG)

        // h mod 2^128, plus s, as four little-endian words.
        let words: [UInt64] = [
            (h0 | (h1 << 26)) & 0xffff_ffff,
            ((h1 >> 6) | (h2 << 20)) & 0xffff_ffff,
            ((h2 >> 12) | (h3 << 14)) & 0xffff_ffff,
            ((h3 >> 18) | (h4 << 8)) & 0xffff_ffff,
        ]
        var tag = [UInt8]()
        tag.reserveCapacity(16)
        var sum: UInt64 = 0
        for i in 0..<4 {
            sum = words[i] + UInt64(littleEndian32(key, 16 + 4 * i)) + (sum >> 32)
            let word = sum & 0xffff_ffff
            tag += [UInt8(word & 0xff), UInt8((word >> 8) & 0xff),
                    UInt8((word >> 16) & 0xff), UInt8((word >> 24) & 0xff)]
        }
        return tag
    }

    // MARK: - HMAC-SHA256 (RFC 2104) and PBKDF2 (RFC 8018 §5.2)

    /// The key's inner and outer states, absorbed once, so each of PBKDF2's
    /// many MACs costs two compressions rather than four.
    struct HMACSHA256 {
        private var inner = SHA256()
        private var outer = SHA256()

        init(key: [UInt8]) {
            var block = key.count > 64 ? SHA256.digest(key) : key
            block += [UInt8](repeating: 0, count: 64 - block.count)
            inner.update(block.map { $0 ^ 0x36 })
            outer.update(block.map { $0 ^ 0x5c })
        }

        func mac(_ message: [UInt8]) -> [UInt8] {
            var innerHash = inner
            innerHash.update(message)
            var outerHash = outer
            outerHash.update(innerHash.finalize())
            return outerHash.finalize()
        }
    }

    static func pbkdf2SHA256(password: [UInt8], salt: [UInt8], iterations: Int, keyLength: Int) -> [UInt8] {
        precondition(iterations >= 1 && keyLength >= 1)
        let hmac = HMACSHA256(key: password)
        var derived: [UInt8] = []
        var blockIndex: UInt32 = 1
        while derived.count < keyLength {
            var u = hmac.mac(salt + [UInt8(blockIndex >> 24), UInt8((blockIndex >> 16) & 0xff),
                                     UInt8((blockIndex >> 8) & 0xff), UInt8(blockIndex & 0xff)])
            var t = u
            for _ in 1..<iterations {
                u = hmac.mac(u)
                for j in 0..<t.count { t[j] ^= u[j] }
            }
            derived += t
            blockIndex += 1
        }
        return Array(derived.prefix(keyLength))
    }

    // MARK: - Bytes

    static func littleEndian32(_ bytes: [UInt8], _ index: Int) -> UInt32 {
        UInt32(bytes[index]) | (UInt32(bytes[index + 1]) << 8)
            | (UInt32(bytes[index + 2]) << 16) | (UInt32(bytes[index + 3]) << 24)
    }

    private static func littleEndian64(_ value: UInt64) -> [UInt8] {
        (0..<8).map { UInt8((value >> (8 * UInt64($0))) & 0xff) }
    }
}

extension SHA256 {
    static func digest(_ bytes: [UInt8]) -> [UInt8] {
        var hasher = SHA256()
        hasher.update(bytes)
        return hasher.finalize()
    }
}
