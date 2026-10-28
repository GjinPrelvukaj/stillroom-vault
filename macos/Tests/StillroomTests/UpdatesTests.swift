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
