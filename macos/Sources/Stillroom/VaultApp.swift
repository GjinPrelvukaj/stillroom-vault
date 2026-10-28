import AppKit
import SwiftUI

/// One window is the whole app, so closing it quits (and quitting drops the key). The keyboard shield is up while
/// Stillroom is in front.
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let service = MoveToVaultService()

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = service
        NSUpdateDynamicServices()
        MainActor.assumeIsolated { Appearance.current.apply() }
        // A desk left by a crash: its working copies go, its RAM disk is ejected.
        MainActor.assumeIsolated { EditDesk.shared.clearLeftovers() }
    }
    /// Files dropped on the Dock icon, or opened with Stillroom.
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated { Inbox.shared.receive(urls, moving: false) }
    }
    /// The RAM disk goes with the app; at quit there's nothing left to keep waiting.
    func applicationWillTerminate(_ notification: Notification) { MainActor.assumeIsolated { Clipboard.clearIfOurs(); EditDesk.shared.ejectNow() } }
    func applicationDidBecomeActive(_ notification: Notification) { KeyboardShield.follow(active: true) }
    func applicationDidResignActive(_ notification: Notification) { KeyboardShield.follow(active: false) }
}

@main
struct VaultApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var state = AppState()
    @AppStorage("menuBarIcon") private var menuBarIcon = true

    var body: some Scene {
        Window("Stillroom", id: "vault") {
            RootView(state: state)
                .containerBackground(.clear, for: .window)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .windowBackgroundDragBehavior(.enabled)
        // File > Import from iPhone or iPad: Scan Documents and Take Photo (Continuity Camera), straight into the vault.
        .commands {
            ImportFromDevicesCommands()
            // Opens the release notes in the browser, which say whether a newer version is out (Updates).
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Updates.check() }
            }
            #if DEBUG
            // Development builds only: freezes on purpose, to check the activity log catches them.
            CommandMenu("Debug") {
                Button("Freeze for 2 Seconds") { Thread.sleep(forTimeInterval: 2) }
                Button("Stall for Half a Second") { Thread.sleep(forTimeInterval: 0.5) }
            }
            #endif
        }
        // Whether Stillroom is open, at a glance, and a way to lock it without finding its window.
        MenuBarExtra(isInserted: $menuBarIcon) {
            if state.isOpen {
                Button("Lock and Hide Stillroom") { lockAndHide(state, "menu bar") }
                    .keyboardShortcut("l", modifiers: [.control, .option, .command])
            } else {
                Text("Stillroom is locked")
            }
            Button("Show Stillroom") { NSApp.activate() }
            Divider()
            Button("Quit Stillroom") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: state.isOpen ? "lock.open.fill" : "lock.fill")
        }
    }
}

/// Shut and out of sight in one go: from the menu bar, or ⌃⌥⌘L in any app.
@MainActor func lockAndHide(_ state: AppState, _ reason: String) {
    state.lock(reason)
    NSApp.hide(nil)
}

/// Shut or open, on the window's black glass.
struct RootView: View {
    let state: AppState
    /// Files are being dragged over the window: its light brightens to take them.
    @State private var dropping = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if state.isOpen {
                VaultView(state: state, dropping: $dropping)
            } else {
                LockView(state: state)
            }
        }
        .transition(.opacity)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : Motion.appear, value: state.isOpen)
        // A licence just added: the whole window blurs behind its welcome.
        .blur(radius: state.isOpen && state.welcome != nil ? 14 : 0)
        .allowsHitTesting(state.welcome == nil)
        .overlay {
            if state.isOpen, let license = state.welcome {
                WelcomeIn(license: license) { withAnimation(Motion.change) { state.welcome = nil } }
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : Motion.appear, value: state.welcome != nil)
        .frame(minWidth: 1000, idealWidth: 1180, maxWidth: .infinity, minHeight: 660, idealHeight: 760, maxHeight: .infinity)
        .background { Glass(open: state.isOpen, bright: dropping) }
        .hiddenFromCapture()
        .onAppear {
            ActivityLog.start()
            LockKey.register { lockAndHide(state, "lock shortcut") }
        }
        .sheet(isPresented: .init(get: { state.isOpen && state.freshRecoveryCode != nil },
                                  set: { if !$0 { state.freshRecoveryCode = nil } })) {
            RecoveryKeySheet(code: state.freshRecoveryCode ?? "")
        }
        // Shut whenever the Mac sleeps or its screen locks, so it is never left open on a Mac someone else wakes.
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in state.lock("Mac going to sleep") }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.screensDidSleepNotification)) { _ in state.lock("display slept") }
        .onReceive(DistributedNotificationCenter.default().publisher(for: Notification.Name("com.apple.screenIsLocked"))) { _ in
            state.lock("screen locked")
        }
        // Quitting locks first, so files being edited get their last save and their working copies go.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in state.lock("quitting") }
        // Shut after the Mac has gone untouched for a while, so walking away doesn't leave it open.
        .task(id: state.isOpen) {
            while state.isOpen, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                if AutoLock.isDue { state.lock("auto-lock after \(AutoLock.minutes) min untouched") }
            }
        }
    }
}

/// Locking after the Mac has been left alone: no key pressed, mouse moved or trackpad touched anywhere for the chosen
/// minutes. Going by the whole Mac, not Vault's window, so working on a file in its own app for an hour doesn't
/// count as gone.
/// Light, dark, or as the Mac is set. A comfort setting, so it's a preference (docs/SECURITY.md rule 3), the same
/// whichever vault is open, and it covers the lock screen too.
enum Appearance: String, CaseIterable {
    case system, light, dark

    var name: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    @MainActor static var current: Appearance {
        get { UserDefaults.standard.string(forKey: "appearance").flatMap(Appearance.init) ?? .system }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "appearance"); newValue.apply() }
    }

    @MainActor func apply() {
        NSApp?.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

enum AutoLock {
    static let choices = [1, 5, 15, 60, 0]
    /// Minutes; 0 is never.
    static var minutes: Int {
        get { UserDefaults.standard.object(forKey: "autoLockMinutes") as? Int ?? 5 }
        set { UserDefaults.standard.set(newValue, forKey: "autoLockMinutes") }
    }

    static func name(_ minutes: Int) -> String {
        switch minutes {
        case 0: "Never"
        case 1: "After 1 minute"
        case 60: "After 1 hour"
        default: "After \(minutes) minutes"
        }
    }

    static var isDue: Bool {
        guard minutes > 0 else { return false }
        // ponytail: any input counts, so a video playing untouched in Stillroom still locks; pause the timer while playing if that annoys.
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        return idle >= Double(minutes * 60)
    }
}
