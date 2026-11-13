import AppKit

/// When Legroom is opened straight from its disk image (or from a translocated
/// copy macOS made of it), it offers once per launch to copy itself into
/// /Applications, reopen from there and eject the disk image. Running from the
/// DMG works, but the app vanishes when the DMG is ejected and Sparkle can't
/// update it.
enum MoveToApplications {
    private static let ejectFlag = "--eject-after-move"

    @MainActor
    static func offerIfNeeded() {
        ejectInstallerIfAsked()

        let source = Bundle.main.bundleURL
        guard isRunningFromInstaller(source) else { return }
        var applications = URL(fileURLWithPath: "/Applications")
        var confirmed = false
        #if DEBUG
        // Testing: LEGROOM_MOVE_TO=<folder> moves there without asking.
        if let dir = ProcessInfo.processInfo.environment["LEGROOM_MOVE_TO"] {
            applications = URL(fileURLWithPath: dir)
            confirmed = true
        }
        #endif
        let destination = applications.appendingPathComponent(source.lastPathComponent)

        let alert = NSAlert()
        alert.messageText = String(localized: "Move Legroom to Applications?")
        alert.informativeText = String(localized: "Legroom is running from its disk image. In the Applications folder it stays after you eject the disk image, and it can update itself.")
        alert.addButton(withTitle: String(localized: "Move to Applications"))
        alert.addButton(withTitle: String(localized: "Not Now"))
        guard confirmed || alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                // An older copy: to the Trash, like everything Legroom removes.
                try FileManager.default.trashItem(at: destination, resultingItemURL: nil)
            }
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            let failed = NSAlert()
            failed.messageText = String(localized: "Couldn't move Legroom")
            failed.informativeText = String(localized: "Drag Legroom from the disk image to the Applications folder in Finder, then open it from there.")
            failed.runModal()
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        if let volume = installerVolume(for: source) {
            config.arguments = [ejectFlag, volume.path]
        }
        NSWorkspace.shared.openApplication(at: destination, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    /// Inside a read-only volume (the mounted DMG) or an App Translocation mount.
    static func isRunningFromInstaller(_ bundle: URL) -> Bool {
        if bundle.path.contains("/AppTranslocation/") { return true }
        guard bundle.path.hasPrefix("/Volumes/"),
              let readOnly = try? bundle.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly
        else { return false }
        return readOnly
    }

    /// The mounted disk image Legroom came from: the volume itself, or, for a
    /// translocated copy, a read-only disk image with a Legroom.app at its root.
    private static func installerVolume(for bundle: URL) -> URL? {
        if !bundle.path.contains("/AppTranslocation/"),
           let volume = try? bundle.resourceValues(forKeys: [.volumeURLKey]).volume {
            return Volume.isDiskImage(volume) ? volume : nil
        }
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeIsReadOnlyKey], options: []) ?? []
        return volumes.first { v in
            v.path.hasPrefix("/Volumes/")
                && (try? v.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) == true
                && Bundle(url: v.appendingPathComponent(bundle.lastPathComponent))?.bundleIdentifier == Bundle.main.bundleIdentifier
                && Volume.isDiskImage(v)
        }
    }

    /// The copy in /Applications ejects the disk image the old copy ran from,
    /// once that one has quit.
    private static func ejectInstallerIfAsked() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: ejectFlag), i + 1 < args.count else { return }
        let volume = URL(fileURLWithPath: args[i + 1])
        guard volume.path.hasPrefix("/Volumes/"), Volume.isDiskImage(volume) else { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            try? NSWorkspace.shared.unmountAndEjectDevice(at: volume)
        }
    }
}
