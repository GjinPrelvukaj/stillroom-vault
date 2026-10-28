import CryptoKit
import Foundation
import Testing
@testable import Stillroom

/// Item keys and bound seals (format 3): no sealed file can stand in for another, and nothing sealed any other way
/// opens.
extension VaultFlowTests {
    private static let password = "real password 123"

    private func blobNames() throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: VaultStore.Slot.a.files.path).filter { $0.hasSuffix(".stillroom") })
    }

    @Test func sealedFilesCantStandInForEachOther() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState()
        try await state.create(password: Self.password, touchID: false)
        try await state.add([sample("one.txt", "first secret"), sample("two.txt", "second secret")])
        let one = state.files[0], two = state.files[1]
        let oneBlob = VaultStore.blob(try state.seal(of: one).blob, state.slot)
        let twoBlob = VaultStore.blob(try state.seal(of: two).blob, state.slot)
        try FileManager.default.removeItem(at: twoBlob)
        try FileManager.default.copyItem(at: oneBlob, to: twoBlob)
        #expect(throws: VaultError.damaged) { try state.read(two) }

        // Each item's own key opens only its own seal, even given the other's binding, and the vault key opens none.
        let key = try #require(state.keyForTests)
        let oneSeal = try state.seal(of: one)
        let forged = ItemSeal(blob: oneSeal.blob, key: oneSeal.key, chunkID: oneSeal.chunkID, binding: Bound.item(two.sealedAs!))
        #expect(throws: VaultError.damaged) { try VaultStore.open(forged, size: one.size, slot: state.slot) }
        #expect(throws: VaultError.damaged) { try VaultStore.open(.item(one.sealedAs!, key: key), size: one.size, slot: state.slot) }

        // The search index copied over the list doesn't open as the list, nor the other slot's list as this one's.
        let slot = state.slot
        state.lock()
        let list = try Data(contentsOf: slot.manifest)
        for impostor in [slot.search, slot.other.manifest] {
            try FileManager.default.removeItem(at: slot.manifest)
            try FileManager.default.copyItem(at: impostor, to: slot.manifest)
            await #expect(throws: VaultError.damaged) { try await state.unlock(password: Self.password) }
        }
        try list.write(to: slot.manifest)
        try await state.unlock(password: Self.password)
    }

    /// An empty list is unwrapped and padded, so every empty list is one size; one holding files is wrapped as
    /// `{"format": 4, …}`.
    @Test func anEmptyListKeepsItsShapeAndAFullOneIsWrapped() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState()
        try await state.create(password: Self.password, touchID: false)
        let key = try #require(state.keyForTests), cover = try #require(state.coverForTests)
        let inner = { VaultStore.readCovered(.list, state.slot, cover: cover)! }
        var index = VaultIndex()
        index.intruder = Data(count: 32).base64EncodedString()
        var empty = try JSONEncoder().encode(index)
        #expect(inner().count == paddedLength(empty.count) + 28)
        empty = try unseal(inner(), with: key, binding: Bound.list)
        #expect(try JSONDecoder().decode(VaultIndex.self, from: empty).files.isEmpty)

        try await state.add([sample("one.txt", "first")])
        let json = try unseal(inner(), with: key, binding: Bound.list)
        #expect(String(decoding: json, as: UTF8.self).contains("\"format\":4"))
        #expect(throws: (any Error).self) { try JSONDecoder().decode(VaultIndex.self, from: json) }
        // Nor is any item key left on a VaultFile in memory.
        #expect(state.files.allSatisfy { $0.key == nil })
    }

    /// A list sealed without its binding doesn't open, empty or not, and unlocking with it deletes nothing. Nor does a
    /// list naming an item without its key.
    @Test func onlyABoundListWithEveryKeyOpens() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState()
        try await state.create(password: Self.password, touchID: false)
        try await state.add([sample("one.txt", "first")])
        let key = try #require(state.keyForTests), cover = try #require(state.coverForTests), slot = state.slot
        let blobs = try blobNames()
        state.lock()
        let bound = try unseal(VaultStore.readCovered(.list, slot, cover: cover)!, with: key, binding: Bound.list)
        for json in [bound, try JSONEncoder().encode(VaultIndex())] {
            try VaultStore.writeCovered(seal(json, with: key), .list, slot, cover: cover)
            await #expect(throws: VaultError.damaged) { try await state.unlock(password: Self.password) }
        }
        #expect(try blobNames() == blobs)

        let keyless = String(decoding: bound, as: UTF8.self).replacingOccurrences(of: "\"key\":\"", with: "\"kee\":\"")
        try VaultStore.writeCovered(seal(Data(keyless.utf8), with: key, binding: Bound.list), .list, slot, cover: cover)
        await #expect(throws: VaultError.damaged) { try await state.unlock(password: Self.password) }

        // The list put back bare, without its cover: damage too.
        try VaultStore.write(seal(bound, with: key, binding: Bound.list), to: slot.manifest)
        await #expect(throws: VaultError.damaged) { try await state.unlock(password: Self.password) }
    }

    /// A password key without today's mark (Argon2id) is damage, not a different way to stretch.
    @Test func aPasswordKeyWithoutTheMarkDoesntOpen() throws {
        let unmarked = SymmetricKey(size: .bits128).data + SymmetricKey(size: .init(bitCount: 60 * 8)).data
        #expect(throws: VaultError.damaged) { try openWithPassword(unmarked, password: Self.password) }
    }

    @Test func lockingForgetsItemKeys() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState()
        try await state.create(password: Self.password, touchID: false)
        try await state.add([sample("one.txt", "first")])
        let copy = state.files[0]
        state.lock()
        #expect(throws: (any Error).self) { try state.read(copy) }
        #expect(throws: (any Error).self) { try state.seal(of: copy) }
    }
}
