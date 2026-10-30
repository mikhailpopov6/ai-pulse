// Renders the widget layouts to PNG to check the design. AIPULSE_LANG=en|ru picks the language.
import AppKit
import SwiftUI

@MainActor func save<V: View>(_ view: V, _ size: CGSize, _ name: String) {
    let content = view
        .padding(16)
        .frame(width: size.width, height: size.height)
        .background(Theme.background)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .environment(\.colorScheme, .dark)
        .padding(10)
    let r = ImageRenderer(content: content)
    r.scale = 2
    let rep = NSBitmapImageRep(cgImage: r.cgImage!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(CommandLine.arguments[1])/\(name).png"))
}

MainActor.assumeIsolated {
    let real = SnapshotIO.read() ?? .placeholder
    var demo = real
    demo.claude = Snapshot.placeholder.claude
    let now = Date()
    for (snap, tag) in [(real, "real"), (demo, "demo"), (Snapshot.placeholder, "docs")] {
        save(SmallGrid(snap: snap, stale: false, now: now), CGSize(width: 170, height: 170), "small-\(tag)")
        save(MediumRow(snap: snap, stale: false, now: now), CGSize(width: 364, height: 170), "medium-\(tag)")
        save(FullPanel(snap: snap, stale: false, now: now), CGSize(width: 340, height: 270), "large-\(tag)")
    }
}
