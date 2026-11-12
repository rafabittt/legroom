import SwiftUI

/// Sortable list of the current folder's children. Kept in sync with the treemap.
struct FileListView: View {
    @Environment(AppState.self) private var state
    let node: FileNode
    var compact = false
    @State private var sortOrder = [KeyPathComparator(\FileNode.allocatedSize, order: .reverse)]

    private var rows: [FileNode] {
        state.visibleChildren(of: node).sorted(using: sortOrder)
    }

    var body: some View {
        @Bindable var state = state
        Table(rows, selection: Binding(
            get: { state.selectedNode?.id },
            set: { id in state.selectedNode = rows.first { $0.id == id } }),
              sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { n in
                HStack(spacing: 6) {
                    Image(systemName: icon(for: n))
                        .foregroundStyle(Theme.categoryColor(n.category))
                        .frame(width: 16)
                    Text(n.name)
                        .foregroundStyle(n.isHidden ? .secondary : .primary)
                    if n.accessDenied {
                        Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary)
                            .help("No permission to read")
                    }
                }
            }
            .width(min: 140, ideal: compact ? 200 : 260)
            TableColumn("On Disk", value: \.allocatedSize) { n in
                Text(Format.bytes(n.allocatedSize)).monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 84, ideal: 92)
            TableColumn("%") { n in
                let pct = node.allocatedSize > 0 ? Double(n.allocatedSize) / Double(node.allocatedSize) * 100 : 0
                Text(pct < 0.1 && pct > 0 ? "<\(0.1.formatted(.number.precision(.fractionLength(1))))" : pct.formatted(.number.precision(.fractionLength(1))))
                    .monospacedDigit().foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(48)
            .defaultVisibility(compact ? .hidden : .visible)
            TableColumn("Items", value: \.fileCount) { n in
                Text(n.isDirectory ? Format.count(n.fileCount) : "")
                    .monospacedDigit().foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 70)
            .defaultVisibility(compact ? .hidden : .visible)
            TableColumn("Date Modified", value: \.modified, comparator: OptionalDateComparator()) { n in
                Text(Format.date(n.modified)).foregroundStyle(.secondary)
            }
            .width(min: 110, ideal: 140)
            .defaultVisibility(compact ? .hidden : .visible)
        }
        .onAppear { Trail.note("table: map") }
        .contextMenu(forSelectionType: FileNode.ID.self) { ids in
            if let id = ids.first, let n = rows.first(where: { $0.id == id }) {
                NodeContextMenu(node: n)
            }
        } primaryAction: { ids in
            if let id = ids.first, let n = rows.first(where: { $0.id == id }) {
                if n.isDirectory { state.enter(n) } else { state.previewWithQuickLook(n) }
            }
        }
        .scrollContentBackground(.hidden)
        .onDeleteCommand {
            if let n = state.selectedNode { state.requestTrash(n) }
        }
    }

    private func icon(for n: FileNode) -> String {
        switch n.category {
        case .directory: return "folder.fill"
        case .application: return "app.fill"
        case .bundle: return "shippingbox.fill"
        case .image: return "photo.fill"
        case .video: return "film.fill"
        case .audio: return "music.note"
        case .archive: return "doc.zipper"
        case .document: return "doc.text.fill"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .diskImage: return "opticaldisc.fill"
        case .other: return n.isSymlink ? "link" : "doc.fill"
        }
    }
}

struct OptionalDateComparator: SortComparator {
    var order: SortOrder = .forward
    func compare(_ lhs: Date?, _ rhs: Date?) -> ComparisonResult {
        let r: ComparisonResult
        switch (lhs, rhs) {
        case (nil, nil): r = .orderedSame
        case (nil, _): r = .orderedAscending
        case (_, nil): r = .orderedDescending
        case let (a?, b?): r = a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
        }
        return order == .forward ? r : r.reversed
    }
}

private extension ComparisonResult {
    var reversed: ComparisonResult {
        switch self {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
        }
    }
}
