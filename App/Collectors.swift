import Foundation
import Darwin

// MARK: - CPU

final class CPUSampler {
    private var prev: host_cpu_load_info?

    // Доля занятости CPU с момента прошлого вызова: (всего, user+nice, system).
    func sample() -> (usage: Double, user: Double, system: Double)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        defer { prev = info }
        guard let p = prev else { return nil }
        // cpu_ticks: USER, SYSTEM, IDLE, NICE
        let user = Double(info.cpu_ticks.0 &- p.cpu_ticks.0)
        let sys = Double(info.cpu_ticks.1 &- p.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2 &- p.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3 &- p.cpu_ticks.3)
        let total = user + sys + idle + nice
        guard total > 0 else { return nil }
        return ((user + sys + nice) / total, (user + nice) / total, sys / total)
    }
}

// MARK: - Memory

enum MemoryReader {
    // Считаем «Использовано» так же, как Мониторинг системы: приложения + wired + сжатая.
    static func read() -> MemoryStats {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        _ = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let page = UInt64(vm_kernel_page_size)
        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let app = (internalPages > purgeable ? internalPages - purgeable : 0) * page
        let wired = UInt64(stats.wire_count) * page
        let compressed = UInt64(stats.compressor_page_count) * page
        let total = ProcessInfo.processInfo.physicalMemory

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0)

        var pressure: Int32 = 1
        var pSize = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &pSize, nil, 0)

        return MemoryStats(used: min(app + wired + compressed, total), total: total, app: app, wired: wired,
                           compressed: compressed, swapUsed: UInt64(swap.xsu_used), pressure: Int(pressure))
    }
}

// MARK: - Codex

// Лимиты Codex берём у самого Codex: `codex app-server`, метод account/rateLimits/read.
// Авторизацией занимается Codex, токены сюда не попадают.
final class CodexFetcher {
    private let queue = DispatchQueue(label: "aipulse.codex")
    private var running = false

    static func codexPath() -> String? {
        let home = SharedPaths.realHome.path
        let candidates = ["\(home)/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func fetch(_ completion: @escaping (LimitsBlock) -> Void) {
        queue.async {
            guard !self.running else { return }
            self.running = true
            let result = self.runOnce()
            self.running = false
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func runOnce() -> LimitsBlock {
        guard let path = Self.codexPath() else { return .unavailable("codex не найден") }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = ["app-server"]
        var env = ProcessInfo.processInfo.environment
        let home = SharedPaths.realHome.path
        env["HOME"] = home
        env["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        proc.environment = env
        proc.currentDirectoryURL = SharedPaths.supportDir
        let stdin = Pipe(), stdout = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = FileHandle.nullDevice

        let done = DispatchSemaphore(value: 0)
        var buffer = Data()
        var response: [String: Any]?
        let lock = NSLock()

        stdout.fileHandleForReading.readabilityHandler = { h in
            let chunk = h.availableData
            if chunk.isEmpty { done.signal(); return }
            lock.lock(); defer { lock.unlock() }
            buffer.append(chunk)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: buffer.startIndex..<nl)
                buffer.removeSubrange(buffer.startIndex...nl)
                if let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                   (obj["id"] as? Int) == 1 {
                    response = obj
                    done.signal()
                }
            }
        }

        do {
            try FileManager.default.createDirectory(at: SharedPaths.supportDir, withIntermediateDirectories: true)
            try proc.run()
        } catch {
            return LimitsBlock(state: .error, message: "не удалось запустить codex", plan: nil, windows: [], fetchedAt: Date())
        }

        let requests = [
            #"{"method":"initialize","id":0,"params":{"clientInfo":{"name":"ai_pulse","title":"AI Pulse","version":"1.0"}}}"#,
            #"{"method":"initialized"}"#,
            #"{"method":"account/rateLimits/read","id":1}"#,
        ]
        for r in requests { stdin.fileHandleForWriting.write((r + "\n").data(using: .utf8)!) }

        let waited = done.wait(timeout: .now() + 25)
        stdout.fileHandleForReading.readabilityHandler = nil
        try? stdin.fileHandleForWriting.close()
        if proc.isRunning { proc.terminate() }

        lock.lock(); let resp = response; lock.unlock()
        guard waited == .success, let resp else {
            return LimitsBlock(state: .error, message: "codex не ответил", plan: nil, windows: [], fetchedAt: Date())
        }
        if let err = resp["error"] as? [String: Any] {
            let msg = (err["message"] as? String).map { String($0.prefix(80)) } ?? "ошибка codex"
            return LimitsBlock(state: .error, message: msg, plan: nil, windows: [], fetchedAt: Date())
        }
        guard let result = resp["result"] as? [String: Any],
              let limits = result["rateLimits"] as? [String: Any] else {
            return LimitsBlock(state: .error, message: "пустой ответ codex", plan: nil, windows: [], fetchedAt: Date())
        }
        return Self.parse(limits)
    }

    static func parse(_ limits: [String: Any]) -> LimitsBlock {
        var windows: [(Int, LimitWindow)] = []
        for key in ["primary", "secondary"] {
            guard let w = limits[key] as? [String: Any],
                  let used = (w["usedPercent"] as? NSNumber)?.doubleValue else { continue }
            let mins = (w["windowDurationMins"] as? NSNumber)?.intValue ?? 0
            let resets = (w["resetsAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            windows.append((mins, LimitWindow(label: Fmt.windowLabel(minutes: mins), usedPercent: used, resetsAt: resets)))
        }
        windows.sort { $0.0 < $1.0 }
        let plan = (limits["planType"] as? String).map { $0.prefix(1).uppercased() + $0.dropFirst() }
        if windows.isEmpty {
            return LimitsBlock(state: .unavailable, message: "codex не вернул лимиты", plan: plan, windows: [], fetchedAt: Date())
        }
        return LimitsBlock(state: .ok, message: nil, plan: plan, windows: windows.map { $0.1 }, fetchedAt: Date())
    }
}

