import Foundation
import WidgetKit
import os

private let bridgeLog = Logger(subsystem: "com.rafabitt.legroom", category: "widget")

/// App → widget bridge (v8). Writes a `WidgetSnapshot` to the App Group and asks
/// WidgetKit to reload timelines when something the widget shows has changed:
/// volumes reread (end of a scan, a trip to the Trash), a goal's summary, a
/// confirmed removal. Metric rounds (1.5 s on the Overview) rewrite the snapshot
/// at most once a minute and never request a reload on their own: the widget
/// reads memory and CPU by itself every 15 min.
@MainActor
enum WidgetBridge {
    enum Reason { case metrics, state }

    /// Last content that triggered a reload (nil when the app opens: the first one always reloads).
    private static var last: WidgetSnapshot?
    private static var lastMetricsWrite = Date.distantPast
    private static var pending: Task<Void, Never>?

    static func publish(_ state: AppState, _ reason: Reason) {
        switch reason {
        case .metrics:
            guard Date().timeIntervalSince(lastMetricsWrite) >= 60 else { return }
            lastMetricsWrite = Date()
            // Doesn't touch `last`: it holds what the widget already received in a reload.
            make(state).write()
        case .state:
            // Coalesces bursts (refreshVolumes + the goal summary arrive together).
            pending?.cancel()
            pending = Task { @MainActor [weak state] in
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled, let state else { return }
                let snap = make(state)
                let changed = last.map { !snap.sameContent(as: $0) } ?? true
                guard snap.write() else { bridgeLog.error("snapshot: App Group unavailable"); return }
                last = snap
                lastMetricsWrite = Date()
                bridgeLog.notice("snapshot written, reload: \(changed, privacy: .public)")
                if changed { WidgetCenter.shared.reloadAllTimelines() }
            }
        }
    }

    private static func make(_ s: AppState) -> WidgetSnapshot {
        let v = s.bootVolume
        return WidgetSnapshot(
            written: Date(),
            volumeName: v?.name,
            totalCapacity: v?.totalCapacity,
            availableCapacity: v?.free,
            memoryUsed: s.memory?.used,
            memoryTotal: s.memory?.total,
            cpuBusy: s.cpu?.busy,
            cpuHistory: s.cpuHistory.suffix(30).map(\.busy),
            trashedBytesTotal: s.trashedBytesTotal,
            trashedItemsTotal: s.trashedItemsTotal,
            lastTrashDate: s.lastTrashDate,
            goals: Goal.scanning.map { WidgetSnapshot.GoalLine(title: $0.title, symbol: $0.symbol, status: status(s, $0)) })
    }

    /// Same text as the Overview's Goals card.
    private static func status(_ s: AppState, _ g: Goal) -> String {
        if g == .map {
            if s.isScanning { return String(localized: "scanning…") }
            return s.rootNode.map { String(localized: "\(Format.bytes($0.allocatedSize)) mapped") } ?? String(localized: "not scanned yet")
        }
        if s.goalScanning.contains(g) { return String(localized: "scanning…") }
        return s.goalSummary[g] ?? (s.goalResults[g] == nil ? String(localized: "not scanned yet") : String(localized: "scanned"))
    }
}
