import SwiftUI

/// "Cleanup": known places where the Mac piles up things it recreates on its own.
/// Nothing comes preselected; each group explains what it is and what happens if it goes to the Trash.
struct CleanupView: View {
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var scheme
    let roots: [FileNode]
    let key: Int
    @State private var groups: [CleanupGroup] = []
    @State private var checked: Set<UUID> = []
    @State private var expanded: Set<String> = []
    /// Identity of the roots the suggestion was already applied to (not reapplied
    /// after the user makes changes; only on a rescan).
    @State private var appliedIdentity: Int?
    /// Removals before this moment don't show the completion banner (a new scan resets it).
    @State private var shownSince = Date()

    private var allItems: [FileNode] { groups.flatMap(\.items) }
    private var selectedNodes: [FileNode] { allItems.filter { checked.contains($0.id) } }
    private var selectedBytes: Int64 { selectedNodes.reduce(0) { $0 + $1.allocatedSize } }
    private var reclaimable: Int64 { groups.filter { $0.rule.mode != .info }.reduce(0) { $0 + $1.total } }
    private var suggestedIDs: Set<UUID> { Set(groups.flatMap { $0.suggested.keys }) }
    private var suggestedBytes: Int64 { groups.reduce(0) { $0 + $1.suggestedBytes } }
    private var rootsIdentity: Int { var h = Hasher(); for r in roots { h.combine(ObjectIdentifier(r)) }; return h.finalize() }
    private var everythingIDs: Set<UUID> { Set(groups.filter { $0.rule.mode != .info }.flatMap { $0.items.map(\.id) }) }
    private var markedEverything: Bool { !everythingIDs.isEmpty && checked == everythingIDs }

    var body: some View {
        VStack(spacing: 12) {
            if let done = state.lastTrash, done.date > shownSince {
                CleanupDoneBanner(outcome: done)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Group {
                if groups.isEmpty {
                    EmptyHint(symbol: "sparkles", title: String(localized: "Nothing has built up here"),
                              text: String(localized: "Caches, logs, and tool folders are empty or don't exist on this Mac."))
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.success)
                        VStack(alignment: .leading, spacing: 1) {
                            let amount = Text(Format.bytes(suggestedBytes)).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
                            (suggestedIDs.count == 1
                             ? Text("Selected \(amount) in 1 item, out of \(Format.bytes(reclaimable)) reclaimable.")
                             : Text("Selected \(amount) in \(suggestedIDs.count) items, out of \(Format.bytes(reclaimable)) reclaimable."))
                                .foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.tail)
                            Text(markedEverything
                                 ? String(localized: "You selected everything, including items that need review. Check the list before moving.")
                                 : String(localized: "Only what the Mac recreates on its own, unchanged for days and not in use by an open app. The rest is up to you."))
                                .font(.system(size: 11)).foregroundStyle(markedEverything ? AnyShapeStyle(Color(hex: scheme == .dark ? 0xFFD60A : 0xB45309)) : AnyShapeStyle(.tertiary)).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Menu {
                            Button { checked = suggestedIDs } label: { Label("Conservative Suggestion Only", systemImage: "sparkles") }
                            Button { checked = everythingIDs } label: { Label("Everything Found (Your Call)", systemImage: "exclamationmark.triangle") }
                            Button { checked = [] } label: { Label("None", systemImage: "circle") }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: markedEverything ? "exclamationmark.triangle" : (checked == suggestedIDs ? "sparkles" : "checklist"))
                                    .font(.system(size: 11, weight: .semibold))
                                Text(markedEverything ? String(localized: "All Selected") : (checked == suggestedIDs ? String(localized: "Suggestion") : String(localized: "Manual Selection")))
                                    .font(.system(size: 12, weight: .medium))
                                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(Theme.card(scheme == .dark)))
                            .overlay(Capsule().strokeBorder(Theme.hairline(scheme == .dark), lineWidth: 1))
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("Selecting everything includes items that need review. Even so, everything goes to the Trash and can be restored.")
                        SelectionBar(count: selectedNodes.count, bytes: selectedBytes) { state.requestTrash(selectedNodes) }
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 4)
                    .animation(.spring(response: 0.3, dampingFraction: 0.85), value: checked == suggestedIDs)
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(Array(groups.enumerated()), id: \.element.id) { i, g in
                                CleanupGroupCard(group: g, checked: $checked, expanded: expanded.contains(g.id)) {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                                        if expanded.contains(g.id) { expanded.remove(g.id) } else { expanded.insert(g.id) }
                                    }
                                }
                                .staggeredAppear(index: i, trigger: AnyHashable(groups.count))
                            }
                        }
                        .padding(2)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .task(id: key) {
            groups = roots.cleanupGroups()
            if appliedIdentity != rootsIdentity {
                // first scan (or rescan): apply the conservative suggestion
                shownSince = Date()
                checked = suggestedIDs
                appliedIdentity = rootsIdentity
                expanded = Set(groups.filter { !$0.suggested.isEmpty }.prefix(1).map(\.id))
            } else {
                checked = checked.intersection(Set(allItems.map(\.id)))
            }
            SiriFacts.saveCleanup(suggested: suggestedBytes, reclaimable: reclaimable)   // v9: Siri's answer
            state.goalSummary[.cleanup] = suggestedBytes > 0 ? String(localized: "\(Format.bytes(suggestedBytes)) suggested") : (reclaimable > 0 ? Format.bytes(reclaimable) : String(localized: "nothing"))
        }
    }
}

private struct CleanupGroupCard: View {
    let group: CleanupGroup
    @Binding var checked: Set<UUID>
    let expanded: Bool
    let toggle: () -> Void
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var scheme
    @State private var showAll = false

    private var selectedCount: Int { group.items.filter { checked.contains($0.id) }.count }
    private var isInfo: Bool { group.rule.mode == .info }
    private var suggestedCount: Int { group.suggested.count }
    /// Only the symbol changes color: amber when the rule calls for review.
    private var symbolColor: Color {
        switch (group.rule.mode, group.rule.safety) {
        case (.info, _): return .secondary
        case (_, .review?): return Color(hex: scheme == .dark ? 0xFFD60A : 0xB45309)
        default: return .primary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(scheme == .dark ? 0.10 : 0.06))
                        Image(systemName: group.rule.symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(symbolColor)
                    }
                    .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(group.rule.title).font(.system(size: 13.5, weight: .semibold))
                            if group.rule.safety == .review {
                                Text("review first").font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(Capsule().fill(Color(hex: 0xF59E0B).opacity(0.18)))
                                    .foregroundStyle(Color(hex: scheme == .dark ? 0xFBBF24 : 0xB45309))
                            }
                            if isInfo {
                                Text("info only").font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(Capsule().fill(Color.primary.opacity(0.08))).foregroundStyle(.secondary)
                            }
                            if suggestedCount > 0 {
                                Label(suggestedCount == 1 ? String(localized: "1 suggested") : String(localized: "\(suggestedCount) suggested"), systemImage: "sparkles")
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(Capsule().fill(Theme.success.opacity(0.14)))
                                    .foregroundStyle(Color(hex: scheme == .dark ? 0x4ADE80 : 0x1B7F3B))
                            }
                        }
                        Text(group.rule.why).font(.system(size: 11)).foregroundStyle(.secondary)
                            .lineLimit(expanded ? nil : 1).fixedSize(horizontal: false, vertical: expanded)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        RollingNumber(text: Format.bytes(group.total), font: .system(size: 15, weight: .semibold))
                        Text(isInfo ? (group.locations.count == 1 ? String(localized: "1 folder") : String(localized: "\(group.locations.count) folders"))
                                    : selectedCount > 0 ? String(localized: "\(selectedCount) of \(group.items.count) selected")
                                    : (group.items.count == 1 ? String(localized: "1 item") : String(localized: "\(group.items.count) items")))
                            .font(.system(size: 10.5)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                Divider().opacity(0.5)
                if isInfo {
                    HStack(spacing: 8) {
                        ForEach(group.locations) { loc in
                            Button { state.revealInFinder(loc) } label: {
                                Label("\(loc.name) · \(Format.bytes(loc.allocatedSize))", systemImage: "folder")
                                    .font(.system(size: 11.5, weight: .medium))
                            }
                            .controlSize(.small)
                        }
                        Spacer()
                    }
                    .padding(12)
                } else {
                    HStack {
                        Button(selectedCount == group.items.count ? String(localized: "Deselect All") : String(localized: "Select All")) {
                            let ids = group.items.map(\.id)
                            if selectedCount == group.items.count { checked.subtract(ids) } else { checked.formUnion(ids) }
                        }
                        .controlSize(.small)
                        Spacer()
                        if group.items.count > 40 && !showAll {
                            Button("Show All \(group.items.count)") { showAll = true }.controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 12).padding(.top, 8)
                    LazyVStack(spacing: 1) {
                        ForEach(showAll ? group.items : Array(group.items.prefix(40))) { n in
                            ItemRow(node: n, checked: Binding(
                                get: { checked.contains(n.id) },
                                set: { if $0 { checked.insert(n.id) } else { checked.remove(n.id) } }),
                                    subtitle: group.rule.mode == .self ? n.path : nil,
                                    trailing: Format.relative(n.lastUsed),
                                    hint: group.suggested[n.id].map { d in d == 0 ? String(localized: "Suggested: unchanged since it was created.") : (d == 1 ? String(localized: "Suggested: unchanged for 1 day; the app recreates it if needed.") : String(localized: "Suggested: unchanged for \(d) days; the app recreates it if needed.")) })
                        }
                    }
                    .padding(8)
                }
            }
        }
        .contentCard(corner: Theme.cornerL)
    }
}


/// After moving to the Trash: what was removed, and a reminder that the space only comes back once the Trash is emptied.
private struct CleanupDoneBanner: View {
    let outcome: AppState.TrashOutcome
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.success.opacity(0.16))
                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.success)
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                (outcome.items == 1
                 ? Text("Done: moved \(Format.bytes(outcome.bytes)) in 1 item to the Trash.")
                 : Text("Done: moved \(Format.bytes(outcome.bytes)) in \(outcome.items) items to the Trash."))
                    .font(.system(size: 13, weight: .semibold))
                Text("The space is only freed when you empty the Trash. If you miss something, you can restore it from there.")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Spacer()
            PillButton(title: String(localized: "Show Trash"), systemImage: "trash", prominent: false, compact: true) { state.revealTrash() }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .contentCard(corner: Theme.cornerL, hoverable: false)
    }
}
