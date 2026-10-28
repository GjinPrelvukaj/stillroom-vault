import Foundation
import Testing
@testable import Stillroom

extension VaultFlowTests {
    @Test func exportAllTakesEverythingOutWithDates() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState()
        try await state.create(password: "real password 123", touchID: false)
        let photo = try sample("photo.jpg", "pixels")
        let old = Date(timeIntervalSince1970: 1_560_000_000)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: photo.path)
        try await state.add([photo], into: "Trips/2019")
        _ = state.newEntry(.note, name: "../../escape", content: Data("not out".utf8))
        state.makeFolder("Empty", in: nil)

        let out = root.deletingLastPathComponent().appending(path: "Export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: out) }
        let top = try await state.exportAll(into: out) { _, _ in }

        let copied = try #require(try FileManager.default.contentsOfDirectory(at: top.appending(path: "Trips/2019"), includingPropertiesForKeys: nil).first)
        #expect(try Data(contentsOf: copied) == Data("pixels".utf8))
        let date = try copied.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        #expect(abs((date ?? .now).timeIntervalSince(old)) < 1)
        // A name trying to climb out stays inside the export folder.
        #expect(FileManager.default.fileExists(atPath: top.appending(path: "..:..:escape.md").path))
        #expect(FileManager.default.fileExists(atPath: top.appending(path: "Empty").path))
    }

    @Test func kitPiecesOpenTheVaultAndOldKitsStopWorking() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState()
        try await state.create(password: "real password 123", touchID: false)
        let old = try await state.makeKit(threshold: 2, count: 3)
        let pieces = try await state.makeKit(threshold: 3, count: 5)
        state.lock()

        await #expect(throws: EmergencyKit.Problem.notEnough(3)) { try await state.unlock(kitPieces: [pieces[0], pieces[4]]) }
        await #expect(throws: VaultError.wrongKit) { try await state.unlock(kitPieces: [old[0], old[1]]) }
        try await state.unlock(kitPieces: [pieces[4], pieces[1], pieces[2]])
        #expect(state.isOpen && state.mustSetPassword)
    }
}
