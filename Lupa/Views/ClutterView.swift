import SwiftUI

/// "Clutter": duplicates, old downloads, installers and screenshots in the user's
/// folders. Duplicates are confirmed by a content signature.
struct ClutterView: View {
    @Environment(AppState.self) private var state
    let roots: [FileNode]
    let key: Int
    @State private var kind: ClutterKind = .duplicates
    @State private var report = ClutterReport()
    @State private var checked: Set<UUID> = []
    @State private var hashing: (done: Int, total: Int)? = nil

    private var allItems: [FileNode] { ClutterKind.allCases.flatMap { report.items(for: $0) } }
    private var selectedNodes: [FileNode] {
        var seen = Set<UUID>()
        return allItems.filter { checked.contains($0.id) && seen.insert($0.id).inserted }
    }
    private var selectedBytes: Int64 { selectedNodes.reduce(0) { $0 + $1.allocatedSize } }

    var body: some View {
        VStack(spacing: 12) {
            if !report.coversHome {
                EmptyHint(symbol: "house", title: String(localized: "No folders to scan"),
                          text: String(localized: "Clutter looks in the visible folders of your home folder, outside Library."))
                    .contentCard()
            } else {
                HStack(spacing: 10) {
                    PillTabs(items: ClutterKind.allCases.map { ($0, "\($0.title) · \(countLabel($0))", $0.symbol) }, selection: $kind)
                    if let hashing {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Comparing \(hashing.done) of \(hashing.total)").font(.system(size: 11.5)).foregroundStyle(.secondary).monospacedDigit()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(.thinMaterial))
                        .transition(.focus)
                    }
                    Spacer()
                }
                HStack(alignment: .center, spacing: 12) {
                    Text(kind.explanation).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    SelectionBar(count: selectedNodes.count, bytes: selectedBytes) { state.requestTrash(selectedNodes) }
                }
                .padding(.horizontal, 4)
                Group {
                    switch kind {
                    case .duplicates:
                        if report.duplicates.isEmpty {
                            EmptyHint(symbol: "checkmark.seal", title: hashing == nil ? String(localized: "No duplicates found") : String(localized: "Looking for duplicates…"),
                                      text: hashing == nil ? String(localized: "Files of 1 MB or larger in your home folder, outside Library.") : String(localized: "Files of the same size are being compared byte by byte."))
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 10) {
                                    ForEach(report.duplicates) { g in DuplicateCard(group: g, checked: $checked) }
                                }
                                .padding(2)
                            }
                            .scrollIndicators(.hidden)
                        }
                    default:
                        let items = report.items(for: kind)
                        if items.isEmpty {
                            EmptyHint(symbol: "checkmark.seal", title: String(localized: "Nothing here"), text: kind.explanation)
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 1) {
                                    HStack {
                                        Button(allChecked(items) ? String(localized: "Deselect All") : String(localized: "Select All")) {
                                            let ids = items.map(\.id)
                                            if allChecked(items) { checked.subtract(ids) } else { checked.formUnion(ids) }
                                        }
                                        .controlSize(.small)
                                        Spacer()
                                        Text("\(Format.bytes(report.total(for: kind))) in \(items.count) items").font(.system(size: 11.5)).foregroundStyle(.secondary).monospacedDigit()
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    ForEach(items) { n in
                                        ItemRow(node: n, checked: binding(n), trailing: Format.relative(n.lastUsed))
                                    }
                                }
                                .padding(8)
                            }
                            .scrollIndicators(.hidden)
                            .contentCard()
                        }
                    }
                }
                .id(kind)
                .transition(.focus)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: kind)
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: hashing == nil)
        .task(id: key) {
            var r = roots.clutterReport()
            let candidates = r.duplicateCandidates
            r.duplicateCandidates = []
            report = r
            let valid = Set(allItems.map(\.id)).union(candidates.flatMap { $0 }.map(\.id))
            checked = checked.intersection(valid)
            guard !candidates.isEmpty else { hashing = nil; return }
            let total = candidates.reduce(0) { $0 + $1.count }
            hashing = (0, total)
            let groups = await Duplicates.resolve(candidates) { done in
                Task { @MainActor in self.hashing = (min(done, total), total) }
            }
            guard !Task.isCancelled else { return }
            report.duplicates = groups
            hashing = nil
            publishSummary()
        }
    }

    private func publishSummary() {
        let total = ClutterKind.allCases.reduce(Int64(0)) { $0 + report.total(for: $1) }
        state.goalSummary[.clutter] = total > 0 ? Format.bytes(total) : String(localized: "nothing")
    }

    private func countLabel(_ k: ClutterKind) -> String {
        k == .duplicates ? "\(report.duplicates.count)" : "\(report.items(for: k).count)"
    }
    private func allChecked(_ items: [FileNode]) -> Bool { !items.isEmpty && items.allSatisfy { checked.contains($0.id) } }
    private func binding(_ n: FileNode) -> Binding<Bool> {
        Binding(get: { checked.contains(n.id) }, set: { if $0 { checked.insert(n.id) } else { checked.remove(n.id) } })
    }
}

private struct DuplicateCard: View {
    let group: DuplicateGroup
    @Binding var checked: Set<UUID>
    @Environment(\.colorScheme) private var scheme

    private var copiesMarked: Bool { group.files.dropFirst().allSatisfy { checked.contains($0.id) } && !group.files.dropFirst().isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: group.files[0].path)).resizable().frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(group.files[0].name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text("\(group.files.count) copies of \(Format.bytes(group.size)) · \(Format.bytes(group.wasted)) more than needed")
                        .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                Button(copiesMarked ? String(localized: "Deselect Copies") : String(localized: "Select Copies, Keep Newest")) {
                    let ids = group.files.dropFirst().map(\.id)
                    if copiesMarked { checked.subtract(ids) } else { checked.formUnion(ids); checked.remove(group.files[0].id) }
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 12).padding(.top, 12)
            LazyVStack(spacing: 1) {
                ForEach(Array(group.files.enumerated()), id: \.element.id) { i, n in
                    ItemRow(node: n, checked: Binding(
                        get: { checked.contains(n.id) },
                        set: { if $0 { checked.insert(n.id) } else { checked.remove(n.id) } }),
                            subtitle: n.parent?.path, trailing: i == 0 ? String(localized: "newest · \(Format.relative(n.lastUsed))") : Format.relative(n.lastUsed))
                }
            }
            .padding(8)
        }
        .contentCard(corner: Theme.cornerL)
    }
}
