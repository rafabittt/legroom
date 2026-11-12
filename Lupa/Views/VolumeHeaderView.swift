import SwiftUI

/// Volume header: name, path and the indicator cards.
struct VolumeHeaderView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if let v = state.selectedVolume {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(state.selectedSource?.label ?? v.name)
                        .font(.system(size: 24, weight: .semibold)).tracking(-0.5)
                    Text(state.selectedSource?.url.path ?? v.url.path)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text("\(Format.bytes(v.usedCapacity)) of \(Format.bytes(v.totalCapacity)) in use")
                        .font(.system(size: 12, weight: .medium)).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                let trigger = AnyHashable(state.selectedSource?.id ?? "")
                HStack(spacing: 12) {
                    GradientCard(title: String(localized: "Used"), value: v.usedCapacity, kind: .used(state.health),
                                 caption: state.health.label, fraction: v.usedFraction,
                                 help: String(localized: "Apps, files and system. Same number as System Settings › Storage."))
                        .staggeredAppear(index: 0, trigger: trigger)
                    GradientCard(title: String(localized: "Purgeable by System"), value: v.purgeableEstimate, kind: .purgeable,
                                 caption: String(localized: "already counted as available"),
                                 help: String(localized: "Caches and snapshots that macOS clears on its own when it needs space. They're already included in available space, as in System Settings; there's nothing to delete."))
                        .staggeredAppear(index: 1, trigger: trigger)
                    GradientCard(title: String(localized: "Available"), value: v.free, kind: .free,
                                 caption: String(localized: "as in System Settings"))
                        .staggeredAppear(index: 2, trigger: trigger)
                    if let root = state.rootNode {
                        GradientCard(title: String(localized: "Mapped by Legroom"), value: root.allocatedSize, kind: .mapped,
                                     caption: state.mapRestored ? String(localized: "scanned \(state.mapDate.map { Format.since($0) } ?? "")") : String(localized: "\(Format.count(root.fileCount)) items in \(scanTime)"),
                                     help: String(localized: "Differences from 'Used' come from folders without read permission, snapshots and APFS metadata."))
                            .staggeredAppear(index: 3, trigger: trigger)
                            .transition(.focus)
                    }
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: state.rootNode == nil)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 10)
        }
    }

    private var scanTime: String {
        guard let d = state.scanDuration else { return "—" }
        return d < 60 ? "\(d.formatted(.number.precision(.fractionLength(1)))) s" : "\((d / 60).safeInt) min"
    }
}
