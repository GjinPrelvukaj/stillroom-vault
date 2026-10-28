import CryptoKit
import Foundation
import Testing
@testable import Stillroom

/// The password is the one way in that always works, so it must open what it sealed and nothing else must.
@Test func thePasswordOpensTheKeyItSealed() throws {
    let key = SymmetricKey(size: .bits256)
    let sealed = try sealWithPassword(key, password: "correct horse battery")
    #expect(try openWithPassword(sealed, password: "correct horse battery").data == key.data)
}

@Test func aWrongPasswordIsTurnedAway() throws {
    let sealed = try sealWithPassword(SymmetricKey(size: .bits256), password: "correct horse battery")
    #expect(throws: VaultError.self) { try openWithPassword(sealed, password: "correct horse batterY") }
}

@Test func aChangedByteIsTurnedAway() throws {
    let key = SymmetricKey(size: .bits256)
    var sealed = try seal(Data("secret".utf8), with: key)
    sealed[sealed.count - 1] ^= 1
    #expect(throws: (any Error).self) { try unseal(sealed, with: key) }
}
