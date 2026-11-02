#if DEBUG
import Foundation

/// Debug builds only, for checking every screen by picture in a demo copy (docs/DEVELOPING.md): a password that
/// unlocks at the lock screen, and the screen to open once in. Never compiled into a release build.
///
/// STILLROOM_DEMO_PASSWORD=<password>   unlocks once, as the lock screen appears
/// STILLROOM_DEMO_SCREEN=<screen>        make (skip the tour), vault, notes, secrets, intruders, newfolder, folder:<name>,
///                                       settings:<access|protection|security|data|licence>[/<password|decoy|check|kit>],
///                                       preview:<name>, note:<name>, secret:<name>, tags:<name>, versions:<name>,
///                                       cooldown:<name>
enum DemoScreen {
    private static let env = ProcessInfo.processInfo.environment
    /// Taken once, so locking afterwards stays locked.
    nonisolated(unsafe) static var password = env["STILLROOM_DEMO_PASSWORD"]
    static let screen = env["STILLROOM_DEMO_SCREEN"]

    /// "preview:Book list" → ("preview", "Book list").
    static var parts: (kind: String, name: String) {
        guard let screen else { return ("", "") }
        let split = screen.split(separator: ":", maxSplits: 1).map(String.init)
        return (split[0], split.count > 1 ? split[1] : "")
    }

    /// For settings:<tab>[/<sheet>]: the tab's name and the sheet's, lowercased.
    static var settings: (tab: String, sheet: String?)? {
        guard parts.kind == "settings" else { return nil }
        let split = parts.name.lowercased().split(separator: "/").map(String.init)
        return (split.first ?? "access", split.count > 1 ? split[1] : nil)
    }
}
#endif
