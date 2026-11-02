import Foundation
import Testing
@testable import Stillroom

struct RoomCheckTests {
    @Test func aQuietMacIsClear() {
        let s = RoomCheck.Signals(processes: ["launchd", "Finder"], fileVaultOn: true, integrityOn: true, gatekeeperOn: true)
        #expect(RoomCheck.findings(s).isEmpty)
    }

    /// Unknown answers (a tool that couldn't run) say nothing rather than raise an alarm.
    @Test func unknownIsNotAFinding() {
        #expect(RoomCheck.findings(RoomCheck.Signals()).isEmpty)
    }

    @Test func seriousFindingsComeFirstAndCantBePutAway() {
        var s = RoomCheck.Signals(processes: ["parsecd", "Maccy", "com.raycast.macos.Pasteboard"], systemProcesses: ["screensharingd"])
        s.microphoneUsers = ["Zoom"]
        s.cameraInUse = true
        s.fileVaultOn = false
        let all = RoomCheck.findings(s)
        let serious = all.prefix { $0.serious }.map { $0.id }
        #expect(serious == ["screen-sharing", "camera", "microphone"])
        #expect(all.contains { $0.id == "remote-Parsec" && !$0.serious })
        #expect(all.first { $0.id == "clipboard" }?.title == "Maccy and Raycast keep a clipboard history")
        #expect(all.first { $0.id == "microphone" }?.detail == "Zoom is listening right now.")
        // Putting everything away leaves only the serious ones.
        let shown = RoomCheck.shown(all, dismissed: Set(all.map { $0.id }))
        #expect(shown.map { $0.id } == ["screen-sharing", "camera", "microphone"])
    }

    @Test func anOpenSSHSessionIsSerious() {
        let all = RoomCheck.findings(RoomCheck.Signals(systemProcesses: ["sshd-session"]))
        #expect(all.map { $0.id } == ["ssh"] && all[0].serious)
    }

    /// Apple's Spotlight service is called `parsecd` too: from /System it's Apple's, not the Parsec app. An app called
    /// screensharingd outside /System isn't macOS's screen sharing either.
    @Test func applesOwnServicesAreToldApartFromApps() {
        let listing = """
        /System/Library/PrivateFrameworks/CoreParsec.framework/parsecd
        /Applications/Raycast.app/Contents/XPCServices/Raycast Pasteboard.xpc/Contents/MacOS/com.raycast.macos.Pasteboard
        /Users/someone/bin/screensharingd
        """
        let running = RoomCheck.processes(listing)
        let found = RoomCheck.findings(RoomCheck.Signals(processes: running.apps, systemProcesses: running.system))
        #expect(found.map { $0.id } == ["clipboard"])
        // Nothing hides by its path: a bare name counts as Apple's too, and /usr/local isn't Apple's.
        let bare = RoomCheck.processes("sshd-session\n/usr/local/bin/screensharingd")
        #expect(bare.system == ["sshd-session"] && bare.apps == ["sshd-session", "screensharingd"])
        // The Parsec app itself, from /Applications, is flagged.
        let parsec = RoomCheck.processes("/Applications/Parsec.app/Contents/MacOS/parsecd")
        #expect(RoomCheck.findings(RoomCheck.Signals(processes: parsec.apps, systemProcesses: parsec.system)).map { $0.id } == ["remote-Parsec"])
    }

    /// The real thing, on whatever Mac runs the tests: it has to finish and not crash. What it finds depends on the Mac,
    /// so only that is checked. About half a second on its own; the bound is loose because the whole suite runs at once.
    @Test func looksAtThisMacAndFinishes() async {
        let start = Date()
        let found = await RoomCheck.look()
        #expect(Date().timeIntervalSince(start) < 20)
        print("Room check on this Mac:", found.map { "\($0.serious ? "!" : "·") \($0.title)" })
    }
}
