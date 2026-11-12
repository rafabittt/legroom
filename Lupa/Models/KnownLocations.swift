import Foundation

/// Short explanations for folders the user sees and doesn't recognize.
/// Kept in one place so they're easy to review and extend.
enum KnownLocations {
    static let descriptions: [String: String] = [
        "/Applications": String(localized: "Installed apps. Deleting an .app here doesn't remove the preferences, caches, and data it left in the Library."),
        "/Library": String(localized: "Data shared by all users: app support, fonts, drivers, and launch agents."),
        "/System": String(localized: "macOS itself. Protected and read-only; its size is fixed and there's nothing to clean here."),
        "/Users": String(localized: "Home folders for each account on this Mac."),
        "/Volumes": String(localized: "Other disks, USB drives, and mounted images. They're scanned separately."),
        "/private": String(localized: "Internal system data: temporary files, logs, and caches in var/folders."),
        "/private/var": String(localized: "System data that changes constantly: logs, databases, caches, and virtual memory."),
        "/private/var/vm": String(localized: "Virtual memory swap and hibernation files. macOS manages them on its own."),
        "/private/var/folders": String(localized: "Per-user caches and temporary files. The system recreates what it needs; deleting by hand is rarely worth it."),
        "/private/tmp": String(localized: "Temporary files. Cleaned up by the system itself."),
        "/usr": String(localized: "Unix command-line tools and libraries."),
        "/opt": String(localized: "Third-party software installed outside the standard locations, like Homebrew on Intel Macs."),
        "/opt/homebrew": String(localized: "Homebrew packages. Run brew cleanup to delete old versions and downloads."),
        "/nix": String(localized: "Packages from the Nix package manager."),
        "~": String(localized: "Your home folder. Almost everything you can safely delete is here."),
        "~/Library": String(localized: "Your apps' data: preferences, caches, support files, containers, and mail. This is where most of “System Data” lives."),
        "~/Library/Caches": String(localized: "App caches. Deleting them frees space, but apps recreate them when they open, so the gain is usually temporary."),
        "~/Library/Application Support": String(localized: "App support data: databases, models, plug-ins. Leftovers from uninstalled apps end up here."),
        "~/Library/Containers": String(localized: "Data from sandboxed apps, one container per app. App Store apps keep almost everything here."),
        "~/Library/Group Containers": String(localized: "Data shared between apps from the same developer, such as extensions and widgets."),
        "~/Library/Developer": String(localized: "Everything Xcode: DerivedData, simulators, device files, and archives. Often tens of GB."),
        "~/Library/Developer/Xcode/DerivedData": String(localized: "Xcode's intermediate builds. Delete them whenever you like; Xcode rebuilds."),
        "~/Library/Developer/Xcode/Archives": String(localized: "Builds archived for distribution. Delete the ones you no longer need to publish."),
        "~/Library/Developer/Xcode/iOS DeviceSupport": String(localized: "Symbols for each iOS version you've connected. Keep only the versions you still use."),
        "~/Library/Developer/CoreSimulator": String(localized: "iPhone, iPad, and Watch simulators, with their apps and data. Run xcrun simctl delete unavailable for outdated ones."),
        "~/Library/Mail": String(localized: "Your Mail messages and attachments. Don't delete them here; use Mail itself."),
        "~/Library/Messages": String(localized: "Messages history and attachments."),
        "~/Library/Application Support/MobileSync/Backup": String(localized: "iPhone and iPad backups made by Finder. Each one can be tens of GB."),
        "~/Library/Logs": String(localized: "Logs from your apps. Safe to delete."),
        "~/Library/Saved Application State": String(localized: "Window state used to restore apps when they reopen. Small and safe."),
        "~/Downloads": String(localized: "Downloads. Used .dmg and .pkg installers often end up here."),
        "~/Movies": String(localized: "Videos, including iMovie and Final Cut libraries."),
        "~/Pictures": String(localized: "Photos, including the Photos library."),
        "~/Music": String(localized: "Music and the Music app library."),
        "~/.Trash": String(localized: "The Trash. Emptying it actually frees the space."),
        "~/node_modules": String(localized: "Dependencies for JavaScript projects."),
        "~/.npm": String(localized: "npm cache. Safe to delete; npm downloads it again."),
        "~/.cache": String(localized: "Caches from command-line tools."),
        "~/.docker": String(localized: "Docker Desktop data, including the virtual machines' disk."),
        "~/.gradle": String(localized: "Gradle caches and distributions."),
        "~/.m2": String(localized: "Local Maven repository."),
        "~/.cargo": String(localized: "Rust caches and binaries."),
        "~/go": String(localized: "Go modules and binaries."),
        "~/.pyenv": String(localized: "Python versions installed by pyenv."),
        "~/.nvm": String(localized: "Node versions installed by nvm."),
    ]

    static func description(forPath path: String) -> String? {
        let home = NSHomeDirectory()
        if let d = descriptions[path] { return d }
        if path.hasPrefix(home) {
            let tilde = "~" + path.dropFirst(home.count)
            if let d = descriptions[String(tilde)] { return d }
            // node_modules in any project
            if path.hasSuffix("/node_modules") { return descriptions["~/node_modules"] }
        }
        if path.hasSuffix("/DerivedData") { return descriptions["~/Library/Developer/Xcode/DerivedData"] }
        return nil
    }
}
