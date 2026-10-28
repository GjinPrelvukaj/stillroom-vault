import Foundation
import Testing
@testable import Stillroom

private func hex(_ bytes: some Sequence<UInt8>) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

/// RFC 9106 section 5.3: H0 with a secret and associated data, H', G and four lanes. Its segments are only two
/// blocks long, so the known answers below cover one lane, address blocks being regenerated, and odd memory sizes.
@Test func argon2idMatchesTheRFCVector() throws {
    let tag = try argon2id(password: Data(repeating: 1, count: 32), salt: Data(repeating: 2, count: 16),
                       memoryKiB: 32, iterations: 3, parallelism: 4, length: 32,
                       secret: Data(repeating: 3, count: 8), associatedData: Data(repeating: 4, count: 12))
    #expect(hex(tag) == "0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659")
}

/// Answers from libargon2 (worked out apart from the copy in the app), at costs the RFC vector doesn't reach.
@Test(arguments: [
    ("password", Data("somesalt".utf8), UInt32(1024), UInt32(1), UInt32(1), "c8e9aedc956f6a7dff0a4d42940df628623f328ea1235005abac933c57093e23"),
    ("password", Data("somesalt".utf8), 4099, 2, 4, "2b6c3ddf0aa362e65218e07fc58dacf51d696bfdf641949a4875e9e1522df718"),
    ("pässwörd 🔐", Data(repeating: 7, count: 16), 65536, 3, 1, "b2411a53d160ea1d19d318c6eac6d2950268c54db0814feae2c999c64406e089"),
])
func argon2idMatchesLibargon2Answers(password: String, salt: Data, memoryKiB: UInt32, passes: UInt32, lanes: UInt32, expected: String) throws {
    let tag = try argon2id(password: Data(password.utf8), salt: salt, memoryKiB: memoryKiB, iterations: passes, parallelism: lanes, length: 32)
    #expect(hex(tag) == expected)
}

/// RFC 7693 appendix A, the empty input, and a two-block one (200 bytes, from Python's hashlib) for the block counter.
@Test func blake2bMatchesKnownAnswers() {
    #expect(hex(blake2b(Array(0..<200), length: 64)) == "fb3c1f0f56a56f8e316fdf5d853c8c872c39635d083634c3904fc3ac07d1b578e85ff0e480e92d44ade33b62e893ee32343e79ddf6ef292e89b582d312502314")
    #expect(hex(blake2b(Array("abc".utf8), length: 64)) == "ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d17d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923")
    #expect(hex(blake2b([], length: 64)) == "786a02f742015903c6c6fd852552d272912f4740e15847618a86e217f71f5419d25e1031afee585313896444934eb04b903a685b1448b755d56f701afe9be2ce")
}

/// A password must stretch to the same key every time, and a fresh salt must give a different one.
@Test func argon2idIsStableAndSaltSensitive() {
    func tag(_ salt: UInt8) -> Data {
        try! argon2id(password: Data("correct horse battery".utf8), salt: Data(repeating: salt, count: 16),
                 memoryKiB: 64, iterations: 2, parallelism: 2, length: 32)
    }
    #expect(tag(7) == tag(7))
    #expect(tag(7) != tag(8))
}

/// How long the real setting takes. Only runs when asked: `ARGON2_BENCH=1 swift test -c release --filter argon2idSpeed`.
@Test(.enabled(if: ProcessInfo.processInfo.environment["ARGON2_BENCH"] != nil))
func argon2idSpeed() {
    let clock = ContinuousClock()
    let time = clock.measure {
        _ = try? argon2id(password: Data("password".utf8), salt: Data(repeating: 0, count: 16),
                     memoryKiB: 131_072, iterations: 3, parallelism: 4, length: 32)
    }
    print("argon2id 128 MiB, t=3, p=4: \(time)")
}

/// The bundled C and the Swift implementation written from the RFC give the same key across lanes, odd memory
/// sizes, passes, tag lengths either side of BLAKE2b's 64 bytes, and with and without a secret and associated data.
@Test func theReferenceCAgreesWithTheSwiftImplementation() throws {
    var random = SystemRandomNumberGenerator()
    for lanes: UInt32 in [1, 2, 3, 4, 8] {
        for memoryKiB in [8 * lanes, 8 * lanes + 3, 300, 1027] {
            for (passes, length) in [(UInt32(1), 4), (2, 32), (3, 65), (1, 129)] {
                let password = Data((0..<Int.random(in: 0...40, using: &random)).map { _ in UInt8.random(in: 0...255, using: &random) })
                let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255, using: &random) })
                let extra = length == 65 ? Data([1, 2, 3, 4, 5, 6, 7, 8]) : Data()
                let c = try argon2id(password: password, salt: salt, memoryKiB: memoryKiB, iterations: passes, parallelism: lanes,
                                     length: length, secret: extra, associatedData: extra)
                let swift = swiftArgon2id(password: password, salt: salt, memoryKiB: memoryKiB, iterations: passes, parallelism: lanes,
                                          length: length, secret: extra, associatedData: extra)
                #expect(c == swift, "m \(memoryKiB) t \(passes) p \(lanes) length \(length)")
            }
        }
    }
}

/// Costs no key should carry are refused, not crashed on.
@Test func impossibleCostsAreRefused() {
    #expect(throws: VaultError.damaged) {
        try argon2id(password: Data("x".utf8), salt: Data(count: 16), memoryKiB: 8, iterations: 0, parallelism: 1, length: 32)
    }
}
