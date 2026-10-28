import CryptoKit
import Foundation

/// How hard a password is stretched with Argon2id: memory, passes and lanes. Each guess then needs this much memory
/// for this long, which graphics cards and custom chips are bad at; written into each sealed key, so it can rise
/// later without existing keys failing to open. Tests turn it down so they stay quick.
struct PasswordCost: Equatable, Sendable {
    var memoryKiB: UInt32
    var passes: UInt32
    var lanes: UInt32

    nonisolated(unsafe) static var current = PasswordCost(memoryKiB: 512 * 1024, passes: 3, lanes: 4)
}

/// The start of every key sealed with a password (Argon2id, mark version 1).
private let argonMark = Data("VA2".utf8) + Data([1])

/// AES-256-GCM: nonce, ciphertext and tag in one piece. Any change to the piece makes `unseal` fail. `binding` is
/// authenticated data naming what the piece is: it isn't stored, so the piece only opens where it's expected.
func seal(_ data: some DataProtocol, with key: SymmetricKey, binding: Data? = nil) throws -> Data {
    if let binding { return try AES.GCM.seal(data, using: key, authenticating: binding).combined! }
    return try AES.GCM.seal(data, using: key).combined!
}

func unseal(_ data: Data, with key: SymmetricKey, binding: Data? = nil) throws -> Data {
    let box = try AES.GCM.SealedBox(combined: data)
    if let binding { return try AES.GCM.open(box, using: key, authenticating: binding) }
    return try AES.GCM.open(box, using: key)
}

/// What each kind of seal is bound to (format 3, and the covers of format 4). Items are bound to the id they were sealed under, so no sealed file
/// opens in another's place; the list and search index each to their own name, so none opens as another.
/// These labels (and the HKDF ones in MacLock, TouchIDKey and IntruderLog) are part of the format and keep the app's
/// first name, "Vault": changing one makes every existing vault unreadable.
enum Bound {
    static let list = Data("Vault list 3".utf8)
    static let search = Data("Vault search 3".utf8)
    /// A slot's list or index inside its cover (format 4): bound to what it is and whose, so neither swaps.
    static func cover(_ kind: String, _ slot: String) -> Data { Data("Vault cover 4".utf8) + Data(kind.utf8) + Data(slot.utf8) }
    /// The cover key sealed with a slot key, in that slot's cover.key.
    static func coverKey(_ slot: String) -> Data { Data("Vault cover key 4".utf8) + Data(slot.utf8) }
    static func item(_ sealedAs: UUID) -> Data { Data("Vault item 3".utf8) + withUnsafeBytes(of: sealedAs.uuid) { Data($0) } }
}

/// A key made from a password and a salt with Argon2id at the given cost.
func stretchArgon(_ password: String, salt: Data, cost: PasswordCost) throws -> SymmetricKey {
    // Not logged: how many times this runs per unlock would say whether a decoy is set.
    var typed = Data(password.utf8)
    defer { typed.resetBytes(in: 0..<typed.count) }
    var stretched = try argon2id(password: typed, salt: salt, memoryKiB: cost.memoryKiB,
                                 iterations: cost.passes, parallelism: cost.lanes, length: 32)
    defer { stretched.resetBytes(in: 0..<stretched.count) }
    return SymmetricKey(data: stretched)
}

/// The vault key sealed with a password: a mark, the Argon2id cost and the salt, then the sealed key. The salt and
/// cost are the ones the password was stretched with, so the same password stretches to the same key again.
func sealWithPassword(_ vaultKey: SymmetricKey, password: String) throws -> Data {
    let cost = PasswordCost.current
    let salt = SymmetricKey(size: .bits128).data
    var header = argonMark
    for value in [cost.memoryKiB, cost.passes, cost.lanes] { withUnsafeBytes(of: value.bigEndian) { header.append(contentsOf: $0) } }
    let sealing = try stretchArgon(password, salt: salt, cost: cost)
    // Sealed straight from the key's own memory, with no plain copy of it left behind.
    return try header + salt + vaultKey.withUnsafeBytes { try seal($0, with: sealing) }
}

func openWithPassword(_ sealed: Data, password: String) throws -> SymmetricKey {
    let sealed = Data(sealed)
    guard usesArgon(sealed), sealed.count > 32 else { throw VaultError.damaged }
    func number(at i: Int) -> UInt32 { sealed[i..<i + 4].reduce(0) { $0 << 8 | UInt32($1) } }
    let cost = PasswordCost(memoryKiB: number(at: 4), passes: number(at: 8), lanes: number(at: 12))
    // A cost no real key would carry (a damaged or doctored file) mustn't hang or crash the app. Up to 2 GiB and
    // 10 passes leaves room to raise today's cost; 4 GiB at 32 passes would take minutes and swap an 8 GB Mac.
    guard cost.lanes >= 1, cost.lanes <= 16, cost.passes >= 1, cost.passes <= 10,
          cost.memoryKiB >= 8 * cost.lanes, cost.memoryKiB <= 2 * 1024 * 1024 else { throw VaultError.damaged }
    let key = try stretchArgon(password, salt: sealed[16..<32], cost: cost)
    let body = sealed.dropFirst(32)
    // A wrong password stretches to a key the seal rejects: that is the only way to tell.
    guard var opened = try? unseal(Data(body), with: key) else { throw VaultError.wrongPassword }
    defer { opened.resetBytes(in: 0..<opened.count) }
    return SymmetricKey(data: opened)
}

/// Whether a file starts like a key sealed with a password.
func usesArgon(_ sealed: Data) -> Bool { sealed.prefix(4) == argonMark }

extension SymmetricKey {
    var data: Data { withUnsafeBytes { Data($0) } }
}

/// Padmé: the length a file is padded to before sealing, so its sealed size tells at most about 12% of its real one.
/// Lengths round up to fewer significant bits the larger they are.
func paddedLength(_ n: Int) -> Int {
    guard n > 1 else { return n }
    let e = Int.bitWidth - 1 - n.leadingZeroBitCount
    let s = Int.bitWidth - e.leadingZeroBitCount
    let mask = (1 << (e - s)) - 1
    return (n + mask) & ~mask
}

/// A recovery key: 25 characters from an alphabet with no look-alikes (no 0/O, 1/I/L), in groups of five. About
/// 124 random bits, far past guessing however many tries an attacker has.
func makeRecoveryCode() -> String {
    let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
    var random = SystemRandomNumberGenerator()
    let chars = (0..<25).map { _ in alphabet.randomElement(using: &random)! }
    return stride(from: 0, to: 25, by: 5).map { String(chars[$0..<$0 + 5]) }.joined(separator: "-")
}

/// A typed recovery key as it is stretched: capitals, no dashes or spaces, so however it's written it matches.
func normalizedRecoveryCode(_ typed: String) -> String {
    typed.uppercased().filter { $0.isLetter || $0.isNumber }
}

enum VaultError: LocalizedError {
    case wrongPassword, wrongRecoveryKey, damaged, folder, touchIDUnavailable, touchIDChanged, notThisMac, sameAsOther, wrongKit,
         newerVault, tooSoon

    var errorDescription: String? {
        switch self {
        case .wrongPassword: "That password doesn't open this vault."
        case .wrongRecoveryKey: "That recovery key doesn't open this vault."
        case .damaged: "The vault's files are damaged or were changed outside Stillroom."
        case .folder: "That's a folder. Add the folder itself and what's inside it goes in."
        case .touchIDUnavailable: "This Mac has no Touch ID set up."
        case .touchIDChanged: "Touch ID couldn't open it. Use your password, then turn Touch ID on again in Settings."
        case .notThisMac: "This vault is locked to another Mac. Open it with your recovery key."
        case .sameAsOther: "Pick a different password: that one is already in use for this vault."
        case .wrongKit: "Those pieces don't open this vault. They may be from an older kit."
        case .newerVault: "This vault was saved by a newer version of Stillroom. Update Stillroom to open it."
        case .tooSoon: "Too many password changes in a row. Wait a few minutes, then try again."
        }
    }
}
