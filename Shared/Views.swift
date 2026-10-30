import SwiftUI

enum Theme {
    static let cpu = Color(red: 0.30, green: 0.80, blue: 0.98)
    static let ram = Color(red: 0.66, green: 0.52, blue: 1.00)
    static let claude = Color(red: 0.86, green: 0.50, blue: 0.36)
    static let codex = Color(red: 0.24, green: 0.84, blue: 0.62)
    static let hot = Color(red: 1.00, green: 0.38, blue: 0.36)
    static let warm = Color(red: 1.00, green: 0.72, blue: 0.28)
    static let track = Color.white.opacity(0.10)
    static let dim = Color.white.opacity(0.55)

    static let background = LinearGradient(
        colors: [Color(red: 0.09, green: 0.10, blue: 0.14), Color(red: 0.13, green: 0.14, blue: 0.20)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    // A metric turns yellow/red as it approaches the limit.
    static func tint(_ base: Color, fraction: Double) -> Color {
        if fraction >= 0.9 { return hot }
        if fraction >= 0.75 { return warm }
        return base
    }
}

struct Ring: View {
    var fraction: Double?
    var color: Color
    var lineWidth: CGFloat = 7
    var tint: Color? = nil

    var body: some View {
        let f = min(max(fraction ?? 0, 0), 1)
        let c = tint ?? Theme.tint(color, fraction: f)
        ZStack {
            Circle().stroke(Theme.track, lineWidth: lineWidth)
            if fraction != nil {
                Circle()
                    .trim(from: 0, to: max(f, 0.005))
                    .stroke(
                        AngularGradient(colors: [c.opacity(0.55), c], center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(360 * max(f, 0.01))),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
    }
}

struct RingGauge: View {
    var title: String
    var fraction: Double?
    var color: Color
    var caption: String? = nil
    var size: CGFloat = 54
    var lineWidth: CGFloat = 7
    var tint: Color? = nil
    var inner: String? = nil

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Ring(fraction: fraction, color: color, lineWidth: lineWidth, tint: tint)
                VStack(spacing: 0) {
                    Text(fraction.map { Fmt.pct($0) } ?? "—")
                        .font(.system(size: size * 0.26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.6)
                    if let inner, fraction != nil {
                        Text(inner)
                            .font(.system(size: max(7, size * 0.12), weight: .medium))
                            .foregroundStyle(Theme.dim)
                            .lineLimit(1)
                    }
                }
            }
            .frame(width: size, height: size)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
            if let caption {
                Text(caption)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}

struct Sparkline: View {
    var values: [Double]
    var color: Color

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                if pts.count > 1 {
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: geo.size.height))
                        pts.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: pts.last!.x, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.35), color.opacity(0.0)],
                                         startPoint: .top, endPoint: .bottom))
                    Path { p in
                        p.move(to: pts[0])
                        pts.dropFirst().forEach { p.addLine(to: $0) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let step = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { i, v in
            CGPoint(x: CGFloat(i) * step, y: size.height * (1 - CGFloat(min(max(v, 0), 1))) )
        }
    }
}

struct Bar: View {
    var fraction: Double
    var color: Color
    var height: CGFloat = 6
    var tint: Color? = nil

    var body: some View {
        GeometryReader { geo in
            let f = min(max(fraction, 0), 1)
            let c = tint ?? Theme.tint(color, fraction: f)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule()
                    .fill(LinearGradient(colors: [c.opacity(0.7), c], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, geo.size.width * f))
            }
        }
        .frame(height: height)
    }
}

// Limits of one service: a row per window.
struct LimitsCard: View {
    var name: String
    var icon: String
    var color: Color
    var block: LimitsBlock
    var now: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(color)
                Text(name).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                if let plan = block.plan {
                    Text(plan.uppercased())
                        .font(.system(size: 8.5, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(Capsule().fill(color.opacity(0.18)))
                        .foregroundStyle(color)
                }
                Spacer(minLength: 0)
            }
            if block.state == .ok, !block.windows.isEmpty {
                ForEach(block.windows) { w in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(w.title).font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.dim)
                            Spacer(minLength: 4)
                            if let r = w.resetsAt {
                                Text(tr("resets in \(Fmt.until(r, from: now))", "сброс через \(Fmt.until(r, from: now))"))
                                    .font(.system(size: 9.5)).foregroundStyle(Theme.dim)
                            }
                            Text(tr("\(Int((w.leftFraction * 100).rounded()))% left", "\(Int((w.leftFraction * 100).rounded()))% осталось"))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                        }
                        Bar(fraction: w.leftFraction, color: color, tint: Theme.limitTint(color, used: w.usedPercent))
                    }
                }
            } else {
                Text(block.message ?? tr("no data", "нет данных"))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(2)
            }
        }
    }
}

struct SystemCard: View {
    var snap: Snapshot

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Ring(fraction: snap.cpu.usage, color: Theme.cpu, lineWidth: 5).frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("CPU").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.cpu)
                        Text(Fmt.pct(snap.cpu.usage))
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .monospacedDigit().foregroundStyle(.white)
                    }
                }
                Sparkline(values: snap.cpu.history, color: Theme.cpu).frame(height: 26)
                Text("\(Fmt.cores(snap.cpu.cores)) · sys \(Fmt.pct(snap.cpu.system))")
                    .font(.system(size: 9.5)).foregroundStyle(Theme.dim)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Ring(fraction: snap.memory.fraction, color: Theme.ram, lineWidth: 5, tint: snap.memory.tint).frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("RAM").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.ram)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(Fmt.gb(snap.memory.used))
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .monospacedDigit().foregroundStyle(.white)
                            Text(tr("/ \(Fmt.gb(snap.memory.total)) GB", "/ \(Fmt.gb(snap.memory.total)) ГБ"))
                                .font(.system(size: 10)).foregroundStyle(Theme.dim)
                        }
                    }
                }
                MemoryBreakdown(mem: snap.memory).frame(height: 26)
                Text(memoryFooter)
                    .font(.system(size: 9.5)).foregroundStyle(pressureColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var memoryFooter: String {
        let level = snap.memory.pressure >= 4 ? tr("high", "высокое") : (snap.memory.pressure >= 2 ? tr("elevated", "среднее") : tr("normal", "норма"))
        let p = tr("pressure: \(level)", "давление: \(level)")
        return snap.memory.swapUsed > 0 ? "\(p) · swap \(Fmt.gb(snap.memory.swapUsed)) \(tr("GB", "ГБ"))" : p
    }

    private var pressureColor: Color {
        snap.memory.pressure >= 4 ? Theme.hot : (snap.memory.pressure >= 2 ? Theme.warm : Theme.dim)
    }
}

// Segmented bar: app / wired / compressed.
struct MemoryBreakdown: View {
    var mem: MemoryStats

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                let total = Double(max(mem.total, 1))
                HStack(spacing: 1.5) {
                    seg(Theme.ram, Double(mem.app) / total, geo.size.width)
                    seg(Theme.ram.opacity(0.65), Double(mem.wired) / total, geo.size.width)
                    seg(Theme.ram.opacity(0.4), Double(mem.compressed) / total, geo.size.width)
                    Spacer(minLength: 0)
                }
                .frame(height: 6)
                .background(Capsule().fill(Theme.track))
                .clipShape(Capsule())
            }
            .frame(height: 6)
            HStack(spacing: 6) {
                legend(Theme.ram, tr("app \(Fmt.gb(mem.app))", "прил. \(Fmt.gb(mem.app))"))
                legend(Theme.ram.opacity(0.65), "wired \(Fmt.gb(mem.wired))")
                legend(Theme.ram.opacity(0.4), tr("compr. \(Fmt.gb(mem.compressed))", "сжат. \(Fmt.gb(mem.compressed))"))
            }
        }
    }

    private func seg(_ c: Color, _ f: Double, _ w: CGFloat) -> some View {
        Rectangle().fill(c).frame(width: max(0, w * CGFloat(min(max(f, 0), 1))))
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(c).frame(width: 5, height: 5)
            Text(t).font(.system(size: 8.5)).foregroundStyle(Theme.dim).lineLimit(1).fixedSize()
        }
    }
}

// The full layout: Large widget, menu bar popover and the large desktop card.
struct FullPanel: View {
    var snap: Snapshot
    var stale: Bool
    var now: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            if stale {
                Label(tr("no data from AI Pulse", "нет связи с AI Pulse"), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 9.5, weight: .medium)).foregroundStyle(Theme.warm)
            }
            SystemCard(snap: snap)
            Divider().overlay(Color.white.opacity(0.08))
            LimitsCard(name: "Claude", icon: "sparkle", color: Theme.claude, block: snap.claude, now: now)
            LimitsCard(name: "Codex", icon: "chevron.left.forwardslash.chevron.right", color: Theme.codex, block: snap.codex, now: now)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

extension MemoryStats {
    // macOS keeps memory nearly full by design, so the warning follows memory pressure.
    var tint: Color { pressure >= 4 ? Theme.hot : (pressure >= 2 ? Theme.warm : Theme.ram) }
}

extension LimitWindow {
    // Like Codex: show how much of the limit is left.
    var leftFraction: Double { min(max(1 - usedPercent / 100, 0), 1) }
}

extension Theme {
    // Warning by usage: yellow from 75% used, red from 90%.
    static func limitTint(_ base: Color, used: Double) -> Color {
        used >= 90 ? hot : (used >= 75 ? warm : base)
    }
}

extension LimitsBlock {
    var gaugeFraction: Double? { state == .ok ? primary?.leftFraction : nil }

    func gaugeTint(_ base: Color) -> Color {
        Theme.limitTint(base, used: primary?.usedPercent ?? 0)
    }

    func caption(now: Date) -> String {
        guard state == .ok, let p = primary else { return tr("no data", "нет данных") }
        if let r = p.resetsAt { return "\(p.title) · \(Fmt.untilShort(r, from: now))" }
        return p.title
    }
}

// Small widget: four rings in a 2×2 grid.
struct SmallGrid: View {
    var snap: Snapshot
    var stale: Bool
    var now: Date = Date()

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                RingGauge(title: "CPU", fraction: snap.cpu.usage, color: Theme.cpu, size: 50, lineWidth: 6)
                RingGauge(title: "RAM", fraction: snap.memory.fraction, color: Theme.ram, size: 50, lineWidth: 6, tint: snap.memory.tint)
            }
            HStack(spacing: 12) {
                RingGauge(title: "Claude", fraction: snap.claude.gaugeFraction, color: Theme.claude, size: 50, lineWidth: 6, tint: snap.claude.gaugeTint(Theme.claude), inner: tr("left", "ост."))
                RingGauge(title: "Codex", fraction: snap.codex.gaugeFraction, color: Theme.codex, size: 50, lineWidth: 6, tint: snap.codex.gaugeTint(Theme.codex), inner: tr("left", "ост."))
            }
        }
        .opacity(stale ? 0.55 : 1)
    }
}

// Medium widget and the "Rings" desktop card: four rings in a row.
struct MediumRow: View {
    var snap: Snapshot
    var stale: Bool
    var now: Date = Date()

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RingGauge(title: "CPU", fraction: snap.cpu.usage, color: Theme.cpu,
                      caption: Fmt.cores(snap.cpu.cores), size: 64)
                .frame(maxWidth: .infinity)
            RingGauge(title: "RAM", fraction: snap.memory.fraction, color: Theme.ram,
                      caption: "\(Fmt.gb(snap.memory.used))/\(Fmt.gb(snap.memory.total)) \(tr("GB", "ГБ"))", size: 64, tint: snap.memory.tint)
                .frame(maxWidth: .infinity)
            RingGauge(title: "Claude", fraction: snap.claude.gaugeFraction, color: Theme.claude,
                      caption: snap.claude.caption(now: now), size: 64,
                      tint: snap.claude.gaugeTint(Theme.claude), inner: tr("left", "осталось"))
                .frame(maxWidth: .infinity)
            RingGauge(title: "Codex", fraction: snap.codex.gaugeFraction, color: Theme.codex,
                      caption: snap.codex.caption(now: now), size: 64,
                      tint: snap.codex.gaugeTint(Theme.codex), inner: tr("left", "осталось"))
                .frame(maxWidth: .infinity)
        }
        .frame(maxHeight: .infinity)
        .opacity(stale ? 0.55 : 1)
    }
}
