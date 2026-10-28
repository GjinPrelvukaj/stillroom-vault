import CryptoKit
import Foundation
import Testing
@testable import Stillroom

/// Padding never shrinks a file and adds at most about 12%, so the sealed size gives little away.
@Test func paddingIsBoundedAndNeverShrinks() {
    for n in [0, 1, 2, 3, 100, 1000, 4097, 65_537, 1_000_000, 7_654_321] {
        let p = paddedLength(n)
        #expect(p >= n)
        #expect(Double(p) <= Double(n) * 1.13 + 2)
    }
}

/// The real vault on disk is never touched: every test here uses a folder of its own, one at a time.
@MainActor @Suite(.serialized) struct VaultFlowTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "StillroomTests-\(UUID().uuidString)")

    init() {
        VaultStore.rootForTests = root
        PasswordCost.current = PasswordCost(memoryKiB: 1024, passes: 1, lanes: 1)
        // Password changes count as tries (AppState.countGuessAtOther); each test starts with none.
        TryLimit.succeeded()
    }

    func sample(_ name: String, _ text: String) throws -> URL {
        let url = root.deletingLastPathComponent().appending(path: "\(UUID().uuidString)-\(name)")
        try Data(text.utf8).write(to: url)
        return url
    }

    func sample(_ name: String, _ data: Data) throws -> URL {
        let url = root.deletingLastPathComponent().appending(path: "\(UUID().uuidString)-\(name)")
        try data.write(to: url)
        return url
    }

    @Test func aChangedPasswordReplacesTheOld() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState()
        try await state.create(password: "old password 123", touchID: false)
        await #expect(throws: VaultError.self) { try await state.changePassword(current: "not it at all", to: "new password 456") }
        try await state.changePassword(current: "old password 123", to: "new password 456")
        state.lock()
        await #expect(throws: VaultError.self) { try await state.unlock(password: "old password 123") }
        try await state.unlock(password: "new password 456")
        #expect(state.isOpen)
    }

    @Test func theRecoveryKeyOpensAndAsksForANewPassword() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState()
        try await state.create(password: "forgotten password", touchID: false)
        let code = try await state.newRecoveryKey()
        state.lock()

        await #expect(throws: VaultError.self) { try await state.unlock(recoveryKey: "AAAAA-BBBBB-CCCCC-DDDDD-EEEEE") }
        // Typed in small letters without dashes, it still opens.
        try await state.unlock(recoveryKey: code.lowercased().replacingOccurrences(of: "-", with: " "))
        #expect(state.mustSetPassword)
        try await state.setPasswordAfterRecovery("brand new password")
        state.lock()
        try await state.unlock(password: "brand new password")
        #expect(state.isOpen)
    }

    @Test func paddedFilesComeBackExactly() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState()
        try await state.create(password: "real password 123", touchID: false)
        let text = String(repeating: "x", count: 4097)
        try await state.add([sample("odd.txt", text)])
        let blob = VaultStore.blob(try state.seal(of: state.files[0]).blob, state.slot)
        let sealedSize = try FileManager.default.attributesOfItem(atPath: blob.path)[.size] as! Int
        #expect(sealedSize == paddedLength(4097) + 28)
        #expect(try state.read(state.files[0]) == Data(text.utf8))
    }

    /// Locked to this Mac, the password key on disk is sealed by the Enclave: without this Mac's key it's useless,
    /// with it the password still opens. Turning the lock off brings the plain key back.
    @Test(.enabled(if: MacLock.canUse)) func lockingToThisMacSealsTheKeyAgain() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState()
        try await state.create(password: "real password 123", touchID: false)
        let plain = try Data(contentsOf: state.slot.keyFile)
        let code = try await state.setMacLock(true)
        #expect(code != nil)
        let locked = try Data(contentsOf: state.slot.keyFile)
        #expect(locked != plain)
        // Without this Mac (the Enclave key gone), the password alone can't open it.
        #expect((try? openWithPassword(locked, password: "real password 123")) == nil)
        state.lock()
        try await state.unlock(password: "real password 123")
        #expect(state.isOpen)
        _ = try await state.setMacLock(false)
        #expect(try Data(contentsOf: state.slot.keyFile) == plain)
    }

    /// A sealed file no list names is deleted when its vault opens; the listed ones stay.
    @Test func unlistedFilesAreClearedOnOpen() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState()
        try await state.create(password: "real password 123", touchID: false)
        try await state.add([sample("keep.txt", "keep")])
        let stray = VaultStore.Slot.a.files.appending(path: "\(UUID().uuidString).stillroom")
        try Data("stray".utf8).write(to: stray)
        state.lock()
        try await state.unlock(password: "real password 123")
        #expect(!FileManager.default.fileExists(atPath: stray.path))
        #expect(try state.read(state.files[0]) == Data("keep".utf8))
    }

    /// A note keeps its earlier text as a version once it's been left alone a while, and can be put back.
    @Test func notesKeepVersionsAndPutThemBack() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState()
        try await state.create(password: "real password 123", touchID: false)
        let note = try #require(state.newEntry(.note, name: "Plans", content: Data("first".utf8)))
        // Typing straight after: no version.
        state.update(note.id, with: Data("second".utf8))
        #expect(state.files[0].versions == nil)
        // Pretend it was last changed an hour ago, as after a break.
        state.update(note.id, with: Data("second".utf8))
        try state.backdate(note.id, by: 3600)
        state.update(note.id, with: Data("third".utf8))
        let versions = try #require(state.files[0].versions)
        #expect(versions.count == 1)
        #expect(try state.readVersion(versions[0]) == Data("second".utf8))
        state.restore(versions[0], of: note.id)
        #expect(try state.read(state.files[0]) == Data("second".utf8))
        #expect(state.files[0].versions?.count == 1)
        state.lock()
        try await state.unlock(password: "real password 123")
        #expect(try state.read(state.files[0]) == Data("second".utf8))
    }

    /// Folders carry what's in them when renamed, tags filter, and everything survives a lock.
    @Test func foldersAndTagsStick() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState()
        try await state.create(password: "real password 123", touchID: false)
        state.makeFolder("Taxes", in: nil)
        state.makeFolder("2025", in: "Taxes")
        try await state.add([sample("w2.txt", "w2")], into: "Taxes/2025")
        let file = state.files[0]
        #expect(file.folder == "Taxes/2025")
        state.setTags(["money"], on: file.id)
        state.renameFolder("Taxes", to: "Paperwork")
        state.lock()
        try await state.unlock(password: "real password 123")
        #expect(state.files[0].folder == "Paperwork/2025")
        #expect(state.folders == ["Paperwork", "Paperwork/2025"])
        #expect(state.tags == ["money"])
        state.deleteFolder("Paperwork")
        #expect(state.files.isEmpty)
    }
}
