import SwiftUI

/// "Large & Forgotten": big files and bundles, filterable by size, age and kind.
/// Nothing is pre-selected; each row shows its path and last use.
struct LargeFilesView: View {
    @Environment(AppState.self) private var state
    let roots: [FileNode]
    let key: Int
    @State private var filter = LargeFilesFilter()
    @State private var items: [FileNode] = []
    @State private var sortOrder = [KeyPathComparator(\FileNode.allocatedSize, order: .reverse)]

    private var total: Int64 { items.reduce(0) { $0 + $1.allocatedSize } }

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                FilterMenu(title: filter.minSize.label, symbol: "arrow.up.arrow.down") {
                    ForEach(LargeFilesFilter.MinSize.allCases) { s in Button(s.label) { filter.minSize = s } }
                }
                FilterMenu(title: filter.age.label, symbol: "clock") {
                    ForEach(LargeFilesFilter.Age.allCases) { a in Button(a.label) { filter.age = a } }
                }
                FilterMenu(title: filter.kind.label, symbol: "line.3.horizontal.decrease") {
                    ForEach(LargeFilesFilter.Kind.allCases) { k in Button(k.label) { filter.kind = k } }
                }
                Spacer()
                HStack(spacing: 6) {
                    RollingNumber(text: Format.bytes(total), font: .system(size: 13, weight: .semibold))
                    Text(items.count == 1 ? String(localized: "in 1 item") : String(localized: "in \(Format.count(items.count)) items"))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(.regularMaterial))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
            }

            Group {
                if items.isEmpty {
                    EmptyHint(symbol: "checkmark.seal", title: String(localized: "Nothing this large here"),
                              text: String(localized: "Loosen the size or age filter to see more items."))
                } else {
                    Table(items.sorted(using: sortOrder), selection: Binding(
                        get: { state.selectedNode?.id },
                        set: { id in state.selectedNode = items.first { $0.id == id } }),
                          sortOrder: $sortOrder) {
                        TableColumn("Name", value: \.name) { n in
                            HStack(spacing: 8) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: n.path)).resizable().frame(width: 18, height: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(n.name).lineLimit(1)
                                    Text(n.parent?.path ?? "").font(.system(size: 10.5)).foregroundStyle(.tertiary)
                                        .lineLimit(1).truncationMode(.middle)
                                }
                            }
                        }
                        .width(min: 220, ideal: 360)
                        TableColumn("Kind") { n in
                            Text(n.category.label).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Capsule().fill(Theme.categoryGradient(n.category)))
                        }
                        .width(min: 90, ideal: 110)
                        TableColumn("On Disk", value: \.allocatedSize) { n in
                            Text(Format.bytes(n.allocatedSize)).monospacedDigit()
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .width(min: 84, ideal: 96)
                        TableColumn("Last Used", value: \.lastUsed, comparator: OptionalDateComparator()) { n in
                            Text(Format.relative(n.lastUsed)).foregroundStyle(.secondary)
                        }
                        .width(min: 100, ideal: 110)
                    }
                    .onAppear { Trail.note("table: large") }
                    .contextMenu(forSelectionType: FileNode.ID.self) { ids in
                        if let id = ids.first, let n = items.first(where: { $0.id == id }) { NodeContextMenu(node: n) }
                    } primaryAction: { ids in
                        if let id = ids.first, let n = items.first(where: { $0.id == id }) { state.previewWithQuickLook(n) }
                    }
                    .onDeleteCommand { if let n = state.selectedNode { state.requestTrash(n) } }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerL, style: .continuous))
            .contentCard()
        }
        .task(id: TaskKey(key: key, filter: filter, hidden: state.showHidden)) {
            items = roots.largeItems(filter: filter, includeHidden: state.showHidden)
            if filter == LargeFilesFilter() { state.goalSummary[.large] = items.isEmpty ? String(localized: "nothing") : Format.bytes(total) }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: filter)
    }

    private struct TaskKey: Equatable { let key: Int; let filter: LargeFilesFilter; let hidden: Bool }
}

/// Pill-shaped menu for filters.
struct FilterMenu<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var scheme
    @State private var hover = false
    var body: some View {
        Menu {
            content
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Capsule().fill(Theme.card(scheme == .dark)))
            .overlay(Capsule().strokeBorder(hover ? Color.primary.opacity(scheme == .dark ? 0.22 : 0.16) : Theme.hairline(scheme == .dark), lineWidth: 1))
            .shadow(color: .black.opacity(hover ? 0.10 : 0), radius: 8, y: 4)
            .scaleEffect(hover ? 1.03 : 1)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { h in withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) { hover = h } }
    }
}

struct EmptyHint: View {
    let symbol: String
    let title: String
    let text: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 34, weight: .light)).foregroundStyle(.secondary)
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
