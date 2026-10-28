import CryptoKit
import Foundation

/// "Lock to this Mac": every password key is sealed once more by a key made inside this Mac's Secure Enclave, which
/// can't be copied off the chip. A copy of the vault folder then opens on no other Mac, even with the password; only
/// the recovery key opens it elsewhere.
enum MacLock {
    private struct Stored: Codable {
        /// The Enclave's key, as the Enclave hands it out: only this Mac's chip can use it.
        var enclaveKey: Data
        /// The other half of the key agreement.
        var publicKey: Data
    }

    static var url: URL { VaultStore.root.appending(path: "mac.key") }
    static var isOn: Bool { FileManager.default.fileExists(atPath: url.path) }
    static var canUse: Bool { SecureEnclave.isAvailable }

    /// Makes this Mac's key. Its use needs no finger (the password is still asked), only this Mac, unlocked.
    static func make() throws {
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                                           .privateKeyUsage, &error)
        else { throw error!.takeRetainedValue() as Error }
        let enclave = try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: access)
        let other = P256.KeyAgreement.PrivateKey()
        let stored = Stored(enclaveKey: enclave.dataRepresentation, publicKey: other.publicKey.rawRepresentation)
        try VaultStore.writeKey(JSONEncoder().encode(stored), to: url)
    }

    static func remove() throws {
        if isOn { try FileManager.default.removeItem(at: url) }
    }

    /// The sealing key, which only this Mac's Enclave can give.
    static func key() throws -> SymmetricKey {
        guard let stored = try? JSONDecoder().decode(Stored.self, from: Data(contentsOf: url)),
              let enclave = try? SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: stored.enclaveKey),
              let other = try? P256.KeyAgreement.PublicKey(rawRepresentation: stored.publicKey),
              let secret = try? enclave.sharedSecretFromKeyAgreement(with: other)
        else { throw VaultError.notThisMac }
        return secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data(), sharedInfo: Data("Vault this Mac".utf8),
                                              outputByteCount: 32)
    }

    /// A password key as it's written to disk: sealed again for this Mac when the lock is on.
    static func wrap(_ data: Data) throws -> Data {
        isOn ? try seal(data, with: key()) : data
    }

    /// A password key as read from disk, ready for the password. One left unsealed (the lock was being turned on
    /// or off when the Mac stopped) is taken as it is: unsealed, it still needs the password.
    static func unwrap(_ data: Data) throws -> Data {
        guard isOn else { return data }
        // On another Mac this throws: the vault is locked to the Mac that made it.
        let key = try key()
        return (try? unseal(data, with: key)) ?? data
    }
}
