import Foundation

/// Backups stay on this Mac or a disk you plug in: one file holding the whole vault folder, in Stillroom's own plain format. Everything in the folder
/// is already sealed, so the file needs no sealing of its own; it opens with the vault's password (or, on another
/// Mac when the vault is locked to this one, its recovery key).
enum Backup {
    static let fileExtension = "stillroombackup"

    enum Problem: LocalizedError {
        case noVault, notABackup, couldNotWrite, busy

        var errorDescription: String? {
            switch self {
            case .noVault: "There's no vault to back up yet."
            case .notABackup: "That file isn't a Stillroom backup."
            case .couldNotWrite: "The backup couldn't be written there. Check the disk is plugged in and has room."
            case .busy: "The vault kept changing while the backup was made. Wait for edits to finish, then try again."
            }
        }
    }

    /// A name like "Stillroom Backup 2026-10-23.stillroombackup".
    static func suggestedName(on date: Date = .now) -> String {
        "Stillroom Backup \(stamp(date, "yyyy-MM-dd")).\(fileExtension)"
    }

    /// Writes the whole vault folder into one file at `url` (written to a temp file first, then moved into place).
    static func make(to url: URL) throws {
        guard VaultStore.exists else { throw Problem.noVault }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        // Next to where it's going, so the last step is a rename on the same disk, never a half-copied file.
        let temp = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                               appropriateFor: url.deletingLastPathComponent(), create: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let written = temp.appending(path: url.lastPathComponent)
        do { try pack(VaultStore.root, into: written) } catch { throw Problem.couldNotWrite }
        // Only you can read it, wherever it's kept: anyone with a copy can try passwords against it offline.
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: written.path)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: written)
        } else {
            try FileManager.default.moveItem(at: written, to: url)
        }
        lastBackup = .now
    }

    /// Checks a file is a Stillroom backup (it unpacks to a folder holding both slots' password keys) without touching the live vault.
    static func check(_ url: URL) throws {
        let temp = try unpack(url, near: FileManager.default.temporaryDirectory)
        try? FileManager.default.removeItem(at: temp.dir)
    }

    /// Puts the vault back from a backup. The backup is staged beside the vault first, then the two folders swap in
    /// one step, so a crash at any moment leaves a whole vault in place: the old one, or the restored one with the old
    /// one beside it as "Store-before-restore-<timestamp>" (never deleted). Returns that set-aside URL (nil if there
    /// was no vault).
    @discardableResult static func restore(from url: URL) throws -> URL? {
        let fm = FileManager.default
        let root = VaultStore.root
        let staged = try stage(url)
        if fm.fileExists(atPath: root.path) {
            do { try swap(staged, root) } catch {
                // Nothing live was touched; the staged copy is only the backup's.
                try? fm.removeItem(at: staged)
                throw error
            }
        } else {
            try fm.moveItem(at: staged, to: root)
        }
        // Only you can list or read it.
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        for slot in VaultStore.Slot.allCases where fm.fileExists(atPath: slot.files.path) {
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: slot.files.path)
        }
        return fm.fileExists(atPath: staged.path) ? staged : nil
    }

    /// The backup unpacked and checked on the vault's own disk, then renamed beside the vault under the name the
    /// current vault takes once it's set aside. Nothing live is touched.
    static func stage(_ url: URL) throws -> URL {
        let fm = FileManager.default
        let parent = VaultStore.root.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let unpacked = try unpack(url, near: parent)
        defer { try? fm.removeItem(at: unpacked.dir) }
        let base = "Store-before-restore-\(stamp(.now, "yyyy-MM-dd-HHmmss"))"
        var spot = parent.appending(path: base, directoryHint: .isDirectory)
        var n = 2
        while fm.fileExists(atPath: spot.path) {
            spot = parent.appending(path: "\(base)-\(n)", directoryHint: .isDirectory)
            n += 1
        }
        try fm.moveItem(at: unpacked.vault, to: spot)
        return spot
    }

    /// Two folders on the same disk swapped in one step: at every moment each name holds a whole folder.
    static func swap(_ a: URL, _ b: URL) throws {
        guard renamex_np(a.path, b.path, UInt32(RENAME_SWAP)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    /// When the last backup was made, remembered in UserDefaults (key "lastBackup").
    static var lastBackup: Date? {
        get { UserDefaults.standard.object(forKey: "lastBackup") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastBackup") }
    }

    // MARK: -

    // MARK: The backup format
    //
    // Stillroom's own, and deliberately plain: a mark, then each file as (path length, path, size, bytes), then a zero.
    // It can hold nothing but regular files at simple paths inside the vault folder: no links, no folders of its own,
    // no paths that climb out. So unpacking can't be tricked into writing anywhere else, whoever made the file.

    private static let mark = Data("STILLBK1".utf8)

    /// Streams every regular file under `folder` into `file`; big videos never sit whole in memory.
    private static func pack(_ folder: URL, into file: URL) throws {
        guard FileManager.default.createFile(atPath: file.path, contents: nil),
              let out = try? FileHandle(forWritingTo: file) else { throw Problem.couldNotWrite }
        defer { try? out.close() }
        try out.write(contentsOf: mark)
        let base = folder.resolvingSymlinksInPath().pathComponents.count
        let walk = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        while let item = walk?.nextObject() as? URL {
            guard isPlainFile(item) else { continue }
            let path = item.resolvingSymlinksInPath().pathComponents.dropFirst(base).joined(separator: "/")
            guard isSafePath(path), let input = try? FileHandle(forReadingFrom: item) else { continue }
            defer { try? input.close() }
            let size = try input.seekToEnd()
            try input.seek(toOffset: 0)
            try out.write(contentsOf: number(UInt64(Data(path.utf8).count), bytes: 2) + Data(path.utf8) + number(size, bytes: 8))
            var left = size
            while left > 0, let piece = try input.read(upToCount: Int(min(left, 1 << 20))), !piece.isEmpty {
                try out.write(contentsOf: piece)
                left -= UInt64(piece.count)
            }
            guard left == 0 else { throw Problem.couldNotWrite }
        }
        try out.write(contentsOf: number(0, bytes: 2))
    }

    /// Unpacks into a fresh temp folder (a folder named Store inside it). Throws `.notABackup` for anything that
    /// isn't exactly what `pack` writes, or that has no password key.
    private static func unpack(_ url: URL, near place: URL) throws -> (dir: URL, vault: URL) {
        let fm = FileManager.default
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let dir = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: place, create: true)
        let vault = dir.appending(path: "Store", directoryHint: .isDirectory)
        do {
            guard let input = try? FileHandle(forReadingFrom: url) else { throw Problem.notABackup }
            defer { try? input.close() }
            let total = try input.seekToEnd()
            try input.seek(toOffset: 0)
            guard try input.read(upToCount: mark.count) == mark else { throw Problem.notABackup }
            try fm.createDirectory(at: vault, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            while true {
                let length = try readNumber(input, bytes: 2)
                if length == 0 { break }
                guard let raw = try input.read(upToCount: Int(length)), raw.count == Int(length),
                      let path = String(data: raw, encoding: .utf8), isSafePath(path) else { throw Problem.notABackup }
                let size = try readNumber(input, bytes: 8)
                guard size <= total - (try input.offset()) else { throw Problem.notABackup }
                let target = vault.appending(path: path)
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true,
                                       attributes: [.posixPermissions: 0o700])
                // A path given twice would mean a doctored file.
                guard !fm.fileExists(atPath: target.path), fm.createFile(atPath: target.path, contents: nil,
                                                                       attributes: [.posixPermissions: 0o600]),
                      let out = try? FileHandle(forWritingTo: target) else { throw Problem.notABackup }
                defer { try? out.close() }
                var left = size
                while left > 0 {
                    guard let piece = try input.read(upToCount: Int(min(left, 1 << 20))), !piece.isEmpty else { throw Problem.notABackup }
                    try out.write(contentsOf: piece)
                    left -= UInt64(piece.count)
                }
            }
            guard VaultStore.Slot.allCases.allSatisfy({ isPlainFile(vault.appending(path: "\($0.rawValue)/password.key")) }), isPlainTree(vault) else { throw Problem.notABackup }
            return (dir, vault)
        } catch {
            try? fm.removeItem(at: dir)
            throw error is Problem ? error : Problem.notABackup
        }
    }

    /// A path inside the vault folder as the vault writes them: a few plain names, letters, digits, dots, dashes.
    private static func isSafePath(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")
        return !parts.isEmpty && parts.count <= 3 && parts.allSatisfy { part in
            !part.isEmpty && part != "." && part != ".." && part.count <= 120 && part.allSatisfy { allowed.contains($0) }
        }
    }

    private static func number(_ value: UInt64, bytes: Int) -> Data {
        Data((0..<bytes).reversed().map { UInt8(truncatingIfNeeded: value >> (8 * UInt64($0))) })
    }

    private static func readNumber(_ input: FileHandle, bytes: Int) throws -> UInt64 {
        guard let raw = try input.read(upToCount: bytes), raw.count == bytes else { throw Problem.notABackup }
        return raw.reduce(0) { $0 << 8 | UInt64($1) }
    }

    /// Only plain files and folders, the folder itself included.
    private static func isPlainTree(_ folder: URL) -> Bool {
        guard isPlainFolder(folder),
              let walk = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey,
                                                                                               .isRegularFileKey, .isDirectoryKey])
        else { return false }
        for case let item as URL in walk where !isPlainFile(item) && !isPlainFolder(item) { return false }
        return true
    }

    private static func isPlainFolder(_ url: URL) -> Bool {
        let v = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        return v?.isSymbolicLink == false && v?.isDirectory == true
    }

    private static func isPlainFile(_ url: URL) -> Bool {
        let v = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        return v?.isSymbolicLink == false && v?.isRegularFile == true
    }

    private static func stamp(_ date: Date, _ format: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f.string(from: date)
    }
}
