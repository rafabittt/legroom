import SwiftUI

/// Area map: each rectangle is a child of the current folder, proportional to
/// its allocated space. Click selects, double-click enters the folder.
struct TreemapView: View {
    @Environment(AppState.self) private var state
    let node: FileNode
    @State private var hovered: FileNode?

    private static let maxTiles = 80

    private struct Tile: Identifiable {
        let node: FileNode?      // nil = the "others" group
        let index: Int
        let rect: CGRect
        let othersCount: Int
        let othersSize: Int64
        var id: String { node?.id.uuidString ?? "others" }
    }

    private func tiles(in bounds: CGRect) -> [Tile] {
        let children = state.visibleChildren(of: node).filter { $0.allocatedSize > 0 }
        guard !children.isEmpty else { return [] }
        let shown = Array(children.prefix(Self.maxTiles))
        let rest = children.dropFirst(Self.maxTiles)
        let restSize = rest.reduce(Int64(0)) { $0 + $1.allocatedSize }
        var values = shown.map { Double($0.allocatedSize) }
        if restSize > 0 { values.append(Double(restSize)) }
        let rects = Squarify.layout(values: values, in: bounds)
        var out: [Tile] = []
        for (i, n) in shown.enumerated() { out.append(Tile(node: n, index: i, rect: rects[i], othersCount: 0, othersSize: 0)) }
        if restSize > 0 { out.append(Tile(node: nil, index: shown.count, rect: rects[shown.count], othersCount: rest.count, othersSize: restSize)) }
        return out
    }

    var body: some View {
        GeometryReader { geo in
            let bounds = CGRect(origin: .zero, size: geo.size).insetBy(dx: 8, dy: 8)
            let tiles = tiles(in: bounds)
            ZStack(alignment: .topLeading) {
                Color.clear
                if tiles.isEmpty {
                    Text(node.accessDenied ? String(localized: "No permission to read this folder.") : String(localized: "Empty folder."))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                ForEach(tiles) { tile in
                    TileView(tile: tile,
                             isSelected: tile.node != nil && tile.node === state.selectedNode,
                             isHovered: tile.node != nil && tile.node === hovered)
                        .frame(width: max(0, tile.rect.width - 4), height: max(0, tile.rect.height - 4))
                        .offset(x: tile.rect.minX + 2, y: tile.rect.minY + 2)
                        .onHover { inside in hovered = inside ? tile.node : (hovered === tile.node ? nil : hovered) }
                        .onTapGesture(count: 2) { if let n = tile.node { state.enter(n) } }
                        .onTapGesture(count: 1) { if let n = tile.node { state.selectedNode = n } }
                        .contextMenu { if let n = tile.node { NodeContextMenu(node: n) } }
                }
            }
        }
        .clipped()
    }

    private struct TileView: View {
        let tile: Tile
        let isSelected: Bool
        let isHovered: Bool

        var body: some View {
            let color = tile.node.map { Theme.categoryColor($0.category) } ?? Theme.categoryColor(.other)
            let shape = RoundedRectangle(cornerRadius: min(Theme.cornerM, tile.rect.width / 4, tile.rect.height / 4), style: .continuous)
            ZStack(alignment: .topLeading) {
                shape.fill(color.opacity(isHovered ? 1 : 0.88))
                    .brightness(Double(tile.index % 5) * 0.015 - 0.03)
                shape.strokeBorder(isSelected ? Color.primary : Color.white.opacity(0.35), lineWidth: isSelected ? 2 : 1)
                if tile.rect.width > 56 && tile.rect.height > 30 {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tile.node?.name ?? String(localized: "\(tile.othersCount) other items"))
                            .font(.system(size: 11.5, weight: .semibold))
                            .lineLimit(tile.rect.height > 64 ? 3 : 1)
                        if tile.rect.height > 46 {
                            Text(Format.bytes(tile.node?.allocatedSize ?? tile.othersSize))
                                .font(.system(size: 11, weight: .medium)).monospacedDigit()
                                .opacity(0.9)
                        }
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
                }
            }
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .help(tile.node.map { "\($0.name)\n\(Format.bytes($0.allocatedSize))" } ?? String(localized: "\(tile.othersCount) smaller items totaling \(Format.bytes(tile.othersSize))"))
        }
    }
}

struct NodeContextMenu: View {
    @Environment(AppState.self) private var state
    let node: FileNode
    var body: some View {
        if node.isDirectory {
            Button("Open Folder") { state.enter(node) }
        }
        Button("Show in Finder") { state.revealInFinder(node) }
        Button("Quick Look") { state.previewWithQuickLook(node) }
        Divider()
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(node.path, forType: .string)
        }
        Divider()
        Button(node.category == .application ? String(localized: "Uninstall…") : String(localized: "Move to Trash…"), role: .destructive) { state.requestTrash(node) }
    }
}
