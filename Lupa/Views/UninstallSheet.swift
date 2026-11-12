import SwiftUI

/// Uninstall review: the app and everything it left outside its bundle, already
/// selected. Everything goes to the Trash; nothing is permanently deleted.
struct UninstallSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var scheme
    /// For screenshots only: no scrolling (ImageRenderer doesn't draw ScrollView).
    var flat = false

    var body: some View {
        let dark = scheme == .dark
        if let plan = state.pendingUninstall {
            VStack(alignment: .leading, spacing: 0) {
                header(plan)
                    .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 14)
                Divider()
                scroller {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            groupTitle(String(localized: "App"))
                            ForEach(plan.apps, id: \.path) { a in
                                row(icon: AnyView(Image(nsImage: NSWorkspace.shared.icon(forFile: a.path)).resizable().frame(width: 18, height: 18)),
                                    path: (a.path as NSString).abbreviatingWithTildeInPath, bytes: a.allocatedSize, toggle: nil)
                            }
                        }
                        if plan.searching {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Looking for the app's data, caches, and preferences…").font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                        } else if plan.leftovers.isEmpty {
                            Text("The app left nothing outside its bundle.").font(.system(size: 12)).foregroundStyle(.secondary)
                        } else {
                            ForEach(Leftover.Kind.allCases, id: \.self) { kind in
                                let items = plan.leftovers.filter { $0.kind == kind }
                                if !items.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        groupTitle(kind.title)
                                        ForEach(items) { l in
                                            row(icon: AnyView(Image(systemName: symbol(kind)).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 18)),
                                                path: l.displayPath, bytes: l.bytes, toggle: l.id)
                                            if !l.suggested {
                                                Text("May belong to a command-line tool with the same name. Select it only if you're sure.")
                                                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
                                                    .padding(.leading, 56)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(22)
                }
                Divider()
                footer(plan)
                    .padding(.horizontal, 22).padding(.vertical, 16)
            }
            .frame(width: 560)
            .background(dark ? Color(hex: 0x1C1C1F) : Color.white)
        }
    }

    @ViewBuilder private func scroller<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        if flat { c() } else { ScrollView { c() }.frame(minHeight: 180, maxHeight: 380) }
    }

    private func header(_ plan: AppState.UninstallPlan) -> some View {
        let name = plan.apps.count == 1 ? ((plan.apps[0].name as NSString).lastPathComponent as NSString).deletingPathExtension : String(localized: "\(plan.apps.count) apps")
        return VStack(alignment: .leading, spacing: 6) {
            Text("Uninstall \(name)").font(.system(size: 18, weight: .semibold)).tracking(-0.3)
            Text("The app and what it stored on your Mac go to the Trash. You can restore them from there until the Trash is emptied.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !plan.running.isEmpty {
                Label("\(name) is open and will be quit first.", systemImage: "info.circle")
                    .font(.system(size: 11.5, weight: .medium)).foregroundStyle(.secondary)
            }
        }
    }

    private func footer(_ plan: AppState.UninstallPlan) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(Format.bytes(plan.selectedBytes)).font(.system(size: 15, weight: .semibold)).monospacedDigit()
                Text(plan.searching ? String(localized: "looking for leftovers…") : (plan.apps.count + plan.selected.count == 1 ? String(localized: "1 item to the Trash") : String(localized: "\(plan.apps.count + plan.selected.count) items to the Trash")))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            PillButton(title: String(localized: "Cancel"), prominent: false) { state.pendingUninstall = nil }
                .keyboardShortcut(.cancelAction)
            PillButton(title: String(localized: "Uninstall"), systemImage: "trash") { state.confirmUninstall() }
                .disabled(plan.searching)
                .opacity(plan.searching ? 0.5 : 1)
        }
    }

    private func groupTitle(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(0.5).foregroundStyle(.secondary)
    }

    private func row(icon: AnyView, path: String, bytes: Int64, toggle id: String?) -> some View {
        HStack(spacing: 10) {
            if let id {
                Toggle("", isOn: Binding(
                    get: { state.pendingUninstall?.selected.contains(id) ?? false },
                    set: { on in
                        if on { state.pendingUninstall?.selected.insert(id) } else { state.pendingUninstall?.selected.remove(id) }
                    }))
                .toggleStyle(.checkbox).labelsHidden()
            } else {
                Image(systemName: "checkmark.square.fill").foregroundStyle(.secondary).font(.system(size: 13))
                    .help("The app is always included.")
            }
            icon
            Text(path).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                .help(path)
            Spacer(minLength: 8)
            Text(Format.bytes(bytes)).font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private func symbol(_ k: Leftover.Kind) -> String {
        switch k {
        case .data: return "folder"
        case .caches: return "clock.arrow.circlepath"
        case .prefs: return "slider.horizontal.3"
        case .logs: return "doc.text"
        case .launch: return "power"
        case .installer: return "shippingbox"
        }
    }
}
