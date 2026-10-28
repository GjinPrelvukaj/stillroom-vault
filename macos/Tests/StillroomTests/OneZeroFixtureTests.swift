import Foundation
import Testing
@testable import Stillroom

/// A vault Stillroom 1.0.0 wrote (Tests/Fixtures/vault-1.0.0, made by writesFormatFixture on 2026-10-28), opened
/// every way in. Every later version must pass this: a buyer's 1.0 vault has to keep opening. Never regenerate or
/// delete the fixture; if a format change breaks this test, the change needs a way to read 1.0 vaults first.
extension VaultFlowTests {
    private var oneZero: URL {
        URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../Fixtures/vault-1.0.0").standardizedFileURL
    }

    /// The fixture copied into this test's own folder, so the committed one is never written to.
    private func oneZeroVault() throws -> [String: Any] {
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: oneZero.appending(path: "vault"), to: root)
        let answers = try Data(contentsOf: oneZero.appending(path: "answers.json"))
        return try #require(try JSONSerialization.jsonObject(with: answers) as? [String: Any])
    }

    private func oneZeroSource(_ name: String) throws -> Data {
        try Data(contentsOf: oneZero.appending(path: "source/\(name)"))
    }

    @Test func aVaultStillroom1Wrote_stillOpensEveryWayIn() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let answers = try oneZeroVault()
        let state = AppState()

        try await state.unlock(password: try #require(answers["password"] as? String))
        #expect(state.files.count == 5)
        func file(_ name: String) throws -> VaultFile { try #require(state.files.first { $0.name == name }) }
        #expect(try state.read(file("w2.txt")) == oneZeroSource("Taxes/2025/w2.txt"))
        #expect(try file("w2.txt").folder == "Taxes/2025")
        #expect(try state.read(file("photo.bin")) == oneZeroSource("photo.bin"))
        #expect(abs(try file("photo.bin").shownDate.timeIntervalSince1970 - 1_560_000_000) < 1)
        let big = try file("big.bin")
        #expect(big.streamed)
        #expect(try state.read(big) == oneZeroSource("big.bin"))
        #expect(try state.read(file("Shopping")) == Data("milk\neggs\n".utf8))
        let secret = try JSONDecoder().decode(Secret.self, from: state.read(file("Bank")))
        #expect(secret.fields.map { "\($0.label): \($0.value)" } == answers["secretLines"] as? [String])
        #expect(state.words[try file("Shopping").id]?.text == "milk\neggs\n")
        #expect(await state.checkVault { _, _ in }.isEmpty)
        state.lock()

        try await state.unlock(recoveryKey: try #require(answers["recovery"] as? String))
        #expect(state.files.count == 5)
        state.lock()
        let pieces = try #require(answers["pieces"] as? [String])
        try await state.unlock(kitPieces: [pieces[1], pieces[2]])
        #expect(state.files.count == 5)
        state.lock()

        try await state.unlock(password: try #require(answers["decoy"] as? String))
        #expect(state.files.map(\.name) == ["Groceries"])
        #expect(try state.read(state.files[0]) == Data("bread\n".utf8))
        state.lock()
    }
}
