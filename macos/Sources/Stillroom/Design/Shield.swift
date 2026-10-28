import AppKit
import Carbon
import SwiftUI

/// Keeps a window out of screenshots, screen recordings and screen sharing: they see it blank. Put it in the
/// background of a window's content (the main window, and each sheet, which is a window of its own).
struct HiddenFromCapture: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Watcher() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class Watcher: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            #if DEBUG
            // Debug builds only, for checking screens by picture.
            if ProcessInfo.processInfo.environment["STILLROOM_SHOW_IN_CAPTURE"] != nil { return }
            #endif
            window?.sharingType = CaptureShield.allowed ? .readOnly : .none
        }
    }
}

/// Letting Vault's windows show in screenshots, recordings and screen sharing, for showing someone. Held in memory
/// only: the setting itself is sealed in the vault (AppState.showInCapture) and applied as it opens, so the lock
/// screen is always hidden and no other program can turn the protection off through the app's preferences.
@MainActor @Observable final class CaptureShield {
    static let shared = CaptureShield()
    private(set) var isAllowed = false

    nonisolated(unsafe) static var allowed = false

    func set(_ allowed: Bool) {
        isAllowed = allowed
        Self.allowed = allowed
        #if DEBUG
        if ProcessInfo.processInfo.environment["STILLROOM_SHOW_IN_CAPTURE"] != nil { return }
        #endif
        // NSApp is nil outside the running app (tests): nothing to update then.
        for window in (NSApp as NSApplication?)?.windows ?? [] { window.sharingType = allowed ? .readOnly : .none }
    }
}

extension View {
    func hiddenFromCapture() -> some View { background(HiddenFromCapture()) }
}

/// The keyboard shield: while Stillroom is the app in front, macOS's Secure Keyboard Entry is on, so other apps
/// (keyloggers among them) receive none of what's typed, in any field. It goes off as Stillroom goes to the back.
enum KeyboardShield {
    static func follow(active: Bool) {
        if active { EnableSecureEventInput() } else { DisableSecureEventInput() }
    }
}
