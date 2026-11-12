import AppIntents
import AppKit

// Siri and Shortcuts (v9). Questions only: no action here reads the whole disk, moves
// files or runs on its own. When a scan is missing, the answer offers to open
// Legroom on the right screen, and the scan is still something you start, in the app.
//
// Phrases and titles are in English in the code (development language) and in
// Portuguese in AppShortcuts.xcstrings / Localizable.xcstrings.

// MARK: Screens Siri can open

enum LegroomScreen: String, AppEnum {
    case summary, map, cleanup, large, apps, clutter

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Legroom screen"
    static let caseDisplayRepresentations: [LegroomScreen: DisplayRepresentation] = [
        .summary: DisplayRepresentation(title: "Overview", image: .init(systemName: "doc.text.below.ecg")),
        .map: DisplayRepresentation(title: "Map", image: .init(systemName: "square.grid.3x3.square")),
        .cleanup: DisplayRepresentation(title: "Cleanup", image: .init(systemName: "sparkles")),
        .large: DisplayRepresentation(title: "Large & Forgotten", image: .init(systemName: "shippingbox")),
        .apps: DisplayRepresentation(title: "Apps", image: .init(systemName: "app.badge")),
        .clutter: DisplayRepresentation(title: "Clutter", image: .init(systemName: "tray.full")),
    ]

    /// Same names that `AppState.handle(url:)` understands.
    var url: URL { URL(string: "legroom://\(rawValue)")! }
}

struct OpenScreenIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Legroom"
    static let description = IntentDescription("Opens Legroom on a screen. It only opens it: nothing is read until you start it.")
    static let openAppWhenRun = true

    @Parameter(title: "Screen", default: .summary)
    var screen: LegroomScreen

    init() {}
    init(screen: LegroomScreen) { self.screen = screen }

    static var parameterSummary: some ParameterSummary { Summary("Open Legroom on \(\.$screen)") }

    @MainActor
    func perform() async throws -> some IntentResult {
        Trail.note("siri: OpenScreenIntent")
        NSWorkspace.shared.open(screen.url)
        return .result()
    }
}

// MARK: Perguntas

struct FreeSpaceIntent: AppIntent {
    static let title: LocalizedStringResource = "Free space"
    static let description = IntentDescription("Says how much free space the startup disk has.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        Trail.note("siri: FreeSpaceIntent")
        guard let s = SiriFacts.space() else {
            let msg = String(localized: "I couldn't read the disk right now.")
            return .result(value: msg, dialog: IntentDialog(stringLiteral: msg))
        }
        let msg = String(localized: "You have \(Format.bytes(s.free)) free of \(Format.bytes(s.total)) on \(s.volumeName). ")
            + SiriFacts.healthPhrase(s.health)
        return .result(value: Format.bytes(s.free), dialog: IntentDialog(stringLiteral: msg))
    }
}

struct CleanableIntent: AppIntent {
    static let title: LocalizedStringResource = "What Legroom can clean"
    static let description = IntentDescription("Says how much the last Cleanup scan found. Legroom doesn't scan anything new on its own.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        Trail.note("siri: CleanableIntent")
        guard let c = SiriFacts.cleanup else {
            // No scan yet: asks before opening the app. The scan itself is still
            // something you do, by holding the button on the Cleanup screen.
            if #available(macOS 15.0, *) {
                try await requestConfirmation(actionName: .open, dialog: IntentDialog(stringLiteral: String(localized: "I haven't scanned Cleanup yet. Do you want me to open Legroom there?")))
            }
            await MainActor.run { _ = NSWorkspace.shared.open(LegroomScreen.cleanup.url) }
            return .result(dialog: IntentDialog(stringLiteral: String(localized: "Legroom is open on Cleanup. Hold the button to scan.")))
        }
        let when = SiriFacts.when(c.date)
        let msg: String
        if c.suggested > 0 {
            msg = String(localized: "In the last scan, \(when), Legroom found \(Format.bytes(c.suggested)) that are safe to move to the Trash, out of \(Format.bytes(c.reclaimable)) possible.")
        } else if c.reclaimable > 0 {
            msg = String(localized: "In the last scan, \(when), there were \(Format.bytes(c.reclaimable)) possible, but nothing I'd select without you looking first.")
        } else {
            msg = String(localized: "In the last scan, \(when), there was nothing to clean up.")
        }
        return .result(dialog: IntentDialog(stringLiteral: msg))
    }
}

struct UnusedAppsIntent: AppIntent {
    static let title: LocalizedStringResource = "Apps I don't use"
    static let description = IntentDescription("Lists apps you haven't opened in three months, from what Spotlight already knows. Nothing is uninstalled.")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<[String]> & ProvidesDialog {
        Trail.note("siri: UnusedAppsIntent")
        let apps = SiriFacts.unusedApps()
        guard !apps.isEmpty else {
            let msg = String(localized: "You've used all your apps in the last three months.")
            return .result(value: [], dialog: IntentDialog(stringLiteral: msg))
        }
        let total = apps.reduce(Int64(0)) { $0 + $1.size }
        let top = apps.prefix(3).map { a in a.size > 0 ? "\(a.name) (\(Format.bytes(a.size)))" : a.name }
        let rest = apps.count - top.count
        var msg = apps.count == 1
            ? String(localized: "One app hasn't been used in over three months: ")
            : String(localized: "\(apps.count) apps haven't been used in over three months, \(Format.bytes(total)) in total. The largest: ")
        msg += SiriFacts.list(Array(top))
        msg += rest > 0 ? String(localized: " and \(rest) more.") : "."
        msg += String(localized: " To uninstall, use the Apps screen in Legroom.")
        return .result(value: apps.map(\.name), dialog: IntentDialog(stringLiteral: msg))
    }
}

// MARK: Siri phrases

struct LegroomShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: FreeSpaceIntent(),
            phrases: [
                "How much free space do I have in \(.applicationName)",
                "Check free space with \(.applicationName)",
                "\(.applicationName) free space",
            ],
            shortTitle: "Free space",
            systemImageName: "internaldrive")
        AppShortcut(
            intent: CleanableIntent(),
            phrases: [
                "How much can \(.applicationName) clean",
                "What can \(.applicationName) clean",
                "\(.applicationName) cleanup",
            ],
            shortTitle: "What can be cleaned",
            systemImageName: "sparkles")
        AppShortcut(
            intent: UnusedAppsIntent(),
            phrases: [
                "Which apps don't I use in \(.applicationName)",
                "Show unused apps in \(.applicationName)",
                "\(.applicationName) unused apps",
            ],
            shortTitle: "Unused apps",
            systemImageName: "app.badge")
        AppShortcut(
            intent: OpenScreenIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Open \(\.$screen) in \(.applicationName)",
                "Show \(\.$screen) in \(.applicationName)",
            ],
            shortTitle: "Open Legroom",
            systemImageName: "rectangle.portrait.and.arrow.right")
    }
}
