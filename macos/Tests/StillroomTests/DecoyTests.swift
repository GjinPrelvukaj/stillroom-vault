import CryptoKit
import Foundation
import Testing
@testable import Stillroom

/// The decoy (format 4): two slots built alike, neither marked, each with every way in, and a copy of the folder
/// showing nothing of which is which or which is used. One test per tell in docs/SECURITY.md rule 2.
extension VaultFlowTests {
    private static let real = "real password 123", decoy = "decoy password 456"

    private func made() async throws -> AppState {
        let state = AppState()
        try await state.create(password: Self.real, touchID: false)
        return state
    }

    /// Every file in the folder (but items) with its size and, for key files, its header.
    private func shape() throws -> [String: [Int]] {
        var found: [String: [Int]] = [:]
        let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])!
        for case let url as URL in walk where (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            let path = String(url.path.dropFirst(root.path.count))
            guard !path.hasPrefix("/Files/"), !path.hasPrefix("/intruder/") else { continue }
            let data = try Data(contentsOf: url)
            found[path] = [data.count] + (path.hasSuffix(".key") && usesArgon(data) ? data.prefix(16).map(Int.init) : [])
        }
        return found
    }

    @Test func eachPasswordOpensItsOwnVault() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let state = try await made()
        let mine = state.slot
        try await state.add([sample("secret.txt", "the real thing")])
        _ = try await state.setOtherSlot(password: Self.decoy)
        state.lock()

        try await state.unlock(password: Self.decoy)
        #expect(state.slot == mine.other)
        #expect(state.files.isEmpty)
        try await state.add([sample("shopping.txt", "milk")])
        state.lock()

        try await state.unlock(password: Self.real)
        #expect(state.slot == mine)
        #expect(String(decoding: try state.read(state.files[0]), as: UTF8.self) == "the real thing")
        state.lock()
        await #expect(throws: VaultError.self) { try await state.unlock(password: "neither of them") }
    }

    /// Tell 5: a slot nobody set is shaped exactly like one set and left empty, file for file, size for size, key
    /// header for key header; and so is it again once removed.
    @Test func unsetSlotLooksLikeASetEmptyOne() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let state = try await made()
        let unset = try shape()
        _ = try await state.setOtherSlot(password: Self.decoy)
        #expect(try shape() == unset)
        try await state.resetOtherSlot()
        #expect(try shape() == unset)
        // Opened, the set one's list has the same fields and size as a fresh one's.
        _ = try await state.setOtherSlot(password: Self.decoy)
        state.lock()
        try await state.unlock(password: Self.decoy)
        let cover = try #require(state.coverForTests)
        let set = try #require(VaultStore.readCovered(.list, state.slot, cover: cover))
        let own = try #require(VaultStore.readCovered(.list, state.slot.other, cover: cover))
        #expect(set.count == own.count)
    }

    /// Tell 1: the letters say nothing. Yours lands in either, and no name says main, decoy or second.
    @Test func theRealVaultIsInEitherLetter() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        var seen = Set<VaultStore.Slot>()
        for _ in 0..<16 where seen.count < 2 {
            let state = try await made()
            seen.insert(state.slot)
            state.lock()
            try VaultStore.wipe()
        }
        #expect(seen.count == 2)
        _ = try await made()
        let names = try shape().keys.joined(separator: " ").lowercased()
        for word in ["main", "decoy", "-2", "manifest"] { #expect(!names.contains(word)) }
    }

    /// Tell 2: the decoy has its own recovery key and kit, and each opens its own slot only.
    @Test func bothSlotsHaveEveryWayIn() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let state = try await made()
        let realCode = try #require(state.freshRecoveryCode)
        let mine = state.slot
        let decoyCode = try await state.setOtherSlot(password: Self.decoy)
        state.lock()
        try await state.unlock(password: Self.decoy)
        let pieces = try await state.makeKit(threshold: 2, count: 3)
        #expect(state.hasKit)
        state.lock()

        try await state.unlock(recoveryKey: decoyCode)
        #expect(state.slot == mine.other)
        state.lock()
        try await state.unlock(recoveryKey: realCode)
        #expect(state.slot == mine)
        #expect(!state.hasKit)
        state.lock()
        try await state.unlock(kitPieces: [pieces[0], pieces[2]])
        #expect(state.slot == mine.other)
    }

    /// Tell 4: a save in one slot rewrites both slots' lists, in covers of one size and one date, the other's
    /// contents untouched inside.
    @Test func aSaveRewritesBothCovers() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let state = try await made()
        let cover = try #require(state.coverForTests)
        let (mine, other) = (state.slot, state.slot.other)
        let before = (try Data(contentsOf: mine.manifest), try Data(contentsOf: other.manifest))
        let theirs = VaultStore.readCovered(.list, other, cover: cover)
        // Enough files that the list grows several steps past an empty one.
        try await state.add((0..<40).map { try sample("file \($0).txt", "contents \($0)") })
        let after = (try Data(contentsOf: mine.manifest), try Data(contentsOf: other.manifest))
        #expect(after.0 != before.0 && after.1 != before.1)
        #expect(after.0.count == after.1.count && after.0.count > before.0.count)
        #expect(VaultStore.readCovered(.list, other, cover: cover) == theirs)
        func dates(_ url: URL) throws -> [Date?] {
            let values = try url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            return [values.creationDate, values.contentModificationDate]
        }
        #expect(try dates(mine.manifest) == dates(other.manifest))
        // The indexes too, once searched.
        try await Task.sleep(for: .milliseconds(500))
        #expect(try Data(contentsOf: mine.search).count == Data(contentsOf: other.search).count)
    }

    /// Tell 5: a decoy set long after the vault was made leaves no key file newer than the rest.
    @Test func keyFilesShareTheirDates() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let state = try await made()
        let old = Date(timeIntervalSinceNow: -400 * 24 * 3600)
        VaultStore.evenDates(VaultStore.keyFiles, old)
        _ = try await state.setOtherSlot(password: Self.decoy)
        let dates = Set(VaultStore.keyFiles.filter { FileManager.default.fileExists(atPath: $0.path) }.map {
            try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        })
        #expect(dates.count == 1)
    }

    /// Tell 1: one folder of items for both slots, named so only a slot can tell its own. Pruning never takes the
    /// other's; replacing a slot takes all of its old ones and none of yours; a file no slot named goes.
    @Test func itemFilesAreUnattributable() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let state = try await made()
        let mine = state.slot
        try await state.add([sample("mine.txt", "mine")])
        let myBlob = try state.seal(of: state.files[0]).blob
        let names = try #require(state.namesForTests)
        #expect(names.owner(myBlob) == mine)
        _ = try await state.setOtherSlot(password: Self.decoy)
        state.lock()
        try await state.unlock(password: Self.decoy)
        try await state.add([sample("theirs.txt", "theirs")])
        let theirBlob = try state.seal(of: state.files[0]).blob
        #expect(names.owner(theirBlob) == mine.other)
        let stray = VaultStore.blob(UUID(), mine)
        try Data("stray".utf8).write(to: stray)
        state.lock()
        try await state.unlock(password: Self.real)
        #expect(FileManager.default.fileExists(atPath: VaultStore.blob(theirBlob, mine).path))
        #expect(!FileManager.default.fileExists(atPath: stray.path))
        _ = try await state.setOtherSlot(password: "another decoy 789")
        #expect(!FileManager.default.fileExists(atPath: VaultStore.blob(theirBlob, mine).path))
        #expect(try state.read(state.files[0]) == Data("mine".utf8))
    }

    /// Replacing a slot is staged and swapped in one step: a half-made one left by a crash changes nothing and goes.
    @Test func aHalfMadeSlotIsLeftBehind() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let state = try await made()
        let other = state.slot.other
        try FileManager.default.createDirectory(at: other.staging, withIntermediateDirectories: true)
        try Data("half".utf8).write(to: other.staging.appending(path: "password.key"))
        state.lock()
        try await state.unlock(password: Self.real)
        #expect(!FileManager.default.fileExists(atPath: other.staging.path))
    }

    /// A wrong try at the lock screen goes to both slots.
    @Test func intruderEntriesReachBothSlots() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let state = try await made()
        _ = try await state.setOtherSlot(password: Self.decoy)
        state.lock()
        try IntruderLog.record(kind: .wrongPassword, photo: nil)
        try await state.unlock(password: Self.decoy)
        #expect(state.intruderEntries().count == 1 && state.intruderCount == 1)
        state.lock()
        try await state.unlock(password: Self.real)
        #expect(state.intruderEntries().count == 1)
        #expect(state.problem == nil)
    }

    /// A new password is checked against the other slot from either side alike.
    @Test func passwordChecksAreSymmetric() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let state = try await made()
        await #expect(throws: VaultError.sameAsOther) { _ = try await state.setOtherSlot(password: Self.real) }
        _ = try await state.setOtherSlot(password: Self.decoy)
        await #expect(throws: VaultError.sameAsOther) { try await state.changePassword(current: Self.real, to: Self.decoy) }
        state.lock()
        try await state.unlock(password: Self.decoy)
        await #expect(throws: VaultError.sameAsOther) { try await state.changePassword(current: Self.decoy, to: Self.real) }
    }

    /// Tell 3: no view decides by slot what to show.
    @Test func noViewLooksAtTheSlot() throws {
        let views = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Sources/Stillroom/Views")
        for name in try FileManager.default.contentsOfDirectory(atPath: views.path) {
            let text = try String(contentsOf: views.appending(path: name), encoding: .utf8)
            #expect(!text.contains("state.slot"), "\(name) looks at the slot")
        }
    }

    /// A folder from before format 4 is reported, and making a vault doesn't write into it.
    @Test func anOldFolderIsLeftAlone() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try VaultStore.write(Data("old".utf8), to: root.appending(path: "password.key"))
        #expect(VaultStore.isOldFormat && !VaultStore.exists)
    }

    /// The licence and the free tier tell nothing: the limit stops both vaults at the same count with the same words,
    /// a licence added in either lifts it in both, and adding or removing one writes nothing in the vault folder.
    @Test func theLicenceAndTheLimitAreTheSameInEitherVault() async throws {
        defer { try? FileManager.default.removeItem(at: root); try? License.remove() }
        let state = try await made()
        _ = try await state.setOtherSlot(password: Self.decoy)
        state.lock()

        /// What each vault does when full: its count, room, and what adding by every way says.
        func probe(_ password: String) async throws -> [String] {
            try await state.unlock(password: password)
            defer { state.lock() }
            try await fill(state, to: max(state.files.count, License.freeItems))
            var said = ["\(state.room == .max ? "unlimited" : String(state.room))"]
            state.problem = nil
            await state.add([try sample("extra.txt", "x")])
            said.append(state.problem ?? "added")
            state.problem = nil
            said.append(state.newEntry(.note, name: "Note", content: Data()) == nil ? state.problem ?? "" : "added")
            state.problem = nil
            return said
        }

        let without = (try await probe(Self.real), try await probe(Self.decoy))
        #expect(without.0 == without.1)
        #expect(without.0 == ["0", AppState.fullMessage(1), AppState.fullMessage(1)])

        // Added from the decoy, it lifts the limit in both; the vault folder doesn't change by a byte.
        func listing() throws -> [String: Int] {
            var found: [String: Int] = [:]
            for path in FileManager.default.subpaths(atPath: root.path) ?? [] {
                found[path] = (try? FileManager.default.attributesOfItem(atPath: root.appending(path: path).path)[.size] as? Int) ?? -1
            }
            return found
        }
        try await state.unlock(password: Self.decoy)
        let before = try listing()
        try state.addLicense(try testLicense())
        #expect(try listing() == before)
        state.lock()
        #expect(!License.file.path.hasPrefix(root.path + "/"))

        let with = (try await probe(Self.real), try await probe(Self.decoy))
        #expect(with.0 == with.1)
        #expect(with.0 == ["unlimited", "added", "added"])

        try await state.unlock(password: Self.real)
        state.removeLicense()
        state.lock()
        #expect(try await probe(Self.decoy) == (try await probe(Self.real)))
    }
}
