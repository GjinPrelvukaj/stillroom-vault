import Foundation
import Testing
@testable import Stillroom

/// Nested in VaultFlowTests so the two never run at once: both point the one shared VaultStore.rootForTests.
extension VaultFlowTests {
    /// Backups go to and come from a folder of the test's own; the real vault is never touched.
    @MainActor @Suite(.serialized) struct BackupTests {
        let base = FileManager.default.temporaryDirectory.appending(path: "BackupTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        var root: URL { base.appending(path: "VaultStore", directoryHint: .isDirectory) }

        init() throws {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            VaultStore.rootForTests = base.appending(path: "VaultStore", directoryHint: .isDirectory)
        }

        private func sample(_ name: String, _ data: Data) throws -> URL {
            let url = base.appending(path: "\(UUID().uuidString)-\(name)")
            try data.write(to: url)
            return url
        }

        private func vault(with data: Data, password: String) async throws -> AppState {
            let state = AppState()
            try await state.create(password: password, touchID: false)
            await state.add([try sample("photo.bin", data)])
            #expect(state.files.count == 1)
            return state
        }

        @Test func aBackupBringsTheVaultBackByteForByte() async throws {
            defer { try? FileManager.default.removeItem(at: base) }
            let bytes = Data((0..<70_000).map { _ in UInt8.random(in: 0...255) })
            let state = try await vault(with: bytes, password: "backup password 1")
            state.lock()

            let file = base.appending(path: Backup.suggestedName())
            try Backup.make(to: file)
            try Backup.check(file)
            #expect(Backup.lastBackup.map { abs($0.timeIntervalSinceNow) < 60 } == true)

            try VaultStore.wipe()
            #expect(!VaultStore.exists)
            #expect(try Backup.restore(from: file) == nil)

            let fresh = AppState()
            try await fresh.unlock(password: "backup password 1")
            #expect(try fresh.read(fresh.files[0]) == bytes)
            let perms = try FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as? Int
            #expect(perms == 0o700)
        }

        @Test func restoringOverAVaultMovesTheOldOneAside() async throws {
            defer { try? FileManager.default.removeItem(at: base) }
            let first = try await vault(with: Data("first".utf8), password: "first password 1")
            first.lock()
            let file = base.appending(path: "one.\(Backup.fileExtension)")
            try Backup.make(to: file)

            try VaultStore.wipe()
            let second = try await vault(with: Data("second".utf8), password: "second password 2")
            second.lock()

            let aside = try #require(try Backup.restore(from: file))
            #expect(aside.lastPathComponent.hasPrefix("Store-before-restore-"))
            #expect(FileManager.default.fileExists(atPath: aside.appending(path: "a/password.key").path))

            let fresh = AppState()
            try await fresh.unlock(password: "first password 1")
            #expect(String(decoding: try fresh.read(fresh.files[0]), as: UTF8.self) == "first")
        }

        /// A restore cut short at either step leaves a whole vault in place: before the swap, the old one, untouched;
        /// after it, the restored one, with the old one whole beside it. There's never a moment with no vault.
        @Test func aRestoreCutShortLeavesAWholeVault() async throws {
            defer { try? FileManager.default.removeItem(at: base) }
            let first = try await vault(with: Data("first".utf8), password: "first password 1")
            first.lock()
            let file = base.appending(path: "one.\(Backup.fileExtension)")
            try Backup.make(to: file)
            let firstKey = try Data(contentsOf: VaultStore.Slot.a.keyFile)
            try VaultStore.wipe()
            let second = try await vault(with: Data("second".utf8), password: "second password 2")
            second.lock()
            let secondKey = try Data(contentsOf: VaultStore.Slot.a.keyFile)

            // Stopped after staging: the live vault is as it was, and the staged copy is the whole backup.
            let staged = try Backup.stage(file)
            #expect(staged.deletingLastPathComponent() == root.deletingLastPathComponent())
            #expect(try Data(contentsOf: staged.appending(path: "a/password.key")) == firstKey)
            let before = AppState()
            try await before.unlock(password: "second password 2")
            #expect(String(decoding: try before.read(before.files[0]), as: UTF8.self) == "second")
            before.lock()

            // The swap: each name holds the other's whole folder.
            try Backup.swap(staged, root)
            #expect(try Data(contentsOf: VaultStore.Slot.a.keyFile) == firstKey)
            #expect(try Data(contentsOf: staged.appending(path: "a/password.key")) == secondKey)
            let after = AppState()
            try await after.unlock(password: "first password 1")
            #expect(String(decoding: try after.read(after.files[0]), as: UTF8.self) == "first")
        }

        @Test func checkRejectsWhatIsntABackup() throws {
            defer { try? FileManager.default.removeItem(at: base) }
            let junk = try sample("junk.stillroombackup", Data((0..<4096).map { _ in UInt8.random(in: 0...255) }))
            #expect(throws: Backup.Problem.notABackup) { try Backup.check(junk) }

            // A real zip, but of a folder that isn't a vault.
            let folder = base.appending(path: "Holiday", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("hi".utf8).write(to: folder.appending(path: "notes.txt"))
            let zip = base.appending(path: "holiday.zip")
            let p = try Process.run(URL(filePath: "/usr/bin/ditto"), arguments: ["-c", "-k", "--keepParent", folder.path, zip.path])
            p.waitUntilExit()
            #expect(p.terminationStatus == 0)
            #expect(throws: Backup.Problem.notABackup) { try Backup.check(zip) }
            #expect(throws: Backup.Problem.notABackup) { try Backup.restore(from: zip) }
        }

        @Test func aFailedBackupLeavesNothingBehind() async throws {
            defer { try? FileManager.default.removeItem(at: base) }
            let state = try await vault(with: Data("x".utf8), password: "some password 1")
            state.lock()
            let missing = base.appending(path: "Unplugged/Disk", directoryHint: .isDirectory)
            let target = missing.appending(path: Backup.suggestedName())
            #expect(throws: (any Error).self) { try Backup.make(to: target) }
            #expect(!FileManager.default.fileExists(atPath: target.path))
            #expect(!FileManager.default.fileExists(atPath: missing.path))
        }

        @Test func theSuggestedNameCarriesTheDay() {
            let day = DateComponents(calendar: .current, year: 2026, month: 10, day: 23, hour: 12).date!
            #expect(Backup.suggestedName(on: day) == "Stillroom Backup 2026-10-23.stillroombackup")
        }
    }
}

extension VaultFlowTests {
    /// A zip holding a link is turned away before anything is unpacked.
    @Test func aBackupWithALinkIsTurnedAway() throws {
        let work = FileManager.default.temporaryDirectory.appending(path: "LinkZip-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: work) }
        let folder = work.appending(path: "VaultStore")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: folder.appending(path: "password.key"))
        try FileManager.default.createSymbolicLink(at: folder.appending(path: "Files"), withDestinationURL: URL(filePath: "/tmp"))
        let zip = work.appending(path: "evil.stillroombackup")
        let p = Process()
        p.executableURL = URL(filePath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", "--keepParent", folder.path, zip.path]
        try p.run()
        p.waitUntilExit()
        #expect(throws: (any Error).self) { try Backup.check(zip) }
    }
}
