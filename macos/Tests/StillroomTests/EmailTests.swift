import Foundation
import Testing
@testable import Stillroom

struct EmailTests {
    private func parse(_ text: String) throws -> Email {
        try #require(Email.parse(Data(text.replacingOccurrences(of: "\n", with: "\r\n").utf8)))
    }

    @Test func plainMessageWithEncodedHeaders() throws {
        let email = try parse("""
            From: =?UTF-8?B?R2rDq24=?= <g@example.com>
            To: someone@example.com
            Subject: =?iso-8859-1?Q?Caf=E9_bill?= and
             =?UTF-8?Q?more_=E2=9C=93?=
            Date: Thu, 23 Oct 2026 10:15:00 +0200
            Content-Type: text/plain; charset=utf-8
            Content-Transfer-Encoding: quoted-printable

            Hello =C3=A9t=C3=A9, this line is soft=
             wrapped.
            """)
        #expect(email.from == "Gjën <g@example.com>")
        #expect(email.subject == "Café bill and more ✓")
        #expect(email.date != nil)
        #expect(email.text?.contains("Hello été, this line is soft wrapped.") == true)
        #expect(email.html == nil)
        #expect(email.page().contains("<pre"))
    }

    @Test func multipartPicksHTMLAndKeepsAttachmentsAndInlinePictures() throws {
        let pdf = Data("%PDF-1.4 fake".utf8).base64EncodedString()
        let png = Data([0x89, 0x50, 0x4E, 0x47]).base64EncodedString()
        let email = try parse("""
            From: a@example.com
            Subject: Report
            MIME-Version: 1.0
            Content-Type: multipart/mixed; boundary="outer"

            --outer
            Content-Type: multipart/related; boundary=rel

            --rel
            Content-Type: multipart/alternative; boundary="alt"

            --alt
            Content-Type: text/plain; charset=us-ascii

            Plain body
            --alt
            Content-Type: text/html; charset=utf-8
            Content-Transfer-Encoding: base64

            \(Data("<p>Hi <img src=\"cid:logo@x\"></p>".utf8).base64EncodedString())
            --alt--
            --rel
            Content-Type: image/png
            Content-ID: <logo@x>
            Content-Transfer-Encoding: base64

            \(png)
            --rel--
            --outer
            Content-Type: application/pdf; name="report.pdf"
            Content-Disposition: attachment; filename*=UTF-8''r%C3%A9port%20final.pdf
            Content-Transfer-Encoding: base64

            \(pdf)
            --outer--
            """)
        #expect(email.text == "Plain body")
        #expect(email.html?.contains("<p>Hi") == true)
        #expect(email.attachments.count == 1)
        #expect(email.attachments.first?.name == "réport final.pdf")
        #expect(email.attachments.first?.data == Data("%PDF-1.4 fake".utf8))
        #expect(email.page().contains("data:image/png;base64,\(png)"))
        #expect(!email.page().contains("cid:"))
        #expect(email.words.contains("Report") && email.words.contains("Plain body"))
    }

    @Test func appleMailEMLX() throws {
        let message = "From: b@example.com\nSubject: Saved by Mail\n\nBody here\n"
        let emlx = "\(message.utf8.count)\n\(message)<?xml version=\"1.0\"?><plist><dict/></plist>"
        let email = try #require(Email.parse(Data(emlx.utf8)))
        #expect(email.subject == "Saved by Mail")
        #expect(email.text?.trimmingCharacters(in: .whitespacesAndNewlines) == "Body here")
    }

    @Test func notAnEmail() {
        #expect(Email.parse(Data([0x00, 0xFF, 0x10])) == nil)
    }

    @MainActor @Test func stagedCopyGoesWhenUnstaged() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "desk-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let desk = EditDesk(root: root)
        desk.useRAMDisk = false
        let id = UUID()
        let url = try await desk.stage(id: id, name: "a/b.docx") { try Data("x".utf8).write(to: $0) }
        #expect(url.lastPathComponent == "a:b.docx")
        #expect(FileManager.default.fileExists(atPath: url.path))
        desk.unstage(id: id)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}

extension EmailTests {
    @Test func hostileInputsDontCrash() {
        // An .emlx byte count far past the end of the file (and past Int's range when added).
        _ = Email.parse(Data("9223372036854775807\nFrom: a@b\n\nhi".utf8))
        // Multiparts nested far deeper than any real message.
        var message = "Content-Type: text/plain\n\ninnermost"
        for i in 0..<2000 {
            message = "Content-Type: multipart/mixed; boundary=b\(i)\n\n--b\(i)\n\(message)\n--b\(i)--"
        }
        _ = Email.parse(Data(("From: a@b\n" + message).utf8))
    }
}
