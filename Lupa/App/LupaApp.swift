import SwiftUI

@main
struct LegroomApp: App {
    /// Identifier of the main window (used by the menu bar's "Open Legroom").
    static let mainWindowID = "main"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var state = AppState()
    @AppStorage(AppearanceMode.key) private var appearance: AppearanceMode = .system
    @AppStorage(MenuBarPrefs.show) private var showMenuBar = true

    init() {
        Trail.note("launched: version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"), arguments \(CommandLine.arguments.count - 1)")
        DebugLaunch.early()
        _ = Updates.shared   // starts Sparkle's scheduler (Release builds)
    }

    var body: some Scene {
        WindowGroup("Legroom", id: Self.mainWindowID) {
            ContentView()
                .environment(state)
                .frame(minWidth: 1080, minHeight: 680)
                .preferredColorScheme(appearance.colorScheme)
                .task { state.refreshVolumes() }
                .onOpenURL { state.handle(url: $0) }   // v8: legroom://resumo (widget)
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])   // v8: reuses the open window
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .appInfo) { CheckForUpdatesButton() }
            CommandMenu("Scan") {
                Button("Scan Folder…") { state.chooseFolder() }
                    .keyboardShortcut("o", modifiers: [.command])
                Button("Refresh Volumes") { state.refreshVolumes() }
                    .keyboardShortcut("r", modifiers: [.command])
                Button("Cancel Scan") { state.cancelScan() }
                    .keyboardShortcut(".", modifiers: [.command])
                    .disabled(!state.isScanning)
                Divider()
                Toggle("Show Hidden Items", isOn: Binding(
                    get: { state.showHidden },
                    set: { state.showHidden = $0 }))
                    .keyboardShortcut("h", modifiers: [.command, .shift])
            }
            CommandMenu("View") {
                ForEach(Array(Goal.allCases.enumerated()), id: \.element) { i, g in
                    Button(g.title) { state.selectGoal(g) }
                        .keyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: [.command])
                }
                Divider()
                Button("Map Only") { state.viewMode = .map }.keyboardShortcut("1", modifiers: [.command, .option])
                Button("List Only") { state.viewMode = .list }.keyboardShortcut("2", modifiers: [.command, .option])
                Button("Map and List") { state.viewMode = .split }.keyboardShortcut("3", modifiers: [.command, .option])
                Divider()
                Picker("Appearance", selection: $appearance) {
                    ForEach(AppearanceMode.allCases) { m in Label(m.title, systemImage: m.symbol).tag(m) }
                }
            }
        }
        Settings {
            SettingsView().environment(state)
                .preferredColorScheme(appearance.colorScheme)
        }
        // Mini overview in the menu bar: same AppState as the window, readings only while the popover is open.
        // Read-only binding: macOS temporarily hides the item when the menu bar runs out
        // of room (notch, active app with many menus) and MenuBarExtra writes that
        // "false" back; bound directly to @AppStorage, that turned the preference off
        // and caused an update loop. Only Settings turns it on and off.
        MenuBarExtra(isInserted: Binding(get: { showMenuBar }, set: { _ in })) {
            // .preferredColorScheme here causes an update loop in the app's graph
            // (the main menu is rebuilt nonstop); the panel applies the appearance itself.
            MenuBarPanel()
                .environment(state)
        } label: {
            MenuBarLabel().environment(state)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Closing the main window doesn't quit the app while the menu bar item is on
/// (it remains the way back to Legroom). Without the item, closing the last
/// window quits, like macOS single-window utilities.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !MenuBarPrefs.isShown
    }

    /// If the last Map scan is still being saved, waits for it to finish
    /// (up to 20 s) before quitting, so it's there the next time the app opens.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard MapStore.isSaving else { return .terminateNow }
        Trail.note("quitting: waiting for the map to finish saving")
        let deadline = Date().addingTimeInterval(20)
        Task.detached {
            while MapStore.isSaving && Date() < deadline { try? await Task.sleep(for: .milliseconds(100)) }
            await MainActor.run { NSApp.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }
}
