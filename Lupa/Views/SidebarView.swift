import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                LegroomMark(size: 30)
                Text("Legroom").font(.system(size: 17, weight: .semibold)).tracking(-0.3)
                Spacer()
            }
            // the window's close/minimize/zoom buttons sit inside the panel, above the logo
            .padding(.horizontal, 16).padding(.top, 46).padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    GoalRow(goal: .home, selected: state.goal == .home) { state.selectGoal(.home) }
                    SidebarSection(title: String(localized: "Goals")) {
                        ForEach(Goal.scanning) { g in
                            GoalRow(goal: g, selected: state.goal == g) { state.selectGoal(g) }
                        }
                    }
                    SidebarSection(title: String(localized: "Volumes")) {
                        ForEach(state.volumes) { v in
                            SidebarRow(source: .volume(v), selected: isSelected(.volume(v))) {
                                VolumeRowContent(volume: v)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
            }
            Spacer(minLength: 0)
            // system folders (SIP, other users) stay denied even with Full Disk
            // Access; the hint only appears when access is actually missing
            if (state.progress.deniedDirectories > 0 || hasDeniedAtRoot) && !FullDiskAccess.granted {
                FullDiskAccessHint().padding(10)
            }
            AppearanceFooter().padding(.horizontal, 12).padding(.bottom, 12)
        }
        .frame(width: 232)
        .frame(maxHeight: .infinity)
        // the panel is always dark and tinted by the disk's health; everything inside it is light
        .environment(\.colorScheme, .dark)
        .background(sidebarBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
        .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.18), radius: 24, y: 12)
        .padding(.leading, 12).padding(.top, 12).padding(.bottom, 12)
        // extends up under the title bar strip, so the window buttons sit inside the panel
        .ignoresSafeArea(.container, edges: .top)
    }

    @ViewBuilder private var sidebarBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        shape.fill(state.health.panelGradient(dark: scheme == .dark))
            .overlay {
                // the health glow at the top of the panel, in a single color
                Circle().fill(state.health.panelGlow(dark: scheme == .dark))
                    .frame(width: 320, height: 320).blur(radius: 90)
                    .offset(x: -60, y: -170).opacity(0.55)
                    .animation(.easeInOut(duration: 1.0), value: state.health)
            }
            .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.08), .clear], startPoint: .top, endPoint: .center)))
            .clipShape(shape)
    }

    private func isSelected(_ s: ScanSource) -> Bool { state.selectedSource == s }
    private var hasDeniedAtRoot: Bool { state.rootNode?.children.contains { $0.accessDenied } ?? false }
}

private struct SidebarSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold)).tracking(0.6)
                .foregroundStyle(.white.opacity(0.55))
                .padding(.horizontal, 10).padding(.bottom, 4)
            content
        }
    }
}

private struct SidebarRow<Content: View>: View {
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var scheme
    let source: ScanSource
    let selected: Bool
    @ViewBuilder let content: Content
    @State private var hover = false

    var body: some View {
        Button { state.select(source) } label: {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selected ? Color.white.opacity(0.16)
                                       : (hover ? Color.white.opacity(0.07) : .clear)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

/// Goal row in the sidebar: minimal, only the active item gets the goal's color
/// (tile, text, and a 10% background). The others stay gray, with a thin symbol.
private struct GoalRow: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(AppState.self) private var state
    let goal: Goal
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        let dark = scheme == .dark
        Button(action: action) {
            HStack(spacing: 10) {
                GoalIcon(goal: goal, size: 24, prominent: selected)
                VStack(alignment: .leading, spacing: 1) {
                    Text(goal.title)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Color.primary : Color.primary.opacity(0.8))
                        .lineLimit(1)
                    if let summary = status {
                        Text(summary).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1).monospacedDigit()
                    }
                }
                Spacer()
                if scanning {
                    ProgressView().controlSize(.mini)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.16)
                                   : (hover ? Color.white.opacity(0.07) : .clear)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(selected ? 0.12 : 0), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
        .animation(.spring(response: 0.3, dampingFraction: 1.0), value: selected)
        .help(goal.promise)
    }

    private var scanning: Bool { goal == .map ? state.isScanning : state.goalScanning.contains(goal) }
    private var status: String? {
        if goal == .home { return nil }
        if scanning { return goal.scanningLabel + "…" }
        if goal == .map {
            return state.rootNode.map { String(localized: "\(Format.bytes($0.allocatedSize)) mapped") }
        }
        // the saved scan appears only in Overview; here, only what was scanned in this session
        return state.goalSummary[goal]
    }
}

struct VolumeRowContent: View {
    @Environment(\.colorScheme) private var scheme
    let volume: Volume
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(volume.name, systemImage: volume.isRootVolume ? "internaldrive" : "externaldrive")
                .lineLimit(1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14))
                    Capsule().fill(Color.white.opacity(0.9))
                        .frame(width: max(3, geo.size.width * volume.usedFraction))
                }
            }
            .frame(height: 4)
            Text("\(Format.bytes(volume.free)) free of \(Format.bytes(volume.totalCapacity))")
                .font(.system(size: 10.5)).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}

struct FullDiskAccessHint: View {
    @Environment(AppState.self) private var state
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Some folders couldn't be read", systemImage: "lock")
                .font(.system(size: 11, weight: .semibold))
            Text("Give Legroom Full Disk Access and scan again to see everything.")
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
            Button("Open Privacy Settings") { state.openFullDiskAccessSettings() }
                .controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }
}


/// Sidebar footer: switch appearance in one click (Match Mac / Light / Dark).
struct AppearanceFooter: View {
    @AppStorage(AppearanceMode.key) private var appearance: AppearanceMode = .system
    @Environment(\.colorScheme) private var scheme
    @Namespace private var ns
    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppearanceMode.allCases) { m in
                let active = m == appearance
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { appearance = m }
                } label: {
                    Image(systemName: m.symbol).font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: 26)
                        .foregroundStyle(active ? Color.primary : Color.secondary)
                        .background {
                            if active {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(0.18))
                                    .matchedGeometryEffect(id: "mode", in: ns)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(m.title)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }
}


/// The Legroom mark: two bars (seat and floor) and the green gap between them.
/// Same drawing as the AppIcon, at interface size.
struct LegroomMark: View {
    var size: CGFloat = 30
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let dark = scheme == .dark
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(dark ? Color(hex: 0xECECF0) : Color.white)
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
            VStack(spacing: size * 0.1) {
                Capsule().fill(Color(hex: 0x111114)).frame(width: size * 0.62, height: size * 0.145)
                Capsule().fill(LinearGradient(colors: [Color(hex: 0x2DD4BF), Color(hex: 0x22C55E)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: size * 0.26, height: size * 0.06)
                    .shadow(color: Color(hex: 0x22C55E).opacity(0.6), radius: size * 0.06)
                Capsule().fill(Color(hex: 0x111114)).frame(width: size * 0.62, height: size * 0.145)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.18), radius: size * 0.12, y: size * 0.06)
    }
}
