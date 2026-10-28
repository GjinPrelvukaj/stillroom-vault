import Foundation
import Testing
@testable import Stillroom

struct PasswordImportTests {
    @Test func readsApplePasswordsExport() throws {
        let csv = """
            \u{FEFF}Title,URL,Username,Password,Notes,OTPAuth
            github.com (gjin),https://github.com/,gjin,"pa,ss""word",,otpauth://totp/GitHub:gjin?secret=ABC
            Bank,https://www.mybank.com/login,me@example.com,hunter2,"line one
            line two",
            ,https://example.org,,,,

            """
        let logins = try PasswordImport.logins(from: Data(csv.utf8))
        #expect(logins.count == 2)
        #expect(logins[0].password == "pa,ss\"word")
        #expect(logins[0].otp.hasPrefix("otpauth://"))
        #expect(logins[1].notes == "line one\nline two")
        #expect(logins[1].key == "mybank.com|me@example.com")
        let secret = logins[1].secret
        #expect(secret.template == .login)
        #expect(secret.fields.map(\.label) == ["Website", "Username", "Password", "Notes"])
        #expect(secret.fields[2].concealed)
    }

    @Test func readsBitwardenAndChromeExports() throws {
        let bitwarden = """
            folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp
            ,,login,Mail,,,0,https://mail.example.com,me,secret1,
            ,,card,Visa,,,0,,,,
            """
        let chrome = "name,url,username,password,note\nexample.com,https://example.com/,bob,pw,\n"
        let fromBitwarden = try PasswordImport.logins(from: Data(bitwarden.utf8))
        #expect(fromBitwarden.map(\.name) == ["Mail"])
        #expect(try PasswordImport.logins(from: Data(chrome.utf8)).first?.username == "bob")
        // Named from the site when the export has no title.
        let untitled = try PasswordImport.logins(from: Data("url,username,password\nhttps://www.shop.com/a,me,pw\n".utf8))
        #expect(untitled.first?.name == "shop.com")
        #expect(throws: PasswordImport.Problem.self) { try PasswordImport.logins(from: Data("hello,world\n1,2\n".utf8)) }
    }
}

extension VaultFlowTests {
    @Test func importingTwiceAddsNothingTwice() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let state = AppState()
        try await state.create(password: "real password 123", touchID: false)
        let logins = try PasswordImport.logins(from: Data("Title,URL,Username,Password\nA,https://a.com,me,1\nB,https://b.com,me,2\n".utf8))
        #expect(state.importLogins(logins) == (2, 0, 0))
        #expect(state.files.allSatisfy { $0.entry == .secret && $0.folder == "Imported" })
        #expect(state.importLogins(logins) == (0, 2, 0))
        let stored = try JSONDecoder().decode(Secret.self, from: state.read(state.files[0]))
        #expect(stored.fields[2].value == "1" || stored.fields[2].value == "2")
    }
}
