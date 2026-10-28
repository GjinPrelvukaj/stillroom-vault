import AppKit
import Foundation
import Observation

/// Edit in place: a file from the vault is opened in its own app (Preview, Pages, TextEdit…), and each time that app
/// saves, the caller re-seals it. The working copy lives on a RAM disk Stillroom makes and ejects, so the plaintext never
/// touches the SSD.
///
/// An item too big for what's free on the RAM disk (1 GiB by default) goes to a 0700 folder in
/// ~/Library/Caches/app.gjin.stillroom/DeskOverflow instead: that is on the SSD, protected only by FileVault, and is
/// deleted when the item is finished.
///
///     Desk/                    the RAM disk's mount point (hidden from Finder: mounted "nobrowse")
///       <UUID>.noindex/name    one folder per item, the file under its own name so the app's title is right
///     DeskOverflow/<UUID>.noindex/name
///
/// The folders end in .noindex so Spotlight keeps the plaintext out of its index.
@MainActor @Observable final class EditDesk {
    static let shared = EditDesk()

    /// Items being edited right now, for the UI ("Editing 2 files — Done").
    private(set) var open: [UUID: URL] = [:]

    /// How a working copy is shown to the person. Tests swap it so no app opens.
    @ObservationIgnored var opener: (URL) -> Void = { NSWorkspace.shared.open($0) }
    /// Off: everything goes to the overflow folder. For places a RAM disk can't be made.
    @ObservationIgnored var useRAMDisk = true
    @ObservationIgnored var ramDiskBytes = 1 << 30
    /// How often each working copy is looked at; a save is reported once the file has held still this long.
    @ObservationIgnored var tick: Duration = .seconds(1)

    private let mountPoint: URL
    private let overflow: URL
    @ObservationIgnored private var items: [UUID: Item] = [:]
    @ObservationIgnored private var watching: Task<Void, Never>?
    /// An eject running in the background; a mount waits for it, so files never land on a disk that's going away.
    @ObservationIgnored private(set) var ejecting: Task<Void, Never>?
    /// Counts clearAll()s: an open or stage that waited on a mount checks it, and writes nothing if the vault locked
    /// (and the desk was cleared) meanwhile.
    @ObservationIgnored private var clears = 0
    /// Copies put out only to be looked at (Quick Look): not opened in an app, not watched.
    @ObservationIgnored private var staged: [UUID: URL] = [:]

    private struct Item {
        let file: URL
        let folder: URL
        let onSave: (URL) -> Void
        /// What the file looked like when last handed to onSave (or when it was put on the desk).
        var saved: Signature?
        /// What it looked like on the last tick: a change is reported only once it stops changing.
        var seen: Signature?
    }

    /// Apps often save by writing a new file and renaming it over the old, so the inode is part of it too.
    private struct Signature: Equatable {
        let modified: Date
        let size: Int
        let inode: Int
    }

    init(root: URL = URL.cachesDirectory.appending(path: "app.gjin.stillroom", directoryHint: .isDirectory)) {
        mountPoint = root.appending(path: "Desk", directoryHint: .isDirectory)
        overflow = root.appending(path: "DeskOverflow", directoryHint: .isDirectory)
    }

    // MARK: On and off the desk

    /// Puts a working copy of an item on the desk and opens it in its default app. `write` fills the given file URL
    /// with the plaintext (the caller streams it in). `onSave` is called (on the main actor) each time the app saves
    /// the file, with the file's URL, so the caller can re-seal it. Returns the working copy's URL.
    @discardableResult
    func open(id: UUID, name: String, write: (URL) throws -> Void, onSave: @escaping (URL) -> Void) async throws -> URL {
        // Already out: show it again rather than writing over edits.
        if let item = items[id] { opener(item.file); return item.file }

        let place: URL
        if useRAMDisk {
            try await mountedSinceLastClear()
            place = mountPoint
        } else {
            place = overflow
        }
        var item: Item
        do {
            item = try put(id: id, name: name, in: place, write: write, onSave: onSave)
        } catch where place == mountPoint && Self.outOfSpace(error) {
            item = try put(id: id, name: name, in: overflow, write: write, onSave: onSave)
        }
        item.saved = signature(item.file)
        item.seen = item.saved
        items[id] = item
        open[id] = item.file
        watch()
        opener(item.file)
        return item.file
    }

    /// Stops watching an item and deletes its working copy (after one last save check).
    func finish(id: UUID) {
        guard let item = items.removeValue(forKey: id) else { return }
        open[id] = nil
        if let now = signature(item.file), now != item.saved { item.onSave(item.file) }
        try? FileManager.default.removeItem(at: item.folder)
        if items.isEmpty {
            watching?.cancel()
            watching = nil
        }
        ejectIfEmpty()
    }

    /// Puts a copy out just to be looked at (Quick Look shows it): on the RAM disk like an edit, but no app is
    /// opened and nothing is watched. Returns the copy's URL; `unstage` deletes it.
    func stage(id: UUID, name: String, write: (URL) throws -> Void) async throws -> URL {
        if let folder = staged[id] { return folder.appending(path: Self.safeName(name)) }
        let place: URL
        if useRAMDisk {
            try await mountedSinceLastClear()
            place = mountPoint
        } else {
            place = overflow
        }
        // Never the overflow folder for a look: a copy that doesn't fit in memory isn't shown, rather than written
        // to the SSD.
        let item = try put(id: UUID(), name: name, in: place, write: write, onSave: { _ in })
        staged[id] = item.folder
        return item.file
    }

    /// The copy goes at once; the RAM disk stays until the vault locks. Ejecting while Quick Look still holds the
    /// file can take a long while, and the next look would only mount it again.
    func unstage(id: UUID) {
        guard let folder = staged.removeValue(forKey: id) else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    /// Nothing left out: the RAM disk goes, and the memory with it.
    private func ejectIfEmpty() {
        if items.isEmpty && staged.isEmpty { ejectRAMDisk() }
    }

    /// Everything off the desk: last save checks, working copies deleted, the RAM disk ejected. Called when the
    /// vault locks or the app quits.
    func clearAll() {
        clears += 1
        for id in Array(items.keys) { finish(id: id) }
        for id in Array(staged.keys) { unstage(id: id) }
        ejectRAMDisk()
        try? FileManager.default.removeItem(at: overflow)
    }

    /// At launch: a desk left behind by a run that crashed is ejected, and any overflow copies deleted.
    func clearLeftovers() {
        ejectRAMDisk()
        try? FileManager.default.removeItem(at: overflow)
    }

    private func put(id: UUID, name: String, in place: URL, write: (URL) throws -> Void,
                     onSave: @escaping (URL) -> Void) throws -> Item {
        let folder = place.appending(path: "\(id.uuidString).noindex", directoryHint: .isDirectory)
        // The RAM disk must still be there: ejected from outside since it was checked, a folder made here would land on
        // the SSD in the empty mount point. So it's checked again, and no folder above the copy's own is ever made.
        let onDesk = place == mountPoint
        if onDesk {
            guard Self.isMounted(place) else { throw DeskError("The in-memory desk went away. Try again.") }
        } else {
            try FileManager.default.createDirectory(at: place, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        let file = folder.appending(path: Self.safeName(name))
        do {
            try write(file)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        return Item(file: file, folder: folder, onSave: onSave)
    }

    // MARK: Seeing saves

    private func watch() {
        guard watching == nil else { return }
        watching = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.tick ?? .seconds(1))
                self?.look()
            }
        }
    }

    /// One look at every item: a file that changed and then held still for a tick is one save.
    private func look() {
        for (id, var item) in items {
            // Missing for a moment while an app swaps the new file in: wait for it to land.
            guard let now = signature(item.file) else { continue }
            if now != item.saved, now == item.seen {
                item.saved = now
                items[id] = item
                item.onSave(item.file)
            }
            // onSave may have finished the item; don't bring it back.
            if items[id] != nil { items[id]?.seen = now }
        }
    }

    private func signature(_ url: URL) -> Signature? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = a[.modificationDate] as? Date, let size = a[.size] as? Int,
              let inode = a[.systemFileNumber] as? Int else { return nil }
        return Signature(modified: modified, size: size, inode: inode)
    }

    // MARK: The RAM disk

    /// Mounts, and throws if the desk was cleared (the vault locked) while that was going on: nothing is put out then.
    private func mountedSinceLastClear() async throws {
        let before = clears
        try await mountRAMDisk()
        guard clears == before else {
            ejectRAMDisk()
            throw CancellationError()
        }
    }

    /// hdiutil and diskutil can take seconds, so they never run on the main thread.
    private func mountRAMDisk() async throws {
        await ejecting?.value
        // Checked every time: ejected from outside, the mount point is just a folder on the SSD.
        if Self.isMounted(mountPoint) { return }
        let (bytes, mountPoint) = (ramDiskBytes, mountPoint)
        let started = Date()
        ActivityLog.note("RAM disk: mounting", action: false)
        try await Task.detached(priority: .userInitiated) { try Self.makeRAMDisk(bytes: bytes, at: mountPoint) }.value
        ActivityLog.note("RAM disk: mounted in \(Int(Date().timeIntervalSince(started) * 1000)) ms", action: false)
    }

    nonisolated private static func makeRAMDisk(bytes ramDiskBytes: Int, at mountPoint: URL) throws {
        let made = try Self.run("/usr/bin/hdiutil", "attach", "-nomount", "ram://\(ramDiskBytes / 512)")
        guard let dev = made.split(whereSeparator: \.isWhitespace).first.map(String.init), dev.hasPrefix("/dev/disk")
        else { throw DeskError("Couldn't make the in-memory desk: hdiutil gave no disk.") }
        do {
            _ = try Self.run("/sbin/newfs_hfs", "-v", "Stillroom Desk", dev)
            try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: mountPoint.deletingLastPathComponent().path)
            // nobrowse keeps it off the desktop and out of Finder's sidebar.
            _ = try Self.run("/usr/sbin/diskutil", "mount", "-mountOptions", "nobrowse", "-mountPoint", mountPoint.path, dev)
            // The volume ignores owners, so its own root is shut to everyone but this account.
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: mountPoint.path)
            guard Self.isMounted(mountPoint) else { throw DeskError("Couldn't make the in-memory desk: it didn't mount.") }
        } catch {
            _ = try? Self.run("/usr/bin/hdiutil", "detach", "-force", dev)
            throw error
        }
    }

    /// By mount point, not /dev/diskN: once ejected from outside, that number can belong to someone's USB drive.
    /// In the background: with a file still held open (Quick Look), hdiutil can take a long while.
    private func ejectRAMDisk() {
        let (mountPoint, previous) = (mountPoint, ejecting)
        ejecting = Task.detached(priority: .utility) {
            await previous?.value
            guard Self.isMounted(mountPoint) else { return }
            let started = Date()
            ActivityLog.note("RAM disk: ejecting", action: false)
            _ = try? Self.run("/usr/bin/hdiutil", "detach", "-force", mountPoint.path)
            ActivityLog.note("RAM disk: ejected in \(Int(Date().timeIntervalSince(started) * 1000)) ms", action: false)
        }
    }

    /// At quit: waited for, since nothing comes after it.
    func ejectNow() {
        if Self.isMounted(mountPoint) { _ = try? Self.run("/usr/bin/hdiutil", "detach", "-force", mountPoint.path) }
    }

    /// True when a volume is mounted right at this folder (statfs, so nothing cached).
    nonisolated private static func isMounted(_ url: URL) -> Bool {
        guard let real = realpath(url.path, nil) else { return false }
        defer { free(real) }
        var fs = statfs()
        guard statfs(real, &fs) == 0 else { return false }
        let on = withUnsafeBytes(of: fs.f_mntonname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return on == String(cString: real)
    }

    // MARK: Small things

    /// Runs a system tool and returns what it printed; a non-zero exit is thrown with what it said.
    @discardableResult
    nonisolated private static func run(_ tool: String, _ args: String...) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = args
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let printed = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let said = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let why = said.split(separator: "\n").last { !$0.contains("deprecated") } ?? "exit \(process.terminationStatus)"
            throw DeskError("Couldn't make the in-memory desk (\(URL(filePath: tool).lastPathComponent): \(why)).")
        }
        return printed
    }

    /// The disk filled up while the plaintext was going in.
    nonisolated private static func outOfSpace(_ error: Error) -> Bool {
        let e = error as NSError
        if e.domain == NSPOSIXErrorDomain, e.code == Int(ENOSPC) { return true }
        if e.domain == NSCocoaErrorDomain, e.code == NSFileWriteOutOfSpaceError { return true }
        return (e.userInfo[NSUnderlyingErrorKey] as? Error).map(outOfSpace) ?? false
    }

    /// A name can't climb out of its folder.
    nonisolated private static func safeName(_ name: String) -> String {
        // ":" on disk is what Finder and other apps show as "/".
        let flat = name.replacingOccurrences(of: "\u{2215}", with: "/").replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: "/", with: ":")
        return flat.isEmpty || flat == "." || flat == ".." ? "Untitled" : flat
    }
}

struct DeskError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
