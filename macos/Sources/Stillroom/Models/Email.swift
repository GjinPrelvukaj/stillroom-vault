import Foundation
import UniformTypeIdentifiers

/// An email message (.eml, or Apple Mail's .emlx), read into what a person sees: who, when, the subject, the body (as
/// the sender's HTML when there is one, else plain text) and the attachments. Read entirely here, on this Mac; nothing
/// in it is ever fetched from the network.
struct Email: Sendable {
    var from = ""
    var to = ""
    var cc = ""
    var subject = ""
    var date: Date?
    var html: String?
    var text: String?
    var attachments: [Attachment] = []
    /// Pictures the HTML shows by Content-ID ("cid:…"), put straight into the page.
    var inline: [String: (type: String, data: Data)] = [:]

    struct Attachment: Identifiable, Sendable {
        let id = UUID()
        var name: String
        var type: String
        var data: Data
    }

    /// The words in it, for search: who, the subject and the body without its markup.
    var words: String {
        let body = text ?? html.map(Self.stripTags) ?? ""
        return [from, to, cc, subject, body, attachments.map(\.name).joined(separator: " ")].joined(separator: "\n")
    }

    /// Reads a message. Nil when the bytes don't look like one at all.
    static func parse(_ data: Data) -> Email? { parse(data, depth: 0) }

    /// How deep parts may sit inside parts (and messages inside messages) before the rest is left unread, so a
    /// message built to nest forever can't crash the app.
    private static let deepest = 16

    /// At most this many inline pictures: putting each in place costs a pass over the whole page, so an email built
    /// with thousands of tiny ones would otherwise take minutes to show. Past it they're listed as attachments.
    private static let mostInline = 256

    private static func parse(_ data: Data, depth: Int) -> Email? {
        // Bytes as Latin-1 keep every byte as one character, so the structure can be cut as text and each part's
        // bytes recovered exactly; each part's own charset is applied only when it's turned into words.
        guard let raw = String(data: unwrapEMLX(data), encoding: .isoLatin1) else { return nil }
        let top = Part(raw)
        guard top.headers["from"] != nil || top.headers["subject"] != nil || top.headers["content-type"] != nil else { return nil }
        var email = Email()
        email.from = decodeWords(top.headers["from"] ?? "")
        email.to = decodeWords(top.headers["to"] ?? "")
        email.cc = decodeWords(top.headers["cc"] ?? "")
        email.subject = decodeWords(top.headers["subject"] ?? "")
        email.date = top.headers["date"].flatMap(parseDate)
        email.take(top, depth: depth)
        return email
    }

    /// Walks a part and everything inside it, keeping the first HTML and plain-text bodies and every attachment.
    private mutating func take(_ part: Part, depth: Int) {
        guard depth < Email.deepest else { return }
        let type = part.contentType.value.lowercased()
        if type.hasPrefix("multipart/") {
            for child in part.children() { take(child, depth: depth + 1) }
            return
        }
        if type == "message/rfc822" {
            // A forwarded message: its body is shown as part of this one.
            if let inner = Email.parse(part.decodedBody, depth: depth + 1) {
                html = html ?? inner.html
                text = text ?? inner.text
                attachments += inner.attachments
                for (id, picture) in inner.inline where inline[id] == nil && inline.count < Email.mostInline {
                    inline[id] = picture
                }
            }
            return
        }
        let disposition = Email.parameters(part.headers["content-disposition"] ?? "")
        let name = Email.fileName(disposition.params, part.contentType.params)
        let isAttachment = disposition.value.lowercased() == "attachment" || (name != nil && !type.hasPrefix("text/"))
        if let id = part.headers["content-id"], type.hasPrefix("image/"), disposition.value.lowercased() != "attachment",
           inline.count < Email.mostInline {
            inline[id.trimmingCharacters(in: CharacterSet(charactersIn: "<> "))] = (type, part.decodedBody)
            return
        }
        if isAttachment {
            attachments.append(Attachment(name: name ?? "Attachment", type: type, data: part.decodedBody))
        } else if type == "text/html" {
            html = html ?? part.text
        } else if type == "text/plain" || type.isEmpty {
            text = text ?? part.text
        } else if !part.decodedBody.isEmpty {
            attachments.append(Attachment(name: name ?? "Attachment", type: type, data: part.decodedBody))
        }
    }

    /// The HTML to show: the sender's, with inline pictures put in place, or the plain text set as a page.
    /// Built off the main thread, once (`EmailView`): with big pictures it takes a moment.
    func page() -> String {
        if var html {
            // Each reference gets a whole copy of its picture, so a small email naming one picture thousands of times
            // would grow into gigabytes: past 64 MB of pictures, the rest stay unshown.
            var budget = 64 << 20
            for (id, picture) in inline {
                let data = "data:\(picture.type);base64,\(picture.data.base64EncodedString())"
                let uses = html.components(separatedBy: "cid:\(id)").count - 1
                guard uses > 0, uses * data.utf8.count <= budget else { continue }
                budget -= uses * data.utf8.count
                html = html.replacingOccurrences(of: "cid:\(id)", with: data)
            }
            return html
        }
        let escaped = (text ?? "").replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return "<pre style=\"white-space:pre-wrap;font:13px -apple-system,sans-serif\">\(escaped)</pre>"
    }

    // MARK: Parts

    private struct Part {
        var headers: [String: String] = [:]
        var body: String = ""

        init(_ raw: String) {
            // Headers end at the first empty line; lines starting with a space or tab continue the one before.
            let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
            // A part with no headers starts with its empty line.
            let split = normalized.hasPrefix("\n") ? normalized.startIndex..<normalized.index(after: normalized.startIndex)
                : normalized.range(of: "\n\n")
            let head = split.map { String(normalized[..<$0.lowerBound]) } ?? normalized
            body = split.map { String(normalized[$0.upperBound...]) } ?? ""
            var current: (String, String)?
            for line in head.split(separator: "\n", omittingEmptySubsequences: false) {
                if let first = line.first, first == " " || first == "\t", current != nil {
                    current!.1 += " " + line.trimmingCharacters(in: .whitespaces)
                    continue
                }
                if let current { headers[current.0] = headers[current.0] ?? current.1 }
                if let colon = line.firstIndex(of: ":") {
                    current = (line[..<colon].lowercased().trimmingCharacters(in: .whitespaces),
                               line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces))
                } else {
                    current = nil
                }
            }
            if let current { headers[current.0] = headers[current.0] ?? current.1 }
        }

        var contentType: (value: String, params: [String: String]) { Email.parameters(headers["content-type"] ?? "text/plain") }

        /// The parts of a multipart, cut at its boundary lines.
        func children() -> [Part] {
            guard let boundary = contentType.params["boundary"], !boundary.isEmpty else { return [] }
            let marker = "--" + boundary
            var parts: [Part] = []
            var current: [Substring]?
            for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed == marker + "--" { break }
                if trimmed == marker {
                    if let current { parts.append(Part(current.joined(separator: "\n"))) }
                    current = []
                } else {
                    current?.append(line)
                }
            }
            if let current, !current.isEmpty { parts.append(Part(current.joined(separator: "\n"))) }
            return parts
        }

        /// The body's bytes, undoing base64 or quoted-printable.
        var decodedBody: Data {
            switch headers["content-transfer-encoding"]?.lowercased().trimmingCharacters(in: .whitespaces) {
            case "base64":
                return Data(base64Encoded: body.filter { !$0.isWhitespace }, options: .ignoreUnknownCharacters) ?? Data()
            case "quoted-printable":
                return Email.quotedPrintable(body)
            default:
                return body.data(using: .isoLatin1) ?? Data()
            }
        }

        /// The body as words, in the charset it says it uses.
        var text: String { Email.string(decodedBody, charset: contentType.params["charset"]) }
    }

    // MARK: Decoding

    /// Apple Mail's .emlx: a byte count on the first line, the message, then a property list after it.
    private static func unwrapEMLX(_ data: Data) -> Data {
        guard let newline = data.prefix(20).firstIndex(of: 0x0A),
              let count = Int(String(decoding: data[data.startIndex..<newline], as: UTF8.self).trimmingCharacters(in: .whitespaces))
        else { return data }
        let start = newline + 1
        // A count that's nonsense (negative, or bigger than the file) leaves the bytes as they are.
        guard count > 0, count <= data.endIndex - start else { return data }
        return data[start..<(start + count)]
    }

    static func string(_ data: Data, charset: String?) -> String {
        if let charset {
            let cf = CFStringConvertIANACharSetNameToEncoding(charset.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) as CFString)
            if cf != kCFStringEncodingInvalidId,
               let text = String(data: data, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))) {
                return text
            }
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    /// Quoted-printable ("=C3=A9", "=" at a line's end joining lines) back to bytes. The text came from Latin-1, so
    /// each character is one original byte.
    static func quotedPrintable(_ text: String) -> Data {
        let s = Array(text.unicodeScalars)
        func hex(_ c: Unicode.Scalar) -> UInt8? { UInt8(String(c), radix: 16) }
        var out = Data()
        var i = 0
        while i < s.count {
            if s[i] == "=" {
                if i + 1 < s.count, s[i + 1] == "\n" { i += 2; continue }
                if i + 2 < s.count, s[i + 1] == "\r", s[i + 2] == "\n" { i += 3; continue }
                if i + 2 < s.count, let high = hex(s[i + 1]), let low = hex(s[i + 2]) {
                    out.append(high << 4 | low); i += 3; continue
                }
            }
            out.append(UInt8(truncatingIfNeeded: s[i].value))
            i += 1
        }
        return out
    }

    /// Header words like "=?UTF-8?B?…?=" or "=?iso-8859-1?Q?…?=", decoded; plain words left as they are.
    static func decodeWords(_ header: String) -> String {
        let latin = header
        guard let pattern = try? NSRegularExpression(pattern: #"=\?([^?]+)\?([BbQq])\?([^?]*)\?="#) else { return latin }
        let ns = latin as NSString
        var out = ""
        var last = 0
        var previousWasEncoded = false
        for match in pattern.matches(in: latin, range: NSRange(location: 0, length: ns.length)) {
            let between = ns.substring(with: NSRange(location: last, length: match.range.location - last))
            // Space between two encoded words is dropped, as the standard says.
            if !(previousWasEncoded && between.trimmingCharacters(in: .whitespaces).isEmpty) { out += plainHeader(between) }
            let charset = ns.substring(with: match.range(at: 1)).split(separator: "*").first.map(String.init)
            let kind = ns.substring(with: match.range(at: 2)).uppercased()
            let payload = ns.substring(with: match.range(at: 3))
            let bytes: Data = kind == "B"
                ? Data(base64Encoded: payload, options: .ignoreUnknownCharacters) ?? Data()
                : quotedPrintable(payload.replacingOccurrences(of: "_", with: " "))
            out += string(bytes, charset: charset)
            last = match.range.location + match.range.length
            previousWasEncoded = true
        }
        out += plainHeader(ns.substring(from: last))
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// Unencoded header text: its bytes were read as Latin-1; most senders meant UTF-8.
    private static func plainHeader(_ text: String) -> String {
        guard let bytes = text.data(using: .isoLatin1), let utf8 = String(data: bytes, encoding: .utf8) else { return text }
        return utf8
    }

    /// "text/html; charset=utf-8; name=\"a b.pdf\"" → ("text/html", ["charset": "utf-8", "name": "a b.pdf"]).
    static func parameters(_ header: String) -> (value: String, params: [String: String]) {
        var pieces: [String] = []
        var current = ""
        var quoted = false
        for c in header {
            if c == "\"" { quoted.toggle(); continue }
            if c == ";" && !quoted { pieces.append(current); current = ""; continue }
            current.append(c)
        }
        pieces.append(current)
        var params: [String: String] = [:]
        for piece in pieces.dropFirst() {
            guard let eq = piece.firstIndex(of: "=") else { continue }
            params[piece[..<eq].trimmingCharacters(in: .whitespaces).lowercased()] = piece[piece.index(after: eq)...].trimmingCharacters(in: .whitespaces)
        }
        return (pieces[0].trimmingCharacters(in: .whitespaces), params)
    }

    /// An attachment's name: RFC 2231 "filename*=UTF-8''…" first, then filename=, then the type's name=.
    private static func fileName(_ disposition: [String: String], _ type: [String: String]) -> String? {
        if let starred = disposition["filename*"] ?? type["name*"] {
            let parts = starred.components(separatedBy: "''")
            let encoded = parts.count == 2 ? parts[1] : starred
            if let decoded = encoded.removingPercentEncoding { return decoded }
        }
        return (disposition["filename"] ?? type["name"]).map(decodeWords)
    }

    private static func parseDate(_ header: String) -> Date? {
        // A trailing "(CET)"-style comment goes: everything from the first "(" (a plain search, not a pattern that
        // backtracks on a header full of brackets).
        let cleaned = String(header[..<(header.firstIndex(of: "(") ?? header.endIndex)]).trimmingCharacters(in: .whitespaces)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for format in ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm Z"] {
            f.dateFormat = format
            if let date = f.date(from: cleaned) { return date }
        }
        return nil
    }

    /// The words of an HTML part, for search: tags, styles and scripts out. One pass, so time grows with the length
    /// (the patterns it replaced took minutes on a long run of "<").
    static func stripTags(_ html: String) -> String {
        let text = Array(html.unicodeScalars)
        var out = String.UnicodeScalarView()
        // Once a search for a closing has failed, it fails from anywhere later too: never searched again.
        var noMore: Set<String> = []
        func find(_ closing: String, from start: Int) -> Int? {
            guard !noMore.contains(closing) else { return nil }
            let needle = Array(closing.unicodeScalars)
            var i = start
            while i + needle.count <= text.count {
                if (0..<needle.count).allSatisfy({ Character(text[i + $0]).lowercased() == Character(needle[$0]).lowercased() }) { return i }
                i += 1
            }
            noMore.insert(closing)
            return nil
        }
        func starts(_ word: String, at i: Int) -> Bool {
            let w = Array(word.unicodeScalars)
            return i + w.count <= text.count && (0..<w.count).allSatisfy { Character(text[i + $0]).lowercased() == Character(w[$0]).lowercased() }
        }
        var i = 0
        while i < text.count {
            guard text[i] == "<" else { out.append(text[i]); i += 1; continue }
            if starts("<style", at: i), let end = find("</style>", from: i) { i = end + 8; out.append(" "); continue }
            if starts("<script", at: i), let end = find("</script>", from: i) { i = end + 9; out.append(" "); continue }
            if i + 1 < text.count, text[i + 1] != ">", let end = find(">", from: i + 1) { i = end + 1; out.append(" "); continue }
            out.append(text[i])
            i += 1
        }
        return String(out).replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    /// Whether a file is an email by its kind or its name.
    static func isEmail(_ file: VaultFile) -> Bool {
        let ending = (file.name as NSString).pathExtension.lowercased()
        return ["eml", "emlx"].contains(ending) || file.uti == "com.apple.mail.email" || file.uti == "com.apple.mail.emlx"
            || UTType("public.email-message").map { file.type?.conforms(to: $0) == true } == true
    }
}
