import CryptoKit
import Foundation

/// A bought licence: one pasteable line, `SR1.<payload>.<signature>`, both parts base64url without padding. The
/// payload is compact JSON and the signature is Ed25519 over the bytes of `SR1.<payload>`, made by the website's
/// signer (website/server/licence.ts). Checked here offline against the public key built in: no network, no clock,
/// no expiry. It lives in one file beside the store, outside both slots, so it lifts the free tier in either vault
/// alike and says nothing about which is which (docs/SECURITY.md rule 2).
struct License: Equatable, Sendable {
    enum Edition: String, Codable, Sendable {
        case personal, family, teams

        var name: String {
            switch self {
            case .personal: "Stillroom Vault"
            case .family: "Family"
            case .teams: "Teams"
            }
        }
    }

    let id: String
    let edition: Edition
    let seats: Int
    let name: String
    let email: String
    /// The day it was issued, as written ("2026-10-28"); shown, never compared with the clock.
    let issued: String

    /// Without a licence a vault holds at most this many items (files, notes and secrets; not folders or versions).
    static let freeItems = 25

    /// Stillroom's public signing key (32 bytes, base64), from `website/scripts/make-licence-keys.mjs` (made
    /// 2026-10-28). Its private half is only in the website's signer and Gjin's own safekeeping.
    static let publicKey = "rVwu2FUZZBSLtMc+bIT0YN6HRTBrkqlyRfEQu/HKvsE="
    static let builtIn = Data(base64Encoded: publicKey).flatMap { try? Curve25519.Signing.PublicKey(rawRepresentation: $0) }
    /// A test key pair's public half, so tests can lift the limit without the real key.
    nonisolated(unsafe) static var signerForTests: Curve25519.Signing.PublicKey?
    static var signer: Curve25519.Signing.PublicKey? { signerForTests ?? builtIn }

    /// Licence ids turned off because the key was posted publicly: each release can refuse them, since nothing offline
    /// can revoke a key. A key that's only shared privately stays on (its name shows in Settings). Add the id
    /// (`txn_…`) here and ship a release; a buyer who lost theirs this way gets a new key by hand.
    static let blocked: Set<String> = []

    enum Problem: Error, LocalizedError {
        case malformed, notSigned, newerVersion, blocked

        var errorDescription: String? {
            switch self {
            case .malformed: "This key doesn't check out: part of it is missing or mistyped. Paste the whole key from the email."
            case .notSigned: "This key doesn't check out: it wasn't signed by Stillroom."
            case .newerVersion: "This key doesn't check out: it's for a newer Stillroom. Update Stillroom, then add it again."
            case .blocked: "This key was turned off because it was posted publicly. If it's yours, write to support@stillroomvault.com for a new one."
            }
        }
    }

    private struct Payload: Codable {
        let v: Int
        let id: String
        let edition: Edition
        let seats: Int
        let name: String
        let email: String
        let issued: String
    }

    /// The key as pasted, with any spaces or line breaks a mail app put in taken out.
    static func tidy(_ typed: String) -> String {
        String(typed.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) })
    }

    /// Checks a pasted key: its shape, then Stillroom's signature, then what it says. Pure: reads nothing but `typed`.
    static func check(_ typed: String, signer: Curve25519.Signing.PublicKey? = signer, blocked: Set<String> = blocked) throws -> License {
        let key = tidy(typed)
        guard key.utf8.count <= 4096 else { throw Problem.malformed }
        let parts = key.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { throw Problem.malformed }
        guard parts[0] == "SR1" else {
            // "SR2" and on: a later format, which this version can't read.
            if parts[0].hasPrefix("SR"), let n = Int(parts[0].dropFirst(2)), n > 1 { throw Problem.newerVersion }
            throw Problem.malformed
        }
        guard let payload = base64url(parts[1]), let signature = base64url(parts[2]), signature.count == 64 else {
            throw Problem.malformed
        }
        guard let signer, signer.isValidSignature(signature, for: Data("SR1.\(parts[1])".utf8)) else { throw Problem.notSigned }
        // Signed by Stillroom, so what follows was written by the signer; still checked, never trusted to be sane.
        guard let p = try? JSONDecoder().decode(Payload.self, from: payload) else { throw Problem.malformed }
        guard p.v == 1 else { throw p.v > 1 ? Problem.newerVersion : Problem.malformed }
        guard p.seats >= 1, !p.id.isEmpty else { throw Problem.malformed }
        guard !blocked.contains(p.id) else { throw Problem.blocked }
        return License(id: p.id, edition: p.edition, seats: p.seats, name: p.name, email: p.email, issued: p.issued)
    }

    /// Strict base64url without padding: anything else is a mistyped key.
    private static func base64url(_ text: Substring) -> Data? {
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return nil }
        var b64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        return Data(base64Encoded: b64)
    }

    // MARK: Kept beside the store

    /// `~/Library/Application Support/Stillroom/License`, beside `Store`, in neither slot. In tests, beside the
    /// test's own store, so no test reads or writes the real one.
    static var file: URL {
        if let test = VaultStore.rootForTests {
            return test.deletingLastPathComponent().appending(path: test.lastPathComponent + "-License")
        }
        return URL.applicationSupportDirectory.appending(path: "Stillroom/License")
    }

    /// The saved licence, if there is one and it still checks out.
    static func load() -> License? {
        guard let data = try? Data(contentsOf: file), data.count <= 8192 else { return nil }
        return try? check(String(decoding: data, as: UTF8.self))
    }

    /// Why a saved key no longer checks out (blocked by a later release, say), or nil when there's none or it's fine.
    static func savedProblem() -> String? {
        guard let data = try? Data(contentsOf: file), data.count <= 8192 else { return nil }
        do { _ = try check(String(decoding: data, as: UTF8.self)); return nil } catch { return error.localizedDescription }
    }

    /// Checks `typed` and, if it's good, keeps it. A signed key isn't secret, so it's a plain file, not the keychain.
    static func save(_ typed: String) throws -> License {
        let license = try check(typed)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(tidy(typed).utf8).write(to: file, options: .atomic)
        return license
    }

    static func remove() throws {
        do { try FileManager.default.removeItem(at: file) } catch CocoaError.fileNoSuchFile {}
    }
}
