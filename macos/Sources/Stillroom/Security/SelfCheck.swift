import Foundation
import Security

/// Whether this copy is still signed by Stillroom's own team: a release (Developer ID) or a development build. A copy
/// someone changed, a crack among them, has to be signed again by someone else, and fails. It protects people who
/// downloaded a doctored Stillroom, not the licence: whoever changes the app can take this out too.
enum SelfCheck {
    /// Apple-issued certificate, Stillroom's team (`Gjin Prelvukaj (WP56DL33UR)`). Checked with `codesign -v -R=…`
    /// against a Developer ID build (passes), a development build (passes) and an ad-hoc re-signed copy (fails).
    static let requirement = #"anchor apple generic and certificate leaf[subject.OU] = "WP56DL33UR""#

    /// Checked once, the first time it's asked: the running code against its own signature.
    static let signedByUs: Bool = {
        var code: SecCode?
        var rule: SecRequirement?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(requirement as CFString, [], &rule) == errSecSuccess, let rule else { return false }
        let ok = SecCodeCheckValidity(code, [], rule) == errSecSuccess
        if !ok { ActivityLog.note("this copy isn't signed by Stillroom", action: false) }
        return ok
    }()
}
