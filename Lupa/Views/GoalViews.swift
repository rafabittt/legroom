import SwiftUI

/// Thin strip under the tabs: the goal's colored icon, title and one-line promise,
/// plus whatever the tab wants to show on the right (totals, actions).
struct GoalHeader<Trailing: View>: View {
    let goal: Goal
    @ViewBuilder var trailing: Trailing
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 12) {
            GoalIcon(goal: goal, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(goal.question).font(.system(size: 15, weight: .semibold))
                Text(goal.promise).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 4)
    }
}

/// Monochrome goal tile: gray with a dark symbol; "prominent" inverts it
/// (black with a white symbol in light mode, white with a black symbol in dark mode).
struct GoalIcon: View {
    let goal: Goal
    var size: CGFloat = 30
    var prominent = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let dark = scheme == .dark
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(prominent ? (dark ? Color.white : Color.black) : Color.primary.opacity(dark ? 0.10 : 0.06))
            Image(systemName: goal.symbol).font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(prominent ? (dark ? Color.black : Color.white) : Color.primary.opacity(0.8))
        }
        .frame(width: size, height: size)
    }
}

/// Selection bar shared by Cleanup and Clutter: total of checked items + button.
struct SelectionBar: View {
    let count: Int
    let bytes: Int64
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                RollingNumber(text: Format.bytes(bytes), font: .system(size: 13, weight: .semibold))
                Text(count == 0 ? String(localized: "nothing selected") : (count == 1 ? String(localized: "in 1 selected item") : String(localized: "in \(Format.count(count)) selected items")))
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
            .fixedSize()
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(scheme == .dark ? Theme.darkCard : Theme.lightCard))
            .overlay(Capsule().strokeBorder(Theme.hairline(scheme == .dark), lineWidth: 1))
            Button(action: action) {
                Label("Move to Trash", systemImage: "trash")
                    .font(.system(size: 12, weight: .semibold)).lineLimit(1).fixedSize()
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .foregroundStyle(.white)
                    .background(Capsule().fill(Theme.destructive))
                    .opacity(count == 0 ? 0.4 : 1)
            }
            .buttonStyle(.plain)
            .disabled(count == 0)
            .help("Nothing is deleted permanently. You confirm first and can restore items from the Trash.")
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: count)
    }
}

/// Checkable file/folder row, used in the Cleanup and Clutter lists.
struct ItemRow: View {
    let node: FileNode
    @Binding var checked: Bool
    var subtitle: String? = nil
    var trailing: String? = nil
    /// When set, the row shows a sparkle and this text in the tooltip (pre-selection).
    var hint: String? = nil
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var scheme
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $checked).toggleStyle(.checkbox).labelsHidden()
            Image(nsImage: NSWorkspace.shared.icon(forFile: node.path)).resizable().frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(node.name).font(.system(size: 12.5)).lineLimit(1)
                Text(subtitle ?? node.parent?.path ?? "").font(.system(size: 10.5)).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if let hint {
                Image(systemName: "sparkles").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(hex: scheme == .dark ? 0x4ADE80 : 0x16A34A)).help(hint)
            }
            if let trailing { Text(trailing).font(.system(size: 11)).foregroundStyle(.secondary) }
            Text(Format.bytes(node.allocatedSize)).font(.system(size: 12, weight: .medium)).monospacedDigit()
                .frame(width: 76, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(state.selectedNode === node ? Color.primary.opacity(scheme == .dark ? 0.12 : 0.07)
                                               : (hover ? Color.primary.opacity(0.04) : .clear)))
        .contentShape(Rectangle())
        .onTapGesture { state.selectedNode = node }
        .onHover { hover = $0 }
        .contextMenu { NodeContextMenu(node: node) }
    }
}
