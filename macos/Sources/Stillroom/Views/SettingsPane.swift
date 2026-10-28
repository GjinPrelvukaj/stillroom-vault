import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// How the vault is kept, in plain words, and what can be changed. The same in either vault, row for row; see
/// docs/SECURITY.md rule 2 for what the decoy does and doesn't protect against.
struct SettingsPane: View {
    let state: AppState
    @State private var wiping = false
    @State private var renewingRecovery = false
    @State private var removingOther = false
    /// A recovery key made with a new decoy, shown once its sheet has gone.
    @State private var pendingCode: String?
    @State private var removingKit = false
    @State private var sheet: Sheet?
    @State private var restoring: URL?
    @State private var backingUp = false
    @State private var confirmingExport = false
    @State private var exporting: (done: Int, total: Int)?
    @AppStorage("intruderPhoto") private var takesPhoto = true
    @State private var cameraUndecided = IntruderCamera.undecided
    @State private var autoLock = AutoLock.minutes
    @AppStorage("activityLog") private var activityLog = ActivityLog.isOn
    @AppStorage("menuBarIcon") private var menuBarIcon = true
    @State private var appearance = Appearance.current
    @State private var licenseKey = ""
    /// Starts with why a saved key stopped working, if it did, so the drop to Free is explained.
    @State private var licenseProblem = License.savedProblem()
    @State private var removingLicense = false

    private enum Sheet: Identifiable {
        case changePassword, setDecoy, recovery(String), check, kit
        var id: String {
            switch self {
            case .check: "check"
            case .kit: "kit"
            case .changePassword: "password"
            case .setDecoy: "decoy"
            case .recovery(let code): code
            }
        }
    }

    /// The same five in either vault.
    private enum Tab: String, CaseIterable, Identifiable {
        case access = "Access", protection = "Protection", security = "Security", data = "Data", license = "Licence"
        var id: Self { self }
    }

    @State private var tab = Tab.access

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Kit.Space.group) {
                VStack(alignment: .leading, spacing: Kit.Space.label) {
                    Text("Settings").eyebrow()
                    Text("How it's kept").font(Kit.title)
                }
                if let problem = state.problem {
                    HStack {
                        Text(problem).font(Kit.quiet).foregroundStyle(.red.opacity(0.85))
                        Button("OK") { state.problem = nil }.buttonStyle(.quiet)
                    }
                }

                Segments(selection: $tab, options: Tab.allCases.map { ($0, $0.rawValue) })

                switch tab {
                case .access: access
                case .protection: protection
                case .security: SecurityFacts(state: state)
                case .data: data
                case .license: licenseTab
                }
            }
            .pane()
        }
        .scrollIndicators(.never)
        .fadesIntoLight()
        .entrance()
        .onChange(of: activityLog) { if activityLog { ActivityLog.start() } else { ActivityLog.stop() } }
        // Never "decoy": that a decoy is being set up mustn't be written anywhere.
        .onChange(of: sheet?.id) {
            let name: String? = switch sheet {
            case .changePassword, .setDecoy, .recovery, .kit: "keys"
            case .check: "check vault"
            case nil: nil
            }
            ActivityLog.note(name.map { "sheet: \($0)" } ?? "sheet closed", action: name != nil)
        }
        .sheet(item: $sheet, onDismiss: {
            if let code = pendingCode { pendingCode = nil; sheet = .recovery(code) }
        }) { sheet in
            switch sheet {
            case .changePassword:
                PasswordSheet(title: "Change password", message: "The new one takes over at once; the old one stops working.") { current, new in
                    try await state.changePassword(current: current, to: new)
                }
            case .setDecoy:
                PasswordSheet(title: "Set a decoy password",
                              message: "It opens a second, empty vault, with a recovery key of its own. Put a few harmless files in it so it looks used. Everything in the other vault is deleted and it starts empty.",
                              asksCurrent: false) { _, new in
                    pendingCode = try await state.setOtherSlot(password: new)
                }
            case .recovery(let code):
                RecoveryKeySheet(code: code)
            case .check:
                CheckSheet(state: state)
            case .kit:
                KitSheet(state: state)
            }
        }
        .confirmationDialog("Make a new recovery key?", isPresented: $renewingRecovery) {
            Button("Make New Key") { run { try await state.newRecoveryKey() } }
        } message: {
            Text("Any recovery key you wrote down before stops opening this vault. Backups made before still open with it.")
        }
        .confirmationDialog("Remove the emergency kit?", isPresented: $removingKit) {
            Button("Remove Kit", role: .destructive, action: state.removeKit)
        } message: {
            Text("The printed pieces stop opening this vault. Backups made before still open with them, so collect and destroy the pieces too.")
        }
        .confirmationDialog("Remove the decoy?", isPresented: $removingOther) {
            Button("Remove Decoy", role: .destructive) { run { try await state.resetOtherSlot(); return nil } }
        } message: {
            Text("The decoy password stops opening anything, and everything in the other vault is deleted.")
        }
        .confirmationDialog("Restore from this backup?", isPresented: .init(get: { restoring != nil }, set: { if !$0 { restoring = nil } })) {
            Button("Restore") { if let restoring { restore(restoring) } }
        } message: {
            Text("The vault closes and the backup's vault takes its place; it opens with the password it had then. The vault here now is kept aside.")
        }
        .confirmationDialog("Export everything, unencrypted?", isPresented: $confirmingExport) {
            // After the dialog has gone, so the folder picker doesn't open over it.
            Button("Choose Where…") { Task { @MainActor in exportAll() } }
        } message: {
            Text("Everything comes out as normal files anyone with access to this Mac can open, secrets' hidden values included. Pick a disk you control, and delete the copy when you're done with it.")
        }
        .confirmationDialog("Remove the licence?", isPresented: $removingLicense) {
            Button("Remove Licence", role: .destructive, action: state.removeLicense)
        } message: {
            Text("Stillroom goes back to the free tier. Nothing in the vault is touched, but past \(License.freeItems) items nothing more can be added. Paste the key again any time.")
        }
        .confirmationDialog("Delete the vault and everything in it?", isPresented: $wiping) {
            Button("Delete Everything", role: .destructive, action: state.wipe)
        } message: {
            Text("Nothing in it can be opened again, by anyone.")
        }
    }

    private func backUp() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Backup.suggestedName()
        panel.message = "Pick a disk you can unplug and keep somewhere safe."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        backingUp = true
        Task {
            do {
                try await ActivityLog.timed("backup made") {
                    // The vault is open, so a save can land while it's packed: pack again until none did.
                    for attempt in 1...3 {
                        let before = state.writes
                        try await Task.detached { try Backup.make(to: url) }.value
                        if state.writes == before { break }
                        if attempt == 3 { throw Backup.Problem.busy }
                    }
                }
            } catch { state.problem = ActivityLog.failed(error, error.localizedDescription) }
            backingUp = false
        }
    }

    private func exportAll() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "A new folder holding everything, unencrypted, is made here."
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        exporting = (0, state.files.count)
        Task {
            do {
                let folder = try await state.exportAll(into: parent) { exporting = ($0, $1) }
                NSWorkspace.shared.activateFileViewerSelecting([folder])
            } catch is CancellationError {
            } catch {
                state.problem = ActivityLog.failed(error, "The export stopped. \(error.localizedDescription)")
            }
            exporting = nil
        }
    }

    private func chooseBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: Backup.fileExtension) ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try Backup.check(url); restoring = url } catch { state.problem = ActivityLog.failed(error, error.localizedDescription) }
    }

    private func restore(_ url: URL) {
        Task {
            // Shut first: nothing still holding the old keys (an Edit in Place save, a note, the index) may write the
            // old list into the restored vault once it's swapped in.
            state.lock("restore")
            do {
                try await Task.detached { _ = try Backup.restore(from: url) }.value
                state.reloadFromDisk()
            } catch {
                state.reloadFromDisk()
                state.problem = ActivityLog.failed(error, error.localizedDescription)
            }
        }
    }

    // MARK: Tabs

    @ViewBuilder private var access: some View {
        section("Getting in") {
            row("Password", "The way in that always works. At least 12 characters.") {
                Button("Change…") { sheet = .changePassword }.buttonStyle(.secondary)
            }
                divider
                row("Open with Touch ID",
                    TouchIDKey.canUse ? "Your finger opens this vault with a key that never leaves this Mac's Secure Enclave. It opens one vault: turning it on here moves it from any other. If you rely on a decoy, turn it on there or nowhere, since a forced finger opens the vault it belongs to."
                                      : "This Mac has no Touch ID set up.") {
                    Toggle("", isOn: .init(get: { state.touchIDOn }, set: state.setTouchID))
                        .toggleStyle(.glass)
                        .disabled(!TouchIDKey.canUse)
                        .accessibilityLabel("Open with Touch ID")
                }
                divider
                row("Lock to this Mac",
                    "The vault opens only on this Mac, even with the password: a copy of its folder is useless anywhere else. Your recovery key opens it if this Mac is lost or repaired.") {
                    Toggle("", isOn: .init(get: { state.macLockOn }, set: lockToMac))
                        .toggleStyle(.glass)
                        .disabled(!MacLock.canUse)
                        .accessibilityLabel("Lock to this Mac")
                }
                divider
                row("Recovery key",
                    state.hasRecovery ? "Opens the vault on any Mac without the password. A new one stops the old one opening this vault, though backups made before still open with it."
                                      : "A key to write on paper, for when the password is forgotten or this Mac is gone.") {
                    Button(state.hasRecovery ? "New Key…" : "Make Key…") { renewingRecovery = true }.buttonStyle(.secondary)
                }
                divider
                row("Emergency kit",
                    state.hasKit ? "Printed pieces you gave out open the vault if something happens to you\(kitAge). A new kit stops the old pieces opening this vault, though backups made before still open with them."
                                 : "Printed pieces for people you trust: any two of three (or your choice) open the vault if something happens to you. One alone opens nothing.") {
                    HStack(spacing: Kit.Space.item) {
                        if state.hasKit { Button("Remove…") { removingKit = true }.buttonStyle(.quiet) }
                        Button(state.hasKit ? "New Kit…" : "Make Kit…") { sheet = .kit }.buttonStyle(.secondary)
                    }
                }
                divider
                row("Decoy password",
                    "A second password that opens a separate, harmless vault with its own recovery key and kit, for when someone makes you open Stillroom in front of them. It won't stand up to someone who has one password and a copy of this Mac's files. Setting one deletes whatever the other vault held.") {
                    HStack(spacing: Kit.Space.item) {
                        Button("Remove…") { removingOther = true }.buttonStyle(.quiet)
                        Button("Set…") { sheet = .setDecoy }.buttonStyle(.secondary)
                    }
                }
        }
    }

    @ViewBuilder private var protection: some View {
        section("Protection") {
            row("Locks by itself", "When the Mac sleeps, its screen locks, Stillroom quits, or nothing on the Mac is touched for this long. Three wrong passwords in a row make each next try wait longer.") {
                Menu(AutoLock.name(autoLock)) {
                    ForEach(AutoLock.choices, id: \.self) { minutes in
                        Button(AutoLock.name(minutes)) {
                            autoLock = minutes
                            AutoLock.minutes = minutes
                            ActivityLog.note("setting changed")
                        }
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.secondary)
                .fixedSize()
            }
            divider
            row("Menu bar icon",
                "Shows whether Stillroom is open, and locks it. Either way, \(LockKey.shortcut) in any app locks Stillroom and hides it at once.") {
                Toggle("", isOn: $menuBarIcon).toggleStyle(.glass).accessibilityLabel("Menu bar icon")
                    .onChange(of: menuBarIcon) { ActivityLog.note("setting changed") }
            }
            divider
            row("Appearance", "Light or dark, or as this Mac is set. The lock screen follows it too.") {
                Segments(selection: $appearance, options: Appearance.allCases.map { ($0, $0.name) })
                    .fixedSize()
                    .onChange(of: appearance) {
                        Appearance.current = appearance
                        ActivityLog.note("setting changed")
                    }
            }
            divider
            // One description for both states, so switching it doesn't change the row's height.
            row("Show in screenshots & screen sharing",
                "When off, screenshots, recordings and screen sharing see Stillroom blank. Turn on to show someone. Remembered with the vault; the lock screen always stays hidden.") {
                Toggle("", isOn: .init(get: { state.showInCapture }, set: state.setShowInCapture))
                    .toggleStyle(.glass)
                    .accessibilityLabel("Show in screenshots and screen sharing")
            }
            divider
            row("Keyboard shield", "While Stillroom is in front, other apps (keyloggers among them) can't read what you type.") { EmptyView() }
        }

        section("Intruder log") {
                row("Take a photo",
                    cameraUndecided ? "Allow the camera now, while the vault is open, so the question never goes to someone at the lock screen."
                                    : IntruderCamera.allowed ? "A photo of whoever types a wrong password. The camera light comes on for a second."
                                    : "The camera isn't allowed. Turn it on for Stillroom in System Settings, Privacy & Security, Camera.") {
                    if cameraUndecided {
                        Button("Allow Camera…") { Task { _ = await IntruderCamera.ask(); cameraUndecided = IntruderCamera.undecided } }
                            .buttonStyle(.secondary)
                    } else {
                        Toggle("", isOn: $takesPhoto).toggleStyle(.glass).disabled(!IntruderCamera.allowed)
                            .accessibilityLabel("Take a photo")
                    }
                }
        }
    }

    /// Kept outside both vaults, so this reads the same in either; only the open vault's own count differs.
    @ViewBuilder private var licenseTab: some View {
        section("Licence") {
            if let license = state.license {
                row(license.edition.name,
                    "Licensed to \(license.name)\(license.seats > 1 ? ", for \(license.seats) people" : ""). No limit on items, and it never expires.") {
                    Button("Remove…") { removingLicense = true }.buttonStyle(.quiet)
                }
            } else {
                row("Free", "This vault holds \(state.files.count) of \(License.freeItems) items. Every feature is included; a licence key lifts the limit, and it never expires. Opening, exporting and backing up never stop, whatever the count.") {
                    EmptyView()
                }
                divider
                VStack(alignment: .leading, spacing: Kit.Space.label) {
                    HStack(spacing: Kit.Space.item) {
                        GlassField(hint: "Paste your licence key", text: $licenseKey, symbol: "key")
                            .onSubmit(addLicense)
                        Button("Add Licence", action: addLicense).buttonStyle(.secondary)
                            .disabled(License.tidy(licenseKey).isEmpty)
                    }
                    if let licenseProblem {
                        Text(licenseProblem).font(Kit.quiet).foregroundStyle(.red.opacity(0.85))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
    }

    @ViewBuilder private var data: some View {
        section("This vault") {
            row("Check vault", "Reads every item and earlier version back, to find any a disk fault or crash has damaged.") {
                Button("Check…") { sheet = .check }.buttonStyle(.secondary)
            }
            Group {
                divider
                row("Where it lives", VaultStore.root.path(percentEncoded: false)) {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([VaultStore.root]) }
                        .buttonStyle(.secondary)
                }
            }
        }

        Group {
            section("Backups") {
                row("Back up", Backup.lastBackup.map { "Last made \($0.formatted(.relative(presentation: .named))). One file holding the whole vault, still encrypted: keep it on a disk you plug in." }
                        ?? "One file holding the whole vault, still encrypted. Keep it on a disk you plug in, not in the cloud.") {
                    Button(backingUp ? "Backing Up…" : "Back Up…", action: backUp).buttonStyle(.secondary).disabled(backingUp)
                }
                divider
                row("Restore", "Put the vault back from a backup file. The vault here now is kept aside, never deleted, until you delete the vault.") {
                    Button("Restore…", action: chooseBackup).buttonStyle(.secondary)
                }
                divider
                row("Export everything", exporting.map { "Taking out \($0.done) of \($0.total)…" }
                        ?? "Every file, note and secret back out as ordinary files in folders, with their own dates. For leaving Stillroom, or a copy anything can read.") {
                    Button(exporting == nil ? "Export…" : "Exporting…") { confirmingExport = true }
                        .buttonStyle(.secondary).disabled(exporting != nil)
                }
            }
        }

        Group {
            section("Updates") {
                row("Check for updates", Updates.detail()) {
                    Button("Check…") { Updates.check() }.buttonStyle(.secondary)
                }
            }
        }

        Group {
            section("Troubleshooting") {
                row("Record activity", "Clicks, shortcuts, what opened and closed, slow steps, errors and freezes, to find what went wrong. Never typing, file names, sizes, passwords or contents. Kept on this Mac for 7 days. If you rely on a decoy, keep it off: over many days its timings could hint that two vaults are used.") {
                    Toggle("", isOn: $activityLog).toggleStyle(.glass).accessibilityLabel("Record activity")
                }
                divider
                row("Activity logs", ActivityLog.folder.path(percentEncoded: false)) {
                    Button("Show in Finder") {
                        try? FileManager.default.createDirectory(at: ActivityLog.folder, withIntermediateDirectories: true)
                        NSWorkspace.shared.activateFileViewerSelecting([ActivityLog.folder])
                    }
                    .buttonStyle(.secondary)
                }
            }
        }

        VStack(spacing: 0) {
            row("Delete the vault", "Every file in it, and the keys, for good.") {
                Button("Delete Vault…") { wiping = true }.buttonStyle(.primary(.red))
            }
        }
        .rowPanel()
        .padding(.top, Kit.Space.item)
    }

    private func addLicense() {
        guard !License.tidy(licenseKey).isEmpty else { return }
        do {
            try state.addLicense(licenseKey)
            licenseKey = ""
            licenseProblem = nil
        } catch {
            licenseProblem = ActivityLog.failed(error, error.localizedDescription)
        }
    }

    private func lockToMac(_ on: Bool) {
        run { try await state.setMacLock(on) }
    }

    /// Runs a change that may hand back a recovery key, showing the key if it does.
    private func run(_ change: @escaping () async throws -> String?) {
        Task {
            do {
                if let code = try await change() { sheet = .recovery(code) }
            } catch {
                state.problem = ActivityLog.failed(error, error.localizedDescription)
            }
        }
    }

    /// " (made 3 months ago)", when it's known.
    private var kitAge: String {
        state.kitMade.map { " (made \($0.formatted(.relative(presentation: .named))))" } ?? ""
    }

    private var divider: some View { Rectangle().fill(Color.ink.opacity(0.05)).frame(height: 1).padding(.leading, 14) }

    private func section(_ title: String, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Kit.Space.label) {
            Text(title).groupLabel().padding(.leading, 4)
            VStack(spacing: 0) { rows() }.rowPanel()
        }
    }

    private func row(_ title: String, _ detail: String, @ViewBuilder control: () -> some View) -> some View {
        HStack(spacing: Kit.Space.group) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Kit.body)
                Text(detail).font(Kit.quiet).opacity(0.45).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Kit.Space.group)
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
