import SwiftUI
import WidgetKit

/// Tapping anywhere opens Legroom to the Overview.
let resumoURL = URL(string: "legroom://resumo")!

struct LegroomWidgetView: View {
    let entry: LegroomEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        WidgetContent(entry: entry, family: family)
            .widgetURL(resumoURL)
            .containerBackground(for: .widget) { WidgetPalette.background(scheme == .dark) }
    }
}

/// Content per size, without depending on the WidgetKit environment (the capture
/// script in tools/widget-snapshots.sh draws this directly).
struct WidgetContent: View {
    let entry: LegroomEntry
    let family: WidgetFamily
    var body: some View {
        switch family {
        case .systemMedium: MediumView(entry: entry)
        case .systemLarge, .systemExtraLarge: LargeView(entry: entry)
        default: SmallView(entry: entry)
        }
    }
}

// MARK: - Pieces

private struct UsageRing: View {
    let fraction: Double
    let accent: Color
    var size: CGFloat
    var lineWidth: CGFloat
    var fontSize: CGFloat
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            Circle().stroke(WidgetPalette.track(scheme == .dark), lineWidth: lineWidth)
            Circle().trim(from: 0, to: max(0.01, fraction))
                .stroke(accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
            VStack(spacing: -1) {
                Text("\(Int(((fraction.isFinite ? fraction : 0) * 100).rounded()))%")
                    .font(.system(size: fontSize, weight: .semibold)).tracking(-0.5).monospacedDigit()
                Text("used").font(.system(size: max(9, fontSize * 0.42))).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

private struct HealthLabel: View {
    let health: DiskHealth
    var size: CGFloat = 13
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: health.symbol).foregroundStyle(health.accent(dark: scheme == .dark)).widgetAccentable()
            Text(health.label).fontWeight(.semibold).tracking(-0.2).lineLimit(1).minimumScaleFactor(0.7)
        }
        .font(.system(size: size))
    }
}

private struct Caption: View {
    let symbol: String
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 9.5, weight: .semibold))
            Text(title).font(.system(size: 10.5, weight: .medium)).lineLimit(1)
            Spacer(minLength: 0)
            if let trailing { Text(trailing).font(.system(size: 10)).foregroundStyle(.tertiary).monospacedDigit() }
        }
        .foregroundStyle(.secondary)
    }
}

/// The same memory bar as the app, in grays: system, apps, compressed.
private struct MemoryBarMini: View {
    let memory: MemorySnapshot
    var height: CGFloat = 6
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let m = memory, dark = scheme == .dark, t = Double(max(1, m.total))
        GeometryReader { geo in
            let w = geo.size.width
            HStack(spacing: 1.5) {
                seg(w, Double(m.wired) / t, Color.primary.opacity(dark ? 0.9 : 0.85))
                seg(w, Double(m.used &- m.wired &- m.compressed) / t, Color.primary.opacity(0.45))
                seg(w, Double(m.compressed) / t, Color.primary.opacity(0.22))
                Spacer(minLength: 0)
            }
            .frame(height: height).background(Capsule().fill(WidgetPalette.track(dark))).clipShape(Capsule())
        }
        .frame(height: height)
    }
    private func seg(_ w: CGFloat, _ f: Double, _ c: Color) -> some View {
        Rectangle().fill(c).frame(width: max(0, w * CGFloat(max(0, min(1, f)))))
    }
}

/// Thin history line, like the app's `Sparkline`.
private struct MiniSparkline: View {
    let values: [Double]
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height, n = max(values.count, 2)
            let pts = values.enumerated().map { i, v in
                CGPoint(x: w * CGFloat(i) / CGFloat(n - 1), y: h - h * CGFloat(min(1, max(0, v))))
            }
            if pts.count > 1 {
                ZStack {
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: h))
                        pts.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: h)); p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [Color.primary.opacity(0.18), Color.primary.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                    Path { p in p.move(to: pts[0]); pts.dropFirst().forEach { p.addLine(to: $0) } }
                        .stroke(Color.primary.opacity(0.75), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
                    Circle().fill(Color.primary).frame(width: 4, height: 4).position(pts[pts.count - 1])
                }
            } else {
                Capsule().fill(Color.primary.opacity(0.08)).frame(height: 1.5).frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }
}

private func percent(_ f: Double) -> String { "\(Int(((f.isFinite ? f : 0) * 100).rounded()))%" }
/// Non-breaking space between number and unit ("172 GB" never wraps).
private func gb(_ n: Int64) -> String { Format.bytes(n).replacingOccurrences(of: " ", with: "\u{00A0}") }
private func mem(_ n: Int64) -> String { Format.memory(n).replacingOccurrences(of: " ", with: "\u{00A0}") }

private struct MemoryBlock: View {
    let memory: MemorySnapshot?
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Caption(symbol: "memorychip", title: String(localized: "Memory"))
            if let m = memory {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(mem(Int64(m.used))).font(.system(size: 15, weight: .semibold)).tracking(-0.3).monospacedDigit()
                    Text("of \(mem(Int64(m.total)))").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                .lineLimit(1).minimumScaleFactor(0.8)
                MemoryBarMini(memory: m)
            } else {
                Text("—").font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
    }
}

private struct CPUBlock: View {
    let cpu: Double?
    let history: [Double]
    var sparkHeight: CGFloat = 18
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Caption(symbol: "cpu", title: String(localized: "CPU"))
            HStack(alignment: .bottom, spacing: 8) {
                Text(cpu.map(percent) ?? "—").font(.system(size: 15, weight: .semibold)).tracking(-0.3).monospacedDigit()
                MiniSparkline(values: history).frame(height: sparkHeight)
            }
        }
    }
}

// MARK: - Small

struct SmallView: View {
    let entry: LegroomEntry
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let h = entry.health, accent = h.accent(dark: scheme == .dark)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                UsageRing(fraction: entry.volume?.usedFraction ?? 0, accent: accent, size: 74, lineWidth: 8, fontSize: 19)
                Spacer(minLength: 0)
                Image(systemName: "internaldrive").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 6)
            HealthLabel(health: h, size: 12.5)
            if let v = entry.volume {
                Text("\(gb(v.free)) available").font(.system(size: 11.5)).foregroundStyle(.secondary)
                    .monospacedDigit().lineLimit(1).padding(.top, 1)
            } else {
                Text("Disk unavailable").font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Medium

struct MediumView: View {
    let entry: LegroomEntry
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let h = entry.health, accent = h.accent(dark: scheme == .dark)
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                UsageRing(fraction: entry.volume?.usedFraction ?? 0, accent: accent, size: 76, lineWidth: 8, fontSize: 19)
                Spacer(minLength: 6)
                HealthLabel(health: h, size: 12.5)
                Text(entry.volume.map { String(localized: "\(gb($0.free)) available") } ?? String(localized: "Disk unavailable"))
                    .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1).padding(.top, 1)
            }
            .frame(width: 128, alignment: .leading)
            Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1).padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 0) {
                MemoryBlock(memory: entry.memory)
                Spacer(minLength: 8)
                CPUBlock(cpu: entry.cpu, history: entry.cpuHistory)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Large

struct LargeView: View {
    let entry: LegroomEntry
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let h = entry.health, accent = h.accent(dark: scheme == .dark)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Overview").font(.system(size: 13, weight: .semibold)).tracking(-0.2)
                Spacer()
                Text(entry.date, style: .time).font(.system(size: 10)).foregroundStyle(.tertiary).monospacedDigit()
            }
            .padding(.bottom, 6)

            HStack(spacing: 14) {
                UsageRing(fraction: entry.volume?.usedFraction ?? 0, accent: accent, size: 64, lineWidth: 7, fontSize: 17)
                VStack(alignment: .leading, spacing: 3) {
                    Caption(symbol: "internaldrive", title: entry.volume?.name ?? String(localized: "Disk"))
                    HealthLabel(health: h, size: 14)
                    if let v = entry.volume {
                        Text("\(gb(v.usedCapacity)) used of \(gb(v.totalCapacity)). \(gb(v.free)) available.")
                            .font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            divider
            HStack(alignment: .top, spacing: 14) {
                MemoryBlock(memory: entry.memory).frame(maxWidth: .infinity, alignment: .leading)
                CPUBlock(cpu: entry.cpu, history: entry.cpuHistory).frame(maxWidth: .infinity, alignment: .leading)
            }

            divider
            freed

            divider
            goals
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1).padding(.vertical, 7)
    }

    @ViewBuilder private var freed: some View {
        VStack(alignment: .leading, spacing: 3) {
            Caption(symbol: "trash", title: String(localized: "Freed by Legroom"),
                    trailing: entry.app?.lastTrashDate.map { relative($0) })
            if let a = entry.app, a.trashedItemsTotal > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(gb(a.trashedBytesTotal)).font(.system(size: 15, weight: .semibold)).tracking(-0.3).monospacedDigit()
                    Text(a.trashedItemsTotal == 1 ? String(localized: "in 1 item") : String(localized: "in \(Format.count(a.trashedItemsTotal)) items"))
                        .font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            } else {
                Text(entry.app == nil ? String(localized: "Open Legroom to start counting here.") : String(localized: "Nothing yet"))
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var goals: some View {
        VStack(alignment: .leading, spacing: 2.5) {
            Caption(symbol: "list.bullet.rectangle", title: String(localized: "Goals"))
            if let lines = entry.app?.goals, !lines.isEmpty {
                ForEach(lines, id: \.self) { g in
                    HStack(spacing: 7) {
                        Image(systemName: g.symbol).font(.system(size: 9, weight: .semibold))
                            .frame(width: 15, height: 15)
                            .background(RoundedRectangle(cornerRadius: 4.5, style: .continuous).fill(Color.primary.opacity(scheme == .dark ? 0.10 : 0.06)))
                            .foregroundStyle(Color.primary.opacity(0.8))
                        Text(g.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 6)
                        Text(g.status).font(.system(size: 10.5)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                    }
                }
            } else {
                Text("Open Legroom to see the status of your goals.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: entry.date)
    }
}
