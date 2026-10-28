import CryptoKit
import Foundation
import UniformTypeIdentifiers

/// Where the vault lives: one folder that grows and shrinks with what's in it, every file in it sealed (format 4).
///
///     a/, b/                   two slots, built exactly alike, neither marked as yours (see `Slot`):
///       password.key           the slot key, sealed with the slot's stretched password
///       recovery.key           the slot key, sealed with the stretched recovery key
///       kit.key                the slot key, sealed with the emergency kit's secret
///       cover.key              the cover key (the same in both slots), sealed with the slot key
///       list, search           the slot's list and search index, each inside a cover (see `writeCovered`)
///     intruder.pub, intruder/  the intruder log, sealed to both slots
///     touchid.key              Touch ID's way into one slot, when on
///     mac.key                  this Mac's Enclave key, when the vault is locked to this Mac
///     Files/                   both slots' items, each sealed with a key of its own, named so only a slot can tell its own
///
/// A slot key is 32 random bytes made with its slot; it is never written down unsealed. A slot nobody set is a real
/// slot whose passwords nobody knows, so it can't be told from one set and left empty.
enum VaultStore {
    /// Each password opens one of two slots. Which one is yours is picked at random when the vault is made and
    /// written nowhere: the letters say nothing.
    enum Slot: String, CaseIterable, Sendable {
        case a, b

        var folder: URL { VaultStore.root.appending(path: rawValue, directoryHint: .isDirectory) }
        var keyFile: URL { folder.appending(path: "password.key") }
        var recoveryFile: URL { folder.appending(path: "recovery.key") }
        var kitFile: URL { folder.appending(path: "kit.key") }
        var coverFile: URL { folder.appending(path: "cover.key") }
        var manifest: URL { folder.appending(path: "list") }
        var search: URL { folder.appending(path: "search") }
        var other: Slot { self == .a ? .b : .a }
        /// Where its items lie: one folder shared by both slots.
        var files: URL { VaultStore.root.appending(path: "Files", directoryHint: .isDirectory) }
        /// Where a new slot is made before it's swapped in.
        var staging: URL { VaultStore.root.appending(path: ".\(rawValue)-new", directoryHint: .isDirectory) }
    }

    /// Tests point the store at a folder of their own, so they never touch the real vault.
    nonisolated(unsafe) static var rootForTests: URL?
    static var root: URL {
        rootForTests ?? URL.applicationSupportDirectory.appending(path: "Stillroom/Store", directoryHint: .isDirectory)
    }

    /// Both slots' password keys are written last when a vault is made, so their being there means it's whole.
    static var exists: Bool { Slot.allCases.allSatisfy { FileManager.default.fileExists(atPath: $0.keyFile.path) } }
    /// A folder left by a test build before format 4. It's never read, and nothing is written over it.
    static var isOldFormat: Bool {
        !exists && FileManager.default.fileExists(atPath: root.appending(path: "password.key").path)
    }

    static func write(_ data: Data, to url: URL) throws {
        // Only you can list or read the folder: other accounts on this Mac can't copy it to guess at offline.
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
    }

    /// Every file that opens a way in, and the slot folders. They all share one date, so a key written later (a decoy
    /// set a year on) isn't newer than the rest.
    static var keyFiles: [URL] {
        Slot.allCases.flatMap { [$0.folder, $0.keyFile, $0.recoveryFile, $0.kitFile, $0.coverFile] }
            + [IntruderLog.publicKeyURL, root.appending(path: "touchid.key"), root.appending(path: "mac.key")]
    }

    /// A key file written, then every key file given the same dates.
    static func writeKey(_ data: Data, to url: URL) throws {
        try write(data, to: url)
        evenDates(keyFiles)
    }

    static func evenDates(_ urls: [URL], _ date: Date = .now) {
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: url.path)
        }
    }

    // MARK: Covers

    enum Covered: String { case list, search }

    static func url(_ kind: Covered, _ slot: Slot) -> URL { kind == .list ? slot.manifest : slot.search }

    /// What's inside a slot's list or index cover: the slot's own sealed list or index, its padding off.
    static func readCovered(_ kind: Covered, _ slot: Slot, cover: SymmetricKey, in folder: URL? = nil) -> Data? {
        let file = folder.map { $0.appending(path: url(kind, slot).lastPathComponent) } ?? url(kind, slot)
        guard let sealed = try? Data(contentsOf: file),
              let plain = try? unseal(sealed, with: cover, binding: Bound.cover(kind.rawValue, slot.rawValue)),
              plain.count >= 8 else { return nil }
        // Unsigned, and checked before it becomes an Int: a doctored length with the top bit set would turn negative.
        let length = plain.prefix(8).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        guard length <= UInt64(plain.count - 8) else { return nil }
        return Data(plain.dropFirst(8).prefix(Int(length)))
    }

    /// One slot's sealed list or index, in a cover padded to `size` (or the least that holds it).
    static func cover(_ inner: Data, _ kind: Covered, _ slot: Slot, cover: SymmetricKey, size: Int = 0) throws -> Data {
        var plain = withUnsafeBytes(of: UInt64(inner.count).bigEndian) { Data($0) } + inner
        plain.append(Data(count: max(size, plain.count) - plain.count))
        return try seal(plain, with: cover, binding: Bound.cover(kind.rawValue, slot.rawValue))
    }

    /// The size both covers of a kind share: enough for the larger inside.
    static func coverSize(_ a: Int, _ b: Int) -> Int { paddedLength(8 + max(a, b)) }

    /// Writes a slot's new list or index, and the other slot's again as it was, both in fresh covers of one size and
    /// with one date: a copy of the folder sees both change together, whichever slot is open.
    static func writeCovered(_ inner: Data, _ kind: Covered, _ slot: Slot, cover key: SymmetricKey) throws {
        let theirs = readCovered(kind, slot.other, cover: key)
        let size = coverSize(inner.count, theirs?.count ?? 0)
        try write(cover(inner, kind, slot, cover: key, size: size), to: url(kind, slot))
        if let theirs { try write(cover(theirs, kind, slot.other, cover: key, size: size), to: url(kind, slot.other)) }
        evenDates([url(kind, slot), url(kind, slot.other)])
    }

    /// Both slots' lists and indexes in fresh covers, as they are: after a slot was swapped in.
    static func recover(cover key: SymmetricKey) throws {
        for kind in [Covered.list, .search] {
            guard let a = readCovered(kind, .a, cover: key) else { continue }
            try writeCovered(a, kind, .a, cover: key)
        }
    }

    // MARK: The list

    /// The list as written once it holds items: `{"format": 4, "vault": {…}}`.
    private struct Wrapped: Codable {
        var format = 4
        var vault: VaultIndex
    }

    /// The list sealed with the slot key, padded, each item's own key (from `itemKeys`, by `sealedAs`) written in.
    static func sealedList(_ index: VaultIndex, using key: SymmetricKey, itemKeys: [UUID: SymmetricKey] = [:]) throws -> Data {
        var stored = index
        func written(_ sealedAs: UUID?) -> String? {
            sealedAs.flatMap { itemKeys[$0] }?.withUnsafeBytes { Data($0).base64EncodedString() }
        }
        for i in stored.files.indices {
            stored.files[i].key = written(stored.files[i].sealedAs)
            for j in (stored.files[i].versions ?? []).indices {
                stored.files[i].versions![j].key = written(stored.files[i].versions![j].sealedAs)
            }
        }
        // A list holding files is wrapped; an empty one isn't, so every empty list is the same size.
        var json = try stored.files.isEmpty ? JSONEncoder().encode(stored) : JSONEncoder().encode(Wrapped(vault: stored))
        // Padded with spaces (still JSON), so the list's size doesn't tell how many files there are.
        json.append(Data(repeating: 0x20, count: paddedLength(json.count) - json.count))
        return try seal(json, with: key, binding: Bound.list)
    }

    static func saveManifest(_ index: VaultIndex, using key: SymmetricKey, itemKeys: [UUID: SymmetricKey] = [:],
                             slot: Slot, cover: SymmetricKey) throws {
        try writeCovered(sealedList(index, using: key, itemKeys: itemKeys), .list, slot, cover: cover)
    }

    /// The list and each item's own key by `sealedAs`. The keys are taken out of the list as it's read, so no
    /// `VaultFile` ever carries one. Every item and version must have its key: one without is damage.
    static func loadManifest(using key: SymmetricKey, slot: Slot, cover: SymmetricKey) throws -> (index: VaultIndex, keys: [UUID: SymmetricKey]) {
        guard let inner = readCovered(.list, slot, cover: cover),
              let json = try? unseal(inner, with: key, binding: Bound.list) else { throw VaultError.damaged }
        let decoder = JSONDecoder()
        var index: VaultIndex
        if let wrapped = try? decoder.decode(Wrapped.self, from: json) {
            // A list from a newer Stillroom: read nothing rather than misread it and save over it.
            guard wrapped.format == 4 else { throw VaultError.newerVault }
            index = wrapped.vault
        } else if let plain = try? decoder.decode(VaultIndex.self, from: json), plain.files.isEmpty {
            index = plain
        } else {
            throw VaultError.damaged
        }
        var keys: [UUID: SymmetricKey] = [:]
        func take(_ text: inout String?, _ sealedAs: UUID?) throws {
            guard let written = text, let sealedAs, var raw = Data(base64Encoded: written), raw.count == 32
            else { throw VaultError.damaged }
            text = nil
            defer { raw.resetBytes(in: 0..<raw.count) }
            keys[sealedAs] = SymmetricKey(data: raw)
        }
        for i in index.files.indices {
            try take(&index.files[i].key, index.files[i].sealedAs)
            for j in (index.files[i].versions ?? []).indices {
                try take(&index.files[i].versions![j].key, index.files[i].versions![j].sealedAs)
            }
        }
        return (index, keys)
    }

    /// The cover key, opened with a slot key. nil when the slot key isn't this slot's.
    static func openCover(_ slot: Slot, with key: SymmetricKey) -> SymmetricKey? {
        guard var raw = try? unseal(Data(contentsOf: slot.coverFile), with: key, binding: Bound.coverKey(slot.rawValue)),
              raw.count == 32 else { return nil }
        defer { raw.resetBytes(in: 0..<raw.count) }
        return SymmetricKey(data: raw)
    }

    // MARK: Making a slot

    /// A password, recovery code or kit secret nobody will ever type: what seals a slot nobody set.
    static func unknowable() -> String { SymmetricKey(size: .bits256).data.base64EncodedString() }

    /// A whole slot, made beside the vault and swapped in at once, so a crash leaves the old slot or the new one,
    /// never half of each. Its password, recovery code and kit secret seal a fresh slot key; its list is empty.
    /// The same code makes a slot you set and one nobody did, so they can't be told apart. Stretches three times:
    /// run it off the main thread. Returns the new slot key.
    @discardableResult
    static func makeSlot(_ slot: Slot, password: String, recoveryCode: String, cover: SymmetricKey) throws -> SymmetricKey {
        let fm = FileManager.default
        let key = SymmetricKey(size: .bits256)
        let staging = slot.staging
        try? fm.removeItem(at: staging)
        func put(_ data: Data, _ url: URL) throws { try write(data, to: staging.appending(path: url.lastPathComponent)) }
        try put(MacLock.wrap(sealWithPassword(key, password: password)), slot.keyFile)
        try put(sealWithPassword(key, password: normalizedRecoveryCode(recoveryCode)), slot.recoveryFile)
        try put(sealWithPassword(key, password: unknowable()), slot.kitFile)
        try put(cover.withUnsafeBytes { try seal($0, with: key, binding: Bound.coverKey(slot.rawValue)) }, slot.coverFile)
        let intruder = Curve25519.KeyAgreement.PrivateKey()
        var index = VaultIndex()
        index.intruder = intruder.rawRepresentation.base64EncodedString()
        // Sized as the other slot's are today; both are put in fresh covers of one size once this is in.
        let list = try sealedList(index, using: key)
        try put(self.cover(list, .list, slot, cover: cover,
                           size: coverSize(list.count, readCovered(.list, slot.other, cover: cover)?.count ?? 0)), slot.manifest)
        let search = try SearchIndex.sealed([:], using: key)
        try put(self.cover(search, .search, slot, cover: cover,
                           size: coverSize(search.count, readCovered(.search, slot.other, cover: cover)?.count ?? 0)), slot.search)
        if fm.fileExists(atPath: slot.folder.path) {
            try Backup.swap(staging, slot.folder)
            try fm.removeItem(at: staging)
        } else {
            try fm.moveItem(at: staging, to: slot.folder)
        }
        try IntruderLog.setPublicKey(intruder.publicKey.rawRepresentation, for: slot)
        try recover(cover: cover)
        evenDates(keyFiles)
        return key
    }

    /// A slot's half-made replacement, left by a crash: the old slot is whole, so it goes.
    static func clearStaging() {
        for slot in Slot.allCases { try? FileManager.default.removeItem(at: slot.staging) }
    }

    /// Seals a file from disk into the vault, with a key of its own. The original is left where it was.
    /// Big files, and all audio and video, are streamed: never whole in memory, and playable as they lie.
    static func add(_ url: URL, folder: String? = nil, slot: Slot, names: Names) throws -> (VaultFile, ItemSeal) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .typeIdentifierKey, .fileSizeKey, .creationDateKey,
                                                      .contentModificationDateKey])
        if values.isDirectory == true { throw VaultError.folder }
        let uti = values.typeIdentifier ?? "public.data"
        var file = VaultFile(name: url.lastPathComponent, uti: uti, size: values.fileSize ?? 0, folder: folder)
        file.created = values.creationDate
        file.contentModified = values.contentModificationDate
        let seal = names.fresh(slot)
        file.sealedAs = seal.blob
        if streams(size: file.size, uti: uti) {
            file.size = try Chunked.seal(from: url, to: blob(seal.blob, slot), key: seal.key, fileID: seal.chunkID)
            file.chunked = true
        } else {
            let data = try Data(contentsOf: url)
            file.size = data.count
            try store(data, in: seal, slot: slot)
        }
        return (file, seal)
    }

    /// Bytes sealed in as a new sealing, with a fresh id and key of its own: one piece, or streamed.
    static func put(_ data: Data, streamed: Bool, slot: Slot, names: Names) throws -> ItemSeal {
        let seal = names.fresh(slot)
        if streamed {
            try Chunked.seal(data, to: blob(seal.blob, slot), key: seal.key, fileID: seal.chunkID)
        } else {
            try store(data, in: seal, slot: slot)
        }
        return seal
    }

    /// A big file on disk sealed in, streamed, as a new sealing. Returns it and the real size.
    static func put(streaming url: URL, slot: Slot, names: Names) throws -> (ItemSeal, Int) {
        let seal = names.fresh(slot)
        return (seal, try Chunked.seal(from: url, to: blob(seal.blob, slot), key: seal.key, fileID: seal.chunkID))
    }

    /// Whether something this big, of this kind, goes in the streaming format.
    static func streams(size: Int, uti: String) -> Bool {
        size > 8 << 20 || UTType(uti)?.conforms(to: .audiovisualContent) == true
    }

    /// The contents of a sealing, whichever format it's in.
    static func contents(of seal: ItemSeal, streamed: Bool, size: Int, slot: Slot) throws -> Data {
        streamed ? try Chunked.read(blob(seal.blob, slot), key: seal.key, fileID: seal.chunkID, plainSize: size)
                 : try open(seal, size: size, slot: slot)
    }

    /// A file's contents written out to `destination`, streamed for big ones, so a large video never sits whole
    /// in memory.
    static func export(_ file: VaultFile, sealed seal: ItemSeal, to destination: URL, slot: Slot) throws {
        if file.streamed {
            try Chunked.unseal(blob(seal.blob, slot), to: destination, key: seal.key, fileID: seal.chunkID, plainSize: file.size)
        } else {
            try open(seal, size: file.size, slot: slot).write(to: destination, options: .atomic)
        }
        stampDates(file, on: destination)
        quarantine(destination)
    }

    /// Marks a copy taken out of the vault as downloaded. Extended attributes aren't kept inside, so a downloaded
    /// program would otherwise come out unflagged and open without Gatekeeper checking it first.
    static func quarantine(_ url: URL) {
        let value = "0081;\(String(Int(Date().timeIntervalSince1970), radix: 16));Stillroom;"
        _ = value.withCString { setxattr(url.path, "com.apple.quarantine", $0, strlen($0), 0, 0) }
    }

    /// A copy taken out gets the file's own dates back: made when it was first made, changed when it last changed.
    static func stampDates(_ file: VaultFile, on url: URL) {
        try? FileManager.default.setAttributes([.creationDate: file.created ?? file.addedAt, .modificationDate: file.shownDate],
                                               ofItemAtPath: url.path)
    }

    /// What goes in for each thing dropped or chosen: a file as itself; a folder as every file inside it, however
    /// deep, each remembering the folder it was in. Hidden files are left out; apps and other bundles are counted as
    /// skipped, as they're folders that only work whole.
    static func expand(_ urls: [URL]) -> (items: [(url: URL, folder: String?)], skipped: Int) {
        var items: [(url: URL, folder: String?)] = []
        var skipped = 0
        for url in urls {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            guard values?.isDirectory == true else { items.append((url, nil)); continue }
            if values?.isPackage == true { skipped += 1; continue }
            // Paths are compared from the folder's parent, so the folder's own name leads ("Taxes/2025").
            let base = url.deletingLastPathComponent().resolvingSymlinksInPath().pathComponents.count
            guard let walk = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .isPackageKey],
                                                            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let item as URL in walk {
                let kind = try? item.resourceValues(forKeys: [.isRegularFileKey, .isPackageKey])
                if kind?.isPackage == true { skipped += 1; continue }
                guard kind?.isRegularFile == true else { continue }
                let folder = item.deletingLastPathComponent().resolvingSymlinksInPath().pathComponents.dropFirst(base)
                items.append((item, folder.joined(separator: "/")))
            }
        }
        return (items, skipped)
    }

    /// Seals bytes in one piece into a sealing's blob, padded first so the sealed size gives away little of the real
    /// one (the list keeps the real size), and bound to its id.
    static func store(_ data: Data, in item: ItemSeal, slot: Slot) throws {
        var padded = data
        padded.append(Data(count: paddedLength(data.count) - data.count))
        try write(seal(padded, with: item.key, binding: item.binding), to: blob(item.blob, slot))
    }

    /// The bytes of a one-piece sealing, `size` long, the padding off.
    static func open(_ seal: ItemSeal, size: Int, slot: Slot) throws -> Data {
        guard let data = try? unseal(Data(contentsOf: blob(seal.blob, slot)), with: seal.key, binding: seal.binding)
        else { throw VaultError.damaged }
        return Data(data.prefix(size))
    }

    /// Whether a sealing opens all the way through: every chunk's seal checks out and nothing is missing. Streamed
    /// blobs are read a chunk at a time, so checking a big video doesn't hold it in memory.
    static func isIntact(_ seal: ItemSeal, streamed: Bool, size: Int, slot: Slot) -> Bool {
        if streamed {
            guard let reader = try? ChunkedReader(url: blob(seal.blob, slot), key: seal.key, fileID: seal.chunkID, plainSize: size)
            else { return false }
            return (0..<reader.count).allSatisfy { (try? reader.chunk($0)) != nil }
        }
        return (try? open(seal, size: size, slot: slot))?.count == size
    }

    static func remove(_ id: UUID, slot: Slot) {
        try? FileManager.default.removeItem(at: blob(id, slot))
    }

    /// Deletes the open slot's sealed files that its list no longer names (left by a crash midway), and files
    /// that are no slot's. The other slot's are never touched. `blobs` are the names the list uses.
    static func prune(keeping blobs: Set<UUID>, slot: Slot, names: Names) {
        for (url, id) in items() where !blobs.contains(id) {
            let owner = names.owner(id)
            if owner == slot || owner == nil { try? FileManager.default.removeItem(at: url) }
        }
    }

    /// Every item file of a slot, for when it's replaced: none of an old decoy stays behind.
    static func removeAll(of slot: Slot, names: Names) {
        for (url, id) in items() where names.owner(id) == slot { try? FileManager.default.removeItem(at: url) }
    }

    private static func items() -> [(URL, UUID)] {
        let found = (try? FileManager.default.contentsOfDirectory(at: Slot.a.files, includingPropertiesForKeys: nil)) ?? []
        return found.compactMap { url in
            guard url.pathExtension == "stillroom", let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent)
            else { return nil }
            return (url, id)
        }
    }

    /// Everything, keys included: nothing in the vault can be opened again. Copies set aside by a restore go too.
    static func wipe() throws {
        if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
        let parent = root.deletingLastPathComponent()
        for url in (try? FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)) ?? []
        where url.lastPathComponent.hasPrefix("Store-before-restore-") {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func blob(_ id: UUID, _ slot: Slot) -> URL { slot.files.appending(path: id.uuidString + ".stillroom") }
}

/// Where one sealing of an item lies and what opens it: its own fresh id and key (format 3).
struct ItemSeal: Sendable {
    /// Its file's name in Files/ (or Files-2/).
    let blob: UUID
    let key: SymmetricKey
    /// What a streamed blob's chunks are bound to.
    let chunkID: UUID
    /// What a one-piece blob's seal is bound to.
    let binding: Data


    static func item(_ sealedAs: UUID, key: SymmetricKey) -> ItemSeal {
        ItemSeal(blob: sealedAs, key: key, chunkID: sealedAs, binding: Bound.item(sealedAs))
    }
}

/// How a slot names its item files: 8 random bytes, then 8 bytes of a keyed hash of them, so a slot (or anyone holding
/// the cover key) can tell its own files from the other's, and a copy of the folder can't.
struct Names: Sendable {
    private let keys: [VaultStore.Slot: SymmetricKey]

    init(cover: SymmetricKey) {
        var keys: [VaultStore.Slot: SymmetricKey] = [:]
        for slot in VaultStore.Slot.allCases {
            keys[slot] = HKDF<SHA256>.deriveKey(inputKeyMaterial: cover, info: Data("Vault names 4".utf8) + Data(slot.rawValue.utf8),
                                               outputByteCount: 32)
        }
        self.keys = keys
    }

    private func tag(_ random: Data, _ slot: VaultStore.Slot) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: random, using: keys[slot]!)).prefix(8)
    }

    /// A new sealing for a slot: a fresh tagged id and a fresh 256-bit key of its own.
    func fresh(_ slot: VaultStore.Slot) -> ItemSeal {
        let random = SymmetricKey(size: .init(bitCount: 64)).data
        let bytes = Array(random + tag(random, slot))
        let id = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                             bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
        return .item(id, key: SymmetricKey(size: .bits256))
    }

    /// Which slot made this id, or nil when neither did.
    func owner(_ id: UUID) -> VaultStore.Slot? {
        let bytes = withUnsafeBytes(of: id.uuid) { Data($0) }
        return VaultStore.Slot.allCases.first { tag(bytes.prefix(8), $0) == bytes.suffix(8) }
    }
}
