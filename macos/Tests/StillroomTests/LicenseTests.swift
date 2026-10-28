import CryptoKit
import Foundation
import Testing
@testable import Stillroom

/// The licence check: a pure parser plus Ed25519. Every key here is signed by a test pair, never the production one.
struct LicenseTests {
    /// A key as the website's signer writes it (website/server/licence.ts), signed here by `key`.
    static func mint(_ json: String, _ key: Curve25519.Signing.PrivateKey, version: String = "SR1") throws -> String {
        let signed = "\(version).\(b64url(Data(json.utf8)))"
        return "\(signed).\(b64url(try key.signature(for: Data(signed.utf8))))"
    }

    static func b64url(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static let payload = #"{"v":1,"id":"txn_1","edition":"personal","seats":1,"name":"Ana Buyer","email":"ana@example.com","issued":"2026-10-28"}"#

    let pair = Curve25519.Signing.PrivateKey()

    @Test func aGoodKeyChecksOut() throws {
        let license = try License.check(try Self.mint(Self.payload, pair), signer: pair.publicKey)
        #expect(license == License(id: "txn_1", edition: .personal, seats: 1, name: "Ana Buyer", email: "ana@example.com", issued: "2026-10-28"))
    }

    /// Mail apps wrap long lines and people paste with spaces around: all of it is taken out.
    @Test func spacesAndLineBreaksDontMatter() throws {
        let key = try Self.mint(Self.payload, pair)
        let wrapped = "  " + key.enumerated().map { $0.offset % 40 == 39 ? "\($0.element)\r\n" : "\($0.element)" }.joined() + " \n"
        #expect(try License.check(wrapped, signer: pair.publicKey).name == "Ana Buyer")
    }

    @Test func aChangedPayloadIsRefused() throws {
        let key = try Self.mint(Self.payload, pair)
        let parts = key.split(separator: ".")
        let more = Self.b64url(Data(Self.payload.replacingOccurrences(of: #""seats":1"#, with: #""seats":500"#).utf8))
        #expect(throws: License.Problem.notSigned) { try License.check("SR1.\(more).\(parts[2])", signer: pair.publicKey) }
    }

    @Test func aChangedSignatureIsRefused() throws {
        var signature = Array(try Self.mint(Self.payload, pair).split(separator: ".")[2])
        signature[10] = signature[10] == "A" ? "B" : "A"
        let key = try Self.mint(Self.payload, pair).split(separator: ".")[0...1].joined(separator: ".") + "." + String(signature)
        #expect(throws: License.Problem.notSigned) { try License.check(key, signer: pair.publicKey) }
    }

    @Test func aKeyFromAnotherPairIsRefused() throws {
        let other = Curve25519.Signing.PrivateKey()
        #expect(throws: License.Problem.notSigned) { try License.check(try Self.mint(Self.payload, other), signer: pair.publicKey) }
        // And against the real key built in, a test key never checks out.
        #expect(License.builtIn != nil, "the production public key is a valid Ed25519 key")
        #expect(throws: License.Problem.notSigned) { try License.check(try Self.mint(Self.payload, pair), signer: License.builtIn) }
    }

    @Test func truncatedOrGarbledInputIsRefused() throws {
        let key = try Self.mint(Self.payload, pair)
        for typed in ["", "hello", "SR1", "SR1..", "SR1.a.b", "SR1.a.b.c", String(key.dropLast(8)), String(key.dropFirst(6)),
                      key.replacingOccurrences(of: ".", with: ","), key + "=", String(key.prefix(10)) + "/" + key.dropFirst(10),
                      "SR1.\(key.split(separator: ".")[1]).", String(repeating: "A", count: 5000)] {
            #expect(throws: License.Problem.malformed, "\(typed.prefix(30))") { try License.check(typed, signer: pair.publicKey) }
        }
        // Signed, but not what the signer writes: unknown edition, no seats, not JSON.
        for json in [Self.payload.replacingOccurrences(of: "personal", with: "gold"),
                     Self.payload.replacingOccurrences(of: #""seats":1"#, with: #""seats":0"#),
                     #"{"v":1}"#, "not json"] {
            #expect(throws: License.Problem.malformed) { try License.check(try Self.mint(json, pair), signer: pair.publicKey) }
        }
    }

    @Test func anUnknownVersionIsRefused() throws {
        #expect(throws: License.Problem.newerVersion) { try License.check(try Self.mint(Self.payload, pair, version: "SR2"), signer: pair.publicKey) }
        let v2 = Self.payload.replacingOccurrences(of: #""v":1"#, with: #""v":2"#)
        #expect(throws: License.Problem.newerVersion) { try License.check(try Self.mint(v2, pair), signer: pair.publicKey) }
        #expect(throws: License.Problem.malformed) { try License.check(try Self.mint(Self.payload, pair, version: "XX1"), signer: pair.publicKey) }
    }

    /// A key posted publicly is refused once its id is on the blocked list; every other key still checks out.
    @Test func aBlockedKeyIsRefused() throws {
        let key = try Self.mint(Self.payload, pair)
        #expect(throws: License.Problem.blocked) { try License.check(key, signer: pair.publicKey, blocked: ["txn_1"]) }
        #expect(try License.check(key, signer: pair.publicKey, blocked: ["txn_other"]).id == "txn_1")
    }

    /// A key minted by the website's Node signer (website/server/fixtures/test-licence.json, checked on that side by
    /// signer.test.ts) checks out here, accents and all: the two sides can't drift apart.
    @Test func nodeMintedKeyVerifies() throws {
        let url = URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "../../../website/server/fixtures/test-licence.json").standardizedFileURL
        struct Fixture: Decodable { let publicKey: String; let key: String }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        let signer = try Curve25519.Signing.PublicKey(rawRepresentation: try #require(Data(base64Encoded: fixture.publicKey)))
        let license = try License.check(fixture.key, signer: signer)
        #expect(license == License(id: "txn_01test0000000000000000000", edition: .family, seats: 5, name: "Zoë Ångström-Test",
                                   email: "zoe@example.com", issued: "2026-10-28"))
        #expect(throws: License.Problem.notSigned) { try License.check(fixture.key, signer: pair.publicKey) }
    }
}

/// The free tier: 25 items without a licence, and only adding ever stops.
extension VaultFlowTests {
    /// A licence from a test pair made now, which the app is told to trust (the real key is never used in tests).
    func testLicense() throws -> String {
        let pair = Curve25519.Signing.PrivateKey()
        License.signerForTests = pair.publicKey
        return try LicenseTests.mint(LicenseTests.payload, pair)
    }

    func fill(_ state: AppState, to count: Int) async throws {
        let urls = try (state.files.count..<count).map { try sample("item \($0).txt", "item \($0)") }
        await state.add(urls)
        #expect(state.files.count == count)
    }

    @Test func theTwentySixthItemNeedsALicence() async throws {
        defer { try? FileManager.default.removeItem(at: root); try? License.remove() }
        let state = AppState()
        try await state.create(password: "real password 123", touchID: false)
        #expect(state.license == nil)
        try await fill(state, to: 20)

        // Ten dropped at once: five fit, and only their originals may be removed.
        let ten = try (0..<10).map { try sample("more \($0).txt", "more") }
        let originals = await state.add(ten)
        #expect(state.files.count == 25)
        #expect(originals.files.count == 5)
        #expect(state.problem == AppState.fullMessage(5))

        // Every other way in stops too, and says why.
        state.problem = nil
        await state.add([try sample("one more.txt", "x")])
        #expect(state.problem == AppState.fullMessage(1))
        #expect(state.newEntry(.note, name: "Note", content: Data()) == nil)
        state.add(Data("scan".utf8), named: "Scan.pdf", folder: nil)
        let logins = try PasswordImport.logins(from: Data("Title,URL,Username,Password\nA,https://a.com,me,1\nB,https://b.com,me,2\n".utf8))
        #expect(state.importLogins(logins) == (0, 0, 2))
        #expect(state.problem == AppState.fullMessage(2))
        #expect(state.files.count == 25)
        // Folders don't count.
        state.makeFolder("Empty", in: nil)
        #expect(state.folders.contains("Empty"))

        // A licence lifts it at once, and is still there after locking and starting again.
        state.problem = nil
        try state.addLicense(try testLicense())
        #expect(state.newEntry(.note, name: "Note", content: Data()) != nil)
        await state.add([try sample("twenty-seventh.txt", "x")])
        #expect(state.importLogins(logins) == (2, 0, 0))
        #expect(state.files.count == 29)
        #expect(state.problem == nil)
        state.lock()
        let again = AppState()
        try await again.unlock(password: "real password 123")
        #expect(again.license?.name == "Ana Buyer")
        again.add(Data("scan".utf8), named: "Scan.pdf", folder: nil)
        #expect(again.files.count == 30)

        // Removed, the limit is back; nothing in the vault is touched.
        again.removeLicense()
        #expect(again.license == nil && AppState().license == nil)
        #expect(again.newEntry(.note, name: "Note", content: Data()) == nil)
        #expect(again.files.count == 30)
    }

    /// Over the limit, everything but adding works: opening, editing (and the versions it makes), moving, renaming,
    /// deleting, exporting, backing up, restoring a backup of more than 25 items, checking.
    @Test func overTheLimitNothingButAddingStops() async throws {
        defer { try? FileManager.default.removeItem(at: root); try? License.remove() }
        let state = AppState()
        try await state.create(password: "real password 123", touchID: false)
        try state.addLicense(try testLicense())
        let note = try #require(state.newEntry(.note, name: "Plans", content: Data("first".utf8)))
        try await fill(state, to: 30)
        state.removeLicense()
        #expect(state.room == 0)

        // Edit, with a version kept.
        try state.backdate(note.id, by: 3600)
        state.update(note.id, with: Data("second".utf8))
        let edited = try #require(state.files.first { $0.id == note.id })
        #expect(try state.read(edited) == Data("second".utf8))
        #expect(edited.versions?.count == 1)
        state.restore(try #require(edited.versions?.first), of: note.id)
        // Move, rename, tag, delete.
        state.makeFolder("Old", in: nil)
        state.move(Set(state.files.prefix(3).map(\.id)), to: "Old")
        #expect(state.files.filter { $0.folder == "Old" }.count == 3)
        state.rename(state.files[5].id, to: "Renamed.txt")
        state.setTags(["kept"], on: state.files[6].id)
        state.delete(state.files[7])
        #expect(state.files.count == 29)
        #expect(state.problem == nil)
        // Still over 25 after a delete: adding still stops.
        #expect(state.newEntry(.note, name: "Note", content: Data()) == nil)
        state.problem = nil

        // Export one, export everything, check.
        let out = root.deletingLastPathComponent().appending(path: "export-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try state.export(state.files[0], to: out.appending(path: "one.txt"))
        let all = try await state.exportAll(into: out) { _, _ in }
        let exported = FileManager.default.enumerator(at: all, includingPropertiesForKeys: nil)!.allObjects.compactMap { $0 as? URL }
            .filter { !$0.hasDirectoryPath }
        #expect(exported.count == 29)
        #expect(await state.checkVault { _, _ in }.isEmpty)

        // Back up, then restore over a vault that's gone: all 29 come back, unlicensed.
        let backup = out.appending(path: Backup.suggestedName())
        try Backup.make(to: backup)
        state.lock()
        try VaultStore.wipe()
        #expect(try Backup.restore(from: backup) == nil)
        let restored = AppState()
        try await restored.unlock(password: "real password 123")
        #expect(restored.files.count == 29)
        #expect(restored.license == nil)
        // The version put back before the backup is what it holds.
        #expect(try restored.read(try #require(restored.files.first { $0.id == note.id })) == Data("first".utf8))
    }
}
