import AppKit

/// How people hear about a new version, since Stillroom never connects. "Check for Updates…" opens the changelog in
/// the browser with this version in the address (stillroomvault.com/changelog/?v=1.0.0), and that page says whether a
/// newer one is out: the browser makes the connection, never the app. And from the build date alone, offline,
/// Settings says when this copy is getting old.
enum Updates {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// The day this copy was built (`StillroomBuilt` in Info.plist, written by make-app.sh). Nil in a debug run.
    static var built: Date? {
        (Bundle.main.object(forInfoDictionaryKey: "StillroomBuilt") as? String).flatMap(day)
    }

    /// After this long, Settings suggests looking for a newer version.
    static let oldAfterDays = 180

    static func pageURL(version: String = version) -> URL {
        URL(string: "https://stillroomvault.com/changelog/?v=\(version)")!
    }

    static func check() { NSWorkspace.shared.open(pageURL()) }

    static func day(_ text: String) -> Date? {
        try? Date(text, strategy: Date.ISO8601FormatStyle().year().month().day())
    }

    static func isOld(built: Date?, now: Date = .now) -> Bool {
        guard let built else { return false }
        return now.timeIntervalSince(built) > Double(oldAfterDays) * 86_400
    }

    /// The line under Check for Updates in Settings.
    static func detail(version: String = version, built: Date? = built, now: Date = .now) -> String {
        guard let built else { return "Version \(version). Opens the release notes in your browser, which say whether a newer one is out." }
        let month = built.formatted(.dateTime.month(.wide).year())
        return isOld(built: built, now: now)
            ? "Version \(version), from \(month): over six months old, so there may well be a newer one. Opens the release notes in your browser."
            : "Version \(version), from \(month). Opens the release notes in your browser, which say whether a newer one is out."
    }
}
