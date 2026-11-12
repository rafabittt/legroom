import SwiftUI
import AppKit

/// Menu bar item preferences (UserDefaults).
enum MenuBarPrefs {
    /// Show the item in the menu bar. On by default.
    static let show = "menuBar.show"
    /// Show the disk's free % next to the icon. Off by default.
    static let freePercent = "menuBar.freePercent"

    static var isShown: Bool { UserDefaults.standard.object(forKey: show) as? Bool ?? true }
}

// MARK: - Icon

/// The Legroom mark (icon outline, the two bars and the dash between them)
/// redrawn as an 18 pt template image: macOS paints it black or white
/// to match the menu bar, like the system icons.
enum MenuBarIcon {
    static let image: NSImage = {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()
            let frame = NSBezierPath(roundedRect: NSRect(x: 1.65, y: 1.65, width: 14.7, height: 14.7), xRadius: 4.4, yRadius: 4.4)
            frame.lineWidth = 1.3
            frame.stroke()
            // bar (seat), dash (the legroom), bar (floor)
            let parts: [(w: CGFloat, h: CGFloat)] = [(8.6, 2.5), (3.6, 1.2), (8.6, 2.5)]
            let gap: CGFloat = 1.45
            var y = (18 - (parts.map(\.h).reduce(0, +) + gap * 2)) / 2
            for p in parts {
                NSBezierPath(roundedRect: NSRect(x: (18 - p.w) / 2, y: y, width: p.w, height: p.h), xRadius: p.h / 2, yRadius: p.h / 2).fill()
                y += p.h + gap
            }
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "Legroom"
        return img
    }()
}

/// What shows in the menu bar: just the icon; the free % is optional (Settings).
struct MenuBarLabel: View {
    @Environment(AppState.self) private var state
    @AppStorage(MenuBarPrefs.freePercent) private var showPercent = false

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: MenuBarIcon.image)
            if showPercent, let v = state.bootVolume, v.totalCapacity > 0 {
                Text("\(Format.percent(Double(v.free) / Double(v.totalCapacity))) free")
                    .monospacedDigit()
            }
        }
        .task(id: showPercent) {
            // With the % on (the user's choice), re-reads only the volume capacity
            // (a single statfs call, not a scan) every minute so the number stays accurate.
            guard showPercent else { return }
            while !Task.isCancelled {
                DebugLaunch.verboseLog("re-reading volume capacity for the menu bar %")
                state.refreshVolumes()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }
}

// MARK: - Popover

/// Mini overview of the Mac in the menu bar: disk, memory, CPU, network and
/// what Legroom has freed so far, with the same look as the Overview. Readings only while
/// the popover is open; no disk scan ever starts from here.
struct MenuBarPanel: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var systemScheme
    @AppStorage(AppearanceMode.key) private var appearance: AppearanceMode = .system
    @State private var isOpen = false

    /// The popover's window, for the development capture (`--menubar`).
    static weak var hostWindow: NSWindow?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            MiniDiskCard()
            MiniMemoryCard()
            MiniCPUCard()
            MiniNetworkCard()
            MiniFreedRow()
            footer.padding(.top, 4)
        }
        .padding(12)
        .frame(width: 320)
        .background(AppBackground())
        // appearance chosen in the app (Match Mac / Light / Dark), without .preferredColorScheme
        .environment(\.colorScheme, appearance.colorScheme ?? systemScheme)
        .background(WindowVisibilityReporter { open in
            guard open != isOpen else { return }
            DebugLaunch.verboseLog(open ? "menu bar popover visible at \(Self.hostWindow?.frame ?? .zero)" : "menu bar popover closed")
            isOpen = open
            if open { Self.applyAppearance(appearance) }
        })
        .onChange(of: appearance) { _, a in Self.applyAppearance(a) }
        .task(id: isOpen) {
            Trail.note("menu bar: \(isOpen ? "open" : "closed")")
            guard isOpen else { return }
            // volume capacity is an instant read; the map is never scanned from here
            state.refreshVolumes()
            await state.withMetrics("barra")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            LegroomMark(size: 20)
            Text("Legroom").font(.system(size: 13, weight: .semibold)).tracking(-0.2)
            Spacer()
            Text(Date().formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11)).foregroundStyle(.tertiary).monospacedDigit()
        }
        .padding(.horizontal, 4).padding(.bottom, 2)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            PillButton(title: String(localized: "Open Legroom"), prominent: true, compact: true) { Self.bringMainWindowForward(openWindow) }
            Spacer()
            PillButton(title: String(localized: "Quit"), prominent: false, compact: true) { NSApp.terminate(nil) }
                .help("Quits Legroom and removes its icon from the menu bar")
        }
    }

    /// The popover's frame (border, shadow) follows the app's appearance.
    @MainActor static func applyAppearance(_ a: AppearanceMode) {
        switch a {
        case .system: hostWindow?.appearance = nil
        case .light: hostWindow?.appearance = NSAppearance(named: .aqua)
        case .dark: hostWindow?.appearance = NSAppearance(named: .darkAqua)
        }
    }

    /// Brings the main window to the front; if it was closed, opens a new one.
    @MainActor static func bringMainWindowForward(_ openWindow: OpenWindowAction) {
        NSApp.activate(ignoringOtherApps: true)
        if let w = NSApp.windows.first(where: { ($0.identifier?.rawValue ?? "").hasPrefix(LegroomApp.mainWindowID) && ($0.isVisible || $0.isMiniaturized) }) {
            if w.isMiniaturized { w.deminiaturize(nil) }
            w.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: LegroomApp.mainWindowID)
        }
        hostWindow?.orderOut(nil)
    }
}

/// Reports when the window containing the view becomes visible or goes away. MenuBarExtra
/// keeps the view alive between openings, so onAppear/onDisappear aren't enough.
private struct WindowVisibilityReporter: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }
    func makeNSView(context: Context) -> NSView {
        let v = ReporterView()
        v.coordinator = context.coordinator
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) { context.coordinator.onChange = onChange }

    final class ReporterView: NSView {
        weak var coordinator: Coordinator?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            coordinator?.attach(to: window)
        }
    }

    final class Coordinator {
        var onChange: (Bool) -> Void
        private weak var window: NSWindow?
        private var observers: [NSObjectProtocol] = []
        init(onChange: @escaping (Bool) -> Void) { self.onChange = onChange }
        deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

        func attach(to window: NSWindow?) {
            guard let window, window !== self.window else { return }
            self.window = window
            MenuBarPanel.hostWindow = window
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            let names: [Notification.Name] = [NSWindow.didChangeOcclusionStateNotification, NSWindow.didBecomeKeyNotification,
                                              NSWindow.didResignKeyNotification, NSWindow.willCloseNotification,
                                              NSWindow.didMiniaturizeNotification]
            observers = names.map { name in
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] n in
                    self?.report(closing: n.name == NSWindow.willCloseNotification)
                }
            }
            report(closing: false)
        }

        private func report(closing: Bool) {
            guard let window else { return }
            let open = !closing && window.isVisible && window.occlusionState.contains(.visible)
            onChange(open)
        }
    }
}

// MARK: - Compact cards

private struct MiniCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 7) { content }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentCard(corner: Theme.cornerL)
    }
}

private struct MiniDiskCard: View {
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let dark = scheme == .dark
        let health = state.bootHealth
        let accent = health.accent(dark: dark)
        let shape = RoundedRectangle(cornerRadius: Theme.cornerL, style: .continuous)
        HStack(spacing: 14) {
            if let v = state.bootVolume {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.08), lineWidth: 6)
                    Circle().trim(from: 0, to: max(0.01, v.usedFraction))
                        .stroke(accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.9, dampingFraction: 1.0), value: v.usedFraction)
                    RollingNumber(text: "\((v.usedFraction * 100).rounded().safeInt)%", font: .system(size: 14, weight: .semibold), tracking: -0.3)
                }
                .frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: 4) {
                    CardTitle(symbol: "internaldrive", title: v.name)
                    HStack(spacing: 6) {
                        Image(systemName: health.symbol).font(.system(size: 13)).foregroundStyle(accent)
                        Text(health.label).font(.system(size: 15, weight: .semibold)).tracking(-0.3).lineLimit(1)
                    }
                    Text("\(Format.bytes(v.free)) free of \(Format.bytes(v.totalCapacity))")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                }
                Spacer(minLength: 0)
            } else {
                Text("No volume found.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            shape.fill(Theme.card(dark))
                .overlay {
                    Circle().fill(accent).frame(width: 130, height: 130).blur(radius: 40)
                        .offset(x: -110, y: 20).opacity(0.22)
                        .animation(.easeInOut(duration: 1.0), value: accent)
                }
                .clipShape(shape)
                .overlay(shape.strokeBorder(Theme.hairline(dark), lineWidth: 1))
        }
        .shadow(color: .black.opacity(dark ? 0.35 : 0.05), radius: dark ? 14 : 10, y: 4)
    }
}

private struct MiniMemoryCard: View {
    @Environment(AppState.self) private var state
    var body: some View {
        MiniCard {
            // short label: the card title already says "Memory"
            CardTitle(symbol: "memorychip", title: String(localized: "Memory"),
                      trailing: state.memory.map(\.pressureShort))
            if let m = state.memory {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    RollingNumber(text: Format.memory(Int64(m.used)), font: .system(size: 18, weight: .semibold), tracking: -0.5)
                    Text("of \(Format.memory(Int64(m.total)))").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .lineLimit(1).fixedSize()
                MemoryBar(memory: m, height: 6)
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
                .padding(.top, 2)
            } else {
                Text("Couldn't read memory.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
}

private struct MiniCPUCard: View {
    @Environment(AppState.self) private var state
    var body: some View {
        let busy = state.cpu?.busy ?? 0
        MiniCard {
            CardTitle(symbol: "cpu", title: String(localized: "CPU"),
                      trailing: (busy < 0.3 ? String(localized: "relaxed") : busy < 0.7 ? String(localized: "busy") : String(localized: "at its limit"))
                        + (state.thermal?.chip.map { " · " + Format.celsius($0) } ?? ""))
            HStack(alignment: .center, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    RollingNumber(text: Format.percent(busy), font: .system(size: 18, weight: .semibold), tracking: -0.5)
                    Text("in use").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Sparkline(values: Array(state.cpuHistory.map(\.busy).suffix(30)), color: .primary)
                    .frame(height: 24)
            }
            if let top = state.topByCPU.first(where: { $0.isApp }), top.cpu >= 20 {
                PillButton(title: String(localized: "Quit \(top.name)"), systemImage: "xmark", prominent: false, compact: true) { top.quit() }
                    .help("\(top.name) is using \(top.cpu.formatted(.number.precision(.fractionLength(0))))% of the CPU. Asks the app to quit, like ⌘Q.")
            }
        }
    }
}

private struct MiniNetworkCard: View {
    @Environment(AppState.self) private var state
    var body: some View {
        let n = state.net ?? NetworkSample(downBytesPerSec: 0, upBytesPerSec: 0)
        MiniCard {
            CardTitle(symbol: state.wifi == nil ? "network" : "wifi",
                      title: state.wifi?.ssid ?? (state.wifi != nil ? "Wi‑Fi" : String(localized: "Network")))
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("↓ \(Format.rate(n.downBytesPerSec))").font(.system(size: 14, weight: .semibold)).monospacedDigit().tracking(-0.3)
                    Text("↑ \(Format.rate(n.upBytesPerSec))").font(.system(size: 11.5, weight: .medium)).monospacedDigit().foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if state.speedTesting {
                    ProgressView().controlSize(.small)
                    Text("Measuring…").font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    PillButton(title: String(localized: "Test Speed"), systemImage: "gauge.with.needle", prominent: false, compact: true) { state.runSpeedTest() }
                }
            }
            if let r = state.speedResult {
                Text("Test: ↓ \(Format.mbps(r.downloadMbps)) · ↑ \(Format.mbps(r.uploadMbps)) · \(r.latencyMs.safeInt) ms")
                    .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            } else if let e = state.speedError {
                Text(e).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }
}

private struct MiniFreedRow: View {
    @Environment(AppState.self) private var state
    var body: some View {
        let _ = state.trashHistoryVersion
        HStack(spacing: 6) {
            Image(systemName: "trash").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            Text("Freed by Legroom").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if state.trashedItemsTotal > 0 {
                Text(Format.bytes(state.trashedBytesTotal)).font(.system(size: 13, weight: .semibold)).monospacedDigit()
            } else {
                Text("nothing yet").font(.system(size: 12)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(corner: Theme.cornerL)
        .help("Total of everything you moved to the Trash with Legroom")
        .refreshesFreedTotal()
    }
}
