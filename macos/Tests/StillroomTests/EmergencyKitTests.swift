import Foundation
import Testing
@testable import Stillroom

struct EmergencyKitTests {
    let secret = (0..<16).map { _ in UInt8.random(in: 0...255) }

    @Test(arguments: [(2, 2), (2, 3), (3, 5)])
    func anyEnoughPiecesGiveTheSecretBack(threshold: Int, count: Int) throws {
        let pieces = EmergencyKit.split(secret, threshold: threshold, count: count)
        // Every combination of exactly `threshold` pieces.
        func combos(_ items: [EmergencyKit.Piece], _ k: Int) -> [[EmergencyKit.Piece]] {
            guard k > 0 else { return [[]] }
            guard let first = items.first else { return [] }
            return combos(Array(items.dropFirst()), k - 1).map { [first] + $0 } + combos(Array(items.dropFirst()), k)
        }
        for combo in combos(pieces, threshold) { #expect(try EmergencyKit.join(combo) == secret) }
        #expect(throws: EmergencyKit.Problem.notEnough(threshold)) { try EmergencyKit.join(Array(pieces.prefix(threshold - 1))) }
    }

    @Test func piecesSurviveBeingWrittenAndTypedBack() throws {
        for piece in EmergencyKit.split(secret, threshold: 2, count: 3) {
            let code = EmergencyKit.code(piece)
            #expect(code.hasPrefix("VK-"))
            #expect(try EmergencyKit.piece(code) == piece)
            // Typed sloppily: lowercase, spaces for dashes, O for 0, L for 1.
            let sloppy = code.lowercased().replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "0", with: "o").replacingOccurrences(of: "1", with: "l")
            #expect(try EmergencyKit.piece(sloppy) == piece)
        }
    }

    @Test func aMistypedPieceIsCaught() {
        let code = EmergencyKit.code(EmergencyKit.split(secret, threshold: 2, count: 3)[0])
        var chars = Array(code)
        // A character in the middle: the last one is partly padding, so changing it may change nothing.
        let i = chars.indices.filter { chars[$0] != "-" }[12]
        chars[i] = chars[i] == "A" ? "B" : "A"
        #expect(throws: EmergencyKit.Problem.mistyped) { try EmergencyKit.piece(String(chars)) }
        #expect(throws: EmergencyKit.Problem.mistyped) { try EmergencyKit.piece("VK-1234") }
    }

    @Test func piecesFromTwoKitsDontMix() throws {
        let a = EmergencyKit.split(secret, threshold: 2, count: 3)
        let b = EmergencyKit.split(secret, threshold: 3, count: 5)
        #expect(throws: EmergencyKit.Problem.mixed) { try EmergencyKit.join([a[0], b[1]]) }
    }
}
