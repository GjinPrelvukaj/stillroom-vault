import Foundation
import Testing
@testable import Stillroom

/// For Gjin to move into macos/Tests/StillroomTests/: the Mac app opens a vault the Windows engine wrote
/// (windows/engine/tests/fixtures-windows, made like writesFormatFixture), so the two apps can't drift apart. The
/// committed vault is copied first and never written to. Nothing compiles this file where it sits.
extension VaultFlowTests {
    private var windowsFixture: URL {
        URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "../../../windows/engine/tests/fixtures-windows").standardizedFileURL
    }

    /// The Windows vault in this test's own folder.
    private func windowsVault() throws -> [String: Any] {
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: windowsFixture.appending(path: "vault"), to: root)
        let answers = try Data(contentsOf: windowsFixture.appending(path: "answers.json"))
        return try #require(try JSONSerialization.jsonObject(with: answers) as? [String: Any])
    }

    private func source(_ name: String) throws -> Data {
        try Data(contentsOf: windowsFixture.appending(path: "source/\(name)"))
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "../../../windows/engine/tests/fixtures-windows/answers.json").standardizedFileURL.path)))
    func theMacOpensAVaultWindowsWrote() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let answers = try windowsVault()
        let password = try #require(answers["password"] as? String)
        let state = AppState()

        try await state.unlock(password: password)
        #expect(state.files.count == 5)
        func file(_ name: String) throws -> VaultFile { try #require(state.files.first { $0.name == name }) }
        #expect(try state.read(file("w2.txt")) == source("Taxes/2025/w2.txt"))
        #expect(try file("w2.txt").folder == "Taxes/2025")
        #expect(try state.read(file("photo.bin")) == source("photo.bin"))
        #expect(abs(try file("photo.bin").shownDate.timeIntervalSince1970 - 1_560_000_000) < 1)
        let big = try file("big.bin")
        #expect(big.streamed)
        #expect(try state.read(big) == source("big.bin"))
        #expect(try state.read(file("Shopping")) == Data("milk\neggs\n".utf8))
        let secret = try JSONDecoder().decode(Secret.self, from: state.read(file("Bank")))
        #expect(secret.template == .login)
        #expect(secret.fields.map { "\($0.label): \($0.value)" } == answers["secretLines"] as? [String])
        // The search index Windows wrote reads as the Mac's own ([UUID: Entry] as a flat array).
        #expect(state.words.count == 3)
        #expect(state.words[try file("Shopping").id]?.text == "milk\neggs\n")
        #expect(await state.checkVault { _, _ in }.isEmpty)
        state.lock()

        let recovery = try #require(answers["recovery"] as? String)
        try await state.unlock(recoveryKey: recovery.lowercased())
        #expect(state.files.count == 5 && state.mustSetPassword)
        state.lock()
        let pieces = try #require(answers["pieces"] as? [String])
        try await state.unlock(kitPieces: [pieces[2], pieces[0]])
        #expect(state.files.count == 5)
        state.lock()

        try await state.unlock(password: try #require(answers["decoy"] as? String))
        #expect(state.files.map(\.name) == ["Groceries"])
        #expect(try state.read(state.files[0]) == Data("bread\n".utf8))
        state.lock()
    }

    /// And the Mac can go on using it: a file added on the Mac opens, and Windows' files are all still there.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "../../../windows/engine/tests/fixtures-windows/answers.json").standardizedFileURL.path)))
    func theMacCanKeepUsingAVaultWindowsWrote() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let answers = try windowsVault()
        let password = try #require(answers["password"] as? String)
        let state = AppState()
        try await state.unlock(password: password)
        try await state.add([sample("from the mac.txt", "added on a Mac")])
        state.lock()
        try await state.unlock(password: password)
        #expect(state.files.count == 6)
        #expect(await state.checkVault { _, _ in }.isEmpty)
    }
}
