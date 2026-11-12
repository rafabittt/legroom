import SwiftUI

/// Bottom panel: everything the user needs to know before deciding to delete.
struct DetailView: View {
    @Environment(AppState.self) private var state
    let node: FileNode
    let isCurrentFolder: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: node.path))
                .resizable()
                .frame(width: 44, height: 44)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.categoryGradient(node.category).opacity(0.25)))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(node.parent == nil ? (state.selectedSource?.label ?? node.name) : node.name)
                        .font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Text(node.category.label).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Theme.categoryGradient(node.category)))
                    if node.isSymlink { Text("symbolic link").font(.caption).foregroundStyle(.secondary) }
                    if node.accessDenied { Label("no read permission", systemImage: "lock").font(.caption).foregroundStyle(.orange) }
                }
                Text(node.path)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 14) {
                    Fact(String(localized: "On Disk"), Format.bytes(node.allocatedSize))
                    Fact(String(localized: "Logical"), Format.bytes(node.logicalSize))
                    if node.isDirectory { Fact(String(localized: "Items"), Format.count(node.fileCount)) }
                    Fact(String(localized: "Modified"), Format.relative(node.modified))
                    Fact(String(localized: "Last Accessed"), Format.relative(node.accessed))
                }
                if let d = KnownLocations.description(forPath: node.path) {
                    Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                } else if node.logicalSize > node.allocatedSize * 2, node.logicalSize > 1_000_000 {
                    Text("The logical size is much larger than the allocated size: a sparse or compressed file, or an APFS clone sharing blocks. Deleting frees only the \"on disk\" amount.")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                } else {
                    FolderExplainer(node: node)   // v9: Apple Intelligence, only when you ask
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                HStack {
                    Button("Show in Finder") { state.revealInFinder(node) }
                    Button("Quick Look") { state.previewWithQuickLook(node) }
                        .keyboardShortcut(.space, modifiers: [])
                }
                Button(role: .destructive) {
                    state.requestTrash(node)
                } label: {
                    Label(node.category == .application ? String(localized: "Uninstall") : String(localized: "Move to Trash"),
                          systemImage: node.category == .application ? "xmark.app" : "trash")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .foregroundStyle(.white)
                        .background(Capsule().fill(Theme.destructive))
                }
                .buttonStyle(.plain)
                .disabled(isCurrentFolder && node === state.rootNode)
                .help(node.category == .application
                      ? String(localized: "Moves the app to the Trash. You confirm first and can restore it. Preferences and caches in ~/Library stay.")
                      : String(localized: "Nothing is permanently deleted. You confirm first and can restore it from the Trash."))
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(height: 136)
    }
}

private struct Fact: View {
    let title: String
    let value: String
    init(_ title: String, _ value: String) { self.title = title; self.value = value }
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.tertiary)
            Text(value).font(.callout.monospacedDigit())
        }
    }
}
