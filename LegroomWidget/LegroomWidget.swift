import WidgetKit
import SwiftUI
import os

let widgetLog = Logger(subsystem: "com.rafabitt.legroom.widget", category: "timeline")

/// A timeline entry: what the widget read just now + what the app published.
struct LegroomEntry: TimelineEntry {
    let date: Date
    let volume: Volume?
    let memory: MemorySnapshot?
    let cpu: Double?
    let cpuHistory: [Double]
    let app: WidgetSnapshot?

    var health: DiskHealth { volume.map(DiskHealth.init(volume:)) ?? .unknown }

    static func read(record: Bool) -> LegroomEntry {
        let app = WidgetSnapshot.read()
        var volume = DiskReader.root()
        if volume == nil, let a = app, let total = a.totalCapacity, let avail = a.availableCapacity {
            volume = Volume(url: URL(fileURLWithPath: "/"), name: a.volumeName ?? "Macintosh HD", totalCapacity: total,
                            availableCapacity: avail, availableForImportantUsage: avail, isInternal: true,
                            isRemovable: false, isEjectable: false, isReadOnly: false, isRootVolume: true)
        }
        let cpu = CPUReader.sample(record: record) ?? app?.cpuBusy
        var history = CPUReader.history
        // No history of its own yet: use the app's, if it published recently (Overview open).
        if history.count < 3, let a = app, Date().timeIntervalSince(a.written) < 30 * 60, a.cpuHistory.count > 2 {
            history = a.cpuHistory
        }
        widgetLog.notice("read: disk \(volume != nil), app group \(WidgetSnapshot.defaults != nil), snapshot \(app != nil ? "yes" : "no", privacy: .public)")
        return LegroomEntry(date: Date(), volume: volume, memory: MemorySnapshot.take(), cpu: cpu, cpuHistory: history, app: app)
    }

    /// Sample data for the gallery when nothing could be read.
    static let placeholder = LegroomEntry(
        date: Date(),
        volume: Volume(url: URL(fileURLWithPath: "/"), name: "Macintosh HD", totalCapacity: 494_000_000_000,
                       availableCapacity: 182_000_000_000, availableForImportantUsage: 190_000_000_000, isInternal: true,
                       isRemovable: false, isEjectable: false, isReadOnly: false, isRootVolume: true),
        memory: MemorySnapshot(total: 17_179_869_184, used: 11_200_000_000, wired: 2_900_000_000,
                               compressed: 1_400_000_000, inactive: 3_100_000_000, free: 900_000_000),
        cpu: 0.18, cpuHistory: [0.12, 0.2, 0.15, 0.32, 0.22, 0.18, 0.26, 0.14, 0.18],
        app: nil)
}

struct LegroomProvider: TimelineProvider {
    func placeholder(in context: Context) -> LegroomEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (LegroomEntry) -> Void) {
        completion(context.isPreview ? .placeholder : .read(record: false))
    }

    /// One entry at a time; the next one after 15 minutes (the system decides
    /// when, and never sooner). The app also requests a reload when something changes.
    func getTimeline(in context: Context, completion: @escaping (Timeline<LegroomEntry>) -> Void) {
        let entry = LegroomEntry.read(record: true)
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

struct LegroomWidget: Widget {
    static let kind = "LegroomResumo"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: LegroomProvider()) { entry in
            LegroomWidgetView(entry: entry)
        }
        .configurationDisplayName("Legroom")
        .description("Your Mac's disk, memory and CPU, plus what Legroom has freed.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// The capture script (tools/widget-snapshots.sh) compiles this file with SNAPSHOT_HARNESS.
#if !SNAPSHOT_HARNESS
@main
struct LegroomWidgetBundle: WidgetBundle {
    var body: some Widget { LegroomWidget() }
}

#Preview("Small", as: .systemSmall) { LegroomWidget() } timeline: { LegroomEntry.placeholder }
#Preview("Medium", as: .systemMedium) { LegroomWidget() } timeline: { LegroomEntry.placeholder }
#Preview("Large", as: .systemLarge) { LegroomWidget() } timeline: { LegroomEntry.placeholder }
#endif
