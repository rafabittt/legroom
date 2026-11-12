import Combine
import Sparkle
import SwiftUI

/// In-app updates with Sparkle.
///
/// The feed is `appcast.xml` at the root of the GitHub repository (SUFeedURL in
/// Info.plist); each entry points to the notarized DMG of a GitHub Release and is
/// signed with an EdDSA key that only the maintainer has (SUPublicEDKey).
///
/// Nothing happens without the user agreeing: on the second launch Sparkle asks
/// whether to check for updates automatically, and the choice can be changed in
/// Settings. "Check for Updates…" in the app menu checks on demand.
///
/// Debug builds don't start the updater (they'd offer to replace the development
/// copy); `--check-updates` turns it on for testing.
@MainActor
final class Updates: ObservableObject {
    static let shared = Updates()

    let controller: SPUStandardUpdaterController
    @Published private(set) var canCheck = false
    private var bag: Set<AnyCancellable> = []

    var updater: SPUUpdater { controller.updater }

    private init() {
        #if DEBUG
        let start = CommandLine.arguments.contains("--check-updates")
        #else
        let start = !CommandLine.arguments.contains("--snapshot")
        #endif
        controller = SPUStandardUpdaterController(startingUpdater: start, updaterDelegate: delegate, userDriverDelegate: nil)
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.canCheck = $0 }
            .store(in: &bag)
        #if DEBUG
        // --check-updates: probe the feed silently and log the result (no UI)
        if start { updater.checkForUpdateInformation() }
        #endif
    }

    private let delegate = UpdaterDelegate()

    func checkForUpdates() {
        Trail.note("updates: checking on demand")
        controller.checkForUpdates(nil)
    }

    /// Mirrors Sparkle's own setting (stored in the app's defaults).
    var automaticallyChecks: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue; objectWillChange.send() }
    }
}

/// Logs what Sparkle decides. In Debug, LEGROOM_FEED_URL points it at a test feed.
final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        #if DEBUG
        return ProcessInfo.processInfo.environment["LEGROOM_FEED_URL"]
        #else
        return nil
        #endif
    }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Trail.note("updates: found \(item.displayVersionString) (\(item.versionString))")
    }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        Trail.note("updates: up to date (\((error as NSError).code))")
    }
    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        Trail.note("updates: aborted: \(error.localizedDescription)")
    }
}

/// "Check for Updates…" for the app menu.
struct CheckForUpdatesButton: View {
    @ObservedObject var updates = Updates.shared
    var body: some View {
        Button("Check for Updates…") { updates.checkForUpdates() }
            .disabled(!updates.canCheck)
    }
}
