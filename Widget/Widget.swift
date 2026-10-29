import WidgetKit
import SwiftUI

struct PulseEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot
    let stale: Bool
    var noData = false
}

struct PulseProvider: TimelineProvider {
    func placeholder(in context: Context) -> PulseEntry {
        PulseEntry(date: Date(), snapshot: .placeholder, stale: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (PulseEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PulseEntry>) -> Void) {
        let entry = current()
        // Агент сам дёргает перезагрузку при новых данных; это страховка.
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60))))
    }

    private func current() -> PulseEntry {
        let now = Date()
        guard let snap = SnapshotIO.read() else {
            return PulseEntry(date: now, snapshot: .placeholder, stale: true, noData: true)
        }
        return PulseEntry(date: now, snapshot: snap, stale: now.timeIntervalSince(snap.updatedAt) > 180)
    }
}

struct PulseWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PulseEntry

    var body: some View {
        Group {
            if entry.noData {
                VStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.cpu)
                    Text("Запусти AI Pulse").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    Text("виджет ждёт данные от приложения").font(.system(size: 10)).foregroundStyle(Theme.dim)
                        .multilineTextAlignment(.center)
                }
            } else {
            switch family {
            case .systemSmall: SmallGrid(snap: entry.snapshot, stale: entry.stale, now: entry.date)
            case .systemMedium: MediumRow(snap: entry.snapshot, stale: entry.stale, now: entry.date)
            default: FullPanel(snap: entry.snapshot, stale: entry.stale, now: entry.date)
            }
            }
        }
        .environment(\.colorScheme, .dark)
        .containerBackground(for: .widget) { Theme.background }
    }
}

struct PulseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AIPulseWidget", provider: PulseProvider()) { entry in
            PulseWidgetView(entry: entry)
        }
        .configurationDisplayName("AI Pulse")
        .description("CPU, память и лимиты Claude и Codex.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct PulseWidgets: WidgetBundle {
    var body: some Widget { PulseWidget() }
}
