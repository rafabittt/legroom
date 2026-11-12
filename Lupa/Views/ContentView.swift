import SwiftUI

enum ViewMode: Hashable { case map, list, split }

struct ContentView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        ZStack {
            AppBackground(health: state.health, goal: state.goal)
            HStack(spacing: 4) {
                SidebarView()
                VStack(spacing: 0) {
                    if state.goal != .home { VolumeHeaderView() }
                    Group {
                        if state.goal == .home {
                            HomeView()
                        } else if state.goal != .map {
                            GoalScreen(goal: state.goal)
                        } else if state.isScanning {
                            ScanProgressView()
                        } else if let root = state.rootNode, let current = state.currentNode {
                            ResultsView(root: root, current: current)
                        } else {
                            StartView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(state.goal == .map ? "map" : (state.goal == .home ? "home" : "goal"))
                    .animation(.spring(response: 0.35, dampingFraction: 0.9), value: state.goal)
                }
                // the invisible toolbar (there only to lower the window buttons) must not push the content down
                .padding(.top, 28)
                .ignoresSafeArea(.container, edges: .top)
            }
        }
        .background(TrafficLightsPlacement(x: 30, y: 28).frame(width: 0, height: 0))
        .task { DebugLaunch.handle(state: state) }
        .alert("Error", isPresented: Binding(get: { state.errorMessage != nil },
                                            set: { if !$0 { state.errorMessage = nil } })) {
            Button("OK") { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "")
        }
        .confirmationDialog(
            trashTitle,
            isPresented: Binding(get: { !state.pendingTrash.isEmpty },
                                 set: { if !$0 { state.pendingTrash = [] } }),
            titleVisibility: .visible
        ) {
            Button(allApps ? String(localized: "Uninstall") : String(localized: "Move to Trash"), role: .destructive) { state.confirmTrash() }
            Button("Cancel", role: .cancel) { state.pendingTrash = [] }
        } message: {
            Text(trashMessage)
        }
        .sheet(isPresented: Binding(get: { state.pendingUninstall != nil },
                                    set: { if !$0 { state.pendingUninstall = nil } })) {
            UninstallSheet()
        }
    }

    private var allApps: Bool { !state.pendingTrash.isEmpty && state.pendingTrash.allSatisfy { $0.category == .application } }

    private var trashTitle: String {
        let p = state.pendingTrash
        if allApps {
            return p.count == 1 ? String(localized: "Uninstall \"\((p[0].name as NSString).deletingPathExtension)\"?") : String(localized: "Uninstall \(p.count) apps?")
        }
        if p.count == 1 { return String(localized: "Move \"\(p[0].name)\" to the Trash?") }
        return String(localized: "Move \(p.count) items to the Trash?")
    }

    private var trashMessage: String {
        let p = state.pendingTrash
        let bytes = p.reduce(0) { $0 + $1.allocatedSize }
        let files = p.reduce(0) { $0 + max(1, $1.fileCount) }
        var s = allApps
            ? String(localized: "\(Format.bytes(bytes)). The app moves to the Trash, where you can restore it.")
            : (files == 1
                ? String(localized: "\(Format.bytes(bytes)) in 1 file. Nothing is permanently deleted: you can restore it from the Trash.")
                : String(localized: "\(Format.bytes(bytes)) in \(Format.count(files)) files. Nothing is permanently deleted: you can restore them from the Trash."))
        if p.count == 1 { s += "\n\n" + p[0].path }
        else { s += "\n\n" + p.prefix(6).map(\.name).joined(separator: "\n") + (p.count > 6 ? "\n" + String(localized: "… and \(p.count - 6) more") : "") }
        return s
    }
}

struct StartView: View {
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            if let source = state.selectedSource {
                VStack(spacing: 8) {
                    Text("What's taking up space on \(source.label)?")
                        .font(.system(size: 26, weight: .semibold)).tracking(-0.6)
                    Text("Legroom scans the disk once and answers the questions in the sidebar. Nothing runs on its own: the scan starts only when you hold the button. Nothing is deleted unless you ask, and removed items go to the Trash.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).frame(maxWidth: 480)
                }
                HoldButton(title: String(localized: "Hold to Scan \(source.label)"), fill: state.health.accent(dark: scheme == .dark)) {
                    state.startScan()
                }
                .frame(width: 340)
                .padding(.top, 10)
                HStack(spacing: 6) {
                    Image(systemName: state.health.symbol).foregroundStyle(state.health.accent(dark: scheme == .dark))
                    Text(state.health.label).font(.system(size: 12, weight: .medium))
                    Text("·").foregroundStyle(.tertiary)
                    Text(source.url.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
                }
                .padding(.top, 6)
            } else {
                Text("Choose a volume in the sidebar.").foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

struct ResultsView: View {
    @Environment(AppState.self) private var state
    let root: FileNode
    let current: FileNode

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 12) {
            GoalHeader(goal: .map) {
                PillTabs(items: [(ViewMode.map, String(localized: "Map"), "square.grid.3x3.topleft.filled"),
                                 (ViewMode.list, String(localized: "List"), "list.bullet"),
                                 (ViewMode.split, String(localized: "Both"), "rectangle.split.2x1")],
                         selection: $state.viewMode)
                if let d = state.mapDate {
                    MapDateLabel(date: d, restored: state.mapRestored)
                }
                RefreshButton { state.startScan() }
            }
            .padding(.horizontal, 24)

            ZStack(alignment: .bottom) {
                VStack(spacing: 12) {
                    BreadcrumbView(root: root, current: current).padding(.horizontal, 2)
                    Group {
                        switch state.viewMode {
                        case .map:
                            TreemapView(node: current)
                        case .list:
                            FileListView(node: current)
                        case .split:
                            // No HSplitView: the AppKit divider and the table resizing in the
                            // same pass fell into a layout loop that crashed the app
                            // (the Nov 10 crash). The list has a fixed width; the map gets the rest.
                            HStack(spacing: 0) {
                                TreemapView(node: current).frame(minWidth: 320, maxWidth: .infinity).layoutPriority(1)
                                Divider()
                                FileListView(node: current, compact: true).frame(width: 400)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerL, style: .continuous))
                    .contentCard()
                }
                .padding(.bottom, 148)

                DetailView(node: state.selectedNode ?? current, isCurrentFolder: state.selectedNode == nil)
                    .navigationGlass(corner: Theme.cornerL)

                TrashNotice()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }
}

/// Screen for a goal other than the Map: scans only that goal's scopes and shows the result.
struct GoalScreen: View {
    @Environment(AppState.self) private var state
    let goal: Goal

    var body: some View {
        let result = state.goalResults[goal]
        let scanning = state.goalScanning.contains(goal)
        VStack(spacing: 12) {
            GoalHeader(goal: goal) {
                if let result, !scanning {
                    if result.fromMap {
                        MapDateLabel(date: result.finished, restored: true, prefix: String(localized: "from Map, scanned"))
                    } else {
                        Text("scanned in \(Format.seconds(result.duration))")
                            .font(.system(size: 11)).foregroundStyle(.tertiary).monospacedDigit()
                    }
                }
                if scanning {
                    PillButton(title: String(localized: "Cancel"), systemImage: "xmark", prominent: false) { state.cancelGoal(goal) }
                } else if result != nil {
                    RefreshButton { state.runGoal(goal) }
                }
            }
            .padding(.horizontal, 24)

            ZStack(alignment: .bottom) {
                Group {
                    if let result, !result.roots.isEmpty || !scanning {
                        Group {
                            switch goal {
                            case .cleanup: CleanupView(roots: result.roots, key: result.key ^ state.treeVersion)
                            case .large: LargeFilesView(roots: result.roots, key: result.key ^ state.treeVersion)
                            case .apps: AppsView(roots: result.roots, key: result.key ^ state.treeVersion)
                            case .clutter: ClutterView(roots: result.roots, key: result.key ^ state.treeVersion)
                            case .map, .home: EmptyView()
                            }
                        }
                        .opacity(scanning ? 0.45 : 1)
                        .allowsHitTesting(!scanning)
                    } else if scanning {
                        GoalProgressView(goal: goal)
                    } else {
                        // nothing runs on its own: the user asks for the scan
                        VStack(spacing: 18) {
                            GoalIcon(goal: goal, size: 64, prominent: true)
                            VStack(spacing: 6) {
                                Text(goal.question).font(.system(size: 22, weight: .semibold)).tracking(-0.4)
                                Text(goal.promise).font(.system(size: 13)).foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center).frame(maxWidth: 440)
                            }
                            PillButton(title: String(localized: "Scan Now"), systemImage: "arrow.right") { state.runGoal(goal) }
                                .keyboardShortcut(.defaultAction)
                            Text(goal.scopes(source: state.selectedSource).map { $0.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }.joined(separator: " · "))
                                .font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(2).multilineTextAlignment(.center).frame(maxWidth: 640)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(.bottom, state.selectedNode == nil ? 0 : 148)
                .transition(.focus)

                if let n = state.selectedNode {
                    DetailView(node: n, isCurrentFolder: false)
                        .navigationGlass(corner: Theme.cornerL)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if scanning, state.goalResults[goal] != nil {
                    GoalProgressStrip(goal: goal).padding(.bottom, state.selectedNode == nil ? 8 : 156)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                TrashNotice()
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: state.selectedNode == nil)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: scanning)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .onChange(of: goal) { _, _ in state.selectedNode = nil }
    }
}

/// Scan of a goal with no previous result: the goal icon pulsing,
/// the scopes being scanned, counters rolling.
struct GoalProgressView: View {
    @Environment(AppState.self) private var state
    let goal: Goal
    var body: some View {
        let p = state.goalProgress[goal] ?? ScanProgress()
        VStack(spacing: 18) {
            GoalIcon(goal: goal, size: 64, prominent: true)
                .symbolEffect(.pulse, options: .repeating, isActive: true)
            Text(goal.scanningLabel + "…").font(.system(size: 20, weight: .semibold))
            HStack(spacing: 24) {
                Stat(title: String(localized: "Files"), value: Format.count(p.files))
                Stat(title: String(localized: "Folders"), value: Format.count(p.directories))
                Stat(title: String(localized: "On Disk"), value: Format.bytes(p.allocatedBytes))
            }
            Text(p.currentPath).font(.caption.monospaced()).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle).frame(maxWidth: 640)
            Text(goal.scopes(source: state.selectedSource).map { $0.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }.joined(separator: " · "))
                .font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(2).multilineTextAlignment(.center).frame(maxWidth: 720)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private struct Stat: View {
        let title: String; let value: String
        var body: some View {
            VStack(spacing: 2) {
                RollingNumber(text: value, font: .system(size: 24, weight: .semibold))
                Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}

/// Rescan with an older result on screen: a thin strip at the bottom instead of a full screen.
struct GoalProgressStrip: View {
    @Environment(AppState.self) private var state
    let goal: Goal
    var body: some View {
        let p = state.goalProgress[goal] ?? ScanProgress()
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(goal.scanningLabel).font(.system(size: 12, weight: .medium))
            Text("\(Format.count(p.files)) files · \(Format.bytes(p.allocatedBytes))").font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Capsule().fill(.thinMaterial))
    }
}

struct RefreshButton: View {
    let action: () -> Void
    @State private var hover = false
    @State private var spins = 0.0
    var body: some View {
        Button {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { spins += 360 }
            action()
        } label: {
            Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold))
                .rotationEffect(.degrees(spins + (hover ? 30 : 0)))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .background(Circle().fill(.regularMaterial))
        .overlay(Circle().strokeBorder(Color.primary.opacity(hover ? 0.18 : 0.08), lineWidth: 1))
        .shadow(color: .black.opacity(hover ? 0.12 : 0), radius: 8, y: 4)
        .scaleEffect(hover ? 1.06 : 1)
        .onHover { h in withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { hover = h } }
        .help("Scan Again")
    }
}

/// Small round button (back) with the same cursor reaction as RefreshButton.
struct RoundIconButton: View {
    let systemImage: String
    var disabled = false
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.system(size: 12, weight: .semibold)).frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .background(Circle().fill(.regularMaterial))
        .overlay(Circle().strokeBorder(Color.primary.opacity(hover && !disabled ? 0.18 : 0.08), lineWidth: 1))
        .shadow(color: .black.opacity(hover && !disabled ? 0.12 : 0), radius: 8, y: 4)
        .scaleEffect(hover && !disabled ? 1.06 : 1)
        .onHover { h in withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { hover = h } }
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }
}

/// Green notice shown for 4 s after moving to the Trash.
struct TrashNotice: View {
    @Environment(AppState.self) private var state
    var body: some View {
        if let notice = state.trashNotice {
            Label(notice, systemImage: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .foregroundStyle(.white)
                .background(Capsule().fill(Theme.success))
                .shadow(color: Theme.success.opacity(0.3), radius: 12, y: 6)
                .padding(.bottom, 152)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: notice)
        }
    }
}

/// "Focus" transition: opacity + blur 6→0 + scale 0.98→1 (react-bits: a crossfade that
/// reads as focusing rather than fading). Entering takes longer than leaving.
struct FocusTransition: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        content
            .opacity(active ? 0 : 1)
            .blur(radius: active ? 6 : 0)
            .scaleEffect(active ? 0.98 : 1)
    }
}

extension AnyTransition {
    static var focus: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: FocusTransition(active: true), identity: FocusTransition(active: false))
                .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.35)),
            removal: .modifier(active: FocusTransition(active: true), identity: FocusTransition(active: false))
                .animation(.easeIn(duration: 0.14)))
    }
}

/// Staggered entrance of the cards when results arrive: rises 16 pt, scales 0.97 → 1.
struct StaggeredAppear: ViewModifier {
    let index: Int
    let trigger: AnyHashable
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 16)
            .scaleEffect(shown || reduceMotion ? 1 : 0.97)
            .onAppear { reveal() }
            .onChange(of: trigger) { _, _ in shown = false; reveal() }
    }
    private func reveal() {
        withAnimation(.spring(response: 0.62, dampingFraction: 0.78).delay(Double(index) * 0.06)) { shown = true }
    }
}

extension View {
    func staggeredAppear(index: Int, trigger: AnyHashable) -> some View {
        modifier(StaggeredAppear(index: index, trigger: trigger))
    }
}

struct BreadcrumbView: View {
    @Environment(AppState.self) private var state
    let root: FileNode
    let current: FileNode

    private var chain: [FileNode] { current.ancestors + [current] }

    var body: some View {
        HStack(spacing: 8) {
            Button { state.goUp() } label: {
                Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .background(Circle().fill(.thinMaterial))
            .disabled(current.parent == nil)
            .opacity(current.parent == nil ? 0.4 : 1)
            .help("Go to Enclosing Folder")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(chain) { node in
                        if node !== chain.first {
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
                        }
                        Button { state.navigate(to: node) } label: {
                            Text(node === root ? (state.selectedSource?.label ?? root.name) : node.name)
                                .font(.system(size: 13, weight: node === current ? .semibold : .regular))
                                .foregroundStyle(node === current ? .primary : .secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(node === current)
                    }
                }
            }
            Text("\(Format.bytes(current.allocatedSize)) · \(Format.count(current.fileCount)) items")
                .font(.system(size: 12, weight: .medium)).monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(.regularMaterial))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        }
    }
}

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @AppStorage(AppearanceMode.key) private var appearance: AppearanceMode = .system
    @AppStorage(MenuBarPrefs.show) private var showMenuBar = true
    @AppStorage(MenuBarPrefs.freePercent) private var showFreePercent = false
    var body: some View {
        @Bindable var state = state
        Form {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppearanceMode.allCases) { m in Label(m.title, systemImage: m.symbol).tag(m) }
            }
            .pickerStyle(.segmented)
            Toggle("Show hidden files and folders", isOn: $state.showHidden)
            Toggle("Show in menu bar", isOn: $showMenuBar)
            Toggle("Show % free next to the icon", isOn: $showFreePercent)
                .disabled(!showMenuBar)
                .padding(.leading, 18)
            Text("Sizes always show the space allocated on disk (what you get back as free space when you delete). The logical size appears in the details panel.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(width: 420)
    }
}

/// "scanned 2 days ago" in the header of the Map and of the tabs derived from it.
struct MapDateLabel: View {
    let date: Date
    var restored: Bool
    var prefix = String(localized: "scanned")
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            Text("\(prefix) \(Format.since(date, now: ctx.date))")
                .font(.system(size: 11)).foregroundStyle(.tertiary).monospacedDigit()
        }
        .help("Scanned on \(date.formatted(date: .long, time: .shortened)). The disk may have changed since then; use Scan Again to update.")
    }
}
