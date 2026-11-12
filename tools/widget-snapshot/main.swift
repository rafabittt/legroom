import SwiftUI
import WidgetKit

// Draws the three widget sizes in light and dark, with real disk, memory and CPU
// readings (no App Group here, so "freed" and the goals are sample data).
// Usage: tools/widget-snapshots.sh <folder>

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let sample = WidgetSnapshot(written: Date(), volumeName: nil, totalCapacity: nil, availableCapacity: nil,
                            memoryUsed: nil, memoryTotal: nil, cpuBusy: nil, cpuHistory: [],
                            trashedBytesTotal: 6_420_000_000, trashedItemsTotal: 37, lastTrashDate: Date().addingTimeInterval(-2 * 86400),
                            goals: [.init(title: "Map", symbol: "square.grid.3x3.topleft.filled", status: "not scanned yet"),
                                    .init(title: "Cleanup", symbol: "sparkles", status: "4.2 GB suggested"),
                                    .init(title: "Large & Forgotten", symbol: "shippingbox", status: "18.7 GB"),
                                    .init(title: "Apps", symbol: "app.badge", status: "42 apps · 31.5 GB"),
                                    .init(title: "Clutter", symbol: "tray.2", status: "not scanned yet")])
let entry = LegroomEntry(date: Date(), volume: DiskReader.root(), memory: MemorySnapshot.take(),
                         cpu: CPUReader.sample(record: false),
                         cpuHistory: [0.12, 0.2, 0.15, 0.32, 0.22, 0.18, 0.26, 0.14, 0.18, 0.21],
                         app: sample)

let sizes: [(String, WidgetFamily, CGSize)] = [("small", .systemSmall, CGSize(width: 160, height: 160)),
                                                ("medium", .systemMedium, CGSize(width: 340, height: 160)),
                                                ("large", .systemLarge, CGSize(width: 340, height: 344))]

@MainActor func render() {
    for scheme in [ColorScheme.light, .dark] {
        let dark = scheme == .dark
        for (name, family, size) in sizes {
            let view = WidgetContent(entry: entry, family: family)
                .padding(16)
                .frame(width: size.width, height: size.height)
                .background(WidgetPalette.background(dark))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(24)
                .background(dark ? Color(hex: 0x141416) : Color(hex: 0xF0F0F3))
                .environment(\.colorScheme, scheme)
            let r = ImageRenderer(content: view)
            r.scale = 2
            guard let img = r.cgImage else { continue }
            let rep = NSBitmapImageRep(cgImage: img)
            let url = out.appendingPathComponent("widget-\(name)-\(dark ? "dark" : "light").png")
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            print(url.path)
        }
    }
}
@main enum Render { @MainActor static func main() { render() } }
