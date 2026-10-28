import Foundation
import Testing
@testable import Stillroom

/// Each test gets a desk of its own in a temp folder (its own small RAM disk), and no app is ever opened.
@MainActor @Suite(.serialized) struct EditDeskTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "EditDeskTests-\(UUID().uuidString)")
    var mountPoint: String { root.appending(path: "Desk").path }

    private func desk(ram: Bool = true, bytes: Int = 16 << 20) -> EditDesk {
        let desk = EditDesk(root: root)
        desk.opener = { _ in }
        desk.useRAMDisk = ram
        desk.ramDiskBytes = bytes
        desk.tick = .milliseconds(200)
        return desk
    }

    private func mounted(_ path: String) -> Bool {
        FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil)?
            .contains { $0.path.hasSuffix(path.replacingOccurrences(of: "/private", with: "")) } == true
    }

    /// Waits a few ticks, long enough for a change to be seen and to hold still.
    private func settle() async throws { try await Task.sleep(for: .milliseconds(900)) }

    /// Edited in place and saved by swapping a new file in: each is one save, read back with its new contents.
    @Test(arguments: [true, false]) func eachSaveIsSeenOnce(ram: Bool) async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let desk = desk(ram: ram)
        defer { desk.clearAll() }
        var saves: [String] = []
        let id = UUID()
        let file = try await desk.open(id: id, name: "notes.txt", write: { try Data("first".utf8).write(to: $0) },
                                 onSave: { saves.append((try? String(contentsOf: $0, encoding: .utf8)) ?? "") })
        #expect(file.lastPathComponent == "notes.txt")
        #expect(desk.open[id] == file)
        #expect(file.path.contains("/Desk/") == ram)
        #expect(mounted(mountPoint) == ram)
        try await settle()
        #expect(saves.isEmpty)

        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(" edit".utf8))
        try handle.close()
        try await settle()
        #expect(saves == ["first edit"])

        try Data("second, swapped in".utf8).write(to: file, options: .atomic)
        try await settle()
        #expect(saves == ["first edit", "second, swapped in"])

        // Saved just before Done: the last check still catches it.
        try Data("third".utf8).write(to: file, options: .atomic)
        desk.finish(id: id)
        #expect(saves.last == "third")
        #expect(saves.count == 3)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(desk.open.isEmpty)
    }

    /// Too big for the RAM disk: it goes to the overflow folder instead, and clearAll takes everything away.
    @Test func tooBigGoesToOverflowAndClearAllEjects() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let desk = desk(bytes: 8 << 20)
        let small = try await desk.open(id: UUID(), name: "small.txt", write: { try Data("hi".utf8).write(to: $0) }, onSave: { _ in })
        let big = try await desk.open(id: UUID(), name: "big.bin", write: { try Data(count: 12 << 20).write(to: $0) }, onSave: { _ in })
        #expect(small.path.contains("/Desk/"))
        #expect(big.path.contains("/DeskOverflow/"))
        #expect((try? Data(contentsOf: big).count) == 12 << 20)
        #expect(mounted(mountPoint))

        desk.clearAll()
        await desk.ejecting?.value
        #expect(!mounted(mountPoint))
        #expect(!FileManager.default.fileExists(atPath: big.path))
        #expect(!FileManager.default.fileExists(atPath: small.path))
        #expect(desk.open.isEmpty)
    }

    /// A desk left mounted by a run that crashed is ejected at the next launch.
    @Test func leftoversAreClearedAtLaunch() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let crashed = desk()
        _ = try await crashed.open(id: UUID(), name: "a.txt", write: { try Data("a".utf8).write(to: $0) }, onSave: { _ in })
        #expect(mounted(mountPoint))

        let next = desk()
        next.clearLeftovers()
        await next.ejecting?.value
        #expect(!mounted(mountPoint))
    }

    /// Locked while a preview's RAM disk was still mounting: nothing is written, and the disk goes.
    @Test func lockingWhileMountingWritesNothing() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let desk = desk()
        let staging = Task { try await desk.stage(id: UUID(), name: "a.txt") { try Data("secret".utf8).write(to: $0) } }
        try await Task.sleep(for: .milliseconds(50))
        desk.clearAll()
        await #expect(throws: CancellationError.self) { _ = try await staging.value }
        await desk.ejecting?.value
        #expect(!mounted(mountPoint))
    }
}
