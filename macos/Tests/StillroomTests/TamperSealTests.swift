import CryptoKit
import Foundation
import Testing
@testable import Stillroom

/// The tamper seal: changes outside Stillroom are noticed at the next unlock, and Stillroom's own never are, whichever
/// vault made them.
extension VaultFlowTests {
    private static let password = "real password 123"
    private static let changed = "changed while it was closed"

    private func made() async throws -> AppState {
        let state = AppState()
        try await state.create(password: Self.password, touchID: false)
        await state.add([try sample("a.txt", "one"), try sample("b.txt", "two")])
        state.lock()
        return state
    }

    private func reopened() async throws -> AppState {
        let state = AppState()
        try await state.unlock(password: Self.password)
        return state
    }

    @Test func stillroomsOwnChangesAreNotTampering() async throws {
        defer { try? FileManager.default.removeItem(at: root); TamperSeal.remove() }
        _ = try await made()
        #expect(TamperSeal.check() == .intact)
        let again = try await reopened()
        #expect(again.problem == nil)
        // Add, rename, delete, then lock: still intact.
        await again.add([try sample("c.txt", "three")])
        again.rename(again.files[0].id, to: "renamed.txt")
        again.delete(again.files[1])
        again.lock()
        #expect(TamperSeal.check() == .intact)
        #expect(try await reopened().problem == nil)
    }

    @Test func aRemovedItemFileIsNoticed() async throws {
        defer { try? FileManager.default.removeItem(at: root); TamperSeal.remove() }
        _ = try await made()
        let files = root.appending(path: "Files")
        let blob = try #require(try FileManager.default.contentsOfDirectory(at: files, includingPropertiesForKeys: nil).first)
        try FileManager.default.removeItem(at: blob)
        #expect(TamperSeal.check() == .changed)
        let again = try await reopened()
        #expect(again.problem?.contains(Self.changed) == true)
        // Said once: the folder as it is now is sealed after.
        again.lock()
        #expect(try await reopened().problem == nil)
    }

    @Test func anOlderCopyPutBackIsNoticed() async throws {
        defer { try? FileManager.default.removeItem(at: root); TamperSeal.remove() }
        _ = try await made()
        let older = root.deletingLastPathComponent().appending(path: "older-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: older) }
        try FileManager.default.copyItem(at: root, to: older)
        let again = try await reopened()
        await again.add([try sample("later.txt", "added later")])
        again.lock()
        // The folder put back as it was before "later.txt", with every file valid on its own.
        try FileManager.default.removeItem(at: root)
        try FileManager.default.copyItem(at: older, to: root)
        let rolledBack = try await reopened()
        #expect(rolledBack.files.count == 2)
        #expect(rolledBack.problem?.contains(Self.changed) == true)
    }

    /// Putting back an older folder together with its own older seal doesn't hide it: this Mac keeps the latest seal.
    @Test func anOlderCopyWithItsOwnSealIsNoticed() async throws {
        defer { try? FileManager.default.removeItem(at: root); TamperSeal.remove() }
        _ = try await made()
        let older = root.deletingLastPathComponent().appending(path: "older-\(UUID().uuidString)")
        let olderSeal = older.appendingPathExtension("seal")
        defer { try? FileManager.default.removeItem(at: older); try? FileManager.default.removeItem(at: olderSeal) }
        try FileManager.default.copyItem(at: root, to: older)
        try FileManager.default.copyItem(at: TamperSeal.url, to: olderSeal)
        let again = try await reopened()
        await again.add([try sample("later.txt", "added later")])
        again.lock()
        try FileManager.default.removeItem(at: root)
        try FileManager.default.copyItem(at: older, to: root)
        try FileManager.default.removeItem(at: TamperSeal.url)
        try FileManager.default.copyItem(at: olderSeal, to: TamperSeal.url)
        #expect(TamperSeal.check() == .changed)
    }

    /// Deleting the seal file isn't a way out either, once this Mac has sealed the vault.
    @Test func aDeletedSealIsNoticed() async throws {
        defer { try? FileManager.default.removeItem(at: root); TamperSeal.remove() }
        _ = try await made()
        try FileManager.default.removeItem(at: TamperSeal.url)
        #expect(TamperSeal.check() == .changed)
    }

    /// One seal for the folder: using the other vault never trips this one's, nor the reverse.
    @Test func usingTheOtherVaultIsNotTampering() async throws {
        defer { try? FileManager.default.removeItem(at: root); TamperSeal.remove() }
        let state = try await reopenedAfterMaking()
        _ = try await state.setOtherSlot(password: "decoy password 456")
        state.lock()
        let decoy = AppState()
        try await decoy.unlock(password: "decoy password 456")
        #expect(decoy.problem == nil)
        await decoy.add([try sample("decoy.txt", "dull")])
        decoy.lock()
        #expect(try await reopened().problem == nil)
    }

    private func reopenedAfterMaking() async throws -> AppState {
        _ = try await made()
        return try await reopened()
    }

    /// Wrong tries write the intruder log while the vault is shut, on purpose: that's not tampering.
    @Test func theIntruderLogIsLeftOut() async throws {
        defer { try? FileManager.default.removeItem(at: root); TamperSeal.remove() }
        _ = try await made()
        try VaultStore.write(Data("a wrong try".utf8), to: root.appending(path: "intruder/\(UUID().uuidString).intruder"))
        #expect(TamperSeal.check() == .intact)
    }

    /// A vault from before 1.1, or one sealed on another Mac: nothing to check against, so nothing said.
    @Test func noSealYetSaysNothing() async throws {
        defer { try? FileManager.default.removeItem(at: root); TamperSeal.remove() }
        _ = try await made()
        TamperSeal.remove()
        #expect(TamperSeal.check() == .fresh)
        #expect(try await reopened().problem == nil)
    }
}

/// Each vault folder keeps its own latest seal in the keychain: a second Stillroom on this Mac (a demo copy, another
/// build) never reads the installed app's, which made macOS stop for an access prompt and say "changed".
@Test func eachFolderHasItsOwnKeychainSeal() {
    let one = URL(filePath: "/Users/someone/Library/Application Support/Stillroom/Store")
    let other = URL(filePath: "/tmp/home/Library/Application Support/Stillroom/Store")
    #expect(TamperSeal.Latest.account(for: one) != TamperSeal.Latest.account(for: other))
    #expect(TamperSeal.Latest.account(for: one) == TamperSeal.Latest.account(for: URL(filePath: "/Users/someone/Library/Application Support/Stillroom/./Store/")))
    #expect(TamperSeal.Latest.account(for: one).count == 64)
}
