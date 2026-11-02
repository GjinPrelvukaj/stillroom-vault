import Foundation
import Security

/// Whether this copy is still signed by Stillroom's own team: a release (Developer ID) or a development build. A copy
/// someone changed, a crack among them, has to be signed again by someone else, and fails. It protects people who
/// downloaded a doctored Stillroom, not the licence: whoever changes the app can take this out too.
enum SelfCheck {
    /// Apple-issued certificate, Stillroom's team (`Gjin Prelvukaj (WP56DL33UR)`). Checked with `codesign -v -R=…`
    /// against a Developer ID build (passes), a development build (passes) and an ad-hoc re-signed copy (fails).
    static let requirement = #"anchor apple generic and certificate leaf[subject.OU] = "WP56DL33UR""#

    /// Both checks run without the network: by default the Security framework may ask Apple about a certificate or a
    /// notarization ticket, and Stillroom never connects, even through it. A release has its ticket stapled on.
    private static let offline = SecCSFlags(rawValue: 1 << 29) // kSecCSNoNetworkAccess (CSCommon.h), not imported into Swift

    /// Checked once, the first time it's asked: the running code against its own signature.
    static let signedByUs: Bool = {
        var code: SecCode?
        var rule: SecRequirement?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(requirement as CFString, [], &rule) == errSecSuccess, let rule else { return false }
        let ok = SecCodeCheckValidity(code, offline, rule) == errSecSuccess
        if !ok { ActivityLog.note("this copy isn't signed by Stillroom", action: false) }
        return ok
    }()

    /// Whether Apple notarized this copy (a release; development builds aren't). Checked once, against the running code.
    static let notarized: Bool = {
        var code: SecCode?
        var rule: SecRequirement?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString("notarized" as CFString, [], &rule) == errSecSuccess, let rule else { return false }
        return SecCodeCheckValidity(code, offline, rule) == errSecSuccess
    }()

    /// The day the build passed check-offline.sh (`StillroomOfflineChecked` in Info.plist, written by make-app.sh only
    /// after the check passes). Nil in a run straight from `swift build`.
    static var offlineChecked: String? {
        Bundle.main.object(forInfoDictionaryKey: "StillroomOfflineChecked") as? String
    }

    /// This copy's proof, as plain lines: what Settings › Security shows and Copy as Text puts on the clipboard.
    static func proof(version: String = Updates.version, signed: Bool = signedByUs, notarized: Bool = notarized,
                      offline: String? = offlineChecked) -> [(label: String, value: String, ok: Bool)] {
        [
            ("Version", version, true),
            ("Signed by Stillroom's maker", signed ? "Yes, team WP56DL33UR" : "No: someone else built or changed this copy", signed),
            ("Notarized by Apple", notarized ? "Yes" : "No", notarized),
            ("Offline check", offline.map { "Passed when built, \($0): no networking code linked" } ?? "Not recorded in this copy", offline != nil),
        ]
    }

    static func proofText() -> String {
        (["Stillroom, this copy:"] + proof().map { "\($0.label): \($0.value)" }).joined(separator: "\n")
    }
}
