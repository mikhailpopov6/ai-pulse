// Рисует иконку AI Pulse: четыре кольца-метрики на тёмном фоне.
// swift tools/make_icon.swift out.png
import AppKit
import SwiftUI

struct IconView: View {
    let colors: [Color] = [
        Color(red: 0.30, green: 0.80, blue: 0.98),
        Color(red: 0.66, green: 0.52, blue: 1.00),
        Color(red: 0.86, green: 0.50, blue: 0.36),
        Color(red: 0.24, green: 0.84, blue: 0.62),
    ]
    let fills: [Double] = [0.78, 0.62, 0.48, 0.34]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 230, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.10, green: 0.11, blue: 0.16), Color(red: 0.17, green: 0.18, blue: 0.26)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 824, height: 824)
            ForEach(0..<4) { i in
                let d = CGFloat(620 - i * 124)
                Circle().stroke(Color.white.opacity(0.08), lineWidth: 46).frame(width: d, height: d)
                Circle()
                    .trim(from: 0, to: fills[i])
                    .stroke(colors[i], style: StrokeStyle(lineWidth: 46, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: d, height: d)
            }
        }
        .frame(width: 1024, height: 1024)
    }
}

MainActor.assumeIsolated {
    let out = CommandLine.arguments.dropFirst().first ?? "icon.png"
    let renderer = ImageRenderer(content: IconView())
    renderer.scale = 1
    guard let cg = renderer.cgImage else { fatalError("render failed") }
    let rep = NSBitmapImageRep(cgImage: cg)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
}
