import CryptoKit
import Foundation

/// Who tried to get in: each wrong password or recovery key at the lock screen. A wrong try happens while locked,
/// when nothing says which vault it was aimed at, so it belongs to both: each entry is sealed (HPKE, X25519 +
/// ChaChaPoly) to both slots' public keys, which sit in the open. Each slot's private half rides in its own sealed
/// list, so either slot, unlocked, reads the same log. What was typed is never kept: shared, it would show your typos
/// of one vault's password to whoever holds the other.
///
///     intruder.pub     both public keys, raw: a's (32 bytes), then b's
///     intruder/        one file per entry: for a, then b, u32 length | HPKE's encapsulated key (32) | sealed JSON
enum IntruderLog {
    typealias Slot = VaultStore.Slot
    enum Kind: String, Codable, Sendable { case wrongPassword, wrongRecoveryKey }

    struct Entry: Identifiable, Codable, Sendable {
        let id: UUID
        let date: Date
        let kind: Kind
        /// A JPEG of whoever was at the Mac, when the camera allowed one.
        let photo: Data?
    }

    private static let suite = HPKE.Ciphersuite.Curve25519_SHA256_ChachaPoly
    private static let info = Data("Vault intruder log".utf8)
    static var publicKeyURL: URL { VaultStore.root.appending(path: "intruder.pub") }
    static var folder: URL { VaultStore.root.appending(path: "intruder", directoryHint: .isDirectory) }

    private static func offset(_ slot: Slot) -> Int { slot == .a ? 0 : 32 }

    /// Puts a slot's public key in its half of intruder.pub, the other half kept.
    static func setPublicKey(_ raw: Data, for slot: Slot) throws {
        var both = (try? Data(contentsOf: publicKeyURL)).flatMap { $0.count == 64 ? $0 : nil } ?? Data(count: 64)
        both.replaceSubrange(offset(slot)..<offset(slot) + 32, with: raw)
        try VaultStore.writeKey(both, to: publicKeyURL)
    }

    private static func publicKey(_ slot: Slot) -> Data? {
        guard let both = try? Data(contentsOf: publicKeyURL), both.count == 64 else { return nil }
        return both[offset(slot)..<offset(slot) + 32]
    }

    /// The slot's private key from its list, checked against its half of intruder.pub: someone able to write the
    /// folder could otherwise swap in a key of their own and see the photos. On a mismatch (or none) a new pair is
    /// made and returned, to be kept in the list; `swapped` says whether there was a key there to mismatch.
    static func check(_ stored: String, for slot: Slot) throws -> (key: String, swapped: Bool) {
        if let raw = Data(base64Encoded: stored), let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw),
           publicKey(slot) == key.publicKey.rawRepresentation { return (stored, false) }
        let key = Curve25519.KeyAgreement.PrivateKey()
        try setPublicKey(key.publicKey.rawRepresentation, for: slot)
        return (key.rawRepresentation.base64EncodedString(), true)
    }

    /// Records one event using only the public keys (works while locked). Does nothing if there are none yet.
    static func record(kind: Kind, photo: Data?) throws {
        guard let both = try? Data(contentsOf: publicKeyURL), both.count == 64 else { return }
        let entry = Entry(id: UUID(), date: .now, kind: kind, photo: photo)
        let json = try JSONEncoder().encode(entry)
        var file = Data()
        for slot in Slot.allCases {
            var sender = try HPKE.Sender(recipientKey: Curve25519.KeyAgreement.PublicKey(rawRepresentation: both[offset(slot)..<offset(slot) + 32]),
                                         ciphersuite: suite, info: info)
            let part = try sender.encapsulatedKey + sender.seal(json)
            withUnsafeBytes(of: UInt32(part.count).bigEndian) { file.append(contentsOf: $0) }
            file.append(part)
        }
        try VaultStore.write(file, to: self.file(entry.id))
    }

    /// The slot's sealing inside an entry file.
    private static func part(_ data: Data, _ slot: Slot) -> Data? {
        var at = data.startIndex
        for each in Slot.allCases {
            guard data.endIndex - at >= 4 else { return nil }
            let length = Int(data[at..<at + 4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
            at += 4
            guard data.endIndex - at >= length else { return nil }
            if each == slot { return data[at..<at + length] }
            at += length
        }
        return nil
    }

    /// Every entry this slot can read, newest first.
    static func entries(_ stored: String, for slot: Slot) -> [Entry] {
        guard let raw = Data(base64Encoded: stored), let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw)
        else { return [] }
        // A file that won't open (cut short by a crash, put there by someone else, or sealed to a slot since
        // replaced) is skipped, not fatal.
        return files().compactMap { url -> Entry? in
            guard let data = try? Data(contentsOf: url), let part = part(data, slot), part.count > 32,
                  var recipient = try? HPKE.Recipient(privateKey: key, ciphersuite: suite, info: info,
                                                      encapsulatedKey: part.prefix(32)),
                  let json = try? recipient.open(part.dropFirst(32)) else { return nil }
            return try? JSONDecoder().decode(Entry.self, from: json)
        }.sorted { $0.date > $1.date }
    }

    /// Gone for both slots.
    static func delete(id: UUID) throws {
        try FileManager.default.removeItem(at: file(id))
    }

    /// Every entry gone; the keys stay, so logging goes on.
    static func clear() throws {
        for url in files() { try FileManager.default.removeItem(at: url) }
    }

    private static func file(_ id: UUID) -> URL { folder.appending(path: id.uuidString + ".intruder") }

    private static func files() -> [URL] {
        let found = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return found.filter { $0.pathExtension == "intruder" }
    }
}
