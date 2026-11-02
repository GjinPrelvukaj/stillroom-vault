import Foundation
import Testing
@testable import Stillroom

struct UpdatesTests {
    @Test func checkForUpdatesOpensTheChangelogWithThisVersion() {
        #expect(Updates.pageURL(version: "1.0.3").absoluteString == "https://stillroomvault.com/changelog/?v=1.0.3")
    }

    @Test func aCopyIsOldAfterSixMonths() throws {
        let built = try #require(Updates.day("2027-01-10"))
        #expect(!Updates.isOld(built: built, now: built.addingTimeInterval(170 * 86_400)))
        #expect(Updates.isOld(built: built, now: built.addingTimeInterval(190 * 86_400)))
        #expect(!Updates.isOld(built: nil))
        #expect(Updates.detail(version: "1.0.0", built: built, now: built.addingTimeInterval(190 * 86_400)).contains("over six months old"))
        #expect(!Updates.detail(version: "1.0.0", built: built, now: built).contains("over six months old"))
    }
}

/// Settings › Security's proof card: what it says about a release, a development build and a copy someone else made.
struct SelfCheckProofTests {
    @Test func aReleaseShowsEveryProof() {
        let lines = SelfCheck.proof(version: "1.1.0", signed: true, notarized: true, offline: "2026-11-02")
        #expect(lines.allSatisfy { $0.ok })
        let labels = lines.map { $0.label }
        #expect(labels == ["Version", "Signed by Stillroom's maker", "Notarized by Apple", "Offline check"])
        #expect(lines[3].value == "Passed when built, 2026-11-02: no networking code linked")
    }

    @Test func aCopySomeoneElseMadeSaysSo() {
        let lines = SelfCheck.proof(version: "1.1.0", signed: false, notarized: false, offline: nil)
        let failing = lines.filter { !$0.ok }.map { $0.label }
        #expect(failing == ["Signed by Stillroom's maker", "Notarized by Apple", "Offline check"])
        #expect(lines[1].value == "No: someone else built or changed this copy")
        #expect(lines[3].value == "Not recorded in this copy")
    }
}
