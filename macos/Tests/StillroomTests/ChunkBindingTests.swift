import Foundation
import Testing
@testable import Stillroom

extension VaultFlowTests {
    /// An older version's chunks, or the whole older version, copied over the current streamed file: refused, because
    /// every sealing ties its chunks to an id of its own. (Before, versions shared one, and both were accepted.)
    @Test func olderVersionsCantBePassedOffAsTheCurrentOne() async throws {
        let state = AppState()
        try await state.create(password: "real password 123", touchID: false)
        let chunk = Chunked.chunkSize
        let first = Data((0..<(3 * chunk + 5)).map { UInt8(truncatingIfNeeded: $0 &* 7) })
        try await state.add([sample("clip.mp3", first)])
        // Old enough that the next change keeps a version.
        let key = try #require(state.keyForTests)
        let cover = try #require(state.coverForTests)
        var (index, keys) = try VaultStore.loadManifest(using: key, slot: state.slot, cover: cover)
        index.files[0].addedAt = .now.addingTimeInterval(-3600)
        try VaultStore.saveManifest(index, using: key, itemKeys: keys, slot: state.slot, cover: cover)
        state.lock()
        try await state.unlock(password: "real password 123")

        let second = Data((0..<(3 * chunk + 1000)).map { UInt8(truncatingIfNeeded: $0 &* 13) })
        state.update(state.files[0].id, from: try sample("clip.mp3", second))
        let file = state.files[0]
        let version = try #require(file.versions?.last)
        #expect(try state.read(file) == second)
        #expect(try state.readVersion(version) == first)

        let current = VaultStore.blob(try state.seal(of: file).blob, state.slot)
        let older = VaultStore.blob(try state.seal(of: version).blob, state.slot)
        let header = 8, sealedChunk = chunk + 28
        var mixed = try Data(contentsOf: current)
        let old = try Data(contentsOf: older)
        mixed.replaceSubrange((header + sealedChunk)..<(header + 2 * sealedChunk), with: old[(header + sealedChunk)..<(header + 2 * sealedChunk)])
        try mixed.write(to: current)
        #expect(throws: (any Error).self) { try state.read(file) }

        try old.write(to: current)
        #expect(throws: (any Error).self) { try state.read(file) }
        #expect(await state.checkVault { _, _ in }.contains { $0.file.id == file.id })
    }
}
