import SwiftUI

/// The Check-up screen: macOS's own defenses, Apple's own scan results and what
/// starts on its own. Calm by design: it shows facts and reasons, never a
/// "threats found" count, and every change it makes can be undone from the Trash.
struct SecurityScreen: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let checking = state.goalScanning.contains(.security)
        VStack(spacing: 12) {
            GoalHeader(goal: .security) {
                if let r = state.securityReport, !checking {
                    MapDateLabel(date: r.date, restored: true, prefix: String(localized: "checked"))
                    RefreshButton { state.runSecurityCheck() }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)

            ZStack(alignment: .bottom) {
                Group {
                    if let report = state.securityReport {
                        SecurityReportView(report: report)
                            .opacity(checking ? 0.45 : 1)
                            .allowsHitTesting(!checking)
                    } else if checking {
                        CheckingView()
                    } else {
                        SecurityStartView()
                    }
                }
                .transition(.focus)
                TrashNotice().padding(.bottom, -132)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Before the first check

private struct SecurityStartView: View {
    @Environment(AppState.self) private var state
    var body: some View {
        VStack(spacing: 18) {
            GoalIcon(goal: .security, size: 64, prominent: true)
            VStack(spacing: 6) {
                Text(Goal.security.question).font(.system(size: 22, weight: .semibold)).tracking(-0.4)
                Text(Goal.security.promise).font(.system(size: 13)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 460)
            }
            PillButton(title: String(localized: "Check Now"), systemImage: "arrow.right") { state.runSecurityCheck() }
                .keyboardShortcut(.defaultAction)
            Text("Runs only on this Mac. Nothing is sent anywhere, and nothing changes unless you ask.")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CheckingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.regular)
            Text("Checking your Mac…").font(.system(size: 14, weight: .semibold))
            Text("Reading Apple's scan results and what starts on its own.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Report

private struct SecurityReportView: View {
    let report: SecurityReport
    @Environment(AppState.self) private var state
    @State private var showApple = false

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                SummaryCard(report: report)

                Section(title: String(localized: "Your Mac's defenses"),
                        subtitle: String(localized: "Protections built into macOS. Legroom only reads their state.")) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
                        ForEach(report.defenses) { DefenseCard(defense: $0) }
                    }
                }

                Section(title: String(localized: "Apple's own checks"),
                        subtitle: String(localized: "XProtect Remediator scans for known malware in the background and removes what it finds. This is Apple's result, as macOS recorded it.")) {
                    AppleScanCard(scan: report.appleScan)
                }

                let review = report.startup.filter { $0.verdict.isReview }
                let leftovers = report.startup.filter { if case .leftover = $0.verdict { return true } else { return false } }
                let developers = report.startup.filter { if case .developer = $0.verdict { return true } else { return false } }
                let apple = report.startup.filter { if case .apple = $0.verdict { return true } else { return false } }

                Color.clear.frame(height: 0).id("startup")
                Section(title: String(localized: "What starts on its own"),
                        subtitle: String(localized: "Launch agents and services, and who signed what they run. Something unsigned isn't necessarily bad — your own scripts look the same — but it's worth knowing what it is.")) {
                    VStack(alignment: .leading, spacing: 18) {
                        if report.startup.isEmpty {
                            Text("Nothing in the launch agent folders.").font(.system(size: 12.5)).foregroundStyle(.secondary)
                        }
                        StartupGroup(title: String(localized: "Worth a look"), symbol: "eye", items: review, tint: .amber)
                        StartupGroup(title: String(localized: "Leftovers"), symbol: "tray",
                                     caption: String(localized: "Point to something that no longer exists. Safe to turn off."), items: leftovers, tint: .gray)
                        StartupGroup(title: String(localized: "Identified developers"), symbol: "checkmark.seal", items: developers, tint: .gray)
                        if !apple.isEmpty {
                            DisclosureGroup(isExpanded: $showApple) {
                                StartupGroup(title: nil, symbol: "apple.logo", items: apple, tint: .gray).padding(.top, 8)
                            } label: {
                                Text(apple.count == 1 ? String(localized: "1 item runs macOS's own tools") : String(localized: "\(apple.count) items run macOS's own tools"))
                                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.secondary)
                            }
                        }
                        LoginItemsHint()
                    }
                }

                TipCard()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        // debug captures only: --scroll-checkup jumps to the startup items
        .onAppear { if CommandLine.arguments.contains("--scroll-checkup") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { proxy.scrollTo("startup", anchor: .top) } } }
        }
    }
}

private struct Section<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 16, weight: .semibold)).tracking(-0.2)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            content
        }
    }
}

// MARK: Summary

private struct SummaryCard: View {
    let report: SecurityReport
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let off = report.defensesOff.count
        let look = report.reviewCount + off
        let on = report.defenses.filter { $0.state == .on }.count
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle().fill((look == 0 ? Theme.success : Palette.amber).opacity(0.16))
                Image(systemName: look == 0 ? "checkmark" : "eye")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(look == 0 ? Theme.success : Palette.amberText(scheme))
            }
            .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(look == 0 ? String(localized: "Nothing unusual") : look == 1 ? String(localized: "1 thing worth a look") : String(localized: "\(look) things worth a look"))
                    .font(.system(size: 20, weight: .semibold)).tracking(-0.4)
                Text(summaryLine(on: on))
                    .font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(corner: Theme.cornerXL, hoverable: false)
    }

    private func summaryLine(on: Int) -> String {
        var parts = [String(localized: "\(on) of \(report.defenses.count) defenses on")]
        if let s = report.appleScan {
            parts.append(s.findings.isEmpty
                         ? String(localized: "Apple's last check found nothing (\(Format.relative(s.date)))")
                         : String(localized: "Apple's last check reported something (\(Format.relative(s.date)))"))
        }
        parts.append(report.startup.count == 1 ? String(localized: "1 item starts on its own") : String(localized: "\(report.startup.count) items start on their own"))
        return parts.joined(separator: " · ")
    }
}

// MARK: Defenses

private struct DefenseCard: View {
    let defense: Defense
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: defense.symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary).frame(width: 18)
                Text(defense.title).font(.system(size: 13, weight: .semibold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                StatePill(state: defense.state)
            }
            Text(defense.explanation).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let d = defense.detail {
                Text(d).font(.system(size: 11.5, weight: .medium)).monospacedDigit()
            }
            if let a = defense.advice {
                Text(a).font(.system(size: 11.5)).foregroundStyle(Palette.amberText(scheme)).fixedSize(horizontal: false, vertical: true)
            }
            if defense.state == .off, let url = defense.settingsURL {
                PillButton(title: String(localized: "Open Settings"), systemImage: "gearshape", prominent: false, compact: true) {
                    NSWorkspace.shared.open(url)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .contentCard(corner: Theme.cornerL, hoverable: false)
    }
}

private struct StatePill: View {
    let state: Defense.State
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let (text, fg, bg): (String, Color, Color) = {
            switch state {
            case .on: return (String(localized: "On"), Color(hex: scheme == .dark ? 0x4ADE80 : 0x1B7F3B), Theme.success.opacity(0.14))
            case .off: return (String(localized: "Off"), Palette.amberText(scheme), Palette.amber.opacity(0.18))
            case .unknown: return (String(localized: "Unknown"), .secondary, Color.primary.opacity(0.08))
            }
        }()
        Text(text).font(.system(size: 10.5, weight: .semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(bg)).foregroundStyle(fg)
    }
}

// MARK: Apple's scan

private struct AppleScanCard: View {
    let scan: AppleScan?
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "apple.logo").font(.system(size: 16)).foregroundStyle(.secondary).frame(width: 22)
            VStack(alignment: .leading, spacing: 6) {
                if let scan {
                    Text("Last run \(Format.relative(scan.date)), with \(scan.scanners) malware-family scanners.")
                        .font(.system(size: 13, weight: .semibold))
                    if scan.findings.isEmpty {
                        Text("None of them found anything.").font(.system(size: 12)).foregroundStyle(.secondary)
                    } else {
                        Text("Apple reported results for these families. XProtect removes what it can on its own; restarting lets it finish.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        ForEach(scan.findings) { f in
                            HStack(spacing: 8) {
                                Text(f.family).font(.system(size: 12, weight: .semibold))
                                Text(f.status).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Palette.amberText(scheme))
                            }
                        }
                    }
                } else {
                    Text("No record of a run in the last 4 days.").font(.system(size: 13, weight: .semibold))
                    Text("XProtect Remediator runs when the Mac is idle, usually on power. This isn't a problem by itself.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(corner: Theme.cornerL, hoverable: false)
    }
}

// MARK: Startup items

private enum RowTint { case amber, gray }

private struct StartupGroup: View {
    let title: String?
    let symbol: String
    var caption: String? = nil
    let items: [StartupItem]
    let tint: RowTint
    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if let title {
                    HStack(spacing: 6) {
                        Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                        Text("\(title) · \(items.count)").font(.system(size: 12.5, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                    if let caption { Text(caption).font(.system(size: 11.5)).foregroundStyle(.tertiary) }
                }
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                        StartupRow(item: item, tint: tint)
                        if i < items.count - 1 { Divider().padding(.leading, 52) }
                    }
                }
                .contentCard(corner: Theme.cornerL, hoverable: false)
            }
        }
    }
}

private struct StartupRow: View {
    let item: StartupItem
    let tint: RowTint
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var scheme
    @State private var confirm = false
    @State private var hover = false

    var body: some View {
        let off = state.securityTurnedOff.contains(item.id)
        HStack(alignment: .top, spacing: 12) {
            icon.frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.displayName).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if off {
                        Text("turned off").font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(Color.primary.opacity(0.08))).foregroundStyle(.secondary)
                    }
                }
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                if let p = item.program {
                    // the script itself is already the program; don't repeat it among the arguments
                    let args = item.arguments.filter { ($0 as NSString).expandingTildeInPath != p }
                    Text(abbreviated(p) + (args.isEmpty ? "" : " " + args.prefix(3).joined(separator: " ")))
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle).help(p)
                }
                chips
            }
            Spacer(minLength: 8)
            if !off { actions }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .opacity(off ? 0.5 : 1)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(hover ? 0.03 : 0)))
        .onHover { hover = $0 }
        .confirmationDialog(String(localized: "Turn off “\(item.displayName)”?"), isPresented: $confirm, titleVisibility: .visible) {
            Button(String(localized: "Turn Off"), role: .destructive) { state.turnOff(item) }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(item.domain == .user
                 ? String(localized: "It stops now and won't start again. Its file (\(item.plist.lastPathComponent)) goes to the Trash; put it back and log in again to undo.")
                 : String(localized: "Its file (\(item.plist.lastPathComponent)) goes to the Trash; Finder will ask for an administrator password. It stops after the next restart; put the file back to undo."))
        }
    }

    @ViewBuilder private var icon: some View {
        if let app = item.ownerApp, FileManager.default.fileExists(atPath: app.path) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().interpolation(.high)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(scheme == .dark ? 0.10 : 0.06))
                Image(systemName: rowSymbol).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint == .amber ? Palette.amberText(scheme) : .secondary)
            }
        }
    }

    private var rowSymbol: String {
        switch item.verdict {
        case .review(let r) where r.contains(.script) || r.contains(.inlineCommand): return "terminal"
        case .leftover: return "questionmark.folder"
        case .apple: return "apple.logo"
        default: return "gearshape.2"
        }
    }

    private var subtitle: String {
        let who: String
        switch item.verdict {
        case .apple: who = item.label.hasPrefix("com.apple.") ? String(localized: "Apple") : String(localized: "Runs a tool built into macOS")
        case .developer(let name, let team): who = name == team ? String(localized: "Signed by \(team)") : String(localized: "Signed by \(name) (\(team))")
        case .review(let r) where r.contains(.script) || r.contains(.inlineCommand): who = String(localized: "Script")
        case .review: who = String(localized: "Not from an identified developer")
        case .leftover: who = String(localized: "Points to a missing file")
        }
        let label = item.displayName == item.label ? "" : " · " + item.label
        return who + " · " + item.domain.title + label
    }

    @ViewBuilder private var chips: some View {
        let reasons: [StartupItem.Reason] = { if case .review(let r) = item.verdict { return r } else { return [] } }()
        if !reasons.isEmpty || !item.notes.isEmpty {
            HStack(spacing: 5) {
                ForEach(reasons, id: \.self) { r in
                    Text(r.text).font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Palette.amber.opacity(0.16))).foregroundStyle(Palette.amberText(scheme))
                }
                ForEach(item.notes, id: \.self) { r in
                    Text(r.text).font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.07))).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 6) {
            if let app = item.ownerApp, FileManager.default.fileExists(atPath: app.path),
               app.path.hasPrefix("/Applications/") || app.path.hasPrefix(NSHomeDirectory() + "/Applications/") {
                PillButton(title: String(localized: "Uninstall…"), prominent: false, compact: true) { state.uninstallOwner(of: item) }
                    .help(String(localized: "Review and uninstall \(app.deletingPathExtension().lastPathComponent) with its leftovers"))
            }
            if case .apple = item.verdict {} else {
                PillButton(title: String(localized: "Turn Off…"), prominent: false, compact: true) { confirm = true }
            }
            Menu {
                Button(String(localized: "Show File in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([item.plist]) }
                if let p = item.program, FileManager.default.fileExists(atPath: p) {
                    Button(String(localized: "Show Program in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]) }
                }
                Button(String(localized: "Copy Label")) {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.label, forType: .string)
                }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold)).frame(width: 26, height: 26)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
    }

    private func abbreviated(_ p: String) -> String { (p as NSString).abbreviatingWithTildeInPath }
}

private struct LoginItemsHint: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.checkmark").foregroundStyle(.secondary)
            Text("Apps can also open at login through Login Items, which only System Settings can list in full.")
                .font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            PillButton(title: String(localized: "Open Login Items"), prominent: false, compact: true) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") { NSWorkspace.shared.open(url) }
            }
        }
    }
}

// MARK: Tip

private struct TipCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "terminal").font(.system(size: 15)).foregroundStyle(.secondary).frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text("No real website asks you to paste commands into Terminal.")
                    .font(.system(size: 13, weight: .semibold))
                Text("Most Mac malware today arrives this way: a fake “verification” or a guide to free up space asks you to paste a command. The same goes for scripts in Script Editor and apps from outside the App Store or the developer's own site.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard(corner: Theme.cornerL, hoverable: false)
    }
}

/// Amber, the "worth a look" color (same as "review first" in Cleanup).
enum Palette {
    static let amber = Color(hex: 0xF59E0B)
    static func amberText(_ scheme: ColorScheme) -> Color { Color(hex: scheme == .dark ? 0xFBBF24 : 0xB45309) }
}
