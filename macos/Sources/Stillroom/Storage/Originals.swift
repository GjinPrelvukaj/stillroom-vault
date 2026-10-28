import AppKit
import CryptoKit
import Foundation

/// What was added from disk, once it's safely in: only files whose sealed copy read back byte for byte, so they can
/// be deleted for good (or moved to the Trash) without losing anything.
struct Originals: Sendable {
    /// Files whose sealed copy was checked against them.
    var files: [URL] = []
    /// Folders added whole. One goes whole only when every file in it is among `files`; otherwise just its checked
    /// files go, and anything that never went in (hidden files, links, apps) stays where it is.
    var folders: [URL] = []

    var isEmpty: Bool { files.isEmpty }
    /// iCloud Drive keeps what's deleted in Recently Deleted for 30 days, out of Vault's reach.
    var fromICloud: Bool { files.contains { $0.path.contains("/Library/Mobile Documents/") } }

    /// Whether a sealed copy reads back exactly as the file it came from: same size, same SHA-256. Streamed a MiB at
    /// a time on both sides, so a big video is never whole in memory.
    static func matches(_ file: VaultFile, original url: URL, sealed seal: ItemSeal, slot: VaultStore.Slot) -> Bool {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size == file.size,
              let source = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? source.close() }
        var original = SHA256()
        var sealed = SHA256()
        do {
            while let piece = try source.read(upToCount: 1 << 20), !piece.isEmpty { original.update(data: piece) }
            if file.streamed {
                let reader = try ChunkedReader(url: VaultStore.blob(seal.blob, slot), key: seal.key,
                                               fileID: seal.chunkID, plainSize: file.size)
                var at = 0
                while at < file.size {
                    sealed.update(data: try reader.read(at..<min(at + reader.chunkSize, file.size)))
                    at += reader.chunkSize
                }
            } else {
                sealed.update(data: try VaultStore.open(seal, size: file.size, slot: slot))
            }
        } catch {
            return false
        }
        return original.finalize() == sealed.finalize()
    }

    /// What actually gets removed: covered folders whole, and every other checked file on its own.
    func removals() -> [URL] {
        let checked = Set(files.map(Self.path))
        let whole = folders.filter { Self.covered($0, by: checked) }
        let inside = whole.map { Self.path($0) + "/" }
        // ponytail: a folder that isn't covered keeps its emptied subfolders; tidy them if that bothers anyone.
        return whole + files.filter { file in !inside.contains { Self.path(file).hasPrefix($0) } }
    }

    /// Deleted for good, skipping the Trash. Returns the names that couldn't be.
    func delete() -> [String] {
        removals().compactMap { url in (try? FileManager.default.removeItem(at: url)) == nil ? url.lastPathComponent : nil }
    }

    @MainActor func trash() async throws {
        _ = try await NSWorkspace.shared.recycle(removals())
    }

    /// FileVault on means a deleted file's leftovers on the disk are encrypted, so unreadable. Asked of the Mac each
    /// time (it can be turned off); "in progress" or no answer counts as off.
    static var fileVaultOn: Bool {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/fdesetup")
        process.arguments = ["status"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return false }
        let said = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return said.contains("FileVault is On")
    }

    /// Every file in the folder, hidden ones too, is a checked one (Finder's .DS_Store aside). A link, an app or any
    /// file that didn't go in keeps the folder.
    private static func covered(_ folder: URL, by checked: Set<String>) -> Bool {
        guard let walk = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
        else { return false }
        for case let item as URL in walk {
            let kind = try? item.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
            if kind?.isSymbolicLink == true { return false }
            if kind?.isDirectory == true || item.lastPathComponent == ".DS_Store" { continue }
            if kind?.isRegularFile == true, checked.contains(path(item)) { continue }
            return false
        }
        return true
    }

    private static func path(_ url: URL) -> String { url.resolvingSymlinksInPath().standardizedFileURL.path }
}
