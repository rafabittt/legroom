import SwiftUI

/// Overview: read-only general status. Disk, memory, CPU, network, what
/// Legroom has freed so far and the state of each goal. The memory, CPU and network cards
/// open a popover with details; each one has a single action button inside.
struct HomeView: View {
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var scheme
    /// Expanded metric card ("memory", "cpu", "network"), drawn on top of the screen.
    @State private var expanded: String?

    var body: some View {
        ZStack {
            summary
            if let key = expanded {
                ExpandedOverlay(key: key) { withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { expanded = nil } }
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: expanded)
        .onAppear { if let k = state.debugOpenMetric { DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { expanded = k } } }
        .environment(\.expandMetric, ExpandMetricAction { key in withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) { expanded = key } })
    }

    private var summary: some View {
        VStack(spacing: 14) {
            GoalHeader(goal: .home) {
                Text(Date().formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11)).foregroundStyle(.tertiary).monospacedDigit()
            }
            .padding(.horizontal, 24)

            ScrollView {
                VStack(spacing: 14) {
                    HStack(spacing: 14) {
                        DiskCard().frame(maxWidth: .infinity).layoutPriority(1)
                        FreedCard().frame(width: 320)
                    }
                    HStack(spacing: 14) {
                        MemoryCard().frame(maxWidth: .infinity)
                        CPUCard().frame(maxWidth: .infinity)
                        NetworkCard().frame(maxWidth: .infinity)
                    }
                    GoalsSummaryCard()
                }
                .padding(.horizontal, 24).padding(.bottom, 24).padding(.top, 2)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.top, 18)
        // readings only while the Overview is on screen (the pace is shared with the menu bar item)
        .task { await state.withMetrics("resumo") }
    }
}

// MARK: - Shared pieces

struct CardTitle: View {
    let symbol: String
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if let trailing { Text(trailing).font(.system(size: 11)).foregroundStyle(.tertiary).monospacedDigit() }
        }
    }
}

private struct Fact: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 10.5)).foregroundStyle(.tertiary)
            Text(value).font(.system(size: 13, weight: .medium)).monospacedDigit()
        }
    }
}

/// Action that expands a metric card (injected by HomeView).
struct ExpandMetricAction { let run: (String) -> Void }
private struct ExpandMetricKey: EnvironmentKey { static let defaultValue = ExpandMetricAction { _ in } }
extension EnvironmentValues {
    var expandMetric: ExpandMetricAction {
        get { self[ExpandMetricKey.self] }
        set { self[ExpandMetricKey.self] = newValue }
    }
}

/// Clickable metric card: opens the expanded card on top of the screen. The action
/// button inside it works without expanding.
private struct MetricCard<Content: View>: View {
    let key: String
    let symbol: String
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var scheme
    @Environment(\.expandMetric) private var expand
    @State private var hover = false
    @State private var pressed = false

    var body: some View {
        let dark = scheme == .dark
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(symbol: symbol, title: title, trailing: hover ? String(localized: "details ↗") : nil)
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
        .contentCard(corner: Theme.cornerXL)
        .contentShape(RoundedRectangle(cornerRadius: Theme.cornerXL, style: .continuous))
        .scaleEffect(pressed ? 0.985 : 1)
        .onHover { h in withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { hover = h } }
        .simultaneousGesture(TapGesture().onEnded { expand.run(key) })
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in if !pressed { withAnimation(.easeOut(duration: 0.08)) { pressed = true } } }
            .onEnded { _ in withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { pressed = false } })
        .cursorReactive(corner: Theme.cornerXL, spotlight: dark ? .white : .black, intensity: dark ? 0.05 : 0.03, tilt: 2, lift: 1.0, borderGlow: 0.1)
        .help("Click for details")
    }
}

/// Expanded card on top of the Overview: dimmed background (click closes), Esc closes,
/// springs in from 0.94 and leaves faster.
private struct ExpandedOverlay: View {
    let key: String
    let close: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let dark = scheme == .dark
        ZStack {
            Color.black.opacity(dark ? 0.55 : 0.28)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { close() }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Spacer()
                    RoundIconButton(systemImage: "xmark") { close() }
                        .keyboardShortcut(.cancelAction)
                        .help("Close (Esc)")
                }
                .padding(.bottom, -22)
                Group {
                    switch key {
                    case "memory": MemoryDetail()
                    case "cpu": CPUDetail()
                    default: NetworkDetail()
                    }
                }
            }
            .padding(22)
            .frame(width: 560)
            .background(RoundedRectangle(cornerRadius: Theme.cornerXL, style: .continuous).fill(Theme.card(dark)))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerXL, style: .continuous).strokeBorder(Theme.hairline(dark), lineWidth: 1))
            .shadow(color: .black.opacity(dark ? 0.6 : 0.22), radius: 40, y: 20)
            .transition(.asymmetric(insertion: .scale(scale: 0.94).combined(with: .opacity),
                                    removal: .scale(scale: 0.97).combined(with: .opacity)))
        }
        .onExitCommand { close() }
    }
}

/// Segmented ring band (memory): several slices in grays, an optional accent color.
private struct Donut: View {
    let slices: [(Double, Color)]   // fraction, color
    var lineWidth: CGFloat = 14
    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
            ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                Circle().trim(from: seg.0, to: seg.1)
                    .stroke(seg.2, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
        }
        .animation(.spring(response: 0.8, dampingFraction: 1.0), value: slices.map(\.0))
    }
    private var segments: [(CGFloat, CGFloat, Color)] {
        var out: [(CGFloat, CGFloat, Color)] = []
        var start: CGFloat = 0
        for (f, c) in slices {
            let end = start + CGFloat(max(0, min(1, f)))
            if end > start { out.append((start, min(1, end), c)) }
            start = end
        }
        return out
    }
}

/// Info tile for the popovers (like "Pressure" / "Swap" in the refs).
private struct InfoTile: View {
    let title: String
    let value: String
    let text: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(title).font(.system(size: 12.5, weight: .semibold)); Spacer(); Text(value).font(.system(size: 12.5, weight: .semibold)).monospacedDigit() }
            Text(text).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(scheme == .dark ? 0.08 : 0.04)))
    }
}

/// "Top Processes" list with Quit only for regular apps.
private struct ConsumersList: View {
    let rows: [ProcessInfoRow]
    let value: (ProcessInfoRow) -> String
    let unit: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Top Processes").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(unit).font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            if rows.isEmpty {
                Text("Reading processes…").font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            ForEach(rows) { r in
                HStack(spacing: 10) {
                    if let icon = r.icon {
                        Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                    } else {
                        Image(systemName: "gearshape").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 20, height: 20)
                    }
                    Text(r.name).font(.system(size: 12.5)).lineLimit(1)
                    Spacer()
                    Text(value(r)).font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
                    if r.isApp {
                        PillButton(title: String(localized: "Quit"), prominent: false, compact: true) { r.quit() }
                            .help("Asks the app to quit, like ⌘Q. It may still ask whether to save.")
                    } else {
                        Text("system").font(.system(size: 10.5)).foregroundStyle(.tertiary).frame(width: 64)
                    }
                }
                .padding(.vertical, 3)
            }
        }
    }
}

// MARK: - Disk and freed

private struct DiskCard: View {
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let dark = scheme == .dark
        let accent = state.health.accent(dark: dark)
        let shape = RoundedRectangle(cornerRadius: Theme.cornerXL, style: .continuous)
        HStack(spacing: 22) {
            if let v = state.selectedVolume {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.08), lineWidth: 9)
                    Circle().trim(from: 0, to: max(0.01, v.usedFraction))
                        .stroke(accent, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.9, dampingFraction: 1.0), value: v.usedFraction)
                    VStack(spacing: 0) {
                        RollingNumber(text: "\((v.usedFraction * 100).rounded().safeInt)%", font: .system(size: 24, weight: .semibold), tracking: -0.6)
                        Text("used").font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 112, height: 112)
                VStack(alignment: .leading, spacing: 8) {
                    CardTitle(symbol: "internaldrive", title: v.name)
                    HStack(spacing: 8) {
                        Image(systemName: state.health.symbol).foregroundStyle(accent)
                        Text(state.health.label).font(.system(size: 22, weight: .semibold)).tracking(-0.5)
                    }
                    Text("\(Format.bytes(v.usedCapacity)) used of \(Format.bytes(v.totalCapacity)). \(Format.bytes(v.free)) available.")
                        .font(.system(size: 12.5)).foregroundStyle(.secondary)
                    HStack(spacing: 18) {
                        Fact(title: String(localized: "Purgeable (in available)"), value: Format.bytes(v.purgeableEstimate))
                        if let root = state.rootNode {
                            Fact(title: String(localized: "Mapped"), value: Format.bytes(root.allocatedSize))
                        } else if let saved = state.savedMap {
                            Fact(title: String(localized: "Mapped"), value: Format.bytes(saved.allocatedSize))
                        } else {
                            Fact(title: String(localized: "Map"), value: String(localized: "not scanned yet"))
                        }
                    }
                }
                Spacer(minLength: 0)
            } else {
                Text("No volume selected.").foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 172, alignment: .leading)
        .background {
            shape.fill(Theme.card(dark))
                .overlay {
                    Circle().fill(accent).frame(width: 220, height: 220).blur(radius: 60)
                        .offset(x: -140, y: 40).opacity(0.22)
                        .animation(.easeInOut(duration: 1.0), value: accent)
                }
                .clipShape(shape)
                .overlay(shape.strokeBorder(Theme.hairline(dark), lineWidth: 1))
        }
        .shadow(color: .black.opacity(dark ? 0.35 : 0.05), radius: dark ? 18 : 12, y: 6)
        .cursorReactive(corner: Theme.cornerXL, spotlight: dark ? .white : .black, intensity: dark ? 0.05 : 0.03, tilt: 2, lift: 1.004, borderGlow: 0.1)
    }
}

private struct FreedCard: View {
    @Environment(AppState.self) private var state
    var body: some View {
        let _ = state.trashHistoryVersion
        VStack(alignment: .leading, spacing: 8) {
            CardTitle(symbol: "trash", title: String(localized: "Freed by Legroom"))
            if state.trashedItemsTotal > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    RollingNumber(text: Format.bytes(state.trashedBytesTotal), font: .system(size: 26, weight: .semibold), tracking: -0.7)
                    Text(state.trashedItemsTotal == 1 ? String(localized: "across \(Format.count(state.trashedItemsTotal)) item") : String(localized: "across \(Format.count(state.trashedItemsTotal)) items")).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                if let d = state.lastTrashDate {
                    Text("Most recent: \(Format.relative(d)). Everything went to the Trash and can be put back from there.").font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
            } else {
                Text("Nothing yet").font(.system(size: 26, weight: .semibold)).tracking(-0.7).foregroundStyle(.secondary)
                Text("Everything you move to the Trash with Legroom adds up here.").font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 172, alignment: .leading)
        .contentCard(corner: Theme.cornerXL)
        .refreshesFreedTotal()
    }
}

extension View {
    /// The freed total lives in UserDefaults and can change outside this window
    /// (Siri, another instance of the app). Re-reads on appear and when returning to the app.
    func refreshesFreedTotal() -> some View { modifier(FreedTotalRefresher()) }
}

private struct FreedTotalRefresher: ViewModifier {
    @Environment(AppState.self) private var state
    func body(content: Content) -> some View {
        content
            .onAppear { state.trashHistoryVersion += 1 }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                state.trashHistoryVersion += 1
            }
    }
}

// MARK: - Memory

private struct MemoryCard: View {
    @Environment(AppState.self) private var state
    var body: some View {
        MetricCard(key: "memory", symbol: "memorychip", title: String(localized: "Memory")) {
            if let m = state.memory {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    RollingNumber(text: Format.memory(Int64(m.used)), font: .system(size: 24, weight: .semibold), tracking: -0.6)
                    Text("of \(Format.memory(Int64(m.total)))").font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                MemoryBar(memory: m)
                Text(m.pressureLabel).font(.system(size: 12, weight: .medium))
            } else {
                Text("Couldn't read memory.").foregroundStyle(.secondary)
            }
            Spacer(minLength: 2)
            HStack(spacing: 8) {
                if state.memoryCleaning {
                    ProgressView().controlSize(.small)
                    Text("Asking the system for memory…").font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    PillButton(title: String(localized: "Free Up Memory"), systemImage: "wind", prominent: false, compact: true) { state.cleanMemory() }
                    if let o = state.memoryOutcome {
                        Text(o.freed > 50_000_000 ? String(localized: "Freed \(Format.memory(o.freed))") : String(localized: "Already had room"))
                            .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                    }
                }
            }
        }
    }
}

/// Memory bar by type, in grays: system (wired), apps, compressed.
/// Used in the Overview card and in the menu bar item.
struct MemoryBar: View {
    let memory: MemorySnapshot
    var height: CGFloat = 8
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let m = memory, dark = scheme == .dark
        GeometryReader { geo in
            let w = geo.size.width
            HStack(spacing: 2) {
                seg(w, Double(m.wired) / Double(m.total), Color.primary.opacity(dark ? 0.9 : 0.85))
                seg(w, Double(m.used - m.wired - m.compressed) / Double(m.total), Color.primary.opacity(0.45))
                seg(w, Double(m.compressed) / Double(m.total), Color.primary.opacity(0.22))
                Spacer(minLength: 0)
            }
            .frame(height: height).background(Capsule().fill(Color.primary.opacity(0.07))).clipShape(Capsule())
        }
        .frame(height: height)
    }
    private func seg(_ w: CGFloat, _ f: Double, _ color: Color) -> some View {
        Rectangle().fill(color).frame(width: max(0, w * CGFloat(max(0, min(1, f)))))
    }
}

private struct MemoryDetail: View {
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let dark = scheme == .dark
        VStack(alignment: .leading, spacing: 16) {
            Text("Memory").font(.system(size: 17, weight: .semibold)).tracking(-0.3)
            if let m = state.memory {
                let apps = m.used - m.wired - m.compressed
                HStack(spacing: 22) {
                    ZStack {
                        Donut(slices: [(Double(apps) / Double(m.total), Color.primary.opacity(0.85)),
                                       (Double(m.wired) / Double(m.total), Color.primary.opacity(0.45)),
                                       (Double(m.compressed) / Double(m.total), Color.primary.opacity(0.22))])
                        VStack(spacing: 0) {
                            RollingNumber(text: Format.memory(Int64(m.used)), font: .system(size: 20, weight: .semibold), tracking: -0.5)
                            Text("of \(Format.memory(Int64(m.total)))").font(.system(size: 10.5)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 136, height: 136)
                    VStack(alignment: .leading, spacing: 10) {
                        Legend(color: Color.primary.opacity(0.85), title: String(localized: "Apps"), value: Format.bytes(Int64(apps)))
                        Legend(color: Color.primary.opacity(0.45), title: String(localized: "System (wired)"), value: Format.memory(Int64(m.wired)))
                        Legend(color: Color.primary.opacity(0.22), title: String(localized: "Compressed"), value: Format.memory(Int64(m.compressed)))
                        Legend(color: Color.primary.opacity(0.08), title: String(localized: "Cached Files"), value: Format.memory(Int64(m.inactive)))
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 10) {
                    InfoTile(title: String(localized: "Pressure"), value: Format.percent(m.usedFraction),
                             text: m.usedFraction < 0.65 ? String(localized: "Your Mac has plenty of room for more tasks.") :
                                   m.usedFraction < 0.85 ? String(localized: "Normal usage. The system compresses what isn't in use.") :
                                   String(localized: "Near the limit: the system is compressing and swapping to disk."))
                    InfoTile(title: String(localized: "Swap"), value: state.swap.map { Format.memory(Int64($0.used)) } ?? "—",
                             text: String(localized: "Memory that overflowed to disk. Zero is ideal; a few GB is normal under heavy use."))
                }
            }
            ConsumersList(rows: state.topByMemory, value: { Format.memory($0.memory) }, unit: String(localized: "in use"))
            HStack {
                if state.memoryCleaning {
                    ProgressView().controlSize(.small); Text("Asking the system for memory…").font(.system(size: 11.5)).foregroundStyle(.secondary)
                } else {
                    PillButton(title: String(localized: "Free Up Memory"), systemImage: "wind") { state.cleanMemory() }
                    if let o = state.memoryOutcome {
                        Text(o.freed > 50_000_000 ? String(localized: "Freed \(Format.memory(o.freed))") : String(localized: "Already had room")).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            Text("Free Up Memory asks the system for memory so it discards file caches, then gives it back right away. The gain lasts until apps need it again.")
                .font(.system(size: 10.5)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct Legend: View {
    let color: Color
    let title: String
    let value: String
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
                Text(value).font(.system(size: 12.5, weight: .medium)).monospacedDigit()
            }
        }
    }
}

// MARK: - CPU

private struct CPUCard: View {
    @Environment(AppState.self) private var state
    var body: some View {
        MetricCard(key: "cpu", symbol: "cpu", title: String(localized: "CPU")) {
            let busy = state.cpu?.busy ?? 0
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                RollingNumber(text: Format.percent(busy), font: .system(size: 24, weight: .semibold), tracking: -0.6)
                Text("in use").font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Sparkline(values: state.cpuHistory.map(\.busy), color: .primary)
                .frame(height: 34)
            HStack(spacing: 6) {
                Text(busy < 0.3 ? String(localized: "CPU relaxed") : busy < 0.7 ? String(localized: "CPU busy") : String(localized: "CPU at its limit"))
                    .font(.system(size: 12, weight: .medium))
                Spacer(minLength: 4)
                if let t = state.thermal?.chip {
                    Label(Format.celsius(t), systemImage: "thermometer.medium")
                        .font(.system(size: 11.5, weight: .medium)).monospacedDigit()
                        .foregroundStyle(.secondary)
                        .help("Chip temperature. \(state.thermal?.stateLabel ?? "").")
                }
            }
            Spacer(minLength: 2)
            HStack(spacing: 8) {
                if let top = state.topByCPU.first(where: { $0.isApp }), top.cpu >= 20 {
                    PillButton(title: String(localized: "Quit \(top.name)"), systemImage: "xmark", prominent: false, compact: true) { top.quit() }
                        .help("\(top.name) is using \(top.cpu.formatted(.number.precision(.fractionLength(0))))% of the CPU. Asks the app to quit, like ⌘Q.")
                } else {
                    Text("No heavy apps right now").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }
        }
    }
}

private struct CPUDetail: View {
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let dark = scheme == .dark
        let c = state.cpu ?? CPUSample(user: 0, system: 0)
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(CPUMonitor.chipName).font(.system(size: 17, weight: .semibold)).tracking(-0.3)
                Text("\(CPUMonitor.coreCount) cores · last \(state.cpuHistory.count * 3 / 2) s").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            HStack(alignment: .top, spacing: 18) {
                ZStack {
                    Sparkline(values: state.cpuHistory.map(\.busy), color: .primary.opacity(0.85))
                    Sparkline(values: state.cpuHistory.map(\.system), color: .primary.opacity(0.35), fill: false)
                }
                .frame(height: 120)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(dark ? 0.06 : 0.035)))
                VStack(alignment: .leading, spacing: 12) {
                    Legend(color: Color.primary.opacity(0.1), title: String(localized: "Idle"), value: Format.percent(c.idle))
                    Legend(color: Color.primary.opacity(0.85), title: String(localized: "User (apps)"), value: Format.percent(c.user))
                    Legend(color: Color.primary.opacity(0.35), title: String(localized: "System"), value: Format.percent(c.system))
                }
                .frame(width: 130, alignment: .leading)
            }
            HStack(spacing: 10) {
                InfoTile(title: String(localized: "Uptime"), value: Format.uptime(CPUMonitor.uptime),
                         text: CPUMonitor.uptime > 7 * 86_400 ? String(localized: "On for more than a week. Restarting now and then frees memory and caches.") : String(localized: "Restarted recently."))
                InfoTile(title: String(localized: "Average Load"), value: state.cpuHistory.isEmpty ? "—" : Format.percent(state.cpuHistory.map(\.busy).reduce(0, +) / Double(state.cpuHistory.count)),
                         text: String(localized: "Average over the charted period. Short spikes are normal when opening apps and compiling."))
            }
            if let t = state.thermal, let chip = t.chip {
                HStack(spacing: 10) {
                    InfoTile(title: String(localized: "Chip Temperature"), value: Format.celsius(chip),
                             text: String(localized: "\(t.stateLabel). Hottest point: \(t.chipMax.map(Format.celsius) ?? "—"). Up to about 95 °C under load is normal for M chips."))
                    if let b = t.battery {
                        InfoTile(title: String(localized: "Battery"), value: Format.celsius(b),
                                 text: t.ssd.map { String(localized: "SSD at \(Format.celsius($0)). The battery ages faster above 35 °C; avoid charging your Mac in a stuffy place.") } ?? String(localized: "The battery ages faster above 35 °C; avoid charging your Mac in a stuffy place."))
                    }
                }
            }
            ConsumersList(rows: state.topByCPU, value: { "\($0.cpu.formatted(.number.precision(.fractionLength(1))))%" }, unit: String(localized: "% CPU"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Network

private struct NetworkCard: View {
    @Environment(AppState.self) private var state
    var body: some View {
        MetricCard(key: "network", symbol: "wifi", title: state.wifi?.ssid ?? (state.wifi != nil ? "Wi‑Fi" : String(localized: "Network"))) {
            let n = state.net ?? NetworkSample(downBytesPerSec: 0, upBytesPerSec: 0)
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("↓ \(Format.rate(n.downBytesPerSec))").font(.system(size: 15, weight: .semibold)).monospacedDigit().tracking(-0.3)
                    Text("↑ \(Format.rate(n.upBytesPerSec))").font(.system(size: 12.5, weight: .medium)).monospacedDigit().foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Sparkline(values: normalized(state.netHistory.map(\.downBytesPerSec)), color: .primary).frame(height: 34)
            if let r = state.speedResult {
                Text("Test: ↓ \(Format.mbps(r.downloadMbps)) · ↑ \(Format.mbps(r.uploadMbps)) · \(r.latencyMs.safeInt) ms")
                    .font(.system(size: 12, weight: .medium)).monospacedDigit().lineLimit(1)
            } else if let w = state.wifi, let rate = w.transmitRateMbps {
                Text(String(localized: "Link \(rate.safeInt) Mb/s") + (w.security.map { " · \($0)" } ?? "")).font(.system(size: 12, weight: .medium))
            } else {
                Text(state.wifi == nil ? String(localized: "Wired connection or Wi‑Fi off") : String(localized: "Wi‑Fi connected")).font(.system(size: 12, weight: .medium))
            }
            Spacer(minLength: 2)
            HStack(spacing: 8) {
                if state.speedTesting {
                    ProgressView().controlSize(.small)
                    Text("Measuring…").font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    PillButton(title: String(localized: "Test Speed"), systemImage: "gauge.with.needle", prominent: false, compact: true) { state.runSpeedTest() }
                }
            }
        }
    }
    private func normalized(_ v: [Double]) -> [Double] {
        let m = max(v.max() ?? 1, 1)
        return v.map { $0 / m }
    }
}

private struct NetworkDetail: View {
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let dark = scheme == .dark
        let n = state.net ?? NetworkSample(downBytesPerSec: 0, upBytesPerSec: 0)
        VStack(alignment: .leading, spacing: 16) {
            Text("Network").font(.system(size: 17, weight: .semibold)).tracking(-0.3)
            HStack(spacing: 12) {
                Image(systemName: state.wifi == nil ? "cable.connector" : "wifi").font(.system(size: 22, weight: .medium))
                VStack(alignment: .leading, spacing: 1) {
                    Text(state.wifi?.ssid ?? (state.wifi != nil ? String(localized: "Wi‑Fi Network") : String(localized: "Wired Connection"))).font(.system(size: 14, weight: .semibold))
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if let w = state.wifi, let rssi = w.rssi {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(rssi) dBm").font(.system(size: 12.5, weight: .medium)).monospacedDigit()
                        Text(rssi > -60 ? String(localized: "excellent signal") : rssi > -70 ? String(localized: "good signal") : String(localized: "weak signal")).font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(dark ? 0.08 : 0.04)))
            HStack(spacing: 10) {
                ThroughputTile(title: String(localized: "Download"), total: state.netTotals?.received, rate: n.downBytesPerSec, history: state.netHistory.map(\.downBytesPerSec))
                ThroughputTile(title: String(localized: "Upload"), total: state.netTotals?.sent, rate: n.upBytesPerSec, history: state.netHistory.map(\.upBytesPerSec))
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Test Connection").font(.system(size: 13, weight: .semibold))
                HStack(spacing: 16) {
                    if state.speedTesting {
                        ProgressView().controlSize(.small)
                        Text("Downloading 40 MB and uploading 12 MB…").font(.system(size: 11.5)).foregroundStyle(.secondary)
                    } else {
                        PillButton(title: String(localized: "Test Speed"), systemImage: "gauge.with.needle") { state.runSpeedTest() }
                        if let r = state.speedResult {
                            HStack(spacing: 14) {
                                Fact(title: String(localized: "Download"), value: Format.mbps(r.downloadMbps))
                                Fact(title: String(localized: "Upload"), value: Format.mbps(r.uploadMbps))
                                Fact(title: String(localized: "Latency"), value: "\(r.latencyMs.safeInt) ms")
                            }
                        }
                    }
                    Spacer()
                }
                if let e = state.speedError { Text(e).font(.system(size: 11)).foregroundStyle(Theme.destructive) }
                Text("The test uses Cloudflare's public servers and runs only when you click. Nothing is measured in the background.")
                    .font(.system(size: 10.5)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var subtitle: String {
        guard let w = state.wifi else { return String(localized: "Interface \(NetworkMonitor.primaryInterface())") }
        var parts: [String] = [String(localized: "Wi‑Fi on \(w.interface)")]
        if let s = w.security { parts.append(s) }
        if let r = w.transmitRateMbps { parts.append(String(localized: "link \(r.safeInt) Mb/s")) }
        if let ch = w.channel { parts.append(String(localized: "channel \(ch)")) }
        return parts.joined(separator: " · ")
    }
}

private struct ThroughputTile: View {
    let title: String
    let total: UInt64?
    let rate: Double
    let history: [Double]
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let m = max(history.max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12.5, weight: .semibold))
            HStack {
                Text(total.map { Format.bytes(Int64(clamping: $0)) } ?? "—").font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Text(Format.rate(rate)).font(.system(size: 11, weight: .medium)).monospacedDigit()
            }
            Sparkline(values: history.map { $0 / m }, color: .primary.opacity(0.8)).frame(height: 44)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(scheme == .dark ? 0.08 : 0.04)))
    }
}

// MARK: - Goals

private struct GoalsSummaryCard: View {
    @Environment(AppState.self) private var state
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle(symbol: "list.bullet.rectangle", title: String(localized: "Goals"))
            HStack(spacing: 0) {
                ForEach(Goal.scanning) { g in
                    HStack(spacing: 10) {
                        GoalIcon(goal: g, size: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(g.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                            Text(status(g)).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                    if g != Goal.scanning.last { Divider().frame(height: 28).padding(.horizontal, 12) }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(corner: Theme.cornerXL)
    }

    private func status(_ g: Goal) -> String {
        if g == .map {
            if state.isScanning { return String(localized: "scanning…") }
            if let r = state.rootNode {
                return Format.bytes(r.allocatedSize)
            }
            return state.savedMap.map { Format.bytes($0.allocatedSize) } ?? String(localized: "not scanned yet")
        }
        if state.goalScanning.contains(g) { return String(localized: "scanning…") }
        return state.goalStatus(g) ?? (state.goalResults[g] == nil ? String(localized: "not scanned yet") : String(localized: "scanned"))
    }
}
