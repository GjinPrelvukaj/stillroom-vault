import AppKit
import Carbon.HIToolbox

/// ⌃⌥⌘L, from any app: Stillroom locks and hides at once, for when someone walks up. A system hot key, so it needs no
/// accessibility permission and sees no other keystrokes.
@MainActor enum LockKey {
    static let shortcut = "⌃⌥⌘L"
    private static var action: (() -> Void)?
    private static var registered = false

    static func register(_ run: @escaping () -> Void) {
        action = run
        guard !registered else { return }
        registered = true
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            // Carbon calls hot keys on the main thread.
            MainActor.assumeIsolated { LockKey.action?() }
            return noErr
        }, 1, &pressed, nil, nil)
        var key: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_L), UInt32(controlKey | optionKey | cmdKey),
                                         EventHotKeyID(signature: OSType(0x564C_4B21), id: 1), GetApplicationEventTarget(), 0, &key)
        // Another app already took the shortcut: the menu bar's Lock still works.
        if status != noErr { ActivityLog.note("lock shortcut unavailable (\(status))") }
    }
}
