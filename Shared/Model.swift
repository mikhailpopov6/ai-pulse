import Foundation

// MARK: - Localization

// English by default; Russian when Russian is the user's first preferred language.
// AIPULSE_LANG=en|ru forces a language (used for previews and screenshots).
enum L10n {
    static let isRussian: Bool = {
        if let forced = ProcessInfo.processInfo.environment["AIPULSE_LANG"], !forced.isEmpty {
            return forced.hasPrefix("ru")
        }
        return (Locale.preferredLanguages.first ?? "en").hasPrefix("ru")
    }()
}

func tr(_ en: String, _ ru: String) -> String { L10n.isRussian ? ru : en }

// MARK: - Snapshot

// Metrics snapshot written by the host app and read by the widget.
struct Snapshot: Codable {
    var updatedAt: Date
    var cpu: CPUStats
    var memory: MemoryStats
    var claude: LimitsBlock
    var codex: LimitsBlock
}

struct CPUStats: Codable {
    var usage: Double          // 0...1
    var user: Double
    var system: Double
    var cores: Int
    var history: [Double]      // recent values 0...1, oldest first
}

struct MemoryStats: Codable {
    var used: UInt64
    var total: UInt64
    var app: UInt64
    var wired: UInt64
    var compressed: UInt64
    var swapUsed: UInt64
    var pressure: Int          // 1 normal, 2 warn, 4 critical

    var fraction: Double { total == 0 ? 0 : Double(used) / Double(total) }
}

struct LimitWindow: Codable, Identifiable {
    // Language-neutral key ("5h", "week", "week_opus", "m720"…): the app and the widget
    // render the title in their own language.
    var kind: String
    var usedPercent: Double    // 0...100
    var resetsAt: Date?

    var id: String { kind }
    var title: String { WindowKind.title(kind) }
}

enum WindowKind {
    static func fromMinutes(_ minutes: Int) -> String {
        switch minutes {
        case 300: return "5h"
        case 1440: return "day"
        case 10080: return "week"
        case 43200...44640: return "month"
        default: return "m\(minutes)"
        }
    }

    static func title(_ kind: String) -> String {
        switch kind {
        case "5h": return tr("5h", "5 ч")
        case "day": return tr("Day", "День")
        case "week": return tr("Week", "Неделя")
        case "month": return tr("Month", "Месяц")
        case "week_opus": return tr("Week · Opus", "Неделя · Opus")
        case "week_sonnet": return tr("Week · Sonnet", "Неделя · Sonnet")
        default:
            guard kind.hasPrefix("m"), let m = Int(kind.dropFirst()) else { return kind }
            if m % 1440 == 0 { return tr("\(m / 1440)d", "\(m / 1440) дн") }
            if m % 60 == 0 { return tr("\(m / 60)h", "\(m / 60) ч") }
            return tr("\(m)m", "\(m) мин")
        }
    }
}

struct LimitsBlock: Codable {
    enum State: String, Codable { case ok, unavailable, error }
    var state: State
    var message: String?
    var plan: String?
    var windows: [LimitWindow]
    var fetchedAt: Date?

    static func unavailable(_ message: String) -> LimitsBlock {
        LimitsBlock(state: .unavailable, message: message, plan: nil, windows: [], fetchedAt: nil)
    }

    // The most-used window is the one shown large.
    var primary: LimitWindow? { windows.max(by: { $0.usedPercent < $1.usedPercent }) }
}

// MARK: - Files

enum SharedPaths {
    // The real home folder: inside the widget sandbox NSHomeDirectory() points into the container.
    static var realHome: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    static var supportDir: URL {
        realHome.appendingPathComponent("Library/Application Support/AIPulse", isDirectory: true)
    }

    static var snapshot: URL { supportDir.appendingPathComponent("snapshot.json") }
}

enum SnapshotIO {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    static func read() -> Snapshot? {
        guard let data = try? Data(contentsOf: SharedPaths.snapshot) else { return nil }
        return try? decoder.decode(Snapshot.self, from: data)
    }

    static func write(_ snapshot: Snapshot) {
        try? FileManager.default.createDirectory(at: SharedPaths.supportDir, withIntermediateDirectories: true)
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: SharedPaths.snapshot, options: .atomic)
        }
    }
}

extension Snapshot {
    static var placeholder: Snapshot {
        let now = Date()
        return Snapshot(
            updatedAt: now,
            cpu: CPUStats(usage: 0.23, user: 0.15, system: 0.08, cores: 12,
                          history: [0.12, 0.18, 0.22, 0.35, 0.28, 0.2, 0.25, 0.4, 0.31, 0.23, 0.19, 0.27, 0.33, 0.24, 0.21, 0.23]),
            memory: MemoryStats(used: 22 << 30, total: 36 << 30, app: 14 << 30, wired: 4 << 30,
                                compressed: 4 << 30, swapUsed: 1 << 30, pressure: 1),
            claude: LimitsBlock(state: .ok, message: nil, plan: "Max", windows: [
                LimitWindow(kind: "5h", usedPercent: 34, resetsAt: now.addingTimeInterval(2 * 3600)),
                LimitWindow(kind: "week", usedPercent: 61, resetsAt: now.addingTimeInterval(3 * 86400)),
            ], fetchedAt: now),
            codex: LimitsBlock(state: .ok, message: nil, plan: "Pro", windows: [
                LimitWindow(kind: "week", usedPercent: 48, resetsAt: now.addingTimeInterval(5 * 86400)),
            ], fetchedAt: now)
        )
    }
}

// MARK: - Formatting

enum Fmt {
    static func gb(_ bytes: UInt64) -> String {
        let v = Double(bytes) / 1_073_741_824
        return v >= 10 ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }

    static func pct(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))%" }

    static func cores(_ n: Int) -> String {
        if !L10n.isRussian { return n == 1 ? "1 core" : "\(n) cores" }
        let mod10 = n % 10, mod100 = n % 100
        if mod10 == 1 && mod100 != 11 { return "\(n) ядро" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "\(n) ядра" }
        return "\(n) ядер"
    }

    // "2d 4h", "3h 12m", "18m"
    static func until(_ date: Date, from now: Date = Date()) -> String {
        let s = max(0, Int(date.timeIntervalSince(now)))
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return h > 0 ? tr("\(d)d \(h)h", "\(d) д \(h) ч") : tr("\(d)d", "\(d) д") }
        if h > 0 { return m > 0 ? tr("\(h)h \(m)m", "\(h) ч \(m) мин") : tr("\(h)h", "\(h) ч") }
        return tr("\(max(m, 1))m", "\(max(m, 1)) мин")
    }

    // For captions under the rings: "5d 22h", "23h", "40m".
    static func untilShort(_ date: Date, from now: Date = Date()) -> String {
        let s = max(0, Int(date.timeIntervalSince(now)))
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return h > 0 ? tr("\(d)d \(h)h", "\(d) д \(h) ч") : tr("\(d)d", "\(d) д") }
        if h > 0 { return tr("\(h)h", "\(h) ч") }
        return tr("\(max(m, 1))m", "\(max(m, 1)) мин")
    }
}
