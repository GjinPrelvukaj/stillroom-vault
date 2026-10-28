import Foundation
import Testing
@testable import Stillroom

/// Check Stillroom finds damage a disk fault would leave, and its fixes put things right.
extension VaultFlowTests {
    private func damage(_ blob: UUID, slot: VaultStore.Slot = .a) throws {
        let url = VaultStore.blob(blob, slot)
        var data = try Data(contentsOf: url)
        data[data.count / 2] ^= 0xFF
        try data.write(to: url)
    }

    @Test func checkFindsAndFixesDamage() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState()
        try await state.create(password: "real password 123", touchID: false)
        try await state.add([sample("fine.txt", "fine"), sample("notes.txt", "first")])
        let notes = try #require(state.files.first { $0.name.hasSuffix("notes.txt") })
        try state.backdate(notes.id, by: 3600)
        state.update(notes.id, with: Data("second".utf8))
        let earlier = try #require(state.files.first { $0.id == notes.id }?.versions?.first)

        #expect(await state.checkVault { _, _ in }.isEmpty)

        // The current contents break: it falls back to the earlier version, which still opens.
        try damage(try state.seal(of: try #require(state.files.first { $0.id == notes.id })).blob)
        let found = await state.checkVault { _, _ in }
        #expect(found.count == 1)
        let item = try #require(found.first)
        #expect(item.version == nil && item.fallback?.id == earlier.id)
        state.fallBack(notes.id, to: earlier)
        let fixed = try #require(state.files.first { $0.id == notes.id })
        #expect(try state.read(fixed) == Data("first".utf8))
        #expect(await state.checkVault { _, _ in }.isEmpty)
    }

    @Test func newVaultComesWithAWorkingRecoveryKey() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState()
        try await state.create(password: "real password 123", touchID: false)
        let code = try #require(state.freshRecoveryCode)
        #expect(state.hasRecovery)
        state.lock()
        #expect(state.freshRecoveryCode == nil)
        try await state.unlock(recoveryKey: code.lowercased())
        #expect(state.isOpen)
    }
}

extension VaultFlowTests {
    /// The screen sharing switch is kept sealed in the vault: remembered across a lock, never on at the lock screen.
    @Test func showInCaptureIsRememberedWithTheVault() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState()
        try await state.create(password: "real password 123", touchID: false)
        state.setShowInCapture(true)
        #expect(CaptureShield.allowed)
        state.lock()
        #expect(!CaptureShield.allowed && !state.showInCapture)
        try await state.unlock(password: "real password 123")
        #expect(state.showInCapture && CaptureShield.allowed)
        state.setShowInCapture(false)
        state.lock()
    }
}
