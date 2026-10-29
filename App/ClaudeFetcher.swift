import Foundation
import CryptoKit

// Лимиты подписки claude.ai (5 часов / неделя) через тот же эндпоинт, что и /usage в Claude Code.
// Вход хранится в отдельном конфиге Claude Code (CLAUDE_CONFIG_DIR), чтобы не трогать основной:
// он может работать через API-ключ или корпоративный прокси. Токен живёт только в Keychain и в памяти процесса: не логируется
// и не пишется в файлы.
final class ClaudeFetcher {
    static let configDir = SharedPaths.supportDir.appendingPathComponent("claude-login").path
    private static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    // Имя записи Keychain, как его строит Claude Code для нестандартного CLAUDE_CONFIG_DIR.
    static var keychainService: String {
        let digest = SHA256.hash(data: Data(configDir.precomposedStringWithCanonicalMapping.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "Claude Code-credentials-\(hex.prefix(8))"
    }

    // Команда входа: отдельный конфиг и без переменных API-ключа/прокси, иначе логин уйдёт не туда.
    static var loginCommand: String {
        let claude = ["\(SharedPaths.realHome.path)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) } ?? "claude"
        return "env -u ANTHROPIC_BASE_URL -u ANTHROPIC_AUTH_TOKEN -u ANTHROPIC_API_KEY " +
            "CLAUDE_CONFIG_DIR='\(configDir)' '\(claude)' auth login --claudeai"
    }

    private let queue = DispatchQueue(label: "aipulse.claude")
    private var running = false
    // Свежий токен после обновления — на случай, если запись в Keychain не удалась.
    private var memoryOAuth: [String: Any]?

    // После 429 молчим 5 минут: виджет держит последние данные.
    private var backoffUntil = Date.distantPast

    func fetch(_ completion: @escaping (LimitsBlock) -> Void) {
        queue.async {
            guard Date() >= self.backoffUntil else { return }
            guard !self.running else { return }
            self.running = true
            let result = self.runOnce()
            self.running = false
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func runOnce() -> LimitsBlock {
        guard var item = Keychain.read(service: Self.keychainService),
              var oauth = item.json["claudeAiOauth"] as? [String: Any],
              var access = oauth["accessToken"] as? String, !access.isEmpty else {
            return .unavailable("войди в claude.ai: меню AI Pulse → «Войти в Claude»")
        }
        func exp(_ o: [String: Any]) -> Double { (o["expiresAt"] as? NSNumber)?.doubleValue ?? 0 }
        if let mem = memoryOAuth, exp(mem) > exp(oauth), let a = mem["accessToken"] as? String {
            oauth = mem
            access = a
        }
        let plan = (oauth["subscriptionType"] as? String).map { $0.prefix(1).uppercased() + $0.dropFirst() }

        var token = access
        let expiresAt = (oauth["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        if let e = expiresAt, e.timeIntervalSinceNow < 300 {
            switch refresh(&oauth) {
            case .success(let t):
                token = t
                memoryOAuth = oauth
                item.json["claudeAiOauth"] = oauth
                Keychain.write(service: Self.keychainService, account: item.account, json: item.json)
            case .failure(let msg):
                return LimitsBlock(state: .error, message: msg, plan: plan, windows: [], fetchedAt: Date())
            }
        }

        var req = URLRequest(url: Self.usageURL, timeoutInterval: 15)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("AIPulse/1.0", forHTTPHeaderField: "User-Agent")
        let (data, status) = Self.send(req)
        switch status {
        case 200: break
        case 401: return LimitsBlock(state: .error, message: "вход истёк — войди в Claude заново", plan: plan, windows: [], fetchedAt: Date())
        case 429:
            backoffUntil = Date().addingTimeInterval(300)
            return LimitsBlock(state: .error, message: "claude.ai просит подождать (429)", plan: plan, windows: [], fetchedAt: Date())
        case 0: return LimitsBlock(state: .error, message: "нет связи с api.anthropic.com", plan: plan, windows: [], fetchedAt: Date())
        default: return LimitsBlock(state: .error, message: "ошибка claude.ai: HTTP \(status)", plan: plan, windows: [], fetchedAt: Date())
        }
        guard let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return LimitsBlock(state: .error, message: "непонятный ответ claude.ai", plan: plan, windows: [], fetchedAt: Date())
        }
        return Self.parse(obj, plan: plan)
    }

    static func parse(_ obj: [String: Any], plan: String?) -> LimitsBlock {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        func date(_ v: Any?) -> Date? {
            guard let s = v as? String else { return nil }
            return iso.date(from: s) ?? isoPlain.date(from: s)
        }
        let names: [(String, String)] = [("five_hour", "5 ч"), ("seven_day", "Неделя"),
                                         ("seven_day_opus", "Неделя · Opus"), ("seven_day_sonnet", "Неделя · Sonnet")]
        var windows: [LimitWindow] = []
        for (key, label) in names {
            guard let w = obj[key] as? [String: Any],
                  let used = (w["utilization"] as? NSNumber)?.doubleValue else { continue }
            // Помодельные окна показываем, только если ими реально пользуются.
            if key.hasPrefix("seven_day_"), used <= 0 { continue }
            windows.append(LimitWindow(label: label, usedPercent: used, resetsAt: date(w["resets_at"])))
        }
        if windows.isEmpty {
            return LimitsBlock(state: .unavailable, message: "claude.ai не вернул лимиты", plan: plan, windows: [], fetchedAt: Date())
        }
        return LimitsBlock(state: .ok, message: nil, plan: plan, windows: windows, fetchedAt: Date())
    }

    private enum RefreshResult { case success(String), failure(String) }

    private func refresh(_ oauth: inout [String: Any]) -> RefreshResult {
        guard let rt = oauth["refreshToken"] as? String, !rt.isEmpty else {
            return .failure("вход истёк — войди в Claude заново")
        }
        var body: [String: Any] = ["grant_type": "refresh_token", "refresh_token": rt, "client_id": Self.clientID]
        if let scopes = oauth["scopes"] as? [String], !scopes.isEmpty { body["scope"] = scopes.joined(separator: " ") }
        var req = URLRequest(url: Self.tokenURL, timeoutInterval: 30)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let (data, status) = Self.send(req)
        guard status == 200, let data,
              let resp = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = resp["access_token"] as? String else {
            return .failure(status == 400 || status == 401 ? "вход истёк — войди в Claude заново" : "не удалось обновить вход (HTTP \(status))")
        }
        oauth["accessToken"] = access
        if let newRT = resp["refresh_token"] as? String { oauth["refreshToken"] = newRT }
        if let exp = (resp["expires_in"] as? NSNumber)?.doubleValue {
            oauth["expiresAt"] = Int64((Date().timeIntervalSince1970 + exp) * 1000)
        }
        if let scope = resp["scope"] as? String { oauth["scopes"] = scope.split(separator: " ").map(String.init) }
        return .success(access)
    }

    private static func send(_ req: URLRequest) -> (Data?, Int) {
        let sem = DispatchSemaphore(value: 0)
        var out: (Data?, Int) = (nil, 0)
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            out = (data, (resp as? HTTPURLResponse)?.statusCode ?? 0)
            sem.signal()
        }.resume()
        sem.wait()
        return out
    }
}

// Работа с Keychain через /usr/bin/security — так же, как это делает сам Claude Code,
// поэтому macOS не спрашивает доступ к записи. Значения не попадают ни в argv, ни в логи.
enum Keychain {
    struct Item {
        var account: String
        var json: [String: Any]
    }

    static func read(service: String) -> Item? {
        guard let attrs = run(["find-generic-password", "-s", service], input: nil), attrs.status == 0 else { return nil }
        let account = attrs.stdout.components(separatedBy: "\n")
            .first { $0.contains("\"acct\"<blob>=") }
            .flatMap { line -> String? in
                guard let start = line.range(of: "=\"")?.upperBound, line.hasSuffix("\"") else { return nil }
                return String(line[start..<line.index(before: line.endIndex)])
            } ?? NSUserName()
        guard let secret = run(["find-generic-password", "-s", service, "-w"], input: nil), secret.status == 0,
              let data = secret.stdout.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return Item(account: account, json: json)
    }

    @discardableResult
    static func write(service: String, account: String, json: [String: Any]) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return false }
        let hex = data.map { String(format: "%02x", $0) }.joined()
        let cmd = "add-generic-password -U -a \"\(account)\" -s \"\(service)\" -X \"\(hex)\"\n"
        return run(["-i"], input: cmd)?.status == 0
    }

    private static func run(_ args: [String], input: String?) -> (status: Int32, stdout: String)? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        let inPipe = Pipe()
        p.standardInput = inPipe
        do { try p.run() } catch { return nil }
        if let input { inPipe.fileHandleForWriting.write(input.data(using: .utf8)!) }
        try? inPipe.fileHandleForWriting.close()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
