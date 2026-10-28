import Foundation

/// Accounts from another password manager's export file (CSV): Apple Passwords, Chrome and other browsers,
/// Bitwarden, 1Password. Each account becomes a Login secret. Read in memory only; nothing is written to disk here.
enum PasswordImport {
    struct Login: Equatable {
        var title: String
        var url: String
        var username: String
        var password: String
        var notes: String
        var otp: String

        /// The name it's listed under: its title, else the site's host, else the username.
        var name: String {
            if !title.isEmpty { return title }
            if let host = URL(string: url)?.host(), !host.isEmpty { return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host }
            return username.isEmpty ? "Login" : username
        }

        /// Two exports of the same account match on site and username, however the site was written.
        var key: String { "\(PasswordImport.site(url))|\(username.lowercased())" }

        var secret: Secret {
            var secret = Secret(template: .login)
            secret.fields[0].value = url
            secret.fields[1].value = username
            secret.fields[2].value = password
            if !notes.isEmpty { secret.fields.append(.init(label: "Notes", value: notes)) }
            if !otp.isEmpty { secret.fields.append(.init(label: "Two-factor setup", value: otp, concealed: true)) }
            return secret
        }
    }

    enum Problem: LocalizedError {
        case notAnExport

        var errorDescription: String? {
            "That file isn't a password export. In the Passwords app, choose File › Export All Passwords, then pick the file it saves."
        }
    }

    /// The column names each app uses, lowercased; the first one present wins.
    private static let titles = ["title", "name"]
    private static let urls = ["url", "login_uri", "website", "web site", "login url"]
    private static let usernames = ["username", "login_username", "user name", "login", "email"]
    private static let passwords = ["password", "login_password"]
    private static let notesColumns = ["notes", "note", "extra", "comments"]
    private static let otps = ["otpauth", "login_totp", "totp", "otp", "one-time password"]

    /// Every account in an export, in order. Rows that aren't logins (Bitwarden's cards and notes) and rows with
    /// neither a password nor a username are left out.
    static func logins(from data: Data) throws -> [Login] {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { throw Problem.notAnExport }
        var rows = parse(text)
        guard !rows.isEmpty else { throw Problem.notAnExport }
        let header = rows.removeFirst().map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        func column(_ names: [String]) -> Int? { names.lazy.compactMap { header.firstIndex(of: $0) }.first }
        guard let password = column(passwords) else { throw Problem.notAnExport }
        let (title, url, username, notes, otp) = (column(titles), column(urls), column(usernames), column(notesColumns), column(otps))
        let type = header.firstIndex(of: "type")

        return rows.compactMap { row in
            func value(_ i: Int?) -> String { i.flatMap { $0 < row.count ? row[$0] : nil }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
            if let type, !value(type).isEmpty, value(type).lowercased() != "login" { return nil }
            let login = Login(title: value(title), url: value(url), username: value(username), password: value(password),
                              notes: value(notes), otp: value(otp))
            return login.password.isEmpty && login.username.isEmpty ? nil : login
        }
    }

    /// The site's host without "www.", or the address as written when it has none.
    static func site(_ url: String) -> String {
        let host = URL(string: url)?.host() ?? URL(string: "https://" + url)?.host() ?? url
        return (host.hasPrefix("www.") ? String(host.dropFirst(4)) : host).lowercased()
    }

    /// CSV as RFC 4180 writes it: commas between fields, quotes round any field holding commas, quotes or line
    /// breaks, and a quote inside one doubled.
    static func parse(_ text: String) -> [[String]] {
        // A byte-order mark at the start (Excel and some exports write one) isn't part of the first column's name.
        let text = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var chars = text.unicodeScalars.makeIterator()
        var pending: Unicode.Scalar?
        func next() -> Unicode.Scalar? {
            if let p = pending { pending = nil; return p }
            return chars.next()
        }
        while let c = next() {
            if quoted {
                if c == "\"" {
                    let after = next()
                    if after == "\"" { field.unicodeScalars.append("\"") } else { quoted = false; pending = after }
                } else {
                    field.unicodeScalars.append(c)
                }
                continue
            }
            switch c {
            case "\"": quoted = true
            case ",": row.append(field); field = ""
            case "\r": break
            case "\n":
                row.append(field); field = ""
                if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                row = []
            default: field.unicodeScalars.append(c)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}
