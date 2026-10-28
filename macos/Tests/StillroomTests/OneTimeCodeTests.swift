import Foundation
import Testing
@testable import Stillroom

struct OneTimeCodeTests {
    // RFC 6238 appendix B: the same 8-digit codes every authenticator gives.
    @Test(arguments: [(59.0, "94287082", "46119246", "90693936"), (1111111109, "07081804", "68084774", "25091201"),
                      (1234567890, "89005924", "91819424", "93441116"), (20000000000, "65353130", "77737706", "47863826")])
    func rfcVectors(time: Double, sha1: String, sha256: String, sha512: String) {
        let at = Date(timeIntervalSince1970: time)
        let seed = { (n: Int) in Data(String(repeating: "1234567890", count: 7).utf8.prefix(n)) }
        #expect(OneTimeCode(key: seed(20), digits: 8).code(at: at) == sha1)
        #expect(OneTimeCode(key: seed(32), digits: 8, algorithm: .sha256).code(at: at) == sha256)
        #expect(OneTimeCode(key: seed(64), digits: 8, algorithm: .sha512).code(at: at) == sha512)
    }

    @Test func readsLinksAndKeys() throws {
        // "12345678901234567890" in base32.
        let key = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
        let link = try #require(OneTimeCode("otpauth://totp/Site:me@x.com?secret=\(key)&issuer=Site&digits=8&period=30&algorithm=SHA1"))
        #expect(link.code(at: .init(timeIntervalSince1970: 59)) == "94287082")
        let pasted = try #require(OneTimeCode("gezd gnbv gy3t qojq gezd gnbv gy3t qojq"))
        #expect(pasted.key == link.key && pasted.digits == 6)
        #expect(pasted.code(at: .init(timeIntervalSince1970: 59)) == "287082")
        #expect(OneTimeCode("otpauth://hotp/Site?secret=\(key)&counter=1") == nil)
        #expect(OneTimeCode("otpauth://totp/Site?secret=\(key)&digits=12") == nil)
        #expect(OneTimeCode("not a key at all") == nil)
        #expect(OneTimeCode("ABC") == nil)
        #expect(link.secondsLeft(at: .init(timeIntervalSince1970: 59)) == 1)
    }

    @Test func fieldsWithASetupShowCodes() {
        let key = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
        #expect(Secret.Field(label: "Two-factor setup", value: key).oneTimeCode != nil)
        #expect(Secret.Field(label: "Anything", value: "otpauth://totp/x?secret=\(key)").oneTimeCode != nil)
        // A password that happens to be valid base32 isn't mistaken for a setup.
        #expect(Secret.Field(label: "Password", value: key).oneTimeCode == nil)
    }
}
