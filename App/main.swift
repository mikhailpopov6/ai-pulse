import AppKit
import SwiftUI
import WidgetKit

// Фоновый агент: собирает метрики, кладёт снимок для виджета и показывает его в меню-баре.
final class Store: ObservableObject {
    @Published var snapshot: Snapshot

    private let cpu = CPUSampler()
    private let codexFetcher = CodexFetcher()
    private let claudeFetcher = ClaudeFetcher()
    private var lastClaudeFetch = Date.distantPast
    private var fastHistory: [Double] = []      // каждые 2 с, для поповера
    private var slowHistory: [Double] = []      // средние за 20 с, для виджета
    private var slowBucket: [Double] = []
    private var lastCPU: (usage: Double, user: Double, system: Double) = (0, 0, 0)
    private var lastWidgetReload = Date.distantPast
    private var lastCodexFetch = Date.distantPast
    private var timers: [Timer] = []

    var onTick: (() -> Void)?

    init() {
        let empty = LimitsBlock.unavailable("загрузка…")
        snapshot = Snapshot(updatedAt: Date(),
                            cpu: CPUStats(usage: 0, user: 0, system: 0, cores: ProcessInfo.processInfo.activeProcessorCount, history: []),
                            memory: MemoryReader.read(), claude: empty, codex: empty)
        if let old = SnapshotIO.read() {
            slowHistory = old.cpu.history
            if old.codex.state == .ok { snapshot.codex = old.codex }
            if old.claude.state == .ok { snapshot.claude = old.claude }
        }
        _ = cpu.sample()
    }

    func start() {
        timers.append(Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.tick() })
        timers.append(Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.refreshLimits() })
        timers.forEach { RunLoop.main.add($0, forMode: .common) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.tick(); self.refreshLimits() }
    }

    func refreshLimits(force: Bool = false) {
        refreshCodex(force: force)
        refreshClaude(force: force)
    }

    func refreshClaude(force: Bool = false) {
        // Эндпоинт usage отвечает 429 на частые запросы — не чаще раза в полторы минуты.
        if !force, Date().timeIntervalSince(lastClaudeFetch) < 85 { return }
        if force, Date().timeIntervalSince(lastClaudeFetch) < 20 { return }
        lastClaudeFetch = Date()
        claudeFetcher.fetch { [weak self] block in
            guard let self else { return }
            if block.state == .error, self.snapshot.claude.state == .ok,
               let t = self.snapshot.claude.fetchedAt, Date().timeIntervalSince(t) < 1800 { return }
            self.snapshot.claude = block
            self.persist(forceReload: true)
        }
    }

    // Открывает Терминал с командой входа в claude.ai для отдельного конфига AI Pulse.
    func openClaudeLogin() {
        let script = SharedPaths.supportDir.appendingPathComponent("claude-login.command")
        let body = """
        #!/bin/zsh
        echo "AI Pulse: вход в claude.ai (отдельный конфиг, основной Claude Code не затрагивается)"
        \(ClaudeFetcher.loginCommand)
        echo; echo "Готово. Окно можно закрыть."
        """
        try? FileManager.default.createDirectory(atPath: ClaudeFetcher.configDir, withIntermediateDirectories: true)
        try? body.write(to: script, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        NSWorkspace.shared.open(script)
        // Подхватить вход, как только он появится.
        for delay in [30.0, 60, 120, 240] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.snapshot.claude.state != .ok else { return }
                self.lastClaudeFetch = .distantPast
                self.refreshClaude()
            }
        }
    }

    func refreshCodex(force: Bool = false) {
        if !force, Date().timeIntervalSince(lastCodexFetch) < 55 { return }
        lastCodexFetch = Date()
        codexFetcher.fetch { [weak self] block in
            guard let self else { return }
            // Ошибку разового запроса не показываем, пока есть свежие данные.
            if block.state != .ok, self.snapshot.codex.state == .ok,
               let t = self.snapshot.codex.fetchedAt, Date().timeIntervalSince(t) < 1800 { return }
            self.snapshot.codex = block
            self.persist(forceReload: true)
        }
    }

    private func tick() {
        if let s = cpu.sample() { lastCPU = s }
        fastHistory.append(lastCPU.usage)
        if fastHistory.count > 60 { fastHistory.removeFirst(fastHistory.count - 60) }
        slowBucket.append(lastCPU.usage)
        if slowBucket.count >= 10 {
            slowHistory.append(slowBucket.reduce(0, +) / Double(slowBucket.count))
            slowBucket.removeAll()
            if slowHistory.count > 36 { slowHistory.removeFirst(slowHistory.count - 36) }
        }

        snapshot.updatedAt = Date()
        snapshot.cpu = CPUStats(usage: lastCPU.usage, user: lastCPU.user, system: lastCPU.system,
                                cores: ProcessInfo.processInfo.activeProcessorCount, history: fastHistory)
        snapshot.memory = MemoryReader.read()
        onTick?()
        persist(forceReload: false)
    }

    private var lastPersist = Date.distantPast

    private func persist(forceReload: Bool) {
        let now = Date()
        guard forceReload || now.timeIntervalSince(lastPersist) >= 20 else { return }
        lastPersist = now
        var forWidget = snapshot
        forWidget.cpu.history = slowHistory.isEmpty ? fastHistory : slowHistory + [lastCPU.usage]
        SnapshotIO.write(forWidget)
        if forceReload || now.timeIntervalSince(lastWidgetReload) >= 60 {
            lastWidgetReload = now
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

struct PopoverView: View {
    @ObservedObject var store: Store
    @ObservedObject var desktop: DesktopWidgetController
    var onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FullPanel(snap: store.snapshot, stale: false)
            Divider().overlay(Color.white.opacity(0.08))
            HStack(spacing: 8) {
                Text("На столе").font(.system(size: 11)).foregroundStyle(Theme.dim)
                Picker("", selection: deskSelection) {
                    Text("Выкл").tag("off")
                    ForEach(DesktopStyle.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
            }
            HStack(spacing: 10) {
                Button { store.refreshLimits(force: true) } label: {
                    Label("Обновить", systemImage: "arrow.clockwise")
                }
                if store.snapshot.claude.state != .ok {
                    Button { store.openClaudeLogin() } label: {
                        Label("Войти в Claude", systemImage: "person.crop.circle.badge.checkmark")
                    }
                }
                Spacer()
                Button(action: onQuit) { Text("Выйти") }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .foregroundStyle(Theme.dim)
        }
        .padding(16)
        .frame(width: 340)
        .background(Theme.background)
        .environment(\.colorScheme, .dark)
    }

    // «Выкл» или вид карточки на рабочем столе.
    private var deskSelection: Binding<String> {
        Binding(
            get: { desktop.isShown ? desktop.style.rawValue : "off" },
            set: { v in
                if v == "off" { desktop.hide() } else if let s = DesktopStyle(rawValue: v) { desktop.setStyle(s) }
            })
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = Store()
    private lazy var desktop = DesktopWidgetController(store: store)
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Второй экземпляр (ручной запуск поверх LaunchAgent) сразу выходит.
        let me = ProcessInfo.processInfo.processIdentifier
        if NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .contains(where: { $0.processIdentifier != me }) {
            NSApp.terminate(nil)
            return
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "AI Pulse")
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: PopoverView(store: store, desktop: desktop, onQuit: { NSApp.terminate(nil) }))

        store.onTick = { [weak self] in self?.updateTitle(); self?.desktop.tick() }
        store.start()
        updateTitle()
        desktop.restore()
    }

    private func updateTitle() {
        guard let button = statusItem?.button else { return }
        let s = store.snapshot
        let text = " \(Fmt.pct(s.cpu.usage))  \(Fmt.pct(s.memory.fraction))"
        button.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium),
        ])
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            store.refreshLimits()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
