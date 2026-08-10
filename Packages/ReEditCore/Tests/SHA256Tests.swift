import Testing

@testable import ReEditCore

#if canImport(CryptoKit)
    import CryptoKit
    import Foundation
#endif

@Suite("SHA256")
struct SHA256Tests {
    // NIST FIPS 180-4 test vectors.
    static let vectors: [(message: String, digest: String)] = [
        ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
        ("abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
        (
            "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
        ),
        (
            "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu",
            "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1"
        ),
    ]

    @Test(arguments: vectors.indices)
    func nistVectors(index: Int) {
        let vector = Self.vectors[index]
        #expect(SHA256.hexDigest(of: vector.message) == vector.digest)
    }

    @Test func millionAs() {
        let message = [UInt8](repeating: UInt8(ascii: "a"), count: 1_000_000)
        #expect(
            SHA256.hexDigest(message)
                == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }

    @Test func boundaryLengths() {
        // Padding edge cases: 55, 56 and 64 byte messages straddle the
        // single-block/two-block boundary.
        for length in [55, 56, 63, 64, 65] {
            let message = [UInt8](repeating: 0x41, count: length)
            let digest = SHA256.digest(message)
            #expect(digest.count == 32)
            // Same input twice gives the same output (determinism).
            #expect(digest == SHA256.digest(message))
        }
    }

    #if canImport(CryptoKit)
        @Test func matchesCryptoKitOnDarwin() {
            let samples: [[UInt8]] = [
                [],
                Array("The quick brown fox jumps over the lazy dog".utf8),
                [UInt8](repeating: 0xff, count: 1000),
                Array("<fcpxml version=\"1.11\"/>".utf8),
            ]
            for sample in samples {
                let ours = SHA256.hexDigest(sample)
                let theirs = CryptoKit.SHA256.hash(data: Data(sample))
                    .map { String(format: "%02x", $0) }.joined()
                #expect(ours == theirs)
            }
        }
    #endif
}

@Suite("StableID")
struct StableIDTests {
    @Test func deterministicAndBoundToSource() {
        let a = StableID.derive(
            sourceFingerprint: "aaaa", xmlPath: "/fcpxml/library", nodeFingerprint: "n1")
        let b = StableID.derive(
            sourceFingerprint: "aaaa", xmlPath: "/fcpxml/library", nodeFingerprint: "n1")
        #expect(a == b)
        #expect(a.count == 32)

        // Any component change changes the identity.
        #expect(
            a != StableID.derive(
                sourceFingerprint: "bbbb", xmlPath: "/fcpxml/library", nodeFingerprint: "n1"))
        #expect(
            a != StableID.derive(
                sourceFingerprint: "aaaa", xmlPath: "/fcpxml/event", nodeFingerprint: "n1"))
        #expect(
            a != StableID.derive(
                sourceFingerprint: "aaaa", xmlPath: "/fcpxml/library", nodeFingerprint: "n2"))
    }

    @Test func componentsCannotCollideAcrossBoundaries() {
        // The separator prevents "ab"+"c" colliding with "a"+"bc".
        let first = StableID.derive(
            sourceFingerprint: "ab", xmlPath: "c", nodeFingerprint: "d")
        let second = StableID.derive(
            sourceFingerprint: "a", xmlPath: "bc", nodeFingerprint: "d")
        #expect(first != second)
    }

    @Test func nodeFingerprintIgnoresAttributeOrder() {
        let forward = StableID.nodeFingerprint(
            elementName: "asset-clip",
            attributes: [("ref", "r2"), ("offset", "0s"), ("duration", "4s")])
        let shuffled = StableID.nodeFingerprint(
            elementName: "asset-clip",
            attributes: [("duration", "4s"), ("ref", "r2"), ("offset", "0s")])
        #expect(forward == shuffled)

        let different = StableID.nodeFingerprint(
            elementName: "asset-clip",
            attributes: [("ref", "r3"), ("offset", "0s"), ("duration", "4s")])
        #expect(forward != different)
    }
}
