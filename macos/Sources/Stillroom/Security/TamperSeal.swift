import CryptoKit
import Foundation

/// The tamper seal: whenever Stillroom has written to the vault folder, it seals a fingerprint of it with a key only this
/// Mac's Secure Enclave can use. At the next unlock, a folder that no longer matches was changed outside Stillroom: a
/// file removed or added, or the whole folder put back from an older copy. (A sealed item swapped for another already
/// fails on its own, by its item key.)
///
/// One seal for the whole folder, beside the store and in neither slot, written alike whichever vault is open: using
/// one vault never trips the other's seal, and the warning never says what changed, which could hint at a second vault.
/// The latest seal is also kept in this Mac's keychain, which a copy of the folder can't roll back: put back an older
/// folder together with its older `Seal` file, or delete the file, and the keychain's newer seal still says "changed".
///
/// It checks on this Mac only (a moved vault starts a new seal), and someone able to run software as you here could
/// make a new one. It never blocks: it only says so.
enum TamperSeal {
    enum Status: Equatable { case intact, changed, fresh }

    /// Beside `Store`, like the licence. In tests, beside the test store.
    static var url: URL {
        if let test = VaultStore.rootForTests {
            return test.deletingLastPathComponent().appending(path: test.lastPathComponent + "-Seal")
        }
        return VaultStore.root.deletingLastPathComponent().appending(path: "Seal")
    }

    /// Tests seal with this instead of the Secure Enclave, which tests must never touch. With a test store and no test
    /// key, nothing is sealed or checked.
    nonisolated(unsafe) static var keyForTests: SymmetricKey?

    private struct Stored: Codable {
        /// The Enclave's key as the Enclave hands it out, and the other half of the key agreement (as `MacLock`).
        var enclaveKey: Data?
        var publicKey: Data?
        /// HMAC-SHA256 of the folder's fingerprint.
        var seal: Data
    }

    // MARK: What it covers

    /// Every file in the vault folder but the intruder log (written while locked, on purpose, with its own check) and
    /// staging folders (dot names): the contents of key files, covers, lists and indexes, and the name and size of each
    /// item file. Hashing names and sizes keeps it quick however much the vault holds.
    static func fingerprint(of root: URL = VaultStore.root) -> Data {
        let fm = FileManager.default
        guard let paths = try? fm.subpathsOfDirectory(atPath: root.path) else { return Data() }
        var hasher = SHA256()
        for path in paths.sorted() {
            let parts = path.split(separator: "/")
            guard let top = parts.first, top != "intruder", !parts.contains(where: { $0.hasPrefix(".") }) else { continue }
            let url = root.appending(path: path)
            guard let attributes = try? fm.attributesOfItem(atPath: url.path),
                  attributes[.type] as? FileAttributeType == .typeRegular else { continue }
            hasher.update(data: Data(path.utf8))
            hasher.update(data: Data([0]))
            if top == "Files" {
                hasher.update(data: Data(String((attributes[.size] as? NSNumber)?.intValue ?? -1).utf8))
            } else if let contents = try? Data(contentsOf: url) {
                hasher.update(data: Data(SHA256.hash(data: contents)))
            }
            hasher.update(data: Data([0]))
        }
        return Data(hasher.finalize())
    }

    // MARK: Sealing and checking

    /// Seals the folder as it is now. Called after Stillroom's own writes; a no-op when there's no vault.
    static func seal() {
        // One at a time, the fingerprint taken inside: whichever seal runs last is also the freshest, and the file and
        // the keychain always end up holding the same one.
        sealing.lock()
        defer { sealing.unlock() }
        guard VaultStore.exists, let (key, stored) = keyForSealing() else { return }
        var out = stored
        out.seal = mac(fingerprint(), key)
        try? VaultStore.write(JSONEncoder().encode(out), to: url)
        // A keychain that won't hold the latest seal is emptied instead: the check falls back to the file alone,
        // rather than warning at every unlock from now on.
        if !Latest.set(out.seal) { Latest.remove() }
    }

    private static let sealing = NSLock()

    /// Whether the folder still matches its seal. `fresh`: no seal yet (a vault from before 1.1), or one this Mac
    /// can't check (made on another Mac); a new one is made at the next seal.
    /// Reads the keychain and may ask the Secure Enclave, so the unlocks call it off the main thread.
    static func check() -> Status {
        sealing.lock()
        defer { sealing.unlock() }
        guard VaultStore.exists else { return .fresh }
        let latest = Latest.get()
        guard let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(Stored.self, from: data),
              let key = key(for: stored)
        else {
            // No seal file, or one this Mac can't read: fresh only if this Mac never sealed this vault.
            return latest == nil ? .fresh : .changed
        }
        // The file's seal must be this Mac's latest (an older `Seal` put back with an older folder isn't), and the
        // folder must match it.
        if let latest, latest != stored.seal { return .changed }
        return mac(fingerprint(), key) == stored.seal ? .intact : .changed
    }

    /// Forgets the seal: a vault deleted, or a new one about to be made.
    static func remove() {
        try? FileManager.default.removeItem(at: url)
        Latest.remove()
    }

    /// The latest seal, kept in the login keychain (a generic password, this device only), where a copy of the vault
    /// folder can't put back an older one. Tests keep it in memory: they never touch the keychain.
    ///
    /// One item per vault folder, named by a hash of its path: a second copy of Stillroom on this Mac (a demo, another
    /// build) has its own folder, and reading the installed app's item instead made macOS stop for an access prompt
    /// and then reported a false "changed".
    enum Latest {
        nonisolated(unsafe) static var forTests: Data?

        static func account(for root: URL) -> String {
            SHA256.hash(data: Data(root.standardizedFileURL.path.utf8)).map { String(format: "%02x", $0) }.joined()
        }

        private static var query: [String: Any] { [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.gjin.stillroom.seal",
            kSecAttrAccount as String: account(for: VaultStore.root),
        ] }

        static func get() -> Data? {
            if keyForTests != nil { return forTests }
            guard VaultStore.rootForTests == nil else { return nil }
            var found: CFTypeRef?
            var ask = query
            ask[kSecReturnData as String] = true
            // Never a keychain prompt: an answer that needs one counts as none, and the file is checked alone.
            ask[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
            guard SecItemCopyMatching(ask as CFDictionary, &found) == errSecSuccess else { return migrated() }
            return found as? Data
        }

        /// Test builds of 1.1 kept one item for every folder (account "latest"). Read once, moved to this folder's
        /// account and deleted, so a rollback is still noticed. Only for the real store under the real home: a demo
        /// copy (another home, the installed app's item) must never read it, which is what made macOS stop and ask.
        private static func migrated() -> Data? {
            guard let home = getpwuid(getuid())?.pointee.pw_dir,
                  VaultStore.root.standardizedFileURL.path.hasPrefix(String(cString: home) + "/") else { return nil }
            var old: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "app.gjin.stillroom.seal",
                kSecAttrAccount as String: "latest",
            ]
            var ask = old
            ask[kSecReturnData as String] = true
            ask[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
            var found: CFTypeRef?
            guard SecItemCopyMatching(ask as CFDictionary, &found) == errSecSuccess, let seal = found as? Data else { return nil }
            if set(seal) {
                old[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
                SecItemDelete(old as CFDictionary)
            }
            return seal
        }

        /// Whether the keychain now holds `seal`. An item it won't update (made by a differently signed copy, say) is
        /// replaced once.
        @discardableResult static func set(_ seal: Data) -> Bool {
            if keyForTests != nil { forTests = seal; return true }
            guard VaultStore.rootForTests == nil else { return false }
            var ask = query
            ask[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
            if SecItemUpdate(ask as CFDictionary, [kSecValueData as String: seal] as CFDictionary) == errSecSuccess { return true }
            SecItemDelete(query as CFDictionary)
            var add = query
            add[kSecValueData as String] = seal
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            add[kSecAttrLabel as String] = "Stillroom tamper seal"
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }

        static func remove() {
            if keyForTests != nil { forTests = nil; return }
            guard VaultStore.rootForTests == nil else { return }
            SecItemDelete(query as CFDictionary)
        }
    }

    private static func mac(_ fingerprint: Data, _ key: SymmetricKey) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: fingerprint, using: key))
    }

    // MARK: The key

    /// The derived key, held for the rest of the run so the Enclave is asked once.
    nonisolated(unsafe) private static var cached: SymmetricKey?

    /// The key to seal with and what to store beside the seal: this Mac's existing seal key, else a new one.
    private static func keyForSealing() -> (SymmetricKey, Stored)? {
        if let keyForTests { return (keyForTests, Stored(seal: Data())) }
        guard VaultStore.rootForTests == nil, SecureEnclave.isAvailable else { return nil }
        if let data = try? Data(contentsOf: url), let stored = try? JSONDecoder().decode(Stored.self, from: data),
           let key = key(for: stored) {
            return (key, stored)
        }
        // None yet, or one from another Mac: a new Enclave key for this Mac.
        // As `MacLock`: usable with no finger, only on this Mac, while it's unlocked.
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .privateKeyUsage, nil),
              let enclave = try? SecureEnclave.P256.KeyAgreement.PrivateKey(accessControl: access) else { return nil }
        let other = P256.KeyAgreement.PrivateKey()
        let stored = Stored(enclaveKey: enclave.dataRepresentation, publicKey: other.publicKey.rawRepresentation, seal: Data())
        guard let key = derive(enclave, other.publicKey) else { return nil }
        cached = key
        return (key, stored)
    }

    private static func key(for stored: Stored) -> SymmetricKey? {
        if let keyForTests { return keyForTests }
        guard VaultStore.rootForTests == nil else { return nil }
        if let cached { return cached }
        guard let enclaveKey = stored.enclaveKey, let publicKey = stored.publicKey,
              let enclave = try? SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: enclaveKey),
              let other = try? P256.KeyAgreement.PublicKey(rawRepresentation: publicKey),
              let key = derive(enclave, other) else { return nil }
        cached = key
        return key
    }

    private static func derive(_ enclave: SecureEnclave.P256.KeyAgreement.PrivateKey, _ other: P256.KeyAgreement.PublicKey) -> SymmetricKey? {
        (try? enclave.sharedSecretFromKeyAgreement(with: other))?
            .hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data(), sharedInfo: Data("Stillroom tamper seal".utf8), outputByteCount: 32)
    }

    // MARK: Soon

    nonisolated(unsafe) private static var pending: Task<Void, Never>?

    /// A seal shortly after a burst of writes (adding many files, saving the search index), done once, off the main
    /// thread. `lock()` seals at once instead.
    static func sealSoon() {
        pending?.cancel()
        // Only the folder it was asked for (tests move the store between runs).
        let folder = VaultStore.root
        pending = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, VaultStore.root == folder else { return }
            seal()
        }
    }

    /// A pending seal, done now: on lock and quit.
    static func sealNow() {
        pending?.cancel()
        pending = nil
        seal()
    }
}
