import Foundation

// Снимок метрик, который пишет хост-приложение и читает виджет.
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
    var history: [Double]      // последние значения 0...1, старые в начале
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
    var id: String { label }
    var label: String          // «5 ч», «Неделя»
    var usedPercent: Double    // 0...100
    var resetsAt: Date?
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

    // Самое «горячее» окно — его показываем крупно.
    var primary: LimitWindow? { windows.max(by: { $0.usedPercent < $1.usedPercent }) }
}

enum SharedPaths {
    // Реальная домашняя папка: в песочнице виджета NSHomeDirectory() указывает в контейнер.
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
                LimitWindow(label: "5 ч", usedPercent: 34, resetsAt: now.addingTimeInterval(2 * 3600)),
                LimitWindow(label: "Неделя", usedPercent: 61, resetsAt: now.addingTimeInterval(3 * 86400)),
            ], fetchedAt: now),
            codex: LimitsBlock(state: .ok, message: nil, plan: "Pro", windows: [
                LimitWindow(label: "Неделя", usedPercent: 48, resetsAt: now.addingTimeInterval(5 * 86400)),
            ], fetchedAt: now)
        )
    }
}

enum Fmt {
    static func gb(_ bytes: UInt64) -> String {
        let v = Double(bytes) / 1_073_741_824
        return v >= 10 ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }

    static func pct(_ fraction: Double) -> String { "\(Int((fraction * 100).rounded()))%" }

    static func windowLabel(minutes: Int) -> String {
        switch minutes {
        case 300: return "5 ч"
        case 1440: return "День"
        case 10080: return "Неделя"
        case 43200...44640: return "Месяц"
        default:
            return minutes % 1440 == 0 ? "\(minutes / 1440) дн" : (minutes % 60 == 0 ? "\(minutes / 60) ч" : "\(minutes) мин")
        }
    }

    // «2 д 4 ч», «3 ч 12 мин», «18 мин»
    static func until(_ date: Date, from now: Date = Date()) -> String {
        let s = max(0, Int(date.timeIntervalSince(now)))
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return h > 0 ? "\(d) д \(h) ч" : "\(d) д" }
        if h > 0 { return m > 0 ? "\(h) ч \(m) мин" : "\(h) ч" }
        return "\(max(m, 1)) мин"
    }

    // Для подписей под кольцами: «5 д 22 ч», «23 ч», «40 мин».
    static func untilShort(_ date: Date, from now: Date = Date()) -> String {
        let s = max(0, Int(date.timeIntervalSince(now)))
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return h > 0 ? "\(d) д \(h) ч" : "\(d) д" }
        if h > 0 { return "\(h) ч" }
        return "\(max(m, 1)) мин"
    }
}
