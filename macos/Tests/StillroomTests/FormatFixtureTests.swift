import Foundation
import Testing
@testable import Stillroom

/// Makes a real vault for tools/test-stillroom-open.sh to open with the Python tool, so the published format and the
/// app can't drift apart. Runs only when that script sets STILLROOM_FIXTURE_DIR.
extension VaultFlowTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["STILLROOM_FIXTURE_DIR"] != nil))
    func writesFormatFixture() async throws {
        let dir = URL(filePath: ProcessInfo.processInfo.environment["STILLROOM_FIXTURE_DIR"]!)
        VaultStore.rootForTests = dir.appending(path: "vault")
        let source = dir.appending(path: "source")
        try FileManager.default.createDirectory(at: source.appending(path: "Taxes/2025"), withIntermediateDirectories: true)
        try Data("W-2 wages 52,000\n".utf8).write(to: source.appending(path: "Taxes/2025/w2.txt"))
        try Data((0..<20_000).map { UInt8(truncatingIfNeeded: $0 &* 7) }).write(to: source.appending(path: "photo.bin"))
        try Data((0..<(9 << 20)).map { UInt8(truncatingIfNeeded: $0 &* 13 &+ 5) }).write(to: source.appending(path: "big.bin"))
        let old = Date(timeIntervalSince1970: 1_560_000_000)  // June 2019
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: source.appending(path: "photo.bin").path)

        let state = AppState()
        try await state.create(password: "fixture password one", touchID: false)
        let recovery = try #require(state.freshRecoveryCode)
        await state.add([source.appending(path: "Taxes"), source.appending(path: "photo.bin"), source.appending(path: "big.bin")])
        _ = state.newEntry(.note, name: "Shopping", content: Data("milk\neggs\n".utf8))
        var secret = Secret(template: .login)
        secret.fields[0].value = "me@example.com"
        secret.fields[1].value = "hunter2-correct"
        _ = state.newEntry(.secret, name: "Bank", content: try JSONEncoder().encode(secret))
        let pieces = try await state.makeKit(threshold: 2, count: 3)
        #expect(state.files.count == 5)
        // A decoy holding one item: the tool must find it in whichever slot it is.
        _ = try await state.setOtherSlot(password: "fixture decoy two")
        state.lock()
        try await state.unlock(password: "fixture decoy two")
        _ = state.newEntry(.note, name: "Groceries", content: Data("bread\n".utf8))
        state.lock()
        let answers: [String: Any] = ["password": "fixture password one", "recovery": recovery, "pieces": pieces,
                                      "decoy": "fixture decoy two",
                                      "secretLines": secret.fields.map { "\($0.label): \($0.value)" }]
        try JSONSerialization.data(withJSONObject: answers).write(to: dir.appending(path: "answers.json"))
    }
}
