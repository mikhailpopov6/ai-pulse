import AppKit
import SwiftUI

// Карточка на рабочем столе: окно без рамки на уровне иконок рабочего стола.
// Лежит под обычными окнами, видна на всех Spaces, перетаскивается мышью
// и обновляется вместе с агентом каждые 2 с. Замена системному виджету,
// пока WidgetKit не принимает ad-hoc подпись.
enum DesktopStyle: String, CaseIterable, Identifiable {
    case rings, small, large
    var id: String { rawValue }

    var title: String {
        switch self {
        case .rings: return "Кольца"
        case .small: return "Маленький"
        case .large: return "Большой"
        }
    }

    // Панель — та же, что в меню-баре; маленькая — её уменьшенная копия.
    var panelScale: CGFloat { self == .small ? 0.8 : 1 }
}

final class DesktopWidgetController: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var isShown = false
    @Published private(set) var style: DesktopStyle

    private let store: Store
    private var panel: NSPanel?
    private var host: DraggableHostingView<DesktopCard>?
    private let defaults = UserDefaults.standard

    // Место карточки: монитор (постоянный UUID дисплея) и отступ её верхнего левого угла
    // от верхнего левого угла этого монитора — своё для каждого набора экранов.
    // Меняется ТОЛЬКО когда пользователь сам перетащил карточку (см. DraggableHostingView).
    // Сдвиги от системы при смене экранов не сохраняются, а карточка возвращается на место.
    private struct Placement: Codable {
        var screen: String
        var dx: Double
        var dy: Double
    }

    init(store: Store) {
        self.store = store
        style = DesktopStyle(rawValue: UserDefaults.standard.string(forKey: "desktop.style") ?? "") ?? .large
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(screensChanged),
                                                          name: NSWorkspace.didWakeNotification, object: nil)
        migrateLegacyPosition()
    }

    func restore() {
        // По умолчанию карточка включена.
        if defaults.object(forKey: "desktop.visible") as? Bool ?? true { show() }
    }

    func toggle() { isShown ? hide() : show() }

    func show() {
        if panel == nil { panel = makePanel() }
        panel?.orderFront(nil)
        isShown = true
        defaults.set(true, forKey: "desktop.visible")
        DispatchQueue.main.async { self.tick() }
    }

    func hide() {
        panel?.orderOut(nil)
        isShown = false
        defaults.set(false, forKey: "desktop.visible")
    }

    func setStyle(_ value: DesktopStyle) {
        style = value
        defaults.set(value.rawValue, forKey: "desktop.style")
        if !isShown { show() }
        DispatchQueue.main.async { self.tick() }
    }

    // Каждые 2 с: подогнать размер под содержимое и вернуть карточку на её место,
    // если система её сдвинула. Пока идёт перетаскивание — не мешаем.
    func tick() {
        guard let p = panel, let host, p.isVisible, !host.isDragging else { return }
        var size = host.fittingSize
        if size.width <= 0 || size.height <= 0 { size = p.frame.size }
        let (target, screen) = expectedFrame(size: size)
        if !Self.same(target, p.frame) {
            if p.frame.size == target.size {
                DesktopLog.write("вернула на место: \(Self.fmt(p.frame)) → \(Self.fmt(target)) [\(screen.localizedName)]")
            }
            setFrame(target)
        }
    }

    private func makePanel() -> NSPanel {
        let host = DraggableHostingView(rootView: DesktopCard(store: store, controller: self))
        host.onDragEnded = { [weak self] in self?.userMovedCard() }
        let size = host.fittingSize
        let p = NSPanel(contentRect: CGRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = false   // тащим сами, чтобы точно знать, что это пользователь
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.contentView = host
        self.host = host
        panel = p
        let (target, screen) = expectedFrame(size: size)
        setFrame(target)
        DesktopLog.write("запуск: \(Self.fmt(target)) [\(screen.localizedName)] экраны: \(Self.screensDescription())")
        p.delegate = self
        return p
    }

    // MARK: - Позиция

    // Место запоминается отдельно для каждого набора подключённых экранов:
    // «ноутбук + монитор» — одно, «только ноутбук» — другое. При смене набора
    // карточка переезжает на место, запомненное для нового набора.
    private static var configKey: String {
        NSScreen.screens.map { id(of: $0) }.sorted().joined(separator: "+")
    }

    private static var configName: String {
        NSScreen.screens.map { $0.localizedName }.joined(separator: " + ")
    }

    private func loadPlacements() -> [String: Placement] {
        guard let data = defaults.data(forKey: "desktop.placements") else { return [:] }
        return (try? JSONDecoder().decode([String: Placement].self, from: data)) ?? [:]
    }

    private func savePlacements(_ all: [String: Placement]) {
        if let data = try? JSONEncoder().encode(all) { defaults.set(data, forKey: "desktop.placements") }
    }

    // Где карточка должна стоять при текущем наборе экранов. Для нового набора,
    // где её ещё не ставили, берём место из другого набора, если его экран подключён,
    // иначе — правый верхний угол главного экрана.
    private func expectedFrame(size: CGSize) -> (CGRect, NSScreen) {
        let all = loadPlacements()
        let connected = Set(NSScreen.screens.map { Self.id(of: $0) })
        let pl = all[Self.configKey] ?? all.values.first { connected.contains($0.screen) }
        if let pl, let screen = NSScreen.screens.first(where: { Self.id(of: $0) == pl.screen }) {
            let frame = CGRect(x: screen.frame.minX + pl.dx, y: screen.frame.maxY - pl.dy - size.height,
                               width: size.width, height: size.height)
            return (clamp(frame.integral, to: screen), screen)
        }
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        let frame = CGRect(x: vf.maxX - size.width - 24, y: vf.maxY - 24 - size.height, width: size.width, height: size.height)
        return (clamp(frame.integral, to: screen), screen)
    }

    private func setFrame(_ frame: CGRect) {
        guard let p = panel else { return }
        p.setFrame(frame, display: true, animate: false)
    }

    private func userMovedCard() {
        guard let p = panel else { return }
        let screen = screenContaining(p.frame)
        // Не даём утащить карточку за край экрана.
        let clamped = clamp(p.frame, to: screen)
        if !Self.same(clamped, p.frame) { setFrame(clamped) }
        let pl = Placement(screen: Self.id(of: screen),
                           dx: Double(p.frame.minX - screen.frame.minX),
                           dy: Double(screen.frame.maxY - p.frame.maxY))
        var all = loadPlacements()
        all[Self.configKey] = pl
        savePlacements(all)
        DesktopLog.write("перетащили [\(Self.configName)]: \(screen.localizedName) отступ \(Int(pl.dx)),\(Int(pl.dy))")
    }

    // Прежние версии хранили одно место на все случаи — отдаём его текущему набору экранов.
    private func migrateLegacyPosition() {
        guard defaults.data(forKey: "desktop.placements") == nil else { return }
        var pl: Placement?
        if let data = defaults.data(forKey: "desktop.placement") {
            pl = try? JSONDecoder().decode(Placement.self, from: data)
        } else {
            var pt: CGPoint?
            if let arr = defaults.array(forKey: "desktop.topLeft") as? [Double], arr.count == 2 {
                pt = CGPoint(x: arr[0], y: arr[1])
            } else if let old = defaults.array(forKey: "desktop.origin") as? [Double], old.count == 2 {
                pt = CGPoint(x: old[0], y: old[1] + 170)
            }
            if let pt, let screen = NSScreen.screens.first(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(pt) }) {
                pl = Placement(screen: Self.id(of: screen), dx: Double(pt.x - screen.frame.minX), dy: Double(screen.frame.maxY - pt.y))
            }
        }
        if let pl { savePlacements([Self.configKey: pl]) }
        for key in ["desktop.placement", "desktop.topLeft", "desktop.origin"] { defaults.removeObject(forKey: key) }
    }

    static func id(of screen: NSScreen) -> String {
        if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
           let uuid = CGDisplayCreateUUIDFromDisplayID(num.uint32Value)?.takeRetainedValue(),
           let str = CFUUIDCreateString(nil, uuid) {
            return str as String
        }
        return screen.localizedName
    }

    private func screenContaining(_ frame: CGRect) -> NSScreen {
        func area(_ s: NSScreen) -> CGFloat { let r = s.frame.intersection(frame); return r.isNull ? 0 : r.width * r.height }
        if let best = NSScreen.screens.max(by: { area($0) < area($1) }), area(best) > 0 { return best }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    private func clamp(_ frame: CGRect, to screen: NSScreen) -> CGRect {
        let vf = screen.visibleFrame
        var f = frame
        f.origin.x = min(max(f.minX, vf.minX), vf.maxX - f.width)
        f.origin.y = min(max(f.minY, vf.minY), vf.maxY - f.height)
        return f
    }

    private static func same(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 1 && abs(a.minY - b.minY) <= 1 && abs(a.width - b.width) <= 1 && abs(a.height - b.height) <= 1
    }

    private static func fmt(_ r: CGRect) -> String { "(\(Int(r.minX)),\(Int(r.maxY)) \(Int(r.width))×\(Int(r.height)))" }

    private static func screensDescription() -> String {
        NSScreen.screens.map { "\($0.localizedName) \(Self.fmt($0.frame))" }.joined(separator: "; ")
    }

    @objc private func screensChanged() {
        DesktopLog.write("экраны изменились [\(Self.configName)]: \(Self.screensDescription())")
        // Сразу и с задержками: macOS переставляет окна не мгновенно. Дальше страхует tick.
        for delay in [0.0, 0.5, 1.5, 3.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.tick() }
        }
    }
}

// Краткий журнал перемещений карточки — для разбора, если она снова «уедет».
enum DesktopLog {
    static func write(_ line: String) {
        let url = SharedPaths.supportDir.appendingPathComponent("desktop.log")
        let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate, .withFullTime, .withSpaceBetweenDateAndTime])
        let data = Data("\(stamp) \(line)\n".utf8)
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(data)
            try? h.close()
            // Держим файл небольшим.
            if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int, size > 200_000,
               let all = try? String(contentsOf: url, encoding: .utf8) {
                try? String(all.suffix(100_000)).write(to: url, atomically: true, encoding: .utf8)
            }
        } else {
            try? data.write(to: url)
        }
    }
}

// Перетаскивание делаем сами: так точно известно, что карточку двигает пользователь,
// и место сохраняется в момент, когда кнопку мыши отпустили.
final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    var onDragEnded: (() -> Void)?
    private(set) var isDragging = false
    private var startMouse: NSPoint?
    private var startOrigin: NSPoint?

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        startMouse = NSEvent.mouseLocation
        startOrigin = window?.frame.origin
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let m0 = startMouse, let o0 = startOrigin, let w = window else { return }
        let m = NSEvent.mouseLocation
        if !isDragging, hypot(m.x - m0.x, m.y - m0.y) < 2 { return }
        isDragging = true
        w.setFrameOrigin(NSPoint(x: (o0.x + m.x - m0.x).rounded(), y: (o0.y + m.y - m0.y).rounded()))
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging { onDragEnded?() }
        isDragging = false
        startMouse = nil
    }
}

// Уменьшает содержимое целиком, и в раскладке оно занимает уменьшенный размер.
struct ScaledLayout: Layout {
    var scale: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let s = child.sizeThatFits(.unspecified)
        return CGSize(width: s.width * scale, height: s.height * scale)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        child.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(child.sizeThatFits(.unspecified)))
    }
}

struct DesktopCard: View {
    @ObservedObject var store: Store
    @ObservedObject var controller: DesktopWidgetController

    var body: some View {
        let style = controller.style
        Group {
            if style == .rings {
                card(MediumRow(snap: store.snapshot, stale: false), width: 364, height: 170)
            } else {
                ScaledLayout(scale: style.panelScale) {
                    card(FullPanel(snap: store.snapshot, stale: false), width: 340, height: nil)
                        .scaleEffect(style.panelScale, anchor: .topLeading)
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .contextMenu {
            ForEach(DesktopStyle.allCases) { s in
                Button { controller.setStyle(s) } label: {
                    if s == style { Label(s.title, systemImage: "checkmark") } else { Text(s.title) }
                }
            }
            Divider()
            Button("Обновить лимиты") { store.refreshLimits(force: true) }
            Button("Убрать с рабочего стола") { controller.hide() }
        }
    }

    private func card<V: View>(_ content: V, width: CGFloat, height: CGFloat?) -> some View {
        content
            .padding(16)
            .frame(width: width, height: height)
            .fixedSize(horizontal: false, vertical: height == nil)
            .background(Theme.background.opacity(0.94))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }
}
