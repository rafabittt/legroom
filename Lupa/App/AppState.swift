import SwiftUI
import Observation

enum ScanSource: Hashable, Identifiable {
    case volume(Volume)
    case folder(URL, label: String)

    var id: String {
        switch self {
        case .volume(let v): return "volume:\(v.url.path)"
        case .folder(let u, _): return "folder:\(u.path)"
        }
    }
    var url: URL {
        switch self {
        case .volume(let v): return v.url
        case .folder(let u, _): return u
        }
    }
    var label: String {
        switch self {
        case .volume(let v): return v.name
        case .folder(_, let l): return l
        }
    }
    var systemImage: String {
        switch self {
        case .volume(let v): return v.isRootVolume ? "internaldrive" : (v.isRemovable || v.isEjectable ? "externaldrive" : "externaldrive.fill")
        case .folder(let u, _):
            if u.path == NSHomeDirectory() { return "house" }
            if u.path == "/Applications" { return "square.grid.2x2" }
            return "folder"
        }
    }
}

@MainActor
@Observable
final class AppState {
    var volumes: [Volume] = []
    var selectedSource: ScanSource?
    var rootNode: FileNode?
    var currentNode: FileNode?
    var selectedNode: FileNode?
    var isScanning = false
    var progress = ScanProgress()
    var scanStarted: Date?
    var scanDuration: TimeInterval?
    var errorMessage: String?
    var showHidden = false
    var viewMode: ViewMode = .split
    var goal: Goal = .home
    /// Memory: latest reading and result of the last cleanup (Overview only).
    var memory: MemorySnapshot? = MemorySnapshot.take()
    var memoryCleaning = false
    var memoryOutcome: MemoryCleaner.Outcome?
    var swap: SwapUsage? = SwapUsage.read()

    /// CPU and network: sampled only while the Overview is on screen.
    let cpuMonitor = CPUMonitor()
    let netMonitor = NetworkMonitor()
    /// Total traffic since the Mac started up (netstat); nil until the first reading.
    var netTotals: NetTotals?
    var cpu: CPUSample?
    var cpuHistory: [CPUSample] = []
    var net: NetworkSample?
    var netHistory: [NetworkSample] = []
    var wifi: WiFiInfo?
    var topByCPU: [ProcessInfoRow] = []
    /// Temperatures (chip, battery, SSD); nil until the first reading.
    var thermal: ThermalReading?
    var topByMemory: [ProcessInfoRow] = []
    var speedTesting = false
    var speedResult: SpeedTest.Result?
    var speedError: String?
    private var metricsTicks = 0
    /// Only for screenshots (--popover): opens the popover of an Overview card when it appears.
    var debugOpenMetric: String?
    /// Results per goal (the Map uses rootNode/currentNode).
    var goalResults: [Goal: GoalResult] = [:]
    var goalScanning: Set<Goal> = []
    var goalProgress: [Goal: ScanProgress] = [:]
    /// Short summary each tab publishes for the sidebar ("19.6 GB", "42 apps").
    var goalSummary: [Goal: String] = [:] { didSet { if goalSummary != oldValue { WidgetBridge.publish(self, .state) } } }
    private var goalTokens: [Goal: CancelToken] = [:]
    /// Items awaiting confirmation to go to the Trash (empty = no dialog).
    var pendingTrash: [FileNode] = []
    /// Uninstall under review: the apps and the leftovers found outside the bundle.
    var pendingUninstall: UninstallPlan?
    /// Short notice after moving to the Trash (disappears on its own).
    var trashNotice: String?

    private var cancelToken: CancelToken?
    private var scanTask: Task<Void, Never>?

    // MARK: Last Map scan (saved per volume)

    /// When the in-memory Map tree was scanned (just now or in a saved scan).
    var mapDate: Date?
    /// True when the in-memory tree came from a saved scan.
    var mapRestored = false
    /// Saved scans, per volume (summaries only; the tree stays on disk).
    var savedMaps: [String: SavedMapInfo] = MapStore.loadIndex()
    /// Opening the saved tree of the current volume.
    var restoringMap = false
    private var restoreToken: CancelToken?

    /// A tab's summary for the Overview and the sidebar: the one computed in this session
    /// or, before the saved scan is opened, the one stored with it.
    func goalStatus(_ g: Goal) -> String? {
        goalSummary[g] ?? (rootNode == nil ? savedMap?.summariesForCurrentLanguage[g.rawValue] : nil)
    }

    /// Saved scan of the selected volume (only whole volumes are saved).
    var savedMap: SavedMapInfo? {
        guard let s = selectedSource, case .volume = s else { return nil }
        return savedMaps[s.id]
    }
    let quickLook = QuickLookController()

    var quickLocations: [ScanSource] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        return [
            .folder(home, label: String(localized: "Home")),
            .folder(home.appendingPathComponent("Library"), label: String(localized: "User Library")),
            .folder(URL(fileURLWithPath: "/Applications"), label: String(localized: "Applications")),
        ]
    }

    /// Health of the current volume; drives the palette of the whole app.
    var health: DiskHealth {
        if let healthOverride { return DiskHealth(fraction: healthOverride) }
        guard let v = selectedVolume else { return .unknown }
        return DiskHealth(volume: v)
    }
    /// Development only (--health), to see the palette at any usage level.
    var healthOverride: Double?

    var selectedVolume: Volume? {
        guard let selectedSource else { return nil }
        if case .volume(let v) = selectedSource { return v }
        // For a folder, shows the volume that contains it.
        let path = selectedSource.url.path
        return volumes.filter { path.hasPrefix($0.url.path) }.max { $0.url.path.count < $1.url.path.count }
    }

    func refreshVolumes() {
        volumes = Volume.mounted()
        if selectedSource == nil, let first = volumes.first {
            selectedSource = .volume(first)
        }
        WidgetBridge.publish(self, .state)
    }

    /// Picks a goal in the sidebar. Never starts a scan by itself: the goal's
    /// screen asks the user (the "Scan Now" button, or the Map's press-and-hold).
    func selectGoal(_ g: Goal) {
        Trail.note("screen: \(g.rawValue)")
        goal = g
        selectedNode = nil
    }

    /// Scans only the goal's scopes, in parallel (up to 4 folders at a time),
    /// reusing Map subtrees when the Map already covers the scope.
    func runGoal(_ g: Goal) {
        Trail.note("goal scan: \(g.rawValue)")
        guard g != .map else { startScan(); return }
        guard g != .security else { runSecurityCheck(); return }
        cancelGoal(g)
        let scopes = g.scopes(source: selectedSource)
        guard !scopes.isEmpty else { goalResults[g] = GoalResult(roots: [], duration: 0, finished: Date()); return }
        let token = CancelToken()
        goalTokens[g] = token
        goalScanning.insert(g)
        goalProgress[g] = ScanProgress()
        let started = Date()

        var reused: [FileNode] = []
        var toScan: [URL] = []
        for url in scopes {
            if !isScanning, let node = rootNode?.node(atPath: url.path) { reused.append(node) } else { toScan.append(url) }
        }

        weak var weakSelf = self
        let group = DispatchGroup()
        let limit = DispatchSemaphore(value: 4)
        let lock = NSLock()
        var perScope: [String: ScanProgress] = [:]
        var scanned: [FileNode] = []

        for url in toScan {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                limit.wait()
                defer { limit.signal(); group.leave() }
                if token.isCancelled { return }
                let scanner = FTSScanner(root: url, token: token) { p in
                    lock.lock(); perScope[url.path] = p
                    let total = perScope.values.reduce(ScanProgress()) { acc, x in
                        var a = acc
                        a.files += x.files; a.directories += x.directories
                        a.allocatedBytes += x.allocatedBytes; a.deniedDirectories += x.deniedDirectories
                        a.currentPath = p.currentPath
                        return a
                    }
                    lock.unlock()
                    DispatchQueue.main.async {
                        guard let self = weakSelf, self.goalTokens[g] === token else { return }
                        self.goalProgress[g] = total
                    }
                }
                if let node = try? scanner.run() {
                    lock.lock(); scanned.append(node); lock.unlock()
                }
            }
        }
        group.notify(queue: .main) {
            guard let self = weakSelf, self.goalTokens[g] === token, !token.isCancelled else { return }
            let order = scopes.map(\.path)
            let roots = (reused + scanned).sorted { (order.firstIndex(of: $0.path) ?? 0) < (order.firstIndex(of: $1.path) ?? 0) }
            self.goalResults[g] = GoalResult(roots: roots, duration: Date().timeIntervalSince(started), finished: Date())
            self.goalScanning.remove(g)
            self.goalTokens[g] = nil
            self.refreshVolumes()
        }
    }

    // MARK: History of what Legroom freed (UserDefaults, numbers only)

    var trashedBytesTotal: Int64 {
        get { Int64(UserDefaults.standard.integer(forKey: "trashedBytesTotal")) }
        set { UserDefaults.standard.set(Int(newValue), forKey: "trashedBytesTotal") }
    }
    var trashedItemsTotal: Int {
        get { UserDefaults.standard.integer(forKey: "trashedItemsTotal") }
        set { UserDefaults.standard.set(newValue, forKey: "trashedItemsTotal") }
    }
    var lastTrashDate: Date? {
        get { UserDefaults.standard.object(forKey: "lastTrashDate") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastTrashDate") }
    }
    /// Only so the UI reacts (the properties above aren't observed).
    var trashHistoryVersion = 0
    /// Last removal made in this session, so the screen can show "done, X went to the Trash".
    struct TrashOutcome: Equatable { let bytes: Int64; let items: Int; let date: Date }
    var lastTrash: TrashOutcome?
    /// Changes whenever the in-memory tree loses nodes (move to Trash), so goal
    /// screens recompute even without a rescan.
    var treeVersion = 0

    // MARK: Memory

    func refreshMemory() { memory = MemorySnapshot.take() }

    /// One round of readings (every 1.5 s on the Overview). Processes every 2 rounds,
    /// Wi‑Fi every 4, because they cost more.
    func tickMetrics() {
        refreshMemory()
        swap = SwapUsage.read()
        if let c = cpuMonitor.tick() { cpu = c; cpuHistory = cpuMonitor.history }
        if let n = netMonitor.tick() { net = n; netHistory = netMonitor.history }
        if metricsTicks % 4 == 0 { wifi = NetworkMonitor.wifi() }
        DebugLaunch.verboseLog("tick \(metricsTicks) \(metricsOwners.sorted())")
        if metricsTicks % 2 == 0 {
            Task.detached(priority: .utility) { [weak self] in
                let byCPU = ProcessInfoRow.top(byCPU: true)
                let byMem = ProcessInfoRow.top(byCPU: false)
                let totals = NetworkMonitor.systemTotals()
                let thermal = Thermal.read()
                await MainActor.run {
                    self?.topByCPU = byCPU; self?.topByMemory = byMem
                    if self?.thermal != thermal { self?.thermal = thermal }
                    if let totals { self?.netTotals = NetTotals(received: totals.received, sent: totals.sent) }
                }
            }
        }
        metricsTicks += 1
        WidgetBridge.publish(self, .metrics)
    }

    // MARK: Reading cadence (shared)

    /// Who is showing metrics right now ("resumo", "barra"). Readings only run
    /// while the set isn't empty, at a single 1.5 s cadence, so the Overview and
    /// the menu bar item open at the same time don't double the frequency.
    private(set) var metricsOwners: Set<String> = []
    private var metricsLoop: Task<Void, Never>?

    /// Keeps readings on while the caller's task is alive.
    /// Use in `.task { await state.withMetrics("name") }`: cancelling the task turns them off.
    func withMetrics(_ owner: String) async {
        metricsOwners.insert(owner)
        if metricsLoop == nil {
            DebugLaunch.verboseLog("readings on (\(owner))")
            metricsLoop = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    self?.tickMetrics()
                    try? await Task.sleep(for: .seconds(1.5))
                }
            }
        }
        while !Task.isCancelled { try? await Task.sleep(for: .seconds(3600)) }
        metricsOwners.remove(owner)
        if metricsOwners.isEmpty {
            metricsLoop?.cancel()
            metricsLoop = nil
            DebugLaunch.verboseLog("readings stopped (\(owner) left)")
        }
    }

    // MARK: Startup volume (menu bar item)

    /// The Mac's disk, regardless of what is selected in the window.
    var bootVolume: Volume? { volumes.first(where: \.isRootVolume) ?? volumes.first }
    var bootHealth: DiskHealth {
        if let healthOverride { return DiskHealth(fraction: healthOverride) }
        return bootVolume.map(DiskHealth.init(volume:)) ?? .unknown
    }

    func runSpeedTest() {
        Trail.note("speed test")
        guard !speedTesting else { return }
        speedTesting = true
        speedError = nil
        Task { @MainActor in
            do { speedResult = try await SpeedTest.run() }
            catch { speedError = String(localized: "Couldn't run the test right now: \(error.localizedDescription)") }
            speedTesting = false
        }
    }

    func cleanMemory() {
        Trail.note("clean memory")
        guard !memoryCleaning else { return }
        memoryCleaning = true
        Task { @MainActor in
            let outcome = await MemoryCleaner.run()
            memoryOutcome = outcome
            memoryCleaning = false
            refreshMemory()
        }
    }

    // MARK: Check-up

    /// Last Check-up (nil until the user runs it; nothing runs on its own).
    var securityReport: SecurityReport?
    /// Items turned off during this session (to show them as done right away).
    var securityTurnedOff: Set<String> = []

    func runSecurityCheck() {
        guard !goalScanning.contains(.security) else { return }
        Trail.note("check-up: start")
        goalScanning.insert(.security)
        let started = Date()
        Task.detached(priority: .userInitiated) { [weak self] in
            let report = SecurityCheck.run()
            await MainActor.run {
                guard let self else { return }
                self.securityReport = report
                self.securityTurnedOff = []
                self.goalScanning.remove(.security)
                self.goalSummary[.security] = Self.securitySummary(report)
                Trail.note("check-up: \(report.startup.count) startup items, \(report.reviewCount) to review, \(report.defensesOff.count) defenses off, in \(Format.seconds(Date().timeIntervalSince(started)))")
            }
        }
    }

    static func securitySummary(_ r: SecurityReport) -> String {
        let look = r.reviewCount + r.defensesOff.count
        if look == 0 { return String(localized: "nothing unusual") }
        return look == 1 ? String(localized: "1 worth a look") : String(localized: "\(look) worth a look")
    }

    /// Turns off a startup item (its plist goes to the Trash; reversible).
    func turnOff(_ item: StartupItem) {
        Trail.note("check-up: turn off \(item.label)")
        Task { @MainActor in
            if await SecurityCheck.turnOff(item) {
                securityTurnedOff.insert(item.id)
                trashNotice = String(localized: "“\(item.displayName)” won't start on its own anymore. Its file is in the Trash.")
                let shown = trashNotice
                try? await Task.sleep(for: .seconds(5))
                if trashNotice == shown { trashNotice = nil }
            } else {
                errorMessage = String(localized: "Couldn't turn off “\(item.displayName)”.")
            }
        }
    }

    /// Opens the uninstall review for the app a startup item belongs to.
    func uninstallOwner(of item: StartupItem) {
        guard let app = item.ownerApp, FileManager.default.fileExists(atPath: app.path) else { return }
        let node = FileNode(name: app.path, isDirectory: true, isHidden: false)
        node.allocatedSize = AppLeftovers.allocatedSize(app)
        startUninstall([node])
    }

    func cancelGoal(_ g: Goal) {
        goalTokens[g]?.cancel()
        goalTokens[g] = nil
        goalScanning.remove(g)
    }

    /// Scan in progress for the current goal (Map or another).
    var isScanningCurrentGoal: Bool { goal == .map ? isScanning : goalScanning.contains(goal) }

    func select(_ source: ScanSource) {
        guard source != selectedSource || rootNode == nil else { return }
        cancelScan()
        selectedSource = source
        rootNode = nil
        currentNode = nil
        selectedNode = nil
        errorMessage = nil
        scanDuration = nil
        mapDate = nil
        mapRestored = false
        // tabs that came from the previous volume's Map are no longer valid
        for (g, r) in goalResults where r.fromMap { goalResults[g] = nil; goalSummary[g] = nil }
    }

    func startScan() {
        Trail.note("map scan")
        guard let source = selectedSource, !isScanning else { return }
        let url = source.url
        let token = CancelToken()
        cancelToken = token
        isScanning = true
        progress = ScanProgress()
        scanStarted = Date()
        scanDuration = nil
        errorMessage = nil
        rootNode = nil
        currentNode = nil
        selectedNode = nil
        mapDate = nil
        mapRestored = false
        restoreToken?.cancel()
        restoreToken = nil
        restoringMap = false

        weak var weakSelf = self
        scanTask = Task.detached(priority: .userInitiated) {
            let scanner = FTSScanner(root: url, token: token) { p in
                Task { @MainActor in
                    guard let self = weakSelf, self.cancelToken === token else { return }
                    self.progress = p
                }
            }
            do {
                let root = try scanner.run()
                await MainActor.run {
                    guard let self = weakSelf, self.cancelToken === token else { return }
                    self.rootNode = root
                    self.currentNode = root
                    self.isScanning = false
                    self.scanDuration = self.scanStarted.map { Date().timeIntervalSince($0) }
                    self.mapDate = Date()
                    self.mapRestored = false
                    self.refreshVolumes()
                    self.adoptMapIntoGoals()
                    self.saveMap(source: source)
                }
            } catch {
                await MainActor.run {
                    guard let self = weakSelf, self.cancelToken === token else { return }
                    self.isScanning = false
                    if case ScanError.cancelled = error { return }
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// A full Map scan covers the other tabs' folders: they start using the same
    /// tree, without scanning again. The reverse doesn't happen (a tab scans only
    /// its own folders, which don't make up a Map).
    func adoptMapIntoGoals() {
        guard let root = rootNode, let date = mapDate else { return }
        for g in Goal.scanning where g != .map && !goalScanning.contains(g) {
            let scopes = g.scopes(source: selectedSource)
            guard !scopes.isEmpty else { continue }
            let nodes = scopes.compactMap { root.node(atPath: $0.path) }
            guard nodes.count == scopes.count else { continue }   // the Map doesn't cover this tab
            // don't replace a newer scan of this tab with an older saved scan
            if let existing = goalResults[g], existing.finished > date { continue }
            goalResults[g] = GoalResult(roots: nodes, duration: scanDuration ?? 0, finished: date, fromMap: true)
        }
        let s = Self.summaries(of: goalResults)
        for (g, text) in s { goalSummary[g] = text }
        if let c = goalResults[.cleanup] {
            let groups = c.roots.cleanupGroups()
            SiriFacts.saveCleanup(suggested: groups.reduce(0) { $0 + $1.suggestedBytes },
                                  reclaimable: groups.filter { $0.rule.mode != .info }.reduce(0) { $0 + $1.total })
        }
    }

    /// The same summaries each tab shows when opened (Clutter only knows the total
    /// after comparing duplicates, so it shows "ready to view").
    static func summaries(of results: [Goal: GoalResult]) -> [Goal: String] {
        var out: [Goal: String] = [:]
        if let r = results[.cleanup] {
            let groups = r.roots.cleanupGroups()
            let suggested = groups.reduce(Int64(0)) { $0 + $1.suggestedBytes }
            let reclaimable = groups.filter { $0.rule.mode != .info }.reduce(Int64(0)) { $0 + $1.total }
            out[.cleanup] = suggested > 0 ? String(localized: "\(Format.bytes(suggested)) suggested") : (reclaimable > 0 ? Format.bytes(reclaimable) : String(localized: "nothing"))
        }
        if let r = results[.large] {
            let items = r.roots.largeItems(filter: LargeFilesFilter(), includeHidden: false)
            out[.large] = items.isEmpty ? String(localized: "nothing") : Format.bytes(items.reduce(0) { $0 + $1.allocatedSize })
        }
        if let r = results[.apps] {
            let apps = r.roots.applications()
            out[.apps] = apps.isEmpty ? String(localized: "nothing") : String(localized: "\(apps.count) apps · \(Format.bytes(apps.reduce(0) { $0 + $1.allocatedSize }))")
        }
        if results[.clutter] != nil { out[.clutter] = String(localized: "ready to view") }
        return out
    }

    /// Saves the volume's scan in the background. Standalone folders aren't saved.
    private func saveMap(source: ScanSource) {
        guard case .volume = source, let root = rootNode, let date = mapDate else { return }
        var summaries: [String: String] = [:]
        for g in Goal.scanning where g != .map { if let s = goalSummary[g], goalResults[g]?.fromMap == true { summaries[g.rawValue] = s } }
        let info = SavedMapInfo(sourceID: source.id, rootPath: root.path, date: date, duration: scanDuration ?? 0,
                                allocatedSize: root.allocatedSize, fileCount: root.fileCount, nodeCount: 0, summaries: summaries)
        savedMaps[source.id] = info
        let started = Date()
        MapStore.markSaving()
        Task.detached(priority: .utility) {
            defer { MapStore.doneSaving() }
            do {
                try MapStore.save(root: root, info: info)
                Trail.note("map saved in \(String(format: "%.2f", Date().timeIntervalSince(started))) s")
            } catch {
                Trail.note("map was not saved: \(error.localizedDescription)")
            }
        }
    }

    /// Opens the current volume's saved scan, if there is one and it isn't open yet.
    /// Doesn't read the disk: it only loads what was scanned on that date.
    func restoreSavedMapIfNeeded() {
        guard rootNode == nil, !isScanning, !restoringMap, let info = savedMap, let source = selectedSource else { return }
        restoringMap = true
        let token = CancelToken()
        restoreToken = token
        let started = Date()
        Trail.note("opening saved scan from \(info.date)")
        weak var weakSelf = self
        Task.detached(priority: .userInitiated) {
            let root = try? MapStore.load(info)
            await MainActor.run {
                guard let self = weakSelf, self.restoreToken === token else { return }
                self.restoringMap = false
                self.restoreToken = nil
                guard let root, self.selectedSource?.id == source.id, self.rootNode == nil, !self.isScanning else {
                    if root == nil { MapStore.delete(info.sourceID); self.savedMaps[info.sourceID] = nil }
                    return
                }
                Trail.note("saved scan opened in \(String(format: "%.2f", Date().timeIntervalSince(started))) s")
                self.rootNode = root
                self.currentNode = root
                self.scanDuration = info.duration
                self.mapDate = info.date
                self.mapRestored = true
                self.adoptMapIntoGoals()
            }
        }
    }

    /// Records in the saved file what left the tree (so it doesn't come back on reopening).
    private func noteRemovedFromSavedMap(_ paths: [String]) {
        guard let s = selectedSource, var info = savedMaps[s.id], !paths.isEmpty,
              let root = rootNode, root.path == info.rootPath else { return }
        let prefix = info.rootPath.hasSuffix("/") ? info.rootPath : info.rootPath + "/"
        let inside = paths.filter { $0.hasPrefix(prefix) }
        guard !inside.isEmpty else { return }
        info.removed += inside
        info.allocatedSize = root.allocatedSize
        info.fileCount = root.fileCount
        if (info.language ?? "pt-BR") != SavedMapInfo.currentLanguage { info.summaries = [:] }
        for (g, text) in Self.summaries(of: goalResults.filter { $0.value.fromMap }) { info.summaries[g.rawValue] = text }
        info.language = SavedMapInfo.currentLanguage
        savedMaps[s.id] = info
        MapStore.writeInfo(info)
    }

    func cancelScan() {
        restoreToken?.cancel()
        restoreToken = nil
        restoringMap = false
        cancelToken?.cancel()
        cancelToken = nil
        scanTask = nil
        isScanning = false
    }

    // MARK: Navigation

    func navigate(to node: FileNode) {
        guard node.isDirectory, !node.isPackage || node === rootNode else {
            selectedNode = node
            return
        }
        currentNode = node
        selectedNode = nil
    }

    func enter(_ node: FileNode) {
        // Entering a package (.app) is explicitly allowed by double-click.
        guard node.isDirectory else { return }
        currentNode = node
        selectedNode = nil
    }

    func goUp() {
        guard let parent = currentNode?.parent else { return }
        selectedNode = currentNode
        currentNode = parent
    }

    func visibleChildren(of node: FileNode) -> [FileNode] {
        showHidden ? node.children : node.children.filter { !$0.isHidden }
    }

    // MARK: Actions

    func revealInFinder(_ node: FileNode) {
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }

    func previewWithQuickLook(_ node: FileNode) {
        quickLook.preview(node.url)
    }

    func requestTrash(_ node: FileNode) { requestTrash([node]) }
    func requestTrash(_ nodes: [FileNode]) {
        // apps only: opens the uninstall review, with the app's leftovers
        if !nodes.isEmpty, nodes.allSatisfy({ $0.category == .application }) {
            startUninstall(nodes)
        } else {
            pendingTrash = nodes
        }
    }

    // MARK: Uninstall

    struct UninstallPlan: Identifiable {
        let id = UUID()
        let apps: [FileNode]
        var leftovers: [Leftover] = []
        var selected: Set<String> = []
        var searching = true
        var running: [NSRunningApplication] = []

        var selectedBytes: Int64 {
            apps.reduce(0) { $0 + $1.allocatedSize } + leftovers.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.bytes }
        }
    }

    func startUninstall(_ apps: [FileNode]) {
        let urls = apps.map(\.url)
        let ids = Set(urls.compactMap { Bundle(url: $0)?.bundleIdentifier })
        var plan = UninstallPlan(apps: apps)
        plan.running = NSWorkspace.shared.runningApplications.filter { app in
            app.bundleIdentifier.map(ids.contains) ?? false || urls.contains { app.bundleURL?.path == $0.path }
        }
        pendingUninstall = plan
        let planID = plan.id
        Task.detached(priority: .userInitiated) { [weak self] in
            let found = AppLeftovers.find(for: urls)
            await MainActor.run {
                guard let self, self.pendingUninstall?.id == planID else { return }
                self.pendingUninstall?.leftovers = found
                self.pendingUninstall?.selected = Set(found.filter(\.suggested).map(\.id))
                self.pendingUninstall?.searching = false
            }
        }
    }

    /// Quits the app (if open), sends the app and the selected leftovers to the Trash.
    func confirmUninstall() {
        guard let plan = pendingUninstall else { return }
        pendingUninstall = nil
        Trail.note("uninstall: \(plan.apps.count) apps, \(plan.selected.count) leftovers")
        Task { @MainActor in
            // asks it to quit, like ⌘Q, and waits a bit
            for app in plan.running where !app.isTerminated { app.terminate() }
            for _ in 0..<40 where plan.running.contains(where: { !$0.isTerminated }) {
                try? await Task.sleep(for: .milliseconds(150))
            }
            for app in plan.running where !app.isTerminated { app.forceTerminate() }
            if !plan.running.isEmpty { try? await Task.sleep(for: .milliseconds(400)) }

            for l in plan.leftovers where plan.selected.contains(l.id) { AppLeftovers.unloadIfLaunchAgent(l.url) }
            let items = plan.apps.map { TrashItem(url: $0.url, bytes: $0.allocatedSize, node: $0, label: $0.name) }
                + plan.leftovers.filter { plan.selected.contains($0.id) }.map { TrashItem(url: $0.url, bytes: $0.bytes, node: nil, label: $0.displayPath) }
            await trash(items)
        }
    }

    /// Moves to the Trash. Never deletes permanently.
    func confirmTrash() {
        let nodes = pendingTrash
        pendingTrash = []
        guard !nodes.isEmpty else { return }
        Task { @MainActor in
            await trash(nodes.map { TrashItem(url: $0.url, bytes: $0.allocatedSize, node: $0, label: $0.name) })
        }
    }

    struct TrashItem { let url: URL; let bytes: Int64; let node: FileNode?; let label: String }

    /// Sends to the Trash. System-owned items (e.g. apps installed by a .pkg, in
    /// root-owned folders) go through the Finder, which asks for the administrator
    /// password in a macOS window and allows "Put Back" later, as if done in the Finder.
    private func trash(_ items: [TrashItem]) async {
        Trail.note("move to Trash: \(items.count) items")
        var moved = 0, bytes: Int64 = 0, failures: [String] = [], removedPaths: [String] = []
        var needsAdmin: [TrashItem] = []

        func done(_ item: TrashItem) {
            bytes += item.bytes; moved += 1
            removedPaths.append(item.url.path)
            let node = item.node ?? rootNode.flatMap { root in root.node(atPath: item.url.path).flatMap { $0 === root ? nil : $0 } }
            guard let node else { return }
            if selectedNode === node { selectedNode = nil }
            if currentNode === node { currentNode = node.parent }
            // scope root (e.g. all of ~/.npm/_cacache): removed from the results
            for g in goalResults.keys { goalResults[g]?.roots.removeAll { $0 === node } }
            if node.parent != nil {
                MapStore.treeLock.lock(); node.detachFromParent(); MapStore.treeLock.unlock()
            }
        }

        for item in items {
            do {
                try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                done(item)
            } catch {
                if TrashMover.isPermissionError(error) { needsAdmin.append(item) }
                else { failures.append("\(item.label): \(error.localizedDescription)") }
            }
        }
        if !needsAdmin.isEmpty {
            await TrashMover.trashWithFinder(needsAdmin.map(\.url))
            for item in needsAdmin {
                if FileManager.default.fileExists(atPath: item.url.path) {
                    failures.append(String(localized: "\(item.label): needs an administrator password, and the operation was canceled or not authorized."))
                } else {
                    done(item)
                }
            }
        }

        refreshVolumes()
        treeVersion += 1
        noteRemovedFromSavedMap(removedPaths)
        if moved > 0 {
            trashedBytesTotal += bytes
            trashedItemsTotal += moved
            lastTrashDate = Date()
            trashHistoryVersion += 1
            lastTrash = TrashOutcome(bytes: bytes, items: moved, date: Date())
            WidgetBridge.publish(self, .state)
            trashNotice = moved == 1 ? String(localized: "\(Format.bytes(bytes)) moved to the Trash") : String(localized: "\(Format.bytes(bytes)) in \(moved) items moved to the Trash")
            let shown = trashNotice
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                if trashNotice == shown { trashNotice = nil }
            }
        }
        if !failures.isEmpty {
            errorMessage = String(localized: "Couldn't move to the Trash:") + "\n" + failures.prefix(5).joined(separator: "\n")
        }
    }

    /// Deep link (v8): legroom://resumo, coming from the widget. Only navigates; never reads the disk.
    func handle(url: URL) {
        Trail.note("link: \(url.host ?? "-")")
        guard url.scheme == "legroom" else { return }
        // v9: Siri opens screens via legroom://<screen>. Navigating doesn't start a scan.
        switch url.host ?? "" {
        case "resumo", "summary", "": selectGoal(.home)
        case "map", "mapa": selectGoal(.map)
        case "cleanup", "limpeza": selectGoal(.cleanup)
        case "large", "grandes": selectGoal(.large)
        case "apps": selectGoal(.apps)
        case "clutter", "bagunca": selectGoal(.clutter)
        case "security", "checkup", "check-up": selectGoal(.security)
        default: break
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Opens the Trash in the Finder (Legroom doesn't empty the Trash for you).
    func revealTrash() {
        NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/.Trash", isDirectory: true))
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Scan")
        panel.message = String(localized: "Choose a folder to scan")
        if panel.runModal() == .OK, let url = panel.url {
            select(.folder(url, label: url.lastPathComponent))
            startScan()
        }
    }
}
