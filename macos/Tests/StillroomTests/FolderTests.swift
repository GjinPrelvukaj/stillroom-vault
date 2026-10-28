import Foundation
import Testing
@testable import Stillroom

/// A dropped folder goes in as every file inside it, each remembering where it was, hidden files and bundles left out.
@Test func aFolderBecomesTheFilesInsideIt() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let taxes = root.appending(path: "Taxes")
    let fm = FileManager.default
    try fm.createDirectory(at: taxes.appending(path: "2025"), withIntermediateDirectories: true)
    try fm.createDirectory(at: taxes.appending(path: "Tool.app/Contents"), withIntermediateDirectories: true)
    try Data("a".utf8).write(to: taxes.appending(path: "notes.txt"))
    try Data("b".utf8).write(to: taxes.appending(path: "2025/w2.pdf"))
    try Data("c".utf8).write(to: taxes.appending(path: ".DS_Store"))
    let alone = root.appending(path: "alone.txt")
    try Data("d".utf8).write(to: alone)
    defer { try? fm.removeItem(at: root) }

    let (items, skipped) = VaultStore.expand([taxes, alone])
    let found = Dictionary(uniqueKeysWithValues: items.map { ($0.url.lastPathComponent, $0.folder) })

    #expect(found.count == 3)
    #expect(found["notes.txt"] == "Taxes")
    #expect(found["w2.pdf"] == "Taxes/2025")
    #expect(found["alone.txt"] == .some(nil))
    #expect(skipped == 1)
}

/// Folders move into folders with everything inside them; never into themselves; a "/" typed in a name stays.
extension VaultFlowTests {
    @Test func foldersMoveIntoFolders() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState()
        try await state.create(password: "real password 123", touchID: false)
        state.makeFolder("26/10/26", in: nil)
        #expect(state.folders.contains("26\u{2215}10\u{2215}26"))
        state.makeFolder("Taxes", in: nil)
        state.makeFolder("2025", in: "Taxes")
        try await state.add([sample("w2.txt", "w2")], into: "Taxes/2025")
        state.makeFolder("Archive", in: nil)

        state.moveFolder("Taxes", into: "Archive")
        #expect(state.files.first?.folder == "Archive/Taxes/2025")
        #expect(state.folders.contains("Archive/Taxes/2025") && !state.folders.contains("Taxes"))

        state.moveFolder("Archive", into: "Archive/Taxes")
        #expect(state.problem != nil)
        #expect(state.files.first?.folder == "Archive/Taxes/2025")
    }
}
