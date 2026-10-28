import CryptoKit
import Foundation

/// The emergency kit: a secret that opens the vault, split into printed pieces so that any `threshold` of them
/// together rebuild it and fewer show nothing at all (Shamir's secret sharing over GF(256)). One piece each to people
/// you trust; no server, nothing to keep running. The secret seals the vault key in emergency.key the way the
/// recovery key does in recovery.key.
///
/// A piece, before it's written out: version (1), threshold, index (1...255), the share's 16 bytes, then the first
/// two bytes of SHA-256 over all of that, to catch a mistyped piece. 21 bytes, written as 34 Crockford base32
/// characters in groups of four, prefixed "VK".
enum EmergencyKit {
    static let secretLength = 16
    static let version: UInt8 = 1

    struct Piece: Equatable {
        let threshold: Int
        let index: Int
        let share: [UInt8]
    }

    enum Problem: LocalizedError, Equatable {
        case mistyped
        case mixed
        case notEnough(Int)

        var errorDescription: String? {
            switch self {
            case .mistyped: "One of those pieces doesn't read right. Check it letter by letter against the paper."
            case .mixed: "Those pieces come from different kits."
            case .notEnough(let n): "This kit needs \(n) different pieces."
            }
        }
    }

    // MARK: Splitting and joining

    /// `count` pieces, any `threshold` of which give back `secret`.
    static func split(_ secret: [UInt8], threshold: Int, count: Int) -> [Piece] {
        precondition((2...count).contains(threshold) && count <= 255)
        var random = SystemRandomNumberGenerator()
        // One random polynomial per byte, its constant term the byte itself.
        let polynomials = secret.map { byte in [byte] + (1..<threshold).map { _ in UInt8.random(in: 0...255, using: &random) } }
        return (1...count).map { x in
            Piece(threshold: threshold, index: x, share: polynomials.map { evaluate($0, at: UInt8(x)) })
        }
    }

    /// The secret from enough pieces of one kit.
    static func join(_ pieces: [Piece]) throws -> [UInt8] {
        guard let first = pieces.first else { throw Problem.notEnough(2) }
        guard pieces.allSatisfy({ $0.threshold == first.threshold && $0.share.count == first.share.count }) else { throw Problem.mixed }
        let distinct = Dictionary(pieces.map { ($0.index, $0) }, uniquingKeysWith: { a, _ in a }).values.sorted { $0.index < $1.index }
        guard distinct.count >= first.threshold else { throw Problem.notEnough(first.threshold) }
        let used = Array(distinct.prefix(first.threshold))
        // Lagrange interpolation at x = 0, byte by byte.
        return (0..<first.share.count).map { b in
            used.indices.reduce(UInt8(0)) { sum, i in
                let xi = UInt8(used[i].index)
                var weight: UInt8 = 1
                for j in used.indices where j != i {
                    let xj = UInt8(used[j].index)
                    weight = multiply(weight, divide(xj, xj ^ xi))
                }
                return sum ^ multiply(used[i].share[b], weight)
            }
        }
    }

    // MARK: Writing pieces down

    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    static func code(_ piece: Piece) -> String {
        var bytes = [version, UInt8(piece.threshold), UInt8(piece.index)] + piece.share
        bytes += Array(SHA256.hash(data: bytes).prefix(2))
        var bits = 0, value = 0
        var chars: [Character] = []
        for byte in bytes {
            value = value << 8 | Int(byte)
            bits += 8
            while bits >= 5 {
                chars.append(alphabet[(value >> (bits - 5)) & 31])
                bits -= 5
            }
            value &= (1 << bits) - 1
        }
        if bits > 0 { chars.append(alphabet[(value << (5 - bits)) & 31]) }
        let groups = stride(from: 0, to: chars.count, by: 4).map { String(chars[$0..<min($0 + 4, chars.count)]) }
        return "VK-" + groups.joined(separator: "-")
    }

    /// A piece as typed from paper: any case, dashes or spaces anywhere, O for 0 and I or L for 1 all fine.
    static func piece(_ typed: String) throws -> Piece {
        var text = typed.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        if text.hasPrefix("VK") { text.removeFirst(2) }
        var value = 0, bits = 0
        var bytes: [UInt8] = []
        for c in text {
            let c: Character = c == "O" ? "0" : (c == "I" || c == "L") ? "1" : c
            guard let digit = alphabet.firstIndex(of: c) else { throw Problem.mistyped }
            value = value << 5 | digit
            bits += 5
            if bits >= 8 {
                bytes.append(UInt8((value >> (bits - 8)) & 0xFF))
                bits -= 8
            }
            value &= (1 << bits) - 1
        }
        let length = 3 + secretLength + 2
        guard bytes.count == length, bytes[0] == version else { throw Problem.mistyped }
        let body = Array(bytes.prefix(length - 2))
        guard Array(SHA256.hash(data: body).prefix(2)) == Array(bytes.suffix(2)),
              (2...10).contains(Int(bytes[1])), bytes[2] >= 1 else { throw Problem.mistyped }
        return Piece(threshold: Int(bytes[1]), index: Int(bytes[2]), share: Array(body.dropFirst(3)))
    }

    /// The secret as the "password" that seals the vault key in emergency.key.
    static func password(_ secret: [UInt8]) -> String { secret.map { String(format: "%02x", $0) }.joined() }

    // MARK: GF(256), the AES field (x^8 + x^4 + x^3 + x + 1)

    private static func multiply(_ a: UInt8, _ b: UInt8) -> UInt8 {
        var a = a, b = b, product: UInt8 = 0
        while b != 0 {
            if b & 1 != 0 { product ^= a }
            a = (a << 1) ^ (a & 0x80 != 0 ? 0x1B : 0)
            b >>= 1
        }
        return product
    }

    /// a / b, as a times b to the 254th (b's inverse, since b^255 = 1).
    private static func divide(_ a: UInt8, _ b: UInt8) -> UInt8 {
        var inverse: UInt8 = 1
        for _ in 0..<254 { inverse = multiply(inverse, b) }
        return multiply(a, inverse)
    }

    private static func evaluate(_ coefficients: [UInt8], at x: UInt8) -> UInt8 {
        coefficients.reversed().reduce(UInt8(0)) { multiply($0, x) ^ $1 }
    }
}
