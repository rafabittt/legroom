import SwiftUI

/// "Apps": applications found during the scan, by bundle size and the date they
/// were last opened (Spotlight metadata). Uninstalling also removes the app's
/// leftovers (see AppLeftovers and UninstallSheet).
struct AppsView: View {
    @Environment(AppState.self) private var state
    let roots: [FileNode]
    let key: Int
    @State private var apps: [AppEntry] = []
    @State private var sortOrder = [KeyPathComparator(\AppEntry.size, order: .reverse)]

    struct AppEntry: Identifiable {
        let node: FileNode
        var lastOpened: Date?
        var id: UUID { node.id }
        var name: String { (node.name as NSString).deletingPathExtension }
        var size: Int64 { node.allocatedSize }
        var version: String?
    }

    private var total: Int64 { apps.reduce(0) { $0 + $1.size } }
    private var stale: Int { apps.filter { ($0.lastOpened.map { Date().timeIntervalSince($0) > 180 * 86_400 }) ?? false }.count }

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Spacer()
                if stale > 0 {
                    Label("\(stale) not opened in over 6 months", systemImage: "moon.zzz")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(.thinMaterial))
                }
                HStack(spacing: 6) {
                    RollingNumber(text: Format.bytes(total), font: .system(size: 13, weight: .semibold))
                    Text("in \(apps.count) apps").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(.thinMaterial))
            }

            Group {
                if apps.isEmpty {
                    EmptyHint(symbol: "app.dashed", title: String(localized: "No apps found"),
                              text: String(localized: "Legroom looks in /Applications and ~/Applications."))
                } else {
                    Table(apps.sorted(using: sortOrder), selection: Binding(
                        get: { state.selectedNode?.id },
                        set: { id in state.selectedNode = apps.first { $0.id == id }?.node }),
                          sortOrder: $sortOrder) {
                        TableColumn("App", value: \.name) { a in
                            HStack(spacing: 8) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: a.node.path)).resizable().frame(width: 22, height: 22)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(a.name).lineLimit(1)
                                    Text(a.version.map { String(localized: "version \($0)") } ?? a.node.parent?.path ?? "")
                                        .font(.system(size: 10.5)).foregroundStyle(.tertiary).lineLimit(1)
                                }
                            }
                        }
                        .width(min: 200, ideal: 300)
                        TableColumn("Size", value: \.size) { a in
                            Text(Format.bytes(a.size)).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .width(min: 84, ideal: 96)
                        TableColumn("Last Opened", value: \.lastOpened, comparator: OptionalDateComparator()) { a in
                            Text(a.lastOpened.map { Format.relative($0) } ?? "—").foregroundStyle(.secondary)
                        }
                        .width(min: 110, ideal: 120)
                        TableColumn("Location") { a in
                            Text(a.node.parent?.path ?? "").font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        .width(min: 90, ideal: 140)
                    }
                    .onAppear { Trail.note("table: apps") }
                    .contextMenu(forSelectionType: AppEntry.ID.self) { ids in
                        if let id = ids.first, let a = apps.first(where: { $0.id == id }) { NodeContextMenu(node: a.node) }
                    } primaryAction: { ids in
                        if let id = ids.first, let a = apps.first(where: { $0.id == id }) { state.revealInFinder(a.node) }
                    }
                    .onDeleteCommand { if let n = state.selectedNode { state.requestTrash(n) } }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerL, style: .continuous))
            .contentCard()
        }
        .task(id: key) {
            let nodes = roots.applications()
            apps = nodes.map { AppEntry(node: $0) }
            state.goalSummary[.apps] = apps.isEmpty ? String(localized: "nothing") : String(localized: "\(apps.count) apps · \(Format.bytes(total))")
            // metadata off the main thread; the list shows up first and fills in later
            let paths = nodes.map(\.path)
            let meta: [(Date?, String?)] = await Task.detached(priority: .utility) {
                paths.map { p in
                    var last: Date? = nil, version: String? = nil
                    if let item = MDItemCreate(nil, p as CFString) {
                        last = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
                        version = MDItemCopyAttribute(item, kMDItemVersion) as? String
                    }
                    return (last, version)
                }
            }.value
            guard apps.count == meta.count else { return }
            for i in apps.indices { apps[i].lastOpened = meta[i].0; apps[i].version = meta[i].1 }
        }
    }
}
