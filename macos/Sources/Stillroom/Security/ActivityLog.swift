import AppKit
import Darwin
import Foundation

/// A record of what happened in the app, for finding bugs, freezes and slowness, including ones nobody noticed:
/// clicks, named keys and ⌘ shortcuts, mouse movement, scrolling, pages and sheets, what kind of thing opened and
/// closed, how long every slow step took, every error's kind, memory use, the app's comings and goings (active,
/// hidden, sleep, screen lock, quit), crashes and unclean quits, and every moment the main thread stalled, with
/// exactly where it was stuck.
///
/// It never holds typing (not even that it happened), file names, sizes, item counts, passwords, contents, error
/// messages' text, or which vault opened (see docs/SECURITY.md). Kept on this Mac only, in ~/Library/Logs/Stillroom
/// (deleted after 7 days). On in development builds; in the app you use, switched in Settings › Troubleshooting.
enum ActivityLog {
    static var isOn: Bool {
        #if DEBUG
        UserDefaults.standard.object(forKey: "activityLog") as? Bool ?? true
        #else
        UserDefaults.standard.bool(forKey: "activityLog")
        #endif
    }

    static var folder: URL { URL.libraryDirectory.appending(path: "Logs/Stillroom", directoryHint: .isDirectory) }

    fileprivate static let queue = DispatchQueue(label: "app.gjin.stillroom.activity")
    nonisolated(unsafe) private static var handle: FileHandle?
    nonisolated(unsafe) private static var day = ""
    nonisolated(unsafe) private static var monitor: Any?
    nonisolated(unsafe) private static var observers: [NSObjectProtocol] = []
    nonisolated(unsafe) private static var memoryTimer: Timer?
    nonisolated(unsafe) private static var lastMove = Date.distantPast
    nonisolated(unsafe) private static var lastScroll = Date.distantPast
    /// Only the running app writes: tests and tools that touch AppState never call start().
    nonisolated(unsafe) private static var started = false
    /// Keys are only noted while a vault is open: at the lock screen, nothing about typing is kept at all.
    nonisolated(unsafe) static var vaultOpen = false
    /// The last thing done, said again when the app freezes.
    nonisolated(unsafe) fileprivate static var lastAction = "nothing yet"

    // MARK: Writing

    /// One line in the log. `action` lines are remembered as the last thing done.
    static func note(_ text: String, action: Bool = true) {
        guard started, isOn else { return }
        let now = Date()
        queue.async {
            if action { lastAction = text }
            write(now, text)
        }
    }

    /// An error, by kind only: where it happened, its type and code. Never its message, which can hold a file name.
    static func error(_ context: String, _ error: Error) {
        let ns = error as NSError
        let kind = String(describing: type(of: error))
        let detail = error is CancellationError ? "cancelled" : "\(kind) \(ns.domain) \(ns.code)"
        note("ERROR in \(context): \(detail)", action: false)
    }

    /// Logs an error by kind and where in the code it happened, and hands back the message shown for it.
    static func failed(_ error: Error, _ message: String, function: String = #function, file: String = #fileID, line: Int = #line) -> String {
        self.error("\((file as NSString).lastPathComponent):\(line) \(function)", error)
        return message
    }

    /// Runs `work` and notes how long it took: exactly when `exact` (work whose cost doesn't depend on what's in the
    /// vault, like password stretching), otherwise only when slow and only roughly (see `took`).
    @discardableResult
    static func timed<T>(_ label: String, exact: Bool = false, _ work: () throws -> T) rethrows -> T {
        let started = DispatchTime.now()
        defer { exact ? note("\(label): \(milliseconds(since: started)) ms", action: false) : took(label, since: started) }
        return try work()
    }

    @discardableResult
    static func timed<T>(_ label: String, isolation: isolated (any Actor)? = #isolation, _ work: () async throws -> T) async rethrows -> T {
        let started = DispatchTime.now()
        defer { took(label, since: started) }
        return try await work()
    }

    /// How long a step took, for steps whose time grows with what's in the vault (opening it, saving the list,
    /// search, encrypting, previews). Exact times would add up to a picture of the vault's size, and a decoy's
    /// would differ from yours; so only slow steps are noted, in rough bands.
    static func took(_ label: String, since start: DispatchTime, action: Bool = false) {
        let ms = milliseconds(since: start)
        guard ms >= 250 else { return }
        let band = ms >= 10_000 ? "over 10 s" : ms >= 3_000 ? "over 3 s" : ms >= 1_000 ? "over 1 s" : "over 0.25 s"
        note("SLOW: \(label) took \(band)", action: action)
    }

    static func milliseconds(since start: DispatchTime) -> Int {
        let now = DispatchTime.now().uptimeNanoseconds
        return Int((now &- min(start.uptimeNanoseconds, now)) / 1_000_000)
    }

    // MARK: Starting and stopping

    /// Starts recording: the header, last run's fate, app events, input, memory, and the stall detector.
    @MainActor static func start() {
        guard isOn, monitor == nil else { return }
        started = true
        MainThreadStack.remember()
        queue.async { removeOld() }
        note(header(), action: false)
        checkLastRun()
        for window in NSApp.windows { window.acceptsMouseMovedEvents = true }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .otherMouseDown,
                                                              .keyDown, .scrollWheel, .mouseMoved, .leftMouseDragged]) { event in
            record(event)
            return event
        }
        watchAppEvents()
        memoryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in note(memory(), action: false) }
        note(memory(), action: false)
        StallWatch.shared.start()
    }

    @MainActor static func stop() {
        note("activity log switched off")
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0)
            DistributedNotificationCenter.default().removeObserver($0) }
        observers = []
        memoryTimer?.invalidate()
        memoryTimer = nil
        StallWatch.shared.stop()
        started = false
    }

    private static func header() -> String {
        let info = ProcessInfo.processInfo
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        #if DEBUG
        let build = "debug"
        #else
        let build = "release"
        #endif
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let ram = info.physicalMemory / 1_073_741_824
        return "started Stillroom \(version) (\(build), pid \(info.processIdentifier)) on macOS \(info.operatingSystemVersionString), "
            + "\(String(decoding: model.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)), \(ram) GB, "
            + "\(info.activeProcessorCount) cores, up \(Int(info.systemUptime / 3600)) h"
    }

    // MARK: Last run

    /// A crash report of this very app, not another build also named Stillroom (a demo copy has its own bundle id).
    /// The report's first line is a JSON header naming it.
    private static func isOurs(_ report: URL) -> Bool {
        guard let id = Bundle.main.bundleIdentifier, let handle = try? FileHandle(forReadingFrom: report),
              let head = try? handle.read(upToCount: 4096) else { return false }
        try? handle.close()
        let header = head.split(separator: UInt8(ascii: "\n"), maxSplits: 1).first.map { Data($0) } ?? head
        return (try? JSONSerialization.jsonObject(with: header) as? [String: Any])?["bundleID"] as? String == id
    }

    private static var marker: URL { folder.appending(path: ".running") }

    /// A marker made at start and removed at a normal quit: still there means the last run ended some other way.
    /// Crash reports macOS wrote for Stillroom since then are copied in beside the log.
    private static func checkLastRun() {
        queue.async {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let previous = (try? marker.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let previous {
                write(Date(), "LAST RUN DIDN'T QUIT NORMALLY (started \(previous.formatted(date: .abbreviated, time: .standard))): a crash, force quit, or power loss")
            }
            let reports = URL.libraryDirectory.appending(path: "Logs/DiagnosticReports")
            let since = previous ?? Date.now.addingTimeInterval(-24 * 3600)
            for report in (try? FileManager.default.contentsOfDirectory(at: reports, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            where report.lastPathComponent.hasPrefix("Stillroom")
                && ((try? report.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > since
                && isOurs(report) {
                let copy = folder.appending(path: "crash-" + report.lastPathComponent)
                try? FileManager.default.copyItem(at: report, to: copy)
                write(Date(), "CRASH REPORT found from macOS: \(copy.lastPathComponent)")
            }
            FileManager.default.createFile(atPath: marker.path, contents: Data("\(ProcessInfo.processInfo.processIdentifier)".utf8),
                                           attributes: [.posixPermissions: 0o600])
        }
    }

    // MARK: App events

    @MainActor private static func watchAppEvents() {
        let app: [(Notification.Name, String)] = [
            (NSApplication.didBecomeActiveNotification, "app came to the front"),
            (NSApplication.didResignActiveNotification, "app went to the back"),
            (NSApplication.didHideNotification, "app hidden"),
            (NSApplication.didUnhideNotification, "app shown again"),
            (NSWindow.didMiniaturizeNotification, "window minimized"),
            (NSWindow.didDeminiaturizeNotification, "window restored"),
            (NSWindow.didEnterFullScreenNotification, "window full screen"),
            (NSWindow.didExitFullScreenNotification, "window left full screen"),
            (NSApplication.didChangeScreenParametersNotification, "displays changed"),
        ]
        for (name, text) in app {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { _ in note(text, action: false) })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { _ in
            let now = Date()
            // Waited for: the app is about to go.
            queue.sync {
                write(now, "quit normally")
                try? FileManager.default.removeItem(at: marker)
            }
        })
        let system: [(Notification.Name, String)] = [
            (NSWorkspace.willSleepNotification, "Mac going to sleep"),
            (NSWorkspace.didWakeNotification, "Mac woke"),
            (NSWorkspace.screensDidSleepNotification, "display slept"),
            (NSWorkspace.screensDidWakeNotification, "display woke"),
            (NSWorkspace.sessionDidResignActiveNotification, "switched to another user"),
            (NSWorkspace.sessionDidBecomeActiveNotification, "back from another user"),
        ]
        for (name, text) in system {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: nil) { _ in note(text, action: false) })
        }
        for (name, text) in [("com.apple.screenIsLocked", "screen locked"), ("com.apple.screenIsUnlocked", "screen unlocked")] {
            observers.append(DistributedNotificationCenter.default().addObserver(forName: .init(name), object: nil, queue: nil) { _ in
                note(text, action: false)
            })
        }
    }

    // MARK: Input

    @MainActor private static func record(_ event: NSEvent) {
        let point = event.window.map { w in
            let p = event.locationInWindow
            return "at \(Int(p.x)),\(Int(w.frame.height - p.y))"
        } ?? ""
        switch event.type {
        case .leftMouseDown: note("click \(point)\(event.clickCount > 1 ? " ×\(event.clickCount)" : "")")
        case .leftMouseUp: note("release \(point)", action: false)
        case .rightMouseDown: note("right-click \(point)")
        case .otherMouseDown: note("other-button click \(point)")
        case .leftMouseDragged:
            guard Date().timeIntervalSince(lastMove) > 0.25 else { return }
            lastMove = Date()
            note("drag \(point)", action: false)
        case .mouseMoved:
            guard Date().timeIntervalSince(lastMove) > 0.25 else { return }
            lastMove = Date()
            note("move \(point)", action: false)
        case .scrollWheel:
            guard Date().timeIntervalSince(lastScroll) > 0.5 else { return }
            lastScroll = Date()
            note("scroll \(point)", action: false)
        case .keyDown:
            // Typing is never noted, not even that it happened. In a text field only ⌘ shortcuts are; outside one,
            // named keys too (arrows, Return, Esc).
            let typing = NSApp.keyWindow?.firstResponder is NSText
            if vaultOpen, let key = name(event), !typing || event.modifierFlags.contains(.command) { note("key \(key)") }
        default: break
        }
    }

    /// A named key or a ⌘ shortcut; nil for typing.
    private static func name(_ event: NSEvent) -> String? {
        let named: [UInt16: String] = [36: "return", 53: "esc", 48: "tab", 51: "delete", 117: "forward-delete", 123: "left",
                                       124: "right", 125: "down", 126: "up", 49: "space", 116: "page-up", 121: "page-down"]
        let mods = event.modifierFlags
        var prefix = ""
        if mods.contains(.control) { prefix += "⌃" }
        if mods.contains(.option) { prefix += "⌥" }
        if mods.contains(.shift) { prefix += "⇧" }
        if mods.contains(.command) { prefix += "⌘" }
        if let key = named[event.keyCode] { return prefix + key }
        // With ⌘ it's a shortcut, not typing: the letter says which.
        if mods.contains(.command), let letter = event.charactersIgnoringModifiers?.lowercased() { return prefix + letter }
        return nil
    }

    // MARK: Memory

    /// How much memory Stillroom uses (what Activity Monitor shows), and how much processor time it has used so far.
    private static func memory() -> String {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        // While a vault is open, memory follows what's in it: rounded to 100 MB so it doesn't sketch the vault's size.
        let mb = Int(info.phys_footprint / 1_048_576)
        let footprint = result != KERN_SUCCESS ? "?" : vaultOpen ? "about \(max(100, (mb + 50) / 100 * 100)) MB" : "\(mb) MB"
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        return "memory \(footprint), processor time \(String(format: "%.1f", cpu)) s"
    }

    // MARK: The file

    fileprivate static func write(_ time: Date, _ text: String) {
        let stamp = localDay(time)
        if stamp != day || handle == nil {
            try? handle?.close()
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let url = folder.appending(path: "activity-\(stamp).log")
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            handle = try? FileHandle(forWritingTo: url)
            _ = try? handle?.seekToEnd()
            day = stamp
        }
        try? handle?.write(contentsOf: Data("\(clock(time))  \(text)\n".utf8))
    }

    /// "2026-10-24", in this Mac's time zone, whatever its date format.
    fileprivate static func localDay(_ time: Date) -> String { dayFormat.string(from: time) }
    private static let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    fileprivate static func clock(_ time: Date) -> String {
        time.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits).secondFraction(.fractional(3)))
    }

    private static func removeOld() {
        let old = Date.now.addingTimeInterval(-7 * 24 * 3600)
        for url in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        where url.lastPathComponent != ".running"
            && ((try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .now) < old {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: Stalls and freezes

    /// Asks the main thread to answer four times a second. When it doesn't, it's stalled: from a quarter second on,
    /// where the main thread is stuck is captured (from inside the app, so at the very moment), again each quarter
    /// second while it lasts. Under a second, it's logged as a stall with the top of where it was stuck; over a
    /// second, it's a FREEZE: every captured stack goes to a freeze file beside the log, and macOS's `sample` takes
    /// a full snapshot of every thread too.
    final class StallWatch: @unchecked Sendable {
        static let shared = StallWatch()
        private let lock = NSLock()
        private var answered = DispatchTime.now()
        private var running = false
        private var stallStart: DispatchTime?
        private var stacks: [[UInt]] = []
        private var froze = false
        private var freezeFile: URL?

        func start() {
            lock.withLock { guard !running else { return }; running = true; answered = .now() }
            Thread.detachNewThread { [self] in
                Thread.current.name = "Stillroom stall watch"
                while lock.withLock({ running }) {
                    Thread.sleep(forTimeInterval: 0.25)
                    DispatchQueue.main.async { self.lock.withLock { self.answered = .now() } }
                    check()
                }
            }
        }

        func stop() { lock.withLock { running = false } }

        private func check() {
            // Read the last answer first: the main thread can answer between the two readings, and an answer later
            // than "now" would make the gap negative.
            let last = lock.withLock { answered }
            let now = DispatchTime.now()
            let gap = Double(now.uptimeNanoseconds &- min(last.uptimeNanoseconds, now.uptimeNanoseconds)) / 1e9
            if gap > 0.3 {
                // Where it's stuck right now; a stack the same as the last one isn't kept twice.
                let stack = MainThreadStack.capture()
                // Asleep in the run loop waiting for input isn't stuck: macOS held the answer back (App Nap, while
                // Stillroom is in the back or the Mac idles). Whatever stalled before this has finished.
                if MainThreadStack.isWaiting(stack) {
                    if let start = stallStart { end(start) }
                    lock.withLock { answered = .now() }
                    return
                }
                if stallStart == nil { stallStart = last; stacks = []; froze = false }
                if !stack.isEmpty, stacks.last != stack, stacks.count < 40 { stacks.append(stack) }
                if gap > 1, !froze { beginFreeze() }
            } else if let start = stallStart {
                end(start)
            }
        }

        private func beginFreeze() {
            froze = true
            let when = Date()
            let file = ActivityLog.folder.appending(path: "freeze-\(ActivityLog.localDay(when))-\(ActivityLog.clock(when).replacingOccurrences(of: ":", with: "").prefix(6)).txt")
            freezeFile = file
            ActivityLog.queue.async {
                ActivityLog.write(when, "FROZE: the main thread stopped answering (last thing done: \(ActivityLog.lastAction)). Where it's stuck: \(file.lastPathComponent)")
            }
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/sample")
            process.arguments = [String(ProcessInfo.processInfo.processIdentifier), "2", "-file",
                                 file.deletingPathExtension().path + "-sample.txt"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
        }

        private func end(_ start: DispatchTime) {
            let nowNanos = DispatchTime.now().uptimeNanoseconds
            let length = Double(nowNanos &- min(start.uptimeNanoseconds, nowNanos)) / 1e9
            let captured = stacks
            let wasFreeze = froze
            let file = freezeFile
            stallStart = nil
            stacks = []
            froze = false
            freezeFile = nil
            ActivityLog.queue.async {
                let top = captured.first.map { MainThreadStack.headline($0) } ?? "no stack captured"
                if wasFreeze, let file {
                    ActivityLog.write(Date(), "answering again after a \(String(format: "%.1f", length)) s freeze; stuck in \(top)")
                    let body = captured.enumerated().map { i, stack in
                        "Stack \(i + 1) of \(captured.count):\n" + stack.map { "  " + MainThreadStack.describe($0) }.joined(separator: "\n")
                    }.joined(separator: "\n\n")
                    FileManager.default.createFile(atPath: file.path,
                                                   contents: Data("Main thread during a \(String(format: "%.1f", length)) s freeze (last thing done: \(ActivityLog.lastAction))\n\n\(body)\n".utf8),
                                                   attributes: [.posixPermissions: 0o600])
                } else {
                    ActivityLog.write(Date(), "STALL: main thread busy for \(Int(length * 1000)) ms (last thing done: \(ActivityLog.lastAction)); stuck in \(top)")
                }
            }
        }
    }
}

/// The main thread's call stack, read from another thread while it's briefly paused: what it was doing at that
/// instant. Walks the frame-pointer chain; nothing is allocated while it's paused (a paused thread may hold the
/// allocator's lock).
enum MainThreadStack {
    nonisolated(unsafe) private static var port: thread_t = 0
    nonisolated(unsafe) private static var stackLow: UInt = 0
    nonisolated(unsafe) private static var stackHigh: UInt = 0
    private static let depth = 64
    nonisolated(unsafe) private static let buffer = UnsafeMutablePointer<UInt>.allocate(capacity: 64)

    /// Called once, on the main thread.
    static func remember() {
        guard port == 0 else { return }
        port = mach_thread_self()
        let me = pthread_self()
        stackHigh = UInt(bitPattern: pthread_get_stackaddr_np(me))
        stackLow = stackHigh - UInt(pthread_get_stacksize_np(me))
    }

    /// Return addresses, innermost first; empty if the main thread couldn't be read.
    static func capture() -> [UInt] {
        #if arch(arm64)
        guard port != 0, thread_suspend(port) == KERN_SUCCESS else { return [] }
        var count = 0
        var state = arm_thread_state64_t()
        var size = mach_msg_type_number_t(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<natural_t>.size)
        let read = withUnsafeMutablePointer(to: &state) {
            $0.withMemoryRebound(to: natural_t.self, capacity: Int(size)) { thread_get_state(port, ARM_THREAD_STATE64, $0, &size) }
        }
        if read == KERN_SUCCESS {
            // Pointer-authentication bits off the top of each address.
            let strip: UInt = 0x0000_7FFF_FFFF_FFFF
            buffer[0] = UInt(state.__pc) & strip
            buffer[1] = UInt(state.__lr) & strip
            count = 2
            var fp = UInt(state.__fp) & strip
            while count < depth, fp >= stackLow, fp + 16 <= stackHigh, fp % 8 == 0 {
                let frame = UnsafePointer<UInt>(bitPattern: fp)!
                let next = frame[0] & strip
                let ret = frame[1] & strip
                if ret == 0 { break }
                buffer[count] = ret
                count += 1
                if next <= fp { break }
                fp = next
            }
        }
        thread_resume(port)
        return Array(UnsafeBufferPointer(start: buffer, count: count))
        #else
        return []
        #endif
    }

    /// The thread is asleep in its run loop, waiting for the next event: nothing is running on it.
    static func isWaiting(_ stack: [UInt]) -> Bool {
        stack.prefix(8).contains { address in
            var info = Dl_info()
            guard dladdr(UnsafeRawPointer(bitPattern: address), &info) != 0, let name = info.dli_sname else { return false }
            return strcmp(name, "__CFRunLoopServiceMachPort") == 0
        }
    }

    /// The first frames that are Stillroom's own (or the top three, when none are), shortened for one log line; the
    /// freeze file keeps them whole.
    static func headline(_ stack: [UInt]) -> String {
        let frames = stack.map(describe)
        let ours = frames.filter { $0.hasPrefix("Stillroom ") }.prefix(3)
        return (ours.isEmpty ? frames.prefix(3) : ours).map(shortened).joined(separator: " ← ")
    }

    /// Generic parameters dropped ("TupleView<…>" becomes "TupleView"), and no more than 120 characters.
    static func shortened(_ frame: String) -> String {
        var out = ""
        var depth = 0
        var previous: Character = " "
        for c in frame {
            defer { previous = c }
            if c == "<" { depth += 1; continue }
            // The ">" of a "->" arrow isn't the end of a generic.
            if c == ">", previous != "-" { depth = max(0, depth - 1); continue }
            if depth == 0 { out.append(c) }
        }
        return out.count > 120 ? String(out.prefix(119)) + "…" : out
    }

    /// "Stillroom  AppState.unlock(password:) + 412".
    static func describe(_ address: UInt) -> String {
        var info = Dl_info()
        guard dladdr(UnsafeRawPointer(bitPattern: address), &info) != 0 else { return String(format: "0x%lx", address) }
        let image = info.dli_fname.map { (String(cString: $0) as NSString).lastPathComponent } ?? "?"
        var symbol = info.dli_sname.map { demangle(String(cString: $0)) } ?? "?"
        // A frame naming the decoy would say one is being set up or used: never written down.
        if symbol.localizedCaseInsensitiveContains("decoy") { symbol = "(a Stillroom step not written down)" }
        let base = info.dli_saddr.map { UInt(bitPattern: $0) } ?? UInt(bitPattern: info.dli_fbase)
        return "\(image)  \(symbol) + \(address &- base)"
    }

    private typealias Demangle = @convention(c) (UnsafePointer<CChar>?, Int, UnsafeMutablePointer<CChar>?,
                                                 UnsafeMutablePointer<Int>?, UInt32) -> UnsafeMutablePointer<CChar>?
    private static let swiftDemangle: Demangle? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "swift_demangle")
        .map { unsafeBitCast($0, to: Demangle.self) }

    private static func demangle(_ name: String) -> String {
        guard name.hasPrefix("$s") || name.hasPrefix("_$s"), let swiftDemangle else { return name }
        return name.withCString { raw in
            guard let out = swiftDemangle(raw, strlen(raw), nil, nil, 0) else { return name }
            defer { free(out) }
            return String(cString: out)
        }
    }
}
