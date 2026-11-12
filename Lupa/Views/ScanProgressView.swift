import SwiftUI

/// Full scan in progress: thin ring in the health color (determinate when
/// the target is a volume), rolling counters and a real Cancel button.
struct ScanProgressView: View {
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState

    private var fraction: Double? {
        guard case .volume(let v)? = state.selectedSource, v.usedCapacity > 0 else { return nil }
        return min(0.98, Double(state.progress.allocatedBytes) / Double(v.usedCapacity))
    }

    var body: some View {
        let accent = state.health.accent(dark: scheme == .dark)
        VStack(spacing: 22) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.08), lineWidth: 6)
                if let f = fraction {
                    Circle().trim(from: 0, to: max(0.02, f))
                        .stroke(accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.6, dampingFraction: 1.0), value: f)
                    RollingNumber(text: "\((f * 100).rounded().safeInt)%", font: .system(size: 22, weight: .semibold), tracking: -0.5)
                } else {
                    TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || activeState == .inactive)) { ctx in
                        let t = ctx.date.timeIntervalSinceReferenceDate
                        Circle().trim(from: 0, to: 0.28)
                            .stroke(accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees((t * 140).truncatingRemainder(dividingBy: 360)))
                    }
                    Image(systemName: "magnifyingglass").font(.system(size: 22, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 104, height: 104)
            .padding(.bottom, 6)

            Text(state.selectedSource.map { String(localized: "Scanning \($0.label)…") } ?? String(localized: "Scanning the disk…"))
                .font(.system(size: 22, weight: .semibold)).tracking(-0.4)
            HStack(spacing: 28) {
                Stat(title: String(localized: "Files"), value: Format.count(state.progress.files))
                Stat(title: String(localized: "Folders"), value: Format.count(state.progress.directories))
                Stat(title: String(localized: "On Disk"), value: Format.bytes(state.progress.allocatedBytes))
                if state.progress.deniedDirectories > 0 {
                    Stat(title: String(localized: "No Access"), value: Format.count(state.progress.deniedDirectories))
                }
            }
            Text(state.progress.currentPath)
                .font(.caption.monospaced()).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle).frame(maxWidth: 640)
            PillButton(title: String(localized: "Cancel"), systemImage: "xmark", prominent: false) { state.cancelScan() }
                .keyboardShortcut(.cancelAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private struct Stat: View {
        let title: String
        let value: String
        var body: some View {
            VStack(spacing: 2) {
                RollingNumber(text: value, font: .system(size: 24, weight: .semibold), tracking: -0.5)
                Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}
