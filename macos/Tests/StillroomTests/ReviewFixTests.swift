import CryptoKit
import Foundation
import Testing
@testable import Stillroom

/// Checks for the fixes from the October 2026 code review.
@MainActor struct ReviewFixTests {
    @Test func webPagesNeverOpenInPlace() {
        for (name, uti) in [("page.html", "public.html"), ("page.xhtml", "public.xhtml"), ("feed.xml", "public.xml"),
                            ("logo.svg", "public.svg-image"), ("saved.webarchive", "com.apple.webarchive")] {
            #expect(!AppState.canEdit(VaultFile(name: name, uti: uti, size: 1)), "\(name) must not open in place")
        }
        // Ordinary documents still do.
        #expect(AppState.canEdit(VaultFile(name: "w2.pdf", uti: "com.adobe.pdf", size: 1)))
        #expect(AppState.canEdit(VaultFile(name: "notes.txt", uti: "public.plain-text", size: 1)))
    }

    @Test func inlinePicturesAreCapped() throws {
        let pictures = (0..<300).map { i in
            "--b\r\nContent-Type: image/png\r\nContent-ID: <p\(i)>\r\nContent-Transfer-Encoding: base64\r\n\r\nAA==\r\n"
        }.joined()
        let text = "From: a@example.com\r\nSubject: many\r\nContent-Type: multipart/related; boundary=\"b\"\r\n\r\n"
            + "--b\r\nContent-Type: text/html\r\n\r\n<img src=\"cid:p0\">\r\n" + pictures + "--b--\r\n"
        let email = try #require(Email.parse(Data(text.utf8)))
        #expect(email.inline.count == 256)
        // The rest aren't lost: they're listed as attachments.
        #expect(email.attachments.count == 44)
        #expect(!email.page().contains("cid:p0"))
    }
}

extension VaultFlowTests {
    @Test func aDoctoredCoverLengthIsRefusedNotACrash() throws {
        let cover = SymmetricKey(size: .bits256)
        let folder = root.deletingLastPathComponent().appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // A length with the top bit set: read as a signed Int it turned negative and crashed the app.
        let inner = Data([0x80, 0, 0, 0, 0, 0, 0, 1]) + Data(repeating: 0, count: 64)
        let name = VaultStore.url(.list, .a).lastPathComponent
        try seal(inner, with: cover, binding: Bound.cover("list", "a")).write(to: folder.appending(path: name))
        #expect(VaultStore.readCovered(.list, .a, cover: cover, in: folder) == nil)
    }
}
