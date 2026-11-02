import Foundation
import Testing
@testable import Stillroom

struct CoolDownStateTests {
    private func file(wait: Int?, asked: CoolDownAsk?) -> VaultFile {
        var f = VaultFile(name: "Seed phrase", uti: "public.plain-text", size: 10)
        f.coolDown = wait
        f.coolDownAsked = asked
        return f
    }

    @Test func theWaitRunsOnUptimeThenOpensForAnHour() {
        let now = CoolDown.Now(boot: "boot-1", uptime: 1000)
        #expect(CoolDown.state(file(wait: nil, asked: nil), now: now) == .none)
        #expect(CoolDown.state(file(wait: 3600, asked: nil), now: now) == .shut)
        let asked = CoolDownAsk(boot: "boot-1", uptime: 1000)
        #expect(CoolDown.state(file(wait: 3600, asked: asked), now: .init(boot: "boot-1", uptime: 1600)) == .waiting(left: 3000))
        #expect(CoolDown.state(file(wait: 3600, asked: asked), now: .init(boot: "boot-1", uptime: 4600)) == .open(left: 3600))
        // An hour after the wait, shut again.
        #expect(CoolDown.state(file(wait: 3600, asked: asked), now: .init(boot: "boot-1", uptime: 8200)) == .shut)
    }

    /// A restart is a new boot session, and uptime can't go backwards within one: either way, the wait starts over.
    @Test func aRestartStartsTheWaitAgain() {
        let asked = CoolDownAsk(boot: "boot-1", uptime: 1000)
        #expect(CoolDown.state(file(wait: 3600, asked: asked), now: .init(boot: "boot-2", uptime: 9000)) == .shut)
        #expect(CoolDown.state(file(wait: 3600, asked: asked), now: .init(boot: "boot-1", uptime: 10)) == .shut)
    }

    @Test func durationsReadPlainly() {
        #expect(CoolDown.duration(30) == "1 min")
        #expect(CoolDown.duration(3000) == "50 min")
        #expect(CoolDown.duration(86_400) == "24 h")
        #expect(CoolDown.duration(83_400) == "23 h 10 min")
        #expect(CoolDown.label(86_400) == "24 hours")
    }
}

extension VaultFlowTests {
    @Test func aCoolDownItemOpensOnlyAfterTheWait() async throws {
        defer { try? FileManager.default.removeItem(at: root); CoolDown.nowForTests = nil; TamperSeal.remove() }
        CoolDown.nowForTests = .init(boot: "boot-1", uptime: 5000)
        let state = AppState()
        try await state.create(password: "real password 123", touchID: false)
        let seed = try #require(state.newEntry(.note, name: "Seed phrase", content: Data("harvest velvet tunnel".utf8)))
        await state.add([try sample("deed.txt", "the deed")])
        let deed = try #require(state.files.first { $0.name.hasSuffix("deed.txt") })
        state.setCoolDown(86_400, on: seed.id)
        state.setCoolDown(3600, on: deed.id)

        // Shut: every way of reading refuses, and editing too.
        #expect(throws: VaultError.coolingDown) { try state.read(seed) }
        let out = root.deletingLastPathComponent().appending(path: "deed-\(UUID().uuidString).txt")
        #expect(throws: VaultError.coolingDown) { try state.export(deed, to: out) }
        state.update(seed.id, with: Data("overwritten".utf8))
        #expect(state.problem == VaultError.coolingDown.localizedDescription)
        state.problem = nil
        // Turning it off waits too.
        state.setCoolDown(nil, on: seed.id)
        #expect(state.files.first { $0.id == seed.id }?.coolDown == 86_400)
        state.problem = nil

        // Asked; it survives a lock, and a changed clock can't move uptime.
        state.askToOpen(seed.id)
        state.lock()
        let again = AppState()
        try await again.unlock(password: "real password 123")
        let kept = try #require(again.files.first { $0.id == seed.id })
        #expect(again.coolDown(of: kept) == .waiting(left: 86_400))
        CoolDown.nowForTests = .init(boot: "boot-1", uptime: 5000 + 86_400 + 60)
        #expect(try again.read(kept) == Data("harvest velvet tunnel".utf8))
        // Open, it can be turned off.
        again.setCoolDown(nil, on: seed.id)
        #expect(again.files.first { $0.id == seed.id }?.coolDown == nil)
    }

    @Test func exportEverythingLeavesWaitingItemsInTheVault() async throws {
        defer { try? FileManager.default.removeItem(at: root); CoolDown.nowForTests = nil; TamperSeal.remove() }
        CoolDown.nowForTests = .init(boot: "boot-1", uptime: 5000)
        let state = AppState()
        try await state.create(password: "real password 123", touchID: false)
        await state.add([try sample("open.txt", "fine"), try sample("waiting.txt", "secret")])
        let waiting = try #require(state.files.first { $0.name.hasSuffix("waiting.txt") })
        state.setCoolDown(3600, on: waiting.id)
        let parent = root.deletingLastPathComponent().appending(path: "export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let top = try await state.exportAll(into: parent) { _, _ in }
        let names = try FileManager.default.contentsOfDirectory(atPath: top.path)
        #expect(names.count == 1 && names[0].hasSuffix("open.txt"))
        #expect(state.problem?.contains("1 item has a cool-down") == true)
    }
}

extension VaultFlowTests {
    /// Search can't show what a cool-down keeps shut, even for words indexed before it had one.
    @Test func aCoolDownItemsWordsLeaveSearch() async throws {
        defer { try? FileManager.default.removeItem(at: root); CoolDown.nowForTests = nil; TamperSeal.remove() }
        CoolDown.nowForTests = .init(boot: "boot-1", uptime: 5000)
        let state = AppState()
        try await state.create(password: "real password 123", touchID: false)
        let seed = try #require(state.newEntry(.note, name: "Seed", content: Data("harvest velvet tunnel".utf8)))
        for _ in 0..<100 where state.words[seed.id] == nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(state.words[seed.id]?.text.contains("velvet") == true)
        state.setCoolDown(3600, on: seed.id)
        #expect(state.words[seed.id] == nil)
        for _ in 0..<50 { try await Task.sleep(for: .milliseconds(20)) }
        state.lock()
        let again = AppState()
        try await again.unlock(password: "real password 123")
        #expect(again.words[seed.id] == nil)
    }
}

extension VaultFlowTests {
    /// The hour ending while a cool-down note is still open in its editor doesn't lose what's typed: saves work until the
    /// vault locks. Reading it again waits.
    @Test func editsKeepSavingAfterTheOpenHourEnds() async throws {
        defer { try? FileManager.default.removeItem(at: root); CoolDown.nowForTests = nil; TamperSeal.remove() }
        CoolDown.nowForTests = .init(boot: "boot-1", uptime: 5000)
        let state = AppState()
        try await state.create(password: "real password 123", touchID: false)
        let note = try #require(state.newEntry(.note, name: "Plans", content: Data("first".utf8)))
        state.setCoolDown(3600, on: note.id)
        state.askToOpen(note.id)
        CoolDown.nowForTests = .init(boot: "boot-1", uptime: 5000 + 3600 + 10)
        _ = try state.read(try #require(state.files.first { $0.id == note.id }))
        // The hour is over.
        CoolDown.nowForTests = .init(boot: "boot-1", uptime: 5000 + 3600 + 3600 + 10)
        state.update(note.id, with: Data("second".utf8))
        #expect(state.problem == nil)
        #expect(throws: VaultError.coolingDown) { try state.read(try #require(state.files.first { $0.id == note.id })) }
        // After a lock, it waits like any shut item.
        state.lock()
        let again = AppState()
        try await again.unlock(password: "real password 123")
        again.update(note.id, with: Data("third".utf8))
        #expect(again.problem == VaultError.coolingDown.localizedDescription)
    }
}
