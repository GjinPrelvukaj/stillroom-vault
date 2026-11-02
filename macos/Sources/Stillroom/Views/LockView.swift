import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// In place of everything while the vault is shut: nothing of what's inside is drawn. The first time, the same screen
/// makes the vault. Touch ID is asked at once when it is on; the password is always there, and the recovery key
/// when one was made. After a few wrong tries, each next try waits longer.
struct LockView: View {
    let state: AppState
    @State private var password = ""
    @State private var again = ""
    @State private var touchID = TouchIDKey.canUse
    @State private var problem: String?
    @State private var working = false
    @State private var shakes = 0
    /// Typing the recovery key instead of the password.
    @State private var recovering = false
    /// Typing pieces of the emergency kit instead: as many fields as the kit needs (two until a piece says more).
    @State private var usingKit = false
    @State private var pieces = ["", ""]
    @State private var now = Date()
    /// The ring's lit dots, scattered at random as typing goes on (see `scatter`).
    @State private var lit: Set<Int> = []
    @State private var newest: Int?
    /// The first-time tour has been read (or skipped) this time round.
    @State private var welcomed: Bool = {
        #if DEBUG
        if DemoScreen.screen == "make" { return true }
        #endif
        return false
    }()
    /// Room check's findings for this showing of the lock screen; nil while it's still looking.
    @State private var room: [RoomCheck.Finding]?
    /// Minor notes put away with Got It, kept outside both vaults.
    @State private var putAway = RoomCheck.dismissed
    /// When this look round began: the breath starts from it.
    @State private var lookStarted = Date()
    /// "The room is clear" has been read: it fades a few seconds after typing starts, so the screen settles.
    @State private var clearRead = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A folder from a test build before format 4: nothing here reads or writes it.
    private var oldFormat: Bool { VaultStore.isOldFormat }
    private var making: Bool { !state.exists && !oldFormat }
    /// The shortest password the vault takes: stretching slows each guess, length makes there be too many.
    private static let shortest = 12

    private var waitLeft: Int { max(0, Int(TryLimit.nextTry.timeIntervalSince(now).rounded(.up))) }

    private var ready: Bool {
        guard waitLeft == 0 else { return false }
        if usingKit { return pieces.allSatisfy { !$0.isEmpty } }
        return making ? password.count >= Self.shortest && PasswordStrength.isEnough(password) && password == again : !password.isEmpty
    }

    var body: some View {
        if making && !welcomed {
            WelcomeTour { withAnimation(Motion.appear) { welcomed = true } }
                .transition(.opacity)
        } else {
            form.transition(.opacity)
        }
    }

    private var form: some View {
        VStack(spacing: Kit.Space.group) {
            if !SelfCheck.signedByUs {
                // Before a password is typed into it: this copy may not be the real Stillroom.
                Label("This copy isn't signed by Stillroom's maker. If you didn't build it yourself, it may have been changed: download Stillroom again from stillroomvault.com.",
                      systemImage: "exclamationmark.shield")
                    .font(Kit.quiet)
                    .foregroundStyle(Color.caution)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color.caution.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            if !Inbox.shared.waiting.isEmpty {
                let n = Inbox.shared.waiting.count
                Label("Unlock to put \(n) \(n == 1 ? "item" : "items") in the vault.", systemImage: "tray.and.arrow.down")
                    .font(Kit.quiet)
                    .padding(.horizontal, 12).frame(height: 28)
                    .background(Color.vault.opacity(0.18), in: Capsule())
            }
            ring
            VStack(spacing: Kit.Space.label) {
                Text(making ? "Make your vault" : recovering ? "Use your recovery key" : usingKit ? "Use the emergency kit" : "Stillroom is locked").font(Kit.title)
                Text(making ? "Pick a password you won't forget. Next you'll get a recovery key to write down: the only other way in."
                     : recovering ? "The recovery key you wrote down. You'll set a new password next."
                     : usingKit ? "Type in the pieces from the printed sheets, one per box. You'll set a new password next."
                     : oldFormat ? "This vault was made by an earlier test version of Stillroom, which this one can't open. Nothing in it has been changed."
                     : "Everything inside is encrypted on this Mac.")
                    .font(Kit.body).quietText()
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                // One slot, as tall as a finding, for checking, clear or one finding: the form doesn't move when
                // Room check finishes.
                roomStatus.frame(minHeight: 48).padding(.top, Kit.Space.label)
            }
            .padding(.bottom, Kit.Space.item)

            VStack(spacing: Kit.Space.item) {
                if usingKit {
                    ForEach(pieces.indices, id: \.self) { i in
                        GlassField(hint: "Piece \(i + 1): VK-…", text: $pieces[i], secure: true, symbol: "doc.text", autofocus: i == 0)
                    }
                } else {
                    GlassField(hint: recovering ? "XXXXX-XXXXX-XXXXX-XXXXX-XXXXX" : "Password", text: $password, secure: true,
                               symbol: recovering ? "lifepreserver" : "key", autofocus: !state.touchIDOn || making)
                        .id(recovering)
                }
                if making { GlassField(hint: "Password again", text: $again, secure: true, symbol: "key") }
            }
            .onSubmit(go)
            .keyframeAnimator(initialValue: CGFloat(0), trigger: shakes) { content, x in
                content.offset(x: x)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(-9, duration: 0.05)
                    LinearKeyframe(8, duration: 0.08)
                    LinearKeyframe(-5, duration: 0.07)
                    SpringKeyframe(0, duration: 0.2, spring: .init(response: 0.2, dampingRatio: 0.6))
                }
            }

            // One line, always room for it, so the buttons never jump when it appears.
            Text(line ?? " ")
                .font(Kit.quiet)
                .foregroundStyle(problem == nil && waitLeft == 0 ? Color.quietInk : Color.problem)
                .multilineTextAlignment(.center)
                // Making a vault, the advice can run to two lines: room for both once typing starts, not before.
                .frame(minHeight: making && !password.isEmpty ? 32 : 16, alignment: .top)
                .animation(Motion.change, value: password.isEmpty)

            if making && TouchIDKey.canUse {
                Toggle("Open it with Touch ID too", isOn: $touchID).toggleStyle(.glass)
            }

            HStack(spacing: Kit.Space.item) {
                if !making && !recovering && state.touchIDOn {
                    Button(action: askTouchID) { Label("Touch ID", systemImage: "touchid") }
                        .buttonStyle(.secondary)
                }
                // Never a block: something serious only asks for a deliberate click.
                Button(making ? "Make My Vault" : seriousRoom ? "Open Anyway" : "Unlock", action: go)
                    .buttonStyle(.primary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!ready || working)
            }

            if making {
                Button("Restore from a Backup…", action: restoreBackup).buttonStyle(.quiet)
            }
            if !making && (recovering || usingKit) {
                Button("Use My Password") { switchTo(recovery: false, kit: false) }.buttonStyle(.quiet)
            } else if !making {
                HStack(spacing: Kit.Space.group) {
                    // Every vault has both, so they always show.
                    Button("Use Recovery Key") { switchTo(recovery: true, kit: false) }.buttonStyle(.quiet)
                    Button("Use Emergency Kit") { switchTo(recovery: false, kit: true) }.buttonStyle(.quiet)
                }
            }
        }
        .frame(width: 320)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, Glass.lightRoom / 2)
        // Room check first; Touch ID is asked once it's done, unless it found something serious.
        .task { await checkRoom(thenTouchID: true) }
        #if DEBUG
        .onAppear {
            if let demo = DemoScreen.password, !making { DemoScreen.password = nil; password = demo; go() }
        }
        #endif
        // Back to Stillroom: look again, since a call or a screen share may have started or ended meanwhile.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await checkRoom(thenTouchID: false) }
        }
        .onChange(of: password) { old, new in
            if !new.isEmpty { problem = nil }
            scatter(from: old.count, to: new.count)
        }
        .task(id: password.isEmpty) {
            guard !password.isEmpty, !clearRead else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(Motion.or(Motion.appear, reduce: reduceMotion)) { clearRead = true }
        }
        // The right password: every dot lights in one short sweep before the vault comes in (RootView waits for it).
        .onChange(of: state.isOpen) {
            guard state.isOpen, !reduceMotion else { return }
            withAnimation(Motion.change) { lit = Set(0..<Self.dots); newest = nil }
        }
        // A piece says how many the kit needs: that many boxes.
        .onChange(of: pieces) {
            problem = nil
            if let needed = pieces.lazy.compactMap({ try? EmergencyKit.piece($0) }).first?.threshold, needed != pieces.count {
                pieces = Array((pieces + Array(repeating: "", count: needed)).prefix(needed))
            }
        }
        // While a try has to wait, the line counts down each second.
        .task(id: TryLimit.nextTry) {
            while !Task.isCancelled {
                now = Date()
                guard waitLeft > 0 else { return }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// The one living thing: dots lighting at random in Vault's colour as you type, never in the same pattern twice.
    private var ring: some View {
        ZStack {
            // While Room check looks round, the whole ring breathes: every dot glows in and out together, starting dim.
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !sweeping)) { timeline in
                let breath = sweeping ? 0.5 - 0.5 * cos(2 * .pi * timeline.date.timeIntervalSince(lookStarted) / Self.breath) : 1
                DotRing(lit: 0,
                        tint: sweeping ? Color.vault.opacity(0.15 + 0.75 * breath)
                            : !making || (password.count >= Self.shortest && PasswordStrength.isEnough(password)) ? .vault : Color.ink.opacity(0.8),
                        count: Self.dots,
                        pattern: sweeping ? Set(0..<Self.dots) : lit,
                        newest: sweeping ? nil : newest)
                    .scaleEffect(sweeping ? 0.97 + 0.03 * breath : 1)
            }
            Image(systemName: working || state.isOpen ? "lock.open.fill" : "lock.fill")
                .font(Kit.glyph)
                .opacity(0.75)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: 84, height: 84)
        .animation(Motion.change, value: lit)
    }

    private static let dots = 48

    private var sweeping: Bool { room == nil && password.isEmpty && !reduceMotion }
    /// One breath, in and out, in seconds; Room check shows at least the breath in.
    private static let breath = 1.8
    private var seriousRoom: Bool { room?.contains { $0.serious } ?? false }

    /// Under the title: what Room check found, or that the room is clear. Hints, never a block.
    @ViewBuilder private var roomStatus: some View {
        if let room {
            let shown = RoomCheck.shown(room, dismissed: putAway)
            if shown.isEmpty {
                Label("The room is clear", systemImage: "checkmark.seal")
                    .font(Kit.quiet)
                    .foregroundStyle(Color.vault)
                    .help("Room check found nothing on this Mac watching or listening right now.")
                    // Only the all-clear fades, keeping its room; a finding never does.
                    .opacity(clearRead ? 0 : 1)
            } else {
                // Only something serious gets a panel; a minor note is one quiet line under the subtitle.
                let heavy = shown.contains { $0.serious }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(shown) { finding in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: finding.serious ? "exclamationmark.triangle.fill" : "info.circle")
                                .foregroundStyle(finding.serious ? Color.caution : Color.quietInk)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(finding.title).font(Kit.quiet)
                                if finding.serious {
                                    Text(finding.detail).font(Kit.quiet).quietText().fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            if heavy { Spacer(minLength: 4) }
                            if !finding.serious {
                                Button("Got It") {
                                    putAway.insert(finding.id)
                                    RoomCheck.dismissed = putAway
                                }
                                .buttonStyle(.quiet)
                                .help("Don't mention this again")
                            }
                        }
                        .help(finding.detail)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(heavy ? 10 : 0)
                .frame(maxWidth: .infinity, alignment: heavy ? .leading : .center)
                .background(Color.ink.opacity(heavy ? 0.04 : 0), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .transition(.opacity)
            }
        } else {
            Text("Checking the room…").font(Kit.quiet).quietText()
        }
    }

    /// Room check, then (the first time round) Touch ID unless it found something serious, which waits for a click.
    private func checkRoom(thenTouchID: Bool) async {
        let started = Date()
        if thenTouchID { lookStarted = started }
        let found = await RoomCheck.look()
        // Long enough for one breath in to read as a look round, never long enough to wait on.
        let left = Self.breath / 2 - Date().timeIntervalSince(started)
        if thenTouchID, left > 0, !reduceMotion { try? await Task.sleep(for: .seconds(left)) }
        // Unlocked meanwhile: this screen is gone, and nothing more is asked.
        guard !Task.isCancelled, !state.isOpen else { return }
        withAnimation(Motion.change) { room = found }
        // All clear: the ring fills for a moment and settles, unless typing has started.
        if thenTouchID, RoomCheck.shown(found, dismissed: putAway).isEmpty, password.isEmpty, !reduceMotion {
            lit = Set(0..<Self.dots)
            try? await Task.sleep(for: .milliseconds(650))
            if password.isEmpty { lit = [] }
        }
        guard !Task.isCancelled, !state.isOpen else { return }
        if thenTouchID, !making, state.touchIDOn, !found.contains(where: \.serious) { askTouchID() }
    }

    /// The ring's answer to typing: each character lights a random handful of dots (four to nine) anywhere round it,
    /// each deletion puts a handful out. So the ring is different every time, never shows how long the password is,
    /// and any password soon fills it; once full, more typing just moves the bright dot.
    private func scatter(from old: Int, to new: Int) {
        guard new > 0 else { lit = []; newest = nil; return }
        for _ in 0..<abs(new - old) {
            let handful = Int.random(in: 4...9)
            if new > old {
                let picked = Set(0..<Self.dots).subtracting(lit).shuffled().prefix(handful)
                lit.formUnion(picked)
                newest = picked.last ?? lit.randomElement()
            } else {
                lit.subtract(lit.shuffled().prefix(handful))
                newest = lit.randomElement()
            }
        }
    }

    /// What the line under the fields says: how long to wait, what went wrong, else what's still missing.
    private var line: String? {
        if waitLeft > 0 { return "Too many wrong tries. Try again in \(waitLeft) s." }
        if let problem { return problem }
        guard making else { return nil }
        if !password.isEmpty && password.count < Self.shortest { return "At least \(Self.shortest) characters. Longer is stronger." }
        if !password.isEmpty && !PasswordStrength.isEnough(password) { return PasswordStrength.advice }
        if !again.isEmpty && again != password { return "The two don't match yet." }
        return nil
    }

    private func go() {
        guard ready, !working else { return }
        working = true
        // What's tried is what was typed when Return was pressed; typing on while it's checked changes nothing.
        let tried = password
        Task {
            do {
                if making {
                    try await state.create(password: tried, touchID: touchID)
                } else if usingKit {
                    try await state.unlock(kitPieces: pieces)
                } else if recovering {
                    try await state.unlock(recoveryKey: tried)
                } else {
                    try await state.unlock(password: tried)
                }
                TryLimit.succeeded()
            } catch is CancellationError {
            } catch {
                fail(error, tried: tried)
            }
            working = false
        }
    }

    private func switchTo(recovery: Bool, kit: Bool) {
        recovering = recovery
        usingKit = kit
        password = ""
        pieces = ["", ""]
        problem = nil
    }

    /// A vault put back from a backup file, before any vault is made here.
    private func restoreBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: Backup.fileExtension) ?? .data]
        panel.message = "Choose a Stillroom backup to put back."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        working = true
        Task {
            do {
                try await Task.detached { _ = try Backup.restore(from: url) }.value
                state.reloadFromDisk()
            } catch {
                problem = ActivityLog.failed(error, error.localizedDescription)
            }
            working = false
        }
    }

    private func askTouchID() {
        guard !working else { return }
        working = true
        Task {
            do { try await state.unlockWithTouchID(); TryLimit.succeeded() } catch is CancellationError {} catch { fail(error, tried: nil) }
            working = false
        }
    }

    private func fail(_ error: Error, tried: String?) {
        // Only a guess counts towards the wait; a vault locked to another Mac isn't a wrong guess.
        if let error = error as? VaultError, error == .wrongPassword || error == .wrongRecoveryKey || error == .wrongKit {
            TryLimit.failed()
            // Into the intruder log, sealed so only your vault, open, can read it.
            // Kit pieces are never written into the log: they're half of a way in.
            IntruderSettings.record(error == .wrongPassword ? .wrongPassword : .wrongRecoveryKey)
        }
        if let error = error as? VaultError, error == .notThisMac { recovering = true }
        if !making { password = "" }
        problem = ActivityLog.failed(error, error.localizedDescription)
        now = Date()
        if !reduceMotion { shakes += 1 }
    }
}

/// Wrong tries at the lock screen: the first three are free, then each next try waits longer (5 s, 10 s, 20 s… up
/// to 5 minutes). Kept across restarts, so quitting doesn't reset it. This slows someone at your Mac; a stolen copy
/// is only slowed by the password's stretching and length.
enum TryLimit {
    private static var defaults: UserDefaults { .standard }
    private static let failuresKey = "wrongTries"
    private static let lastKey = "lastWrongTry"

    static var nextTry: Date {
        let failures = defaults.integer(forKey: failuresKey)
        guard failures > 3 else { return .distantPast }
        let wait = min(300, 5 * pow(2, Double(failures - 4)))
        let last = Date(timeIntervalSince1970: defaults.double(forKey: lastKey))
        return last.addingTimeInterval(wait)
    }

    static func failed() {
        defaults.set(defaults.integer(forKey: failuresKey) + 1, forKey: failuresKey)
        defaults.set(Date().timeIntervalSince1970, forKey: lastKey)
    }

    static func succeeded() {
        defaults.removeObject(forKey: failuresKey)
        defaults.removeObject(forKey: lastKey)
    }
}
