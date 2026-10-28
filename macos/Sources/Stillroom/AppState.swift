import CryptoKit
import Foundation
import Observation
import UniformTypeIdentifiers

/// The vault, open or shut. The vault key is held here, in memory only, and only while it is open; locking drops it
/// and the list with it. Each password opens one of two slots; nothing here, or anywhere, says which is yours.
@MainActor @Observable final class AppState {
    typealias Slot = VaultStore.Slot

    private(set) var exists = VaultStore.exists
    private(set) var isOpen = false
    /// Which slot is open. Both are built and shown alike: nothing tells yours from a decoy.
    private(set) var slot = Slot.a
    private(set) var files: [VaultFile] = []
    /// Folders made in the vault, empty ones included; folders that hold something also come from their files.
    private(set) var madeFolders: [String] = []
    /// Locked: whether Touch ID opens a slot (its button shows). Open: whether it opens this one.
    private(set) var touchIDOn = TouchIDKey.isOn
    private(set) var macLockOn = MacLock.isOn
    /// Every slot always has a recovery key.
    let hasRecovery = true
    var hasKit: Bool { kitMade != nil }
    var kitMade: Date? { VaultIndex.date(meta.kitMade) }
    /// Whether this vault, once open, shows in screenshots and screen sharing (see VaultIndex.showInCapture).
    private(set) var showInCapture = false
    /// A recovery key made with a new vault, to be shown (and checked) once; nil once it has been.
    var freshRecoveryCode: String?
    /// Opened with the recovery key: a new password must be set before anything else.
    private(set) var mustSetPassword = false
    /// How many files are being sealed right now.
    private(set) var adding = 0
    /// The last thing that went wrong, in plain words, until it is read.
    var problem: String? {
        didSet { if problem != nil { ActivityLog.note("message shown in the window", action: false) } }
    }

    /// The words inside items, for search; read in the background after unlocking and kept sealed between times.
    private(set) var words: [UUID: SearchIndex.Entry] = [:]
    /// Entries in the intruder log this slot can read, for the sidebar.
    private(set) var intruderCount = 0

    private var key: SymmetricKey?
    /// The cover key (both slots share it) and what it names files with, while open.
    private var cover: SymmetricKey?
    private var names: Names?
    /// The open slot's list fields other than its files and folders (intruder key, Touch ID, kit dates).
    private var meta = VaultIndex()
    /// Each item's own key, by the `sealedAs` it was sealed under: read out of the list on unlock, written back into it
    /// on every save, and let go on lock with the vault key. Kept here rather than on `VaultFile`, which is copied
    /// into views and tasks that can outlive a lock.
    private var itemKeys: [UUID: SymmetricKey] = [:]
    @ObservationIgnored private var indexing: Task<Void, Never>?
    /// Bumped by every lock: an unlock that started before a lock must not open the vault after it.
    private var locks = 0
    /// Counts every write to the vault folder while open (lists, items, the search index). A backup of an open vault
    /// is packed again if this moved while it was packing, so a backup never names a file it doesn't hold.
    private(set) var writes = 0

    var size: Int { files.reduce(0) { $0 + $1.size } }

    // MARK: Licence and the free tier

    /// The licence kept beside the store, in neither slot: it lifts the limit in whichever vault is open.
    private(set) var license = License.load()
    /// How many more items the open vault may take: unlimited with a licence, otherwise up to `License.freeItems`
    /// counting its files, notes and secrets (folders and earlier versions don't count). Only adding asks.
    var room: Int { license == nil ? max(0, License.freeItems - files.count) : .max }
    /// Said when adding stops at the free tier's limit, the same words in either vault.
    static func fullMessage(_ left: Int) -> String {
        let what = left == 1 ? "1 item didn't go in" : "\(left) items didn't go in"
        return "\(what): without a licence a vault holds \(License.freeItems) items. Everything already in it keeps working. Add a licence in Settings › Licence to lift the limit."
    }

    /// Checks and keeps a pasted licence key; the limit lifts at once.
    /// A licence just added, to be welcomed (`WelcomeIn`) until the person moves on.
    var welcome: License?

    func addLicense(_ typed: String) throws {
        license = try License.save(typed)
        welcome = license
        ActivityLog.note("licence added")
    }

    func removeLicense() {
        do {
            try License.remove()
            license = nil
            ActivityLog.note("licence removed")
        } catch {
            problem = ActivityLog.failed(error, "The licence couldn't be removed. \(error.localizedDescription)")
        }
    }

    // MARK: Getting in

    func create(password: String, touchID: Bool) async throws {
        let started = locks
        defer { ActivityLog.note("made a vault") }
        // Yours goes in either slot, at random, and the choice is written nowhere. The other is a real slot whose
        // passwords nobody knows, made by the same code as a decoy you set: the two can't be told apart.
        let mine: Slot = Bool.random() ? .a : .b
        let cover = SymmetricKey(size: .bits256)
        let code = makeRecoveryCode()
        // Stretching takes a moment by design: off the main thread, one at a time.
        let key = try await Task.detached { () -> SymmetricKey in
            VaultStore.clearStaging()
            // Made in a random order, so which slot's files are newer says nothing about which one is yours.
            func other() throws {
                try VaultStore.makeSlot(mine.other, password: VaultStore.unknowable(), recoveryCode: VaultStore.unknowable(), cover: cover)
            }
            let otherFirst = Bool.random()
            if otherFirst { try other() }
            let key = try VaultStore.makeSlot(mine, password: password, recoveryCode: code, cover: cover)
            if !otherFirst { try other() }
            return key
        }.value
        exists = true
        try open(with: key, slot: mine, started: started)
        // Touch ID is extra: the vault still opens with the password if the Enclave says no.
        if touchID { setTouchID(true) }
        freshRecoveryCode = code
    }

    /// Tries the password on both slots. Both are always tried, so how long it takes doesn't tell which one opened.
    func unlock(password: String) async throws {
        let started = locks
        defer { ActivityLog.note("password tried: \(isOpen ? "opened" : "didn't open")") }
        var sealed: [(Slot, Data)] = []
        for slot in Slot.allCases {
            guard let data = try? Data(contentsOf: slot.keyFile) else { continue }
            // Locked to another Mac: say so, rather than "wrong password".
            sealed.append((slot, try MacLock.unwrap(data)))
        }
        guard let found = await Self.tryEach(sealed, password) else { throw VaultError.wrongPassword }
        try open(with: found.1, slot: found.0, started: started)
    }

    /// One secret stretched against every slot's file, all of them every time.
    nonisolated private static func tryEach(_ sealed: [(Slot, Data)], _ secret: String) async -> (Slot, SymmetricKey)? {
        await Task.detached { () -> (Slot, SymmetricKey)? in
            var found: (Slot, SymmetricKey)?
            for (slot, data) in sealed {
                do {
                    let key = try openWithPassword(data, password: secret)
                    if found == nil { found = (slot, key) }
                } catch VaultError.damaged {
                    // Refused before stretching (still locked to an old Mac, or damaged): stretch anyway, so every try
                    // costs the same whichever slot is readable.
                    AppState.stretchInVain(secret)
                } catch {}
            }
            // A missing file costs a stretch too, so how long a try takes never counts the slots that answered.
            for _ in sealed.count..<max(sealed.count, Slot.allCases.count) { AppState.stretchInVain(secret) }
            return found
        }.value
    }

    /// One stretch at today's cost whose result is thrown away: the time a slot that can't answer would have taken.
    nonisolated private static func stretchInVain(_ secret: String) {
        _ = try? stretchArgon(secret, salt: SymmetricKey(size: .bits128).data, cost: .current)
    }

    private static func files(_ url: (Slot) -> URL) -> [(Slot, Data)] {
        Slot.allCases.compactMap { slot in (try? Data(contentsOf: url(slot))).map { (slot, $0) } }
    }

    func unlockWithTouchID() async throws {
        let started = locks
        defer { ActivityLog.note("Touch ID: \(isOpen ? "opened" : "didn't open")") }
        let key = try await TouchIDKey.open()
        // The slot its key opens; both are tried.
        let opens = Slot.allCases.filter { VaultStore.openCover($0, with: key) != nil }
        guard let slot = opens.first else { throw VaultError.touchIDChanged }
        try open(with: key, slot: slot, started: started)
    }

    /// A recovery key opens its slot on any Mac, without the password; a new password is asked for at once.
    func unlock(recoveryKey typed: String) async throws {
        let started = locks
        defer { ActivityLog.note("recovery key tried: \(isOpen ? "opened" : "didn't open")") }
        guard let found = await Self.tryEach(Self.files(\.recoveryFile), normalizedRecoveryCode(typed))
        else { throw VaultError.wrongRecoveryKey }
        try open(with: found.1, slot: found.0, started: started)
        mustSetPassword = true
    }

    /// Pieces of an emergency kit open its slot on any Mac, without the password; a new password is asked for at once.
    func unlock(kitPieces typed: [String]) async throws {
        let started = locks
        defer { ActivityLog.note("kit pieces tried: \(isOpen ? "opened" : "didn't open")") }
        let secret = try EmergencyKit.join(typed.filter { !$0.isEmpty }.map(EmergencyKit.piece))
        guard let found = await Self.tryEach(Self.files(\.kitFile), EmergencyKit.password(secret)) else { throw VaultError.wrongKit }
        try open(with: found.1, slot: found.0, started: started)
        mustSetPassword = true
    }

    private func open(with key: SymmetricKey, slot: Slot, started: Int) throws {
        // Locked (the Mac slept) while the password was being stretched: stay shut.
        guard started == locks else { throw CancellationError() }
        guard let cover = VaultStore.openCover(slot, with: key) else { throw VaultError.damaged }
        let (index, keys) = try VaultStore.loadManifest(using: key, slot: slot, cover: cover)
        let names = Names(cover: cover)
        VaultStore.clearStaging()
        files = index.files
        madeFolders = index.folders
        itemKeys = keys
        meta = index
        meta.files = []
        meta.folders = []
        showInCapture = index.showInCapture
        CaptureShield.shared.set(showInCapture)
        VaultStore.prune(keeping: Set(files.flatMap(blobs)), slot: slot, names: names)
        self.key = key
        self.cover = cover
        self.names = names
        self.slot = slot
        touchIDOn = TouchIDKey.publicKey() == meta.touchID
        macLockOn = MacLock.isOn
        if let checked = try? IntruderLog.check(meta.intruder, for: slot), checked.key != meta.intruder {
            meta.intruder = checked.key
            try? save()
            if checked.swapped {
                problem = "Someone changed the intruder log's lock while Stillroom was shut. It's been reset; check your Mac for anything you didn't install."
            }
        }
        intruderCount = IntruderLog.entries(meta.intruder, for: slot).count
        remindAboutKit()
        words = SearchIndex.load(using: key, slot: slot, cover: cover)
        isOpen = true
        // Nothing about what's inside, nor which vault opened: that would give a decoy away.
        ActivityLog.vaultOpen = true
        ActivityLog.note("unlocked")
        refreshIndex()
    }

    /// Shut: the key and the list are let go. Nothing of what's inside stays in the window.
    /// `reason` is for the activity log: what made it lock.
    func lock(_ reason: String = "lock button") {
        if isOpen { ActivityLog.note("lock (\(reason))") }
        ActivityLog.vaultOpen = false
        welcome = nil
        // A copied password doesn't outlive the vault being open (rule 8), nor waits out its 30 seconds on a quit.
        Clipboard.clearIfOurs()
        FolderDrag.forget()
        // Shut, the window is hidden again; the vault's own setting comes back with the next unlock.
        CaptureShield.shared.set(false)
        showInCapture = false
        // Anything being edited in its app gets a last save check, then its working copy goes; previews too.
        EditDesk.shared.clearAll()
        locks += 1
        indexing?.cancel()
        words = [:]
        key = nil
        cover = nil
        names = nil
        meta = VaultIndex()
        touchIDOn = TouchIDKey.isOn
        itemKeys = [:]
        files = []
        madeFolders = []
        isOpen = false
        slot = .a
        mustSetPassword = false
        problem = nil
        // Not kept while shut. Locked before it was checked, the key still works; Settings makes a new one.
        freshRecoveryCode = nil
    }

    // MARK: Inside

    /// Encrypts files into the vault, one by one; a folder brings every file inside it. Each sealed copy is read
    /// back and checked against its file; returns the checked ones, the only originals that may then be removed.
    @discardableResult
    func add(_ urls: [URL], into parent: String? = nil) async -> Originals {
        guard key != nil, let names else { return Originals() }
        let slot = slot
        // A dropped folder's permission covers what's inside it only while it's held.
        let scoped = urls.map { $0.startAccessingSecurityScopedResource() }
        defer { for (url, held) in zip(urls, scoped) where held { url.stopAccessingSecurityScopedResource() } }
        // Listed off the main thread: a big folder takes a moment to walk.
        let planned = Task<[(URL, [(url: URL, folder: String?)], Int)], Never>.detached(priority: .userInitiated) {
            urls.map { url in
                let expanded = VaultStore.expand([url])
                return (url, expanded.items, expanded.skipped)
            }
        }
        let plan = await planned.value
        let skipped = plan.reduce(0) { $0 + $1.2 }
        if skipped > 0 { problem = "Skipped \(skipped) \(skipped == 1 ? "app or bundle" : "apps or bundles"): those can't go in yet." }
        let total = plan.reduce(0) { $0 + $1.1.count }
        ActivityLog.note("adding files")
        adding += total
        defer { adding -= total }
        var originals = Originals()
        var refused = 0
        defer { if refused > 0 { problem = Self.fullMessage(refused) } }
        // ponytail: the list is saved after every file so a crash loses nothing; batch it if huge folders feel slow.
        for (source, items, _) in plan {
            if items.first?.folder != nil { originals.folders.append(source) }
            for (url, folder) in items {
                // Full: the rest stay where they are (a folder not wholly in is never removed, see Originals).
                guard room > 0 else { refused += 1; continue }
                do {
                    // Dropped into a folder that's open: it goes in there, keeping any folders it brought.
                    let place = [parent, folder].compactMap { $0 }.joined(separator: "/")
                    let fileClock = DispatchTime.now()
                    defer { ActivityLog.took("a file encrypted and checked", since: fileClock, action: false) }
                    let (file, sealed, checked) = try await Task.detached(priority: .userInitiated) {
                        let (file, sealed) = try VaultStore.add(url, folder: place.isEmpty ? nil : place, slot: slot, names: names)
                        return (file, sealed, Originals.matches(file, original: url, sealed: sealed, slot: slot))
                    }.value
                    // Locked while sealing: the list is gone, so saving it now would write an empty one over the real one.
                    guard isOpen else { return originals }
                    files.append(file)
                    itemKeys[sealed.blob] = sealed.key
                    try save()
                    if checked {
                        originals.files.append(url)
                    } else {
                        problem = "\(url.lastPathComponent) went in, but its copy didn't read back the same (was it changing?). The original is kept."
                    }
                } catch {
                    problem = ActivityLog.failed(error, "\(url.lastPathComponent) didn't go in. \(error.localizedDescription)")
                }
            }
        }
        return originals
    }

    func read(_ file: VaultFile) throws -> Data {
        try VaultStore.contents(of: seal(of: file), streamed: file.streamed, size: file.size, slot: slot)
    }

    /// Where an item's current contents (or a version) lie and what opens them: its own id and key.
    func seal(of file: VaultFile) throws -> ItemSeal { try seal(file.sealedAs) }
    func seal(of version: VaultFile.Version) throws -> ItemSeal { try seal(version.sealedAs) }

    private func seal(_ sealedAs: UUID?) throws -> ItemSeal {
        guard key != nil else { throw CancellationError() }
        guard let sealedAs, let own = itemKeys[sealedAs] else { throw VaultError.damaged }
        return .item(sealedAs, key: own)
    }

    /// Every blob an item uses: its current contents and each earlier version.
    private func blobs(of file: VaultFile) -> [UUID] {
        ([file.sealedAs] + (file.versions ?? []).map(\.sealedAs)).compactMap { $0 }
    }

    func delete(_ file: VaultFile) {
        let before = files
        files.removeAll { $0.id == file.id }
        do {
            // The list first: a sealed file the list forgets is harmless, a listed one that is gone is not.
            try save()
            for gone in blobs(of: file) { VaultStore.remove(gone, slot: slot) }
        } catch {
            files = before
            problem = ActivityLog.failed(error, "\(file.name) couldn't be deleted. \(error.localizedDescription)")
        }
    }

    /// Writes the list as it now stands, then reads any new or changed item for search.
    private func save() throws {
        guard let key else { throw CancellationError() }
        let clock = DispatchTime.now()
        defer { ActivityLog.took("list sealed and saved", since: clock, action: false) }
        guard let cover else { throw CancellationError() }
        writes += 1
        var index = meta
        index.files = files
        index.folders = madeFolders
        index.showInCapture = showInCapture
        try VaultStore.saveManifest(index, using: key, itemKeys: itemKeys, slot: slot, cover: cover)
        refreshIndex()
    }

    /// Reads, in the background, every item whose words aren't known or have changed since; forgets removed ones;
    /// seals the index when done.
    private func refreshIndex() {
        guard let key, let cover else { return }
        let slot = slot
        let stale = files.filter { file in
            guard SearchIndex.reads(file) else { return false }
            guard let known = words[file.id] else { return true }
            return known.changed != file.changedAt || known.size != file.size
        }.compactMap { file in (try? seal(of: file)).map { (file, $0) } }
        let present = Set(files.map(\.id))
        let forgotten = words.keys.contains { !present.contains($0) }
        guard !stale.isEmpty || forgotten else { return }
        indexing?.cancel()
        indexing = Task { [weak self] in
            let clock = DispatchTime.now()
            defer { ActivityLog.took("search index refreshed", since: clock, action: false) }
            for (file, sealed) in stale {
                let entry = await Task.detached(priority: .utility) { () -> SearchIndex.Entry? in
                    guard let data = try? VaultStore.contents(of: sealed, streamed: file.streamed, size: file.size, slot: slot)
                    else { return nil }
                    return SearchIndex.Entry(changed: file.changedAt, size: file.size, text: SearchIndex.words(in: file, data) ?? "")
                }.value
                guard let self, !Task.isCancelled, self.isOpen, self.slot == slot else { return }
                if let entry { self.words[file.id] = entry }
            }
            guard let self, !Task.isCancelled, self.isOpen, self.slot == slot else { return }
            let present = Set(self.files.map(\.id))
            self.words = self.words.filter { present.contains($0.key) }
            self.writes += 1
            SearchIndex.save(self.words, using: key, slot: slot, cover: cover)
        }
    }

    // MARK: Intruders

    func intruderEntries() -> [IntruderLog.Entry] {
        guard isOpen else { return [] }
        return IntruderLog.entries(meta.intruder, for: slot)
    }

    func deleteIntruder(_ id: UUID) {
        try? IntruderLog.delete(id: id)
        intruderCount = intruderEntries().count
    }

    func clearIntruders() {
        try? IntruderLog.clear()
        intruderCount = 0
    }

    /// After a restore from a backup: shut, and read again what's on disk now.
    func reloadFromDisk() {
        lock()
        exists = VaultStore.exists
        touchIDOn = TouchIDKey.isOn
        macLockOn = MacLock.isOn
    }

    /// Applies a change to the list and saves it; if saving fails the change is undone and said in plain words.
    private func change(_ what: String, _ edit: () -> Void) {
        let before = (files, madeFolders)
        edit()
        do { try save() } catch {
            (files, madeFolders) = before
            problem = ActivityLog.failed(error, "\(what) didn't work. \(error.localizedDescription)")
        }
    }

    private func replace(_ file: VaultFile) {
        if let i = files.firstIndex(where: { $0.id == file.id }) { files[i] = file }
    }

    // MARK: Notes, secrets and versions

    /// A new note or secret, empty, in `folder`. Returns it, to be opened for editing.
    func newEntry(_ entry: VaultFile.Entry, name: String, content: Data, folder: String? = nil) -> VaultFile? {
        guard key != nil else { return nil }
        guard room > 0 else { problem = Self.fullMessage(1); return nil }
        let uti = entry == .note ? "net.daringfireball.markdown" : "public.json"
        var item = VaultFile(name: name, uti: uti, size: content.count, folder: folder, modifiedAt: .now, entry: entry)
        do {
            let sealed = try VaultStore.put(content, streamed: false, slot: slot, names: names!)
            item.sealedAs = sealed.blob
            itemKeys[sealed.blob] = sealed.key
            files.append(item)
            try save()
            return item
        } catch {
            files.removeAll { $0.id == item.id }
            problem = ActivityLog.failed(error, "That couldn't be made. \(error.localizedDescription)")
            return nil
        }
    }

    /// Remembered with the vault (sealed), so it holds across locks and restarts and nothing else can change it.
    func setShowInCapture(_ on: Bool) {
        ActivityLog.note("setting changed")
        let before = showInCapture
        showInCapture = on
        CaptureShield.shared.set(on)
        do {
            try save()
        } catch {
            showInCapture = before
            CaptureShield.shared.set(before)
            problem = ActivityLog.failed(error, "That setting couldn't be saved. \(error.localizedDescription)")
        }
    }

    /// Accounts from a password export, each a Login secret in the "Imported" folder, all saved in one go. An account
    /// already in the vault (same site and username) is skipped, so importing twice adds nothing twice. Past the free
    /// tier's limit the rest are `left` out, and said so.
    func importLogins(_ logins: [PasswordImport.Login]) -> (added: Int, skipped: Int, left: Int) {
        guard key != nil else { return (0, 0, 0) }
        let clock = DispatchTime.now()
        defer { ActivityLog.note("password import done", action: false); ActivityLog.took("password import", since: clock) }
        var known = Set(files.filter { $0.entry == .secret }.compactMap { file -> String? in
            guard let data = try? read(file), let secret = try? JSONDecoder().decode(Secret.self, from: data),
                  secret.template == .login else { return nil }
            let site = secret.fields.first { $0.label == "Website" }?.value ?? ""
            let user = secret.fields.first { $0.label == "Username" }?.value ?? ""
            return "\(PasswordImport.site(site))|\(user.lowercased())"
        })
        let folder = "Imported"
        var added: [VaultFile] = []
        var skipped = 0
        var left = 0
        let room = room
        defer { if left > 0 { problem = Self.fullMessage(left) } }
        for login in logins {
            guard known.insert(login.key).inserted else { skipped += 1; continue }
            guard added.count < room else { left += 1; continue }
            guard let content = try? JSONEncoder().encode(login.secret) else { continue }
            var item = VaultFile(name: login.name, uti: "public.json", size: content.count, folder: folder, modifiedAt: .now, entry: .secret)
            do {
                let sealed = try VaultStore.put(content, streamed: false, slot: slot, names: names!)
                item.sealedAs = sealed.blob
                itemKeys[sealed.blob] = sealed.key
                added.append(item)
            } catch {
                problem = ActivityLog.failed(error, "The import stopped partway. \(error.localizedDescription)")
                break
            }
        }
        guard !added.isEmpty else { return (0, skipped, left) }
        let before = (files, madeFolders)
        files += added
        if !madeFolders.contains(folder) { madeFolders.append(folder) }
        do {
            try save()
        } catch {
            (files, madeFolders) = before
            for item in added { VaultStore.remove(item.sealedAs!, slot: slot) }
            problem = ActivityLog.failed(error, "The accounts couldn't be saved. \(error.localizedDescription)")
            return (0, skipped, left)
        }
        return (added.count, skipped, left)
    }

    /// New contents for an item, as bytes or as a file on disk (a save from editing in place). What it held before is
    /// kept as a version, unless it was itself changed less than ten minutes ago (so typing in a note doesn't make a
    /// version a second); at most 20 are kept.
    func update(_ id: VaultFile.ID, with data: Data? = nil, from url: URL? = nil, name: String? = nil) {
        guard key != nil, var file = files.first(where: { $0.id == id }) else { return }
        let clock = DispatchTime.now()
        defer { ActivityLog.took("\(url == nil ? "edit" : "edit-in-place save") sealed", since: clock, action: false) }
        do {
            // Blobs to delete once the list no longer names them: the contents replaced, and versions past 20.
            var unused: [UUID?] = []
            if file.changedAt < Date.now.addingTimeInterval(-600) {
                file.versions = (file.versions ?? []) + [asVersion(file)]
                while (file.versions?.count ?? 0) > 20 { unused.append(file.versions!.removeFirst().sealedAs) }
            } else {
                unused.append(file.sealedAs)
            }
            let sealed: ItemSeal
            if let url, VaultStore.streams(size: (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0, uti: file.uti) {
                (sealed, file.size) = try VaultStore.put(streaming: url, slot: slot, names: names!)
                file.chunked = true
            } else {
                let data = try data ?? Data(contentsOf: url!)
                sealed = try VaultStore.put(data, streamed: false, slot: slot, names: names!)
                file.size = data.count
                file.chunked = nil
            }
            file.sealedAs = sealed.blob
            itemKeys[sealed.blob] = sealed.key
            file.modifiedAt = .now
            if let name { file.name = name }
            replace(file)
            try save()
            for gone in unused.compactMap({ $0 }) { VaultStore.remove(gone, slot: slot) }
        } catch {
            problem = ActivityLog.failed(error, "\(file.name) couldn't be saved. \(error.localizedDescription)")
        }
    }

    func readVersion(_ version: VaultFile.Version) throws -> Data {
        try VaultStore.contents(of: seal(of: version), streamed: version.chunked == true, size: version.size, slot: slot)
    }

    /// The current contents of an item, as a version: it keeps its blob and key.
    private func asVersion(_ file: VaultFile) -> VaultFile.Version {
        VaultFile.Version(date: file.changedAt, size: file.size, chunked: file.chunked, sealedAs: file.sealedAs)
    }

    /// A file's contents written to a place outside the vault (a copy the person saves, or a working copy).
    func export(_ file: VaultFile, to url: URL) throws {
        try VaultStore.export(file, sealed: seal(of: file), to: url, slot: slot)
    }

    /// A copy on the RAM disk for Quick Look to draw (its previewers are Apple's own, each in its own sandbox).
    /// Marked as downloaded like an edit copy. `EditDesk.shared.unstage(id:)` deletes it.
    /// `data`, when already read (an earlier version), is what's shown; otherwise the item is streamed out.
    func stage(_ file: VaultFile, data: Data) async throws -> URL {
        try await EditDesk.shared.stage(id: file.id, name: file.name) { url in
            if data.isEmpty { try export(file, to: url) } else { try data.write(to: url) }
            Self.quarantine(url)
        }
    }

    /// Something held only in memory (an email's attachment) sealed in as a file of its own, in `folder`.
    func add(_ data: Data, named name: String, folder: String?) {
        guard key != nil else { return }
        guard room > 0 else { problem = Self.fullMessage(1); return }
        let uti = UTType(filenameExtension: (name as NSString).pathExtension)?.identifier ?? UTType.data.identifier
        var item = VaultFile(name: name, uti: uti, size: data.count, folder: folder)
        do {
            let streamed = VaultStore.streams(size: data.count, uti: uti)
            let sealed = try VaultStore.put(data, streamed: streamed, slot: slot, names: names!)
            item.chunked = streamed ? true : nil
            item.sealedAs = sealed.blob
            itemKeys[sealed.blob] = sealed.key
            files.append(item)
            try save()
        } catch {
            files.removeAll { $0.id == item.id }
            problem = ActivityLog.failed(error, "\(name) didn't go in. \(error.localizedDescription)")
        }
    }

    /// A player for audio or video, reading straight from the sealed file; nothing decrypted touches the disk.
    func player(for file: VaultFile) -> VaultPlayer? {
        guard file.streamed, let sealed = try? seal(of: file) else { return nil }
        return VaultPlayer(url: VaultStore.blob(sealed.blob, slot), key: sealed.key, fileID: sealed.chunkID,
                           plainSize: file.size, uti: file.uti)
    }

    /// Puts an earlier version back; what was current becomes the newest version, so nothing is lost.
    func restore(_ version: VaultFile.Version, of id: VaultFile.ID) {
        guard var file = files.first(where: { $0.id == id }) else { return }
        do {
            file.versions = (file.versions ?? []).filter { $0.id != version.id } + [asVersion(file)]
            file.size = version.size
            file.chunked = version.chunked
            file.sealedAs = version.sealedAs
            file.modifiedAt = .now
            replace(file)
            try save()
        } catch {
            problem = ActivityLog.failed(error, "That version couldn't be put back. \(error.localizedDescription)")
        }
    }

    // MARK: Taking everything out

    /// Everything back out as ordinary, unencrypted files in a new folder inside `parent`: files in their folders with
    /// their own dates, notes as Markdown, secrets as plain text (hidden values included). The way to leave Stillroom,
    /// or keep a readable copy. Returns the folder made. `progress` hears (done, total).
    func exportAll(into parent: URL, progress: @escaping @MainActor (Int, Int) -> Void) async throws -> URL {
        guard key != nil else { throw CancellationError() }
        let clock = DispatchTime.now()
        ActivityLog.note("export everything started")
        defer { ActivityLog.note("export everything ended", action: false); ActivityLog.took("export everything", since: clock) }
        let slot = slot
        let list = files
        let stamp = Date.now.formatted(.iso8601.year().month().day())
        let top = Self.unused(parent.appending(path: "Stillroom Export \(stamp)", directoryHint: .isDirectory))
        try FileManager.default.createDirectory(at: top, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // Folders made empty are kept as empty folders.
        for folder in madeFolders { try FileManager.default.createDirectory(at: Self.place(folder, in: top), withIntermediateDirectories: true) }
        for (done, file) in list.enumerated() {
            let sealed = try seal(of: file)
            try await Task.detached(priority: .userInitiated) {
                let folder = Self.place(file.folder, in: top)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                switch file.entry {
                case nil:
                    let url = Self.unused(folder.appending(path: Self.safe(file.name)))
                    try VaultStore.export(file, sealed: sealed, to: url, slot: slot)
                case .note:
                    let url = Self.unused(folder.appending(path: Self.safe(file.name) + ".md"))
                    try VaultStore.contents(of: sealed, streamed: file.streamed, size: file.size, slot: slot).write(to: url)
                    VaultStore.stampDates(file, on: url)
                    VaultStore.quarantine(url)
                case .secret:
                    let secret = try JSONDecoder().decode(Secret.self, from: VaultStore.contents(of: sealed, streamed: file.streamed,
                                                                                                  size: file.size, slot: slot))
                    let text = secret.fields.map { "\($0.label): \($0.value)" }.joined(separator: "\n") + "\n"
                    let url = Self.unused(folder.appending(path: Self.safe(file.name) + ".txt"))
                    try Data(text.utf8).write(to: url)
                    VaultStore.stampDates(file, on: url)
                    VaultStore.quarantine(url)
                }
            }.value
            guard isOpen, self.slot == slot else { throw CancellationError() }
            progress(done + 1, list.count)
        }
        return top
    }

    /// A folder path from the list as a place on disk, inside `top` and nowhere else: no "..", no empty parts.
    nonisolated private static func place(_ path: String?, in top: URL) -> URL {
        (path ?? "").split(separator: "/").map { safe(String($0)) }.reduce(top) { $0.appending(path: $1, directoryHint: .isDirectory) }
    }

    nonisolated private static func safe(_ name: String) -> String {
        // On a Mac's disk ":" is what Finder shows as "/", so a slash in a name comes out looking the same.
        let flat = name.shownName.replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: "/", with: ":")
        return flat.isEmpty || flat == "." || flat == ".." ? "Untitled" : flat
    }

    /// `url`, or "name 2.ext", "name 3.ext"… when something's already there.
    nonisolated private static func unused(_ url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        let folder = url.deletingLastPathComponent()
        for n in 2... {
            let candidate = folder.appending(path: ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return url
    }

    // MARK: Checking

    /// Something that no longer opens: an item's current contents, or one of its earlier versions.
    struct Damage: Identifiable, Sendable {
        let id = UUID()
        let file: VaultFile
        /// The damaged version; nil when it's the current contents.
        let version: VaultFile.Version?
        /// For damaged current contents: the newest earlier version that still opens, to fall back to.
        let fallback: VaultFile.Version?
    }

    /// Reads every item and every earlier version all the way through, off the main thread, and lists what doesn't
    /// open (a disk fault, a crash midway, a file changed from outside). `progress` hears (done, total).
    func checkVault(progress: @escaping @MainActor (Int, Int) -> Void) async -> [Damage] {
        guard key != nil else { return [] }
        let clock = DispatchTime.now()
        ActivityLog.note("check vault started")
        defer { ActivityLog.note("check vault finished", action: false); ActivityLog.took("check vault", since: clock) }
        let slot = slot
        let list = files
        let total = list.reduce(0) { $0 + 1 + ($1.versions?.count ?? 0) }
        var done = 0
        var found: [Damage] = []
        for file in list {
            guard let sealed = try? seal(of: file),
                  let versionSeals = try? (file.versions ?? []).map({ ($0, try seal(of: $0)) }) else { return found }
            let (current, versions) = await Task.detached(priority: .userInitiated) { () -> (Bool, [(VaultFile.Version, Bool)]) in
                let current = VaultStore.isIntact(sealed, streamed: file.streamed, size: file.size, slot: slot)
                let versions = versionSeals.map { v, sealed in
                    (v, VaultStore.isIntact(sealed, streamed: v.chunked == true, size: v.size, slot: slot))
                }
                return (current, versions)
            }.value
            guard isOpen, self.slot == slot else { return found }
            if !current {
                found.append(Damage(file: file, version: nil, fallback: versions.last { $0.1 }?.0))
            }
            for (version, intact) in versions where !intact {
                found.append(Damage(file: file, version: version, fallback: nil))
            }
            done += 1 + versions.count
            progress(done, total)
        }
        return found
    }

    /// Damaged current contents swapped for an earlier version that still opens; the damaged blob goes.
    func fallBack(_ id: VaultFile.ID, to version: VaultFile.Version) {
        guard var file = files.first(where: { $0.id == id }) else { return }
        do {
            if let damaged = file.sealedAs { VaultStore.remove(damaged, slot: slot) }
            file.versions = file.versions?.filter { $0.id != version.id }
            file.size = version.size
            file.chunked = version.chunked
            file.sealedAs = version.sealedAs
            file.modifiedAt = .now
            replace(file)
            try save()
        } catch {
            problem = ActivityLog.failed(error, "\(file.name) couldn't be put back. \(error.localizedDescription)")
        }
    }

    /// An earlier version taken out of an item's list, and its sealed file deleted.
    func dropVersion(_ version: VaultFile.Version, of id: VaultFile.ID) {
        guard var file = files.first(where: { $0.id == id }) else { return }
        file.versions = file.versions?.filter { $0.id != version.id }
        replace(file)
        do {
            try save()
            if let gone = version.sealedAs { VaultStore.remove(gone, slot: slot) }
        } catch {
            problem = ActivityLog.failed(error, "That version couldn't be removed. \(error.localizedDescription)")
        }
    }

    #if DEBUG
    /// Tests only: makes an item look last changed `seconds` ago, and hands over the key.
    func backdate(_ id: VaultFile.ID, by seconds: TimeInterval) throws {
        if let i = files.firstIndex(where: { $0.id == id }) { files[i].modifiedAt = Date.now.addingTimeInterval(-seconds) }
        try save()
    }
    var keyForTests: SymmetricKey? { key }
    var coverForTests: SymmetricKey? { cover }
    var namesForTests: Names? { names }
    #endif

    // MARK: Editing in place

    /// Whether a file may be opened in another app: only documents, pictures, PDFs, audio and video, judged both by
    /// the kind Stillroom recorded and by the name's extension (which is what macOS goes by when it opens the copy), so a
    /// renamed program can't slip through. Anything that runs (apps, scripts, installers, disk images) never opens.
    static func canEdit(_ file: VaultFile) -> Bool {
        // Sketches: nothing on the Mac opens a PencilKit drawing.
        guard file.isFile, let stored = file.type, !Sketch.isSketch(uti: file.uti, name: file.name) else { return false }
        let ending = (file.name as NSString).pathExtension
        guard !ending.isEmpty, let named = UTType(filenameExtension: ending) else { return false }
        let documents: [UTType] = [.text, .image, .pdf, .audiovisualContent, .compositeContent, .spreadsheet,
                                   .presentation, .rtf, .rtfd, .font]
        let runs: [UTType] = [.executable, .script, .shellScript, .applicationBundle, .application, .unixExecutable,
                              .diskImage, .package, .sourceCode, UTType("com.apple.installer-package-archive"),
                              // Web pages count as text, but open in a browser that runs their scripts and loads
                              // from the network: the email viewer's lockdown would mean nothing.
                              .html, .xml, .svg, .webArchive, .internetLocation, .internetShortcut,
                              UTType("public.xhtml")].compactMap { $0 }
        return [stored, named].allSatisfy { type in
            documents.contains { type.conforms(to: $0) } && !runs.contains { type.conforms(to: $0) }
        }
    }

    /// Opens a file in its usual app from a working copy on Vault's RAM disk; each save there is sealed back in
    /// (keeping a version as any change does). The copy goes when editing is done or the vault locks.
    func editInPlace(_ file: VaultFile) {
        guard Self.canEdit(file) else { problem = "That kind of file can't be opened outside the vault."; return }
        let id = file.id
        Task {
            do {
                try await EditDesk.shared.open(id: id, name: file.name, write: { url in
                    try export(file, to: url)
                    Self.quarantine(url)
                }, onSave: { [weak self] url in
                    self?.update(id, from: url)
                })
            } catch {
                problem = ActivityLog.failed(error, "\(file.name) couldn't be opened for editing. \(error.localizedDescription)")
            }
        }
    }

    private static func quarantine(_ url: URL) { VaultStore.quarantine(url) }

    // MARK: Names, tags and folders

    func rename(_ id: VaultFile.ID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        change("Renaming") { if let i = files.firstIndex(where: { $0.id == id }) { files[i].name = name } }
    }

    func setTags(_ tags: [String], on id: VaultFile.ID) {
        change("Tagging") {
            if let i = files.firstIndex(where: { $0.id == id }) { files[i].tags = tags.isEmpty ? nil : tags }
        }
    }

    /// Every tag in use, A to Z.
    var tags: [String] { Array(Set(files.flatMap(\.tagList))).sorted { $0.localizedStandardCompare($1) == .orderedAscending } }

    /// Every folder: those made, and those that hold something, with each one's parents.
    var folders: [String] {
        var all = Set(madeFolders)
        for path in files.compactMap(\.folder) {
            var parts = path.split(separator: "/").map(String.init)
            while !parts.isEmpty { all.insert(parts.joined(separator: "/")); parts.removeLast() }
        }
        return all.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// "/" divides a folder's path ("Taxes/2025"), so one typed in a name (a date, 26/10/26) becomes "∕", which looks
    /// the same.
    static func folderName(_ typed: String) -> String {
        typed.replacingOccurrences(of: "/", with: "\u{2215}").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func makeFolder(_ name: String, in parent: String?) {
        let name = Self.folderName(name)
        guard !name.isEmpty else { return }
        let path = [parent, name].compactMap { $0 }.joined(separator: "/")
        guard !folders.contains(path) else { return }
        change("Making the folder") { madeFolders.append(path) }
    }

    func move(_ ids: Set<VaultFile.ID>, to folder: String?) {
        change("Moving") {
            for i in files.indices where ids.contains(files[i].id) { files[i].folder = folder }
        }
    }

    /// Renames a folder, carrying everything inside it along.
    /// Returns the folder's new path, or nil when nothing changed.
    @discardableResult
    func renameFolder(_ path: String, to name: String) -> String? {
        let name = Self.folderName(name)
        guard !name.isEmpty else { return nil }
        let parent = path.split(separator: "/").dropLast().joined(separator: "/")
        let new = parent.isEmpty ? name : parent + "/" + name
        return relocate(path, to: new, "Renaming the folder") ? new : nil
    }

    /// A folder, with everything in it, into another folder (nil: the top).
    func moveFolder(_ path: String, into parent: String?) {
        // Dropped on itself, or where it already is: nothing to do.
        guard parent != path else { return }
        if let parent, parent.hasPrefix(path + "/") { problem = "A folder can't go inside one of its own folders."; return }
        let name = String(path.split(separator: "/").last ?? "")
        relocate(path, to: [parent, name].compactMap { $0 }.joined(separator: "/"), "Moving the folder")
    }

    /// A folder and everything below it to a new path. False when it couldn't go there.
    @discardableResult
    private func relocate(_ path: String, to new: String, _ what: String) -> Bool {
        guard new != path else { return false }
        guard !folders.contains(new) else {
            problem = "There's already a folder called “\(new.split(separator: "/").last ?? "")” there."
            return false
        }
        func moved(_ p: String) -> String { p == path ? new : p.hasPrefix(path + "/") ? new + p.dropFirst(path.count) : p }
        change(what) {
            madeFolders = madeFolders.map(moved)
            for i in files.indices { if let f = files[i].folder { files[i].folder = moved(f) } }
        }
        return true
    }

    /// Deletes a folder and everything inside it, versions too.
    func deleteFolder(_ path: String) {
        let gone = files.filter { $0.isInside(path) }
        change("Deleting the folder") {
            files.removeAll { $0.isInside(path) }
            madeFolders.removeAll { $0 == path || $0.hasPrefix(path + "/") }
        }
        for file in gone { for unused in blobs(of: file) { VaultStore.remove(unused, slot: slot) } }
    }

    // MARK: Keys

    /// Checking a new password against the other slot answers a guess at that slot's password, so each check counts
    /// as a wrong try at the lock screen: the first three are free, then each waits longer. Unlocking resets it.
    private func countGuessAtOther() throws {
        guard Date() >= TryLimit.nextTry else { throw VaultError.tooSoon }
        TryLimit.failed()
    }

    /// A new password for the open slot, after the current one is given again.
    func changePassword(current: String, to new: String) async throws {
        ActivityLog.note("setting changed")
        guard let key else { return }
        try countGuessAtOther()
        let slot = slot
        let sealed = try MacLock.unwrap(Data(contentsOf: slot.keyFile))
        // One password, one slot: the new one mustn't already open the other. Checked the same from either slot; a
        // refusal needs the right guess, limited as at the lock screen (countGuessAtOther).
        let other = try? MacLock.unwrap(Data(contentsOf: slot.other.keyFile))
        let written = try await Task.detached { () -> Data in
            _ = try openWithPassword(sealed, password: current)
            if let other, (try? openWithPassword(other, password: new)) != nil { throw VaultError.sameAsOther }
            return try sealWithPassword(key, password: new)
        }.value
        try VaultStore.writeKey(MacLock.wrap(written), to: slot.keyFile)
    }

    /// After a recovery key or kit: a new password, and on a new Mac the lock moved to this one. The other slot's
    /// password key stays sealed to the old Mac (same size and layout as ever); its own recovery key brings it back.
    func setPasswordAfterRecovery(_ new: String) async throws {
        guard let key, mustSetPassword else { return }
        try countGuessAtOther()
        let slot = slot
        if MacLock.isOn, (try? MacLock.key()) == nil {
            try MacLock.remove()
            try MacLock.make()
        }
        let other = try? MacLock.unwrap(Data(contentsOf: slot.other.keyFile))
        let written = try await Task.detached { () -> Data in
            if let other, (try? openWithPassword(other, password: new)) != nil { throw VaultError.sameAsOther }
            return try sealWithPassword(key, password: new)
        }.value
        try VaultStore.writeKey(MacLock.wrap(written), to: slot.keyFile)
        macLockOn = MacLock.isOn
        mustSetPassword = false
    }

    /// A decoy password: the other slot becomes a new, empty vault it opens, with a recovery key of its own (returned,
    /// to be shown once). Whatever the other slot held is deleted. The same from either slot.
    func setOtherSlot(password: String) async throws -> String {
        guard let key, let cover, let names else { throw CancellationError() }
        ActivityLog.note("setting changed")
        try countGuessAtOther()
        let (slot, started) = (slot, locks)
        let mine = try MacLock.unwrap(Data(contentsOf: slot.keyFile))
        _ = key
        let code = makeRecoveryCode()
        try await Task.detached {
            if (try? openWithPassword(mine, password: password)) != nil { throw VaultError.sameAsOther }
        }.value
        guard started == locks else { throw CancellationError() }
        try await replaceOtherSlot(password: password, code: code, cover: cover, names: names)
        return code
    }

    /// No decoy: the other slot becomes one whose passwords nobody knows, and what it held is deleted.
    func resetOtherSlot() async throws {
        guard key != nil, let cover, let names else { throw CancellationError() }
        ActivityLog.note("setting changed")
        try await replaceOtherSlot(password: VaultStore.unknowable(), code: VaultStore.unknowable(), cover: cover, names: names)
    }

    /// Called with the vault open; reads the slot before anything waits.
    private func replaceOtherSlot(password: String, code: String, cover: SymmetricKey, names: Names) async throws {
        let other = slot.other
        // Touch ID that opened the slot being replaced would open nothing now.
        if !touchIDOn { try? TouchIDKey.turnOff() }
        try await Task.detached {
            VaultStore.removeAll(of: other, names: names)
            try VaultStore.makeSlot(other, password: password, recoveryCode: code, cover: cover)
        }.value
    }

    // MARK: Emergency kit

    /// A new emergency kit: `count` printed pieces, any `threshold` of which open this slot. Any kit before it stops
    /// working. Returns the pieces, written out, to be printed once.
    func makeKit(threshold: Int, count: Int) async throws -> [String] {
        guard let key else { throw CancellationError() }
        ActivityLog.note("setting changed")
        var random = SystemRandomNumberGenerator()
        let secret = (0..<EmergencyKit.secretLength).map { _ in UInt8.random(in: 0...255, using: &random) }
        let password = EmergencyKit.password(secret)
        // Locked meanwhile (another slot may be open now): write nothing.
        let (slot, started) = (slot, locks)
        let sealed = try await Task.detached { try sealWithPassword(key, password: password) }.value
        guard started == locks else { throw CancellationError() }
        try VaultStore.writeKey(sealed, to: slot.kitFile)
        meta.kitMade = VaultIndex.stamp(.now)
        meta.kitReminded = VaultIndex.never
        try save()
        return EmergencyKit.split(secret, threshold: threshold, count: count).map(EmergencyKit.code)
    }

    /// The kit's file is sealed again under a secret nobody has: every slot always has one, so none goes missing.
    func removeKit() {
        guard let key else { return }
        ActivityLog.note("setting changed")
        let (slot, started) = (slot, locks)
        Task {
            do {
                let sealed = try await Task.detached { try sealWithPassword(key, password: VaultStore.unknowable()) }.value
                // Locked meanwhile (another slot may be open now): leave it, as if never asked.
                guard started == locks else { return }
                try VaultStore.writeKey(sealed, to: slot.kitFile)
                meta.kitMade = VaultIndex.never
                try save()
            } catch {
                // Still there means it still opens the vault: say so rather than show it gone.
                problem = ActivityLog.failed(error, "The emergency kit couldn't be removed. \(error.localizedDescription)")
            }
        }
    }

    /// Once a year: are the pieces still with the right people? Said in the window, once, when the vault opens.
    private func remindAboutKit() {
        guard problem == nil, let made = kitMade else { return }
        let last = VaultIndex.date(meta.kitReminded) ?? made
        guard Date.now.timeIntervalSince(last) > 365 * 24 * 3600 else { return }
        problem = "Your emergency kit is a year old. Check each piece is still with the right person, or make a new kit in Settings."
        meta.kitReminded = VaultIndex.stamp(.now)
        try? save()
    }

    /// A new recovery key for the open slot; the old one stops working. Returns it, to be shown once.
    func newRecoveryKey() async throws -> String {
        guard let key else { throw CancellationError() }
        ActivityLog.note("setting changed")
        let code = makeRecoveryCode()
        let normalized = normalizedRecoveryCode(code)
        let (slot, started) = (slot, locks)
        let sealed = try await Task.detached { try sealWithPassword(key, password: normalized) }.value
        guard started == locks else { throw CancellationError() }
        try VaultStore.writeKey(sealed, to: slot.recoveryFile)
        return code
    }

    /// Locks both slots' password keys to this Mac's Enclave, or frees them: it needs no slot key, so either slot can.
    /// Turning it on makes a recovery key for the open slot, as otherwise a dead Mac would take it with it; it's
    /// returned to be shown once. The other slot's recovery key is never locked, so it opens that slot anywhere.
    func setMacLock(_ on: Bool) async throws -> String? {
        guard key != nil, on != MacLock.isOn else { return nil }
        ActivityLog.note("setting changed")
        var code: String?
        if on {
            code = try await newRecoveryKey()
            try MacLock.make()
            // Each key sealed again for this Mac. One left plain by a crash midway still needs its password.
            for slot in Slot.allCases {
                guard let data = try? Data(contentsOf: slot.keyFile) else { continue }
                let plain = try MacLock.unwrap(data)
                try VaultStore.writeKey(Stillroom.seal(plain, with: MacLock.key()), to: slot.keyFile)
            }
        } else {
            for slot in Slot.allCases {
                guard let data = try? Data(contentsOf: slot.keyFile) else { continue }
                try VaultStore.writeKey(MacLock.unwrap(data), to: slot.keyFile)
            }
            try MacLock.remove()
            VaultStore.evenDates(VaultStore.keyFiles)
        }
        macLockOn = MacLock.isOn
        return code
    }

    /// Touch ID opens one slot: turning it on here moves it from the other.
    func setTouchID(_ on: Bool) {
        guard let key else { return }
        ActivityLog.note("setting changed")
        do {
            if on {
                meta.touchID = try TouchIDKey.turnOn(key)
            } else {
                if touchIDOn { try TouchIDKey.turnOff() }
                meta.touchID = VaultIndex.noTouchID
            }
            try save()
        } catch {
            problem = ActivityLog.failed(error, error.localizedDescription)
        }
        touchIDOn = TouchIDKey.publicKey() == meta.touchID
    }

    /// The vault and every file in it, for good.
    func wipe() {
        ActivityLog.note("deleting the whole vault")
        do {
            try VaultStore.wipe()
            lock()
            exists = false
            touchIDOn = false
            macLockOn = false
        } catch {
            problem = ActivityLog.failed(error, "The vault couldn't be deleted. \(error.localizedDescription)")
        }
    }
}
