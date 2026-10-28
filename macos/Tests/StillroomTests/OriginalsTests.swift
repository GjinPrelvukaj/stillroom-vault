import Foundation
import Testing
@testable import Stillroom

/// Removing originals: only checked files go, and a folder goes whole only when nothing in it is left out.
extension VaultFlowTests {
    private func folder(_ files: [String: String]) throws -> URL {
        let top = root.deletingLastPathComponent().appending(path: "Originals-\(UUID().uuidString)/Taxes")
        for (path, text) in files {
            let url = top.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        return top
    }

    @Test func folderWithEverythingInGoesWhole() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState()
        try await state.create(password: "real password 123", touchID: false)
        let top = try folder(["w2.txt": "w2", "2025/receipt.txt": "receipt", ".DS_Store": "finder"])
        defer { try? FileManager.default.removeItem(at: top.deletingLastPathComponent()) }

        let added = await state.add([top])
        #expect(added.files.count == 2)
        #expect(added.removals().map(\.lastPathComponent) == ["Taxes"])
        #expect(added.delete().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: top.path))
        #expect(state.files.count == 2)
    }

    @Test func hiddenFilesKeepTheirFolder() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState()
        try await state.create(password: "real password 123", touchID: false)
        let top = try folder(["w2.txt": "w2", ".env": "never went in"])
        defer { try? FileManager.default.removeItem(at: top.deletingLastPathComponent()) }

        let added = await state.add([top])
        #expect(added.removals().map(\.lastPathComponent) == ["w2.txt"])
        #expect(added.delete().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: top.appending(path: "w2.txt").path))
        #expect(FileManager.default.fileExists(atPath: top.appending(path: ".env").path))
    }

    @Test func copiesAreCheckedAgainstTheirOriginals() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState()
        try await state.create(password: "real password 123", touchID: false)
        // Small (one piece) and big (streamed in chunks).
        let small = try sample("note.txt", "hello")
        let big = root.deletingLastPathComponent().appending(path: "\(UUID().uuidString)-big.bin")
        try Data((0..<(9 << 20)).map { UInt8(truncatingIfNeeded: $0 &* 31) }).write(to: big)
        defer { try? FileManager.default.removeItem(at: big) }

        let added = await state.add([small, big])
        #expect(added.files.count == 2)
        let bigFile = try #require(state.files.first { $0.name.hasSuffix("big.bin") })
        #expect(bigFile.streamed)
        #expect(Originals.matches(bigFile, original: big, sealed: try state.seal(of: bigFile), slot: state.slot))

        // The original changes after sealing: it no longer matches, so it would never be offered for deletion.
        try Data("hellO".utf8).write(to: small)
        let smallFile = try #require(state.files.first { $0.name.hasSuffix("note.txt") })
        #expect(!Originals.matches(smallFile, original: small, sealed: try state.seal(of: smallFile), slot: state.slot))
    }
}
