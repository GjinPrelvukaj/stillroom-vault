import CryptoKit
import Foundation
import LocalAuthentication

/// Touch ID's way in to one slot (a finger can't choose, so it's whichever slot last turned it on): its slot key sealed by a key that lives in this Mac's Secure Enclave and only works after a
/// fingerprint enrolled when it was made. The file alone is useless on any other Mac, and on this one without a finger.
@MainActor enum TouchIDKey {
    private struct Sealed: Codable {
        /// The Secure Enclave key, as the Enclave hands it out: only that chip can use it.
        var enclaveKey: Data
        /// The other half of the key agreement, made fresh when sealing.
        var publicKey: Data
        var vaultKey: Data
    }

    static var url: URL { VaultStore.root.appending(path: "touchid.key") }
    static var isOn: Bool { FileManager.default.fileExists(atPath: url.path) }
    static var canUse: Bool {
        SecureEnclave.isAvailable && LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    /// Seals the slot key for Touch ID. Returns the file's public key, for the slot's list to know the file as its own.
    static func turnOn(_ vaultKey: SymmetricKey) throws -> String {
        guard canUse else { throw VaultError.touchIDUnavailable }
        var error: Unmanaged<CFError>?
        // `.biometryCurrentSet`: adding a finger later makes this key unusable, so a new finger can't open the vault.
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                                                           [.privateKeyUsage, .biometryCurrentSet], &error)
        else { throw error!.takeRetainedValue() as Error }
        let enclave = try SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: access)
        let mine = P256.KeyAgreement.PrivateKey()
        let key = wrappingKey(try mine.sharedSecretFromKeyAgreement(with: enclave.publicKey))
        let sealed = Sealed(enclaveKey: enclave.dataRepresentation, publicKey: mine.publicKey.rawRepresentation,
                            vaultKey: try vaultKey.withUnsafeBytes { try seal($0, with: key) })
        try VaultStore.writeKey(JSONEncoder().encode(sealed), to: url)
        return sealed.publicKey.base64EncodedString()
    }

    /// The public key in touchid.key, read as plain data (no Enclave): which slot made it.
    static func publicKey() -> String? {
        (try? JSONDecoder().decode(Sealed.self, from: Data(contentsOf: url)))?.publicKey.base64EncodedString()
    }

    static func turnOff() throws {
        if isOn { try FileManager.default.removeItem(at: url); VaultStore.evenDates(VaultStore.keyFiles) }
    }

    /// Asks for a finger, then opens the vault key. Throws `CancellationError` when the person cancels.
    static func open() async throws -> SymmetricKey {
        let sealed = try JSONDecoder().decode(Sealed.self, from: Data(contentsOf: url))
        let context = LAContext()
        // The password field is right there; no second way in through this sheet.
        context.localizedFallbackTitle = ""
        do {
            try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "open your vault")
        } catch let error as LAError where [.userCancel, .appCancel, .systemCancel].contains(error.code) {
            throw CancellationError()
        }
        // The finger is checked: the Enclave uses its key with this context and asks no second time.
        do {
            let enclave = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: sealed.enclaveKey,
                                                                         authenticationContext: context)
            let theirs = try P256.KeyAgreement.PublicKey(rawRepresentation: sealed.publicKey)
            let key = wrappingKey(try enclave.sharedSecretFromKeyAgreement(with: theirs))
            var opened = try unseal(sealed.vaultKey, with: key)
            defer { opened.resetBytes(in: 0..<opened.count) }
            return SymmetricKey(data: opened)
        } catch {
            throw VaultError.touchIDChanged
        }
    }

    private static func wrappingKey(_ secret: SharedSecret) -> SymmetricKey {
        secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data(), sharedInfo: Data("Vault Touch ID".utf8),
                                       outputByteCount: 32)
    }
}
