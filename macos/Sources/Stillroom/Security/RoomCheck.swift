import AppKit
import AVFoundation
import CoreAudio

/// Room check: before the vault opens, a quick look at whether this Mac is a safe place to open it right now. All of it
/// is read on this Mac, nothing leaves it, and none of it is about either vault, so it reads the same before any
/// unlock. It never blocks: a serious finding turns Unlock into Open Anyway, a minor one is a note that can be put
/// away. macOS keeps some things from apps (which apps may record the screen, for one), so these are hints, not proof.
enum RoomCheck {
    struct Finding: Identifiable, Equatable, Sendable {
        /// Stable, for remembering a note someone put away.
        let id: String
        let title: String
        let detail: String
        /// Someone or something may be seeing or hearing this Mac right now.
        let serious: Bool
    }

    /// What was seen, gathered once, so the judging below is plain and testable.
    struct Signals: Sendable {
        /// Names of running programs outside Apple's system folders: apps people install.
        var processes: Set<String> = []
        /// Names of Apple's own running services (in /System, /usr, /sbin, /bin). Kept apart, because Apple uses
        /// names that look like apps' (its Spotlight service is `parsecd`, like Parsec's).
        var systemProcesses: Set<String> = []
        var cameraInUse = false
        /// Apps capturing from a microphone, by name or bundle id.
        var microphoneUsers: [String] = []
        var fileVaultOn: Bool?
        var integrityOn: Bool?
        var gatekeeperOn: Bool?
    }

    /// Process names of apps that can show or hand this screen to someone else, as `ps` names them.
    static let remoteControl: [(process: String, name: String)] = [
        ("TeamViewer", "TeamViewer"), ("AnyDesk", "AnyDesk"), ("RustDesk", "RustDesk"), ("parsecd", "Parsec"),
        ("Splashtop Streamer", "Splashtop"), ("vncserver", "VNC Server"), ("remoting_me2me_host", "Chrome Remote Desktop"),
    ]
    /// Clipboard managers that keep a history: a password copied from Stillroom would stay in it.
    static let clipboardHistory: [(process: String, name: String)] = [
        ("Maccy", "Maccy"), ("Paste", "Paste"), ("Pastebot", "Pastebot"), ("Flycut", "Flycut"), ("CopyClip", "CopyClip"),
        ("CopyClip 2", "CopyClip"), ("Clipy", "Clipy"), ("PasteNow", "PasteNow"), ("ClipBook", "ClipBook"),
        ("com.raycast.macos.Pasteboard", "Raycast"),
    ]

    /// The findings for what was seen: serious ones first.
    static func findings(_ s: Signals) -> [Finding] {
        var out: [Finding] = []
        if s.systemProcesses.contains("screensharingd") {
            out.append(Finding(id: "screen-sharing", title: "Someone may be viewing this screen",
                               detail: "A screen sharing session is open. Stillroom hides itself from it, but files you open in other apps aren't hidden.",
                               serious: true))
        }
        if s.systemProcesses.contains("sshd-session") || s.systemProcesses.contains("sshd") {
            out.append(Finding(id: "ssh", title: "Someone is logged in over the network",
                               detail: "A Remote Login (SSH) session is open on this Mac.", serious: true))
        }
        if s.cameraInUse {
            out.append(Finding(id: "camera", title: "A camera is in use by another app",
                               detail: "Something else is using a camera right now. Check the green light and the camera icon in the menu bar.",
                               serious: true))
        }
        if !s.microphoneUsers.isEmpty {
            out.append(Finding(id: "microphone", title: "The microphone is in use",
                               detail: "\(list(s.microphoneUsers)) \(s.microphoneUsers.count == 1 ? "is" : "are") listening right now.",
                               serious: true))
        }
        for app in remoteControl where s.processes.contains(app.process) {
            out.append(Finding(id: "remote-\(app.name)", title: "\(app.name) is running",
                               detail: "It can show this screen to someone else when a session is open. Stillroom stays hidden from it.",
                               serious: false))
        }
        if s.systemProcesses.contains("ARDAgent") {
            out.append(Finding(id: "remote-management", title: "Remote Management is on",
                               detail: "Apple Remote Desktop can show and control this screen. Stillroom stays hidden from it.",
                               serious: false))
        }
        let clipboards = Set(clipboardHistory.filter { s.processes.contains($0.process) }.map(\.name)).sorted()
        if !clipboards.isEmpty {
            out.append(Finding(id: "clipboard", title: "\(list(clipboards)) \(clipboards.count == 1 ? "keeps" : "keep") a clipboard history",
                               detail: "A password you copy from Stillroom would stay there after Stillroom clears it.",
                               serious: false))
        }
        if s.fileVaultOn == false {
            out.append(Finding(id: "filevault", title: "FileVault is off",
                               detail: "Your vault is encrypted either way, but the rest of this Mac's disk isn't. Turn it on in System Settings › Privacy & Security.",
                               serious: false))
        }
        if s.integrityOn == false {
            out.append(Finding(id: "sip", title: "System Integrity Protection isn't fully on",
                               detail: "macOS isn't fully protecting its own files, so other software can change them.", serious: false))
        }
        if s.gatekeeperOn == false {
            out.append(Finding(id: "gatekeeper", title: "Gatekeeper is off",
                               detail: "This Mac runs apps without checking who made them.", serious: false))
        }
        return out.sorted { $0.serious && !$1.serious }
    }

    private static func list(_ names: [String]) -> String {
        names.count <= 1 ? names.joined() : names.dropLast().joined(separator: ", ") + " and " + names.last!
    }

    // MARK: Looking

    /// Everything looked at, off the main thread: a moment's work, run each time the lock screen shows.
    static func look() async -> [Finding] {
        await Task.detached(priority: .userInitiated) { findings(signals()) }.value
    }

    nonisolated static func signals() -> Signals {
        let running = processes()
        return Signals(
            processes: running.apps,
            systemProcesses: running.system,
            cameraInUse: cameraInUse(),
            microphoneUsers: microphoneUsers(),
            fileVaultOn: run("/usr/bin/fdesetup", ["isactive"]).map { $0.contains("true") },
            // Exactly "enabled.": "enabled (Custom Configuration)" means parts of it are off.
            integrityOn: run("/usr/bin/csrutil", ["status"]).map { $0.contains("status: enabled.") },
            gatekeeperOn: run("/usr/sbin/spctl", ["--status"]).map { $0.contains("enabled") })
    }

    /// Every running process (`ps`), by name, split by where it runs from: Apple's system folders or anywhere else.
    static func processes(_ listing: String? = run("/bin/ps", ["-axo", "comm="])) -> (apps: Set<String>, system: Set<String>) {
        var apps: Set<String> = [], system: Set<String> = []
        for line in (listing ?? "").split(separator: "\n") {
            let path = line.trimmingCharacters(in: .whitespaces)
            let name = String(path.split(separator: "/").last ?? Substring(path))
            // A bare name with no path can't be placed: it counts on both sides, so nothing hides by dropping its path.
            guard path.hasPrefix("/") else { system.insert(name); apps.insert(name); continue }
            // Apple's own folders only: /usr/local is where other software installs.
            let apple = ["/System/", "/usr/bin/", "/usr/sbin/", "/usr/libexec/", "/usr/lib/", "/sbin/", "/bin/", "/Library/Apple/"]
                .contains { path.hasPrefix($0) }
            if apple { system.insert(name) } else { apps.insert(name) }
        }
        return (apps, system)
    }

    private static func cameraInUse() -> Bool {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                                         mediaType: .video, position: .unspecified)
            .devices.contains { $0.isInUseByAnotherApplication }
    }

    /// The apps capturing audio input right now, from Core Audio's list of audio processes (macOS 14.2 and later):
    /// exact, so a headset playing music doesn't count.
    private static func microphoneUsers() -> [String] {
        func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
            AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        }
        var list = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &list, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &list, 0, nil, &size, &ids) == noErr else { return [] }
        let me = ProcessInfo.processInfo.processIdentifier
        var names: [String] = []
        for id in ids {
            var running: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            var isRunning = address(kAudioProcessPropertyIsRunningInput)
            guard AudioObjectGetPropertyData(id, &isRunning, 0, nil, &runningSize, &running) == noErr, running != 0 else { continue }
            var pid: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            var pidAddress = address(kAudioProcessPropertyPID)
            _ = AudioObjectGetPropertyData(id, &pidAddress, 0, nil, &pidSize, &pid)
            if pid == me { continue }
            names.append(NSRunningApplication(processIdentifier: pid)?.localizedName ?? "An app")
        }
        return Array(Set(names)).sorted()
    }

    /// A system tool's output, or nil if it couldn't run. Only Apple's own tools, by full path.
    private static func run(_ tool: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return nil }
        // A tool that hangs is stopped after a few seconds: the check says less, and never waits on it.
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { if process.isRunning { process.terminate() } }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    // MARK: Notes put away

    /// Minor notes someone put away ("Got it"), kept outside both vaults like the lock screen itself.
    /// Serious findings can't be put away.
    static var dismissed: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "roomCheckDismissed") ?? []) }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: "roomCheckDismissed") }
    }

    static func shown(_ all: [Finding], dismissed: Set<String> = dismissed) -> [Finding] {
        all.filter { $0.serious || !dismissed.contains($0.id) }
    }
}
