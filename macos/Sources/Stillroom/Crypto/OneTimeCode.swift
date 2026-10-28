import CoreImage
import CryptoKit
import Foundation

/// A two-factor setup (RFC 6238 time-based codes): the secret a website shows as a QR code or a "setup key", turned
/// into the rolling 6-digit code it asks for. Takes an `otpauth://totp/…` link or a bare base32 key.
struct OneTimeCode: Equatable, Sendable {
    var key: Data
    var digits = 6
    var period = 30
    var algorithm = Algorithm.sha1

    enum Algorithm: String, Sendable { case sha1 = "SHA1", sha256 = "SHA256", sha512 = "SHA512" }

    /// nil when the text is neither a usable link nor a base32 key. Counter-based (HOTP) links aren't taken.
    init?(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("otpauth://") {
            guard let link = URLComponents(string: text), link.host?.lowercased() == "totp" else { return nil }
            let item = { (name: String) in link.queryItems?.first { $0.name.lowercased() == name }?.value }
            guard let secret = item("secret"), let key = Self.base32(secret) else { return nil }
            self.key = key
            if let digits = item("digits") { guard let n = Int(digits), (6...8).contains(n) else { return nil }; self.digits = n }
            if let period = item("period") { guard let n = Int(period), (1...300).contains(n) else { return nil }; self.period = n }
            if let name = item("algorithm") { guard let a = Algorithm(rawValue: name.uppercased()) else { return nil }; algorithm = a }
        } else {
            guard let key = Self.base32(text) else { return nil }
            self.key = key
        }
    }

    init(key: Data, digits: Int = 6, period: Int = 30, algorithm: Algorithm = .sha1) {
        (self.key, self.digits, self.period, self.algorithm) = (key, digits, period, algorithm)
    }

    /// The code for a moment, as digits (leading zeros kept).
    func code(at date: Date = .now) -> String {
        var counter = UInt64(max(0, date.timeIntervalSince1970) / Double(period)).bigEndian
        let message = Data(bytes: &counter, count: 8)
        let symmetric = SymmetricKey(data: key)
        let mac: [UInt8] = switch algorithm {
        case .sha1: Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: symmetric))
        case .sha256: Array(HMAC<SHA256>.authenticationCode(for: message, using: symmetric))
        case .sha512: Array(HMAC<SHA512>.authenticationCode(for: message, using: symmetric))
        }
        let at = Int(mac[mac.count - 1] & 0x0f)
        let number = (UInt32(mac[at] & 0x7f) << 24 | UInt32(mac[at + 1]) << 16 | UInt32(mac[at + 2]) << 8 | UInt32(mac[at + 3]))
        let code = String(number % UInt32(pow(10, Double(digits))))
        return String(repeating: "0", count: digits - code.count) + code
    }

    /// Seconds until the code changes.
    func secondsLeft(at date: Date = .now) -> Int { period - Int(max(0, date.timeIntervalSince1970)) % period }

    /// RFC 4648 base32, forgiving how people paste it: any case, spaces, dashes, missing padding.
    static func base32(_ text: String) -> Data? {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        let clean = text.uppercased().filter { !" -\t\n=".contains($0) }
        // Under 80 bits isn't a real setup key (and rules out short words typed into the field).
        guard clean.count >= 16 else { return nil }
        var bytes = Data()
        var buffer = 0, bits = 0
        for character in clean {
            guard let value = alphabet.firstIndex(of: character) else { return nil }
            buffer = (buffer << 5 | value) & 0xffff
            bits += 5
            if bits >= 8 {
                bytes.append(UInt8(buffer >> (bits - 8) & 0xff))
                bits -= 8
            }
        }
        return bytes
    }

    /// A QR code in an image (a screenshot of the website's setup page), if it holds a two-factor link.
    static func fromQR(in image: CGImage) -> String? {
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let found = detector?.features(in: CIImage(cgImage: image)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        return found?.first { OneTimeCode($0) != nil }
    }
}

extension Secret.Field {
    /// The field holds a two-factor setup: a link always counts; a bare key only under a label that says so.
    var oneTimeCode: OneTimeCode? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("otpauth://") { return OneTimeCode(value) }
        let label = label.lowercased()
        guard ["two-factor", "2fa", "totp", "one-time", "authenticator"].contains(where: label.contains) else { return nil }
        return OneTimeCode(value)
    }
}
