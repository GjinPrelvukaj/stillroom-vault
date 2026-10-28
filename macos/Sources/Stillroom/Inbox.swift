import AppKit
import Observation

/// Files sent to Stillroom from outside it: Finder's "Move to Stillroom" (in its right-click menu, under Services or Quick
/// Actions) and files dropped on Vault's Dock icon. They wait here until the vault is open, then go in.
@MainActor @Observable final class Inbox {
    static let shared = Inbox()

    /// Waiting to go in.
    private(set) var waiting: [URL] = []
    /// Whether the originals go to the Trash once they're in ("Move to Stillroom"), or are offered to ("open with").
    private(set) var moving = false

    func receive(_ urls: [URL], moving: Bool) {
        guard !urls.isEmpty else { return }
        waiting += urls.filter { !waiting.contains($0) }
        self.moving = self.moving || moving
        NSApp.activate()
    }

    /// Everything waiting, handed over once.
    func take() -> (urls: [URL], moving: Bool) {
        defer { waiting = []; moving = false }
        return (waiting, moving)
    }
}

/// The "Move to Stillroom" service: Finder hands over the chosen files' URLs.
final class MoveToVaultService: NSObject {
    @objc func moveToStillroom(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        MainActor.assumeIsolated { Inbox.shared.receive(urls, moving: true) }
    }
}
