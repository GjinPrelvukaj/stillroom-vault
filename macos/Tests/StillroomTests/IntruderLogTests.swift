import CryptoKit
import Foundation
import Testing
@testable import Stillroom

/// The intruder log writes while locked, sealed to both slots, and reads only with a slot's own key.
@MainActor @Suite(.serialized) struct IntruderLogTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "IntruderTests-\(UUID().uuidString)")

    /// VaultFlowTests runs alongside and points the store elsewhere between its awaits: these tests have no awaits,
    /// so on the main actor they swap the folder in and back out before it can look.
    private func inOwnFolder(_ body: () throws -> Void) rethrows {
        let before = VaultStore.rootForTests
        VaultStore.rootForTests = root
        defer { VaultStore.rootForTests = before; try? FileManager.default.removeItem(at: root) }
        try body()
    }

    /// Both slots' keys in place, as making a vault leaves them.
    private func keys() throws -> (a: String, b: String) {
        let a = try IntruderLog.check("", for: .a).key
        let b = try IntruderLog.check("", for: .b).key
        return (a, b)
    }

    @Test func nothingIsWrittenBeforeTheKeysExist() throws {
        try inOwnFolder {
            try IntruderLog.record(kind: .wrongPassword, photo: nil)
            #expect(!FileManager.default.fileExists(atPath: IntruderLog.folder.path))
        }
    }

    /// Every entry is sealed to both slots: either one, open, reads the same log; a stranger's key reads nothing.
    @Test func entriesReachBothSlots() throws {
        try inOwnFolder {
            let (a, b) = try keys()
            let photo = Data((0..<500).map { UInt8($0 % 256) })
            try IntruderLog.record(kind: .wrongPassword, photo: nil)
            try IntruderLog.record(kind: .wrongRecoveryKey, photo: photo)
            #expect(IntruderLog.entries(a, for: .a).count == 2)
            #expect(IntruderLog.entries(b, for: .b).map(\.id) == IntruderLog.entries(a, for: .a).map(\.id))
            #expect(IntruderLog.entries(b, for: .b).first?.photo == photo)
            #expect(IntruderLog.entries(a, for: .b).isEmpty)
            let stranger = Curve25519.KeyAgreement.PrivateKey().rawRepresentation.base64EncodedString()
            #expect(IntruderLog.entries(stranger, for: .a).isEmpty)
            // Deleted in one, gone for both.
            try IntruderLog.delete(id: IntruderLog.entries(a, for: .a)[0].id)
            #expect(IntruderLog.entries(b, for: .b).count == 1)
            try IntruderLog.clear()
            #expect(IntruderLog.entries(a, for: .a).isEmpty)
        }
    }

    /// A public half swapped by someone who can write the folder is noticed and reset, that half only.
    @Test func aSwappedHalfIsReset() throws {
        try inOwnFolder {
            let (a, b) = try keys()
            #expect(try IntruderLog.check(a, for: .a) == (a, false))
            var both = try Data(contentsOf: IntruderLog.publicKeyURL)
            both.replaceSubrange(0..<32, with: Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation)
            try both.write(to: IntruderLog.publicKeyURL)
            let checked = try IntruderLog.check(a, for: .a)
            #expect(checked.swapped && checked.key != a)
            #expect(try IntruderLog.check(b, for: .b) == (b, false))
        }
    }
}
