import Darwin
import Foundation

/// When opening an item with a cool-down was asked for: this Mac's boot session and its uptime then.
struct CoolDownAsk: Codable, Hashable, Sendable {
    /// `kern.bootsessionuuid`: a restart makes a new one, so the wait starts again.
    var boot: String
    /// Seconds since this boot, sleep included (`mach_continuous_time`). Setting the clock doesn't move it.
    var uptime: Double
}

/// Cool-down items: an item marked with a wait opens only that long after opening it was asked for, so "open it right
/// now" can honestly be answered "I can't". The wait runs on the Mac's uptime, which changing the date and time doesn't
/// touch; a restart starts it again. Once over, the item stays open for an hour, then shuts again. Changing or turning
/// off a cool-down waits too. It's a rule the app keeps, not more encryption: with the password, a copy of the folder
/// and the open reader, the item can still be read. The settings live in the sealed list.
enum CoolDown {
    static let choices: [(label: String, seconds: Int?)] = [("Off", nil), ("1 Hour", 3600), ("24 Hours", 86_400), ("3 Days", 259_200)]
    /// Once the wait is over, how long the item stays open.
    static let openFor: Double = 3600

    enum State: Equatable {
        /// No cool-down: opens as usual.
        case none
        /// Shut: opening it has to be asked for.
        case shut
        case waiting(left: Double)
        case open(left: Double)

        var opens: Bool { if case .none = self { true } else if case .open = self { true } else { false } }
    }

    /// Where this Mac is now: its boot session and uptime. Tests set their own.
    struct Now: Sendable {
        var boot: String
        var uptime: Double
    }
    nonisolated(unsafe) static var nowForTests: Now?

    static var now: Now {
        if let nowForTests { return nowForTests }
        return Now(boot: bootSession, uptime: uptime)
    }

    static func state(_ file: VaultFile, now: Now = now) -> State {
        guard let wait = file.coolDown else { return .none }
        guard let ask = file.coolDownAsked, ask.boot == now.boot, now.uptime >= ask.uptime else { return .shut }
        let gone = now.uptime - ask.uptime
        if gone < Double(wait) { return .waiting(left: Double(wait) - gone) }
        if gone < Double(wait) + openFor { return .open(left: Double(wait) + openFor - gone) }
        return .shut
    }

    static func ask(now: Now = now) -> CoolDownAsk { CoolDownAsk(boot: now.boot, uptime: now.uptime) }

    /// "23 h 10 min", "52 min", "under a minute".
    static func duration(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes < 1 { return "under a minute" }
        let (h, m) = (minutes / 60, minutes % 60)
        return h == 0 ? "\(m) min" : m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    static func label(_ seconds: Int?) -> String {
        choices.first { $0.seconds == seconds }?.label.lowercased() ?? seconds.map { duration(Double($0)) } ?? "off"
    }

    private static var bootSession: String {
        var size = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &bytes, &size, nil, 0) == 0 else { return "" }
        return String(cString: bytes)
    }

    private static var uptime: Double {
        var base = mach_timebase_info_data_t()
        mach_timebase_info(&base)
        return Double(mach_continuous_time()) * Double(base.numer) / Double(base.denom) / 1_000_000_000
    }
}
