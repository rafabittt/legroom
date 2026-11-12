import Foundation

/// Quick answers for Siri and Shortcuts (v9). Nothing here scans the whole disk:
/// free space comes from the volume itself, unused apps come from Spotlight (which
/// already knows the last-used date), and "how much can be cleaned" is what the last
/// Cleanup scan, run by you in the app, left saved.
enum SiriFacts {
    // MARK: Response language

    /// Siri answers in the system language.
    static var english: Bool { !(Locale.preferredLanguages.first ?? "pt").hasPrefix("pt") }
    static func t(_ pt: String, _ en: String) -> String { english ? en : pt }

    // MARK: Free space

    struct Space {
        let volumeName: String
        let free: Int64
        let total: Int64
        let health: DiskHealth
    }

    static func space() -> Space? {
        guard let v = Volume.mounted().first(where: \.isRootVolume) ?? Volume.mounted().first else { return nil }
        return Space(volumeName: v.name, free: v.availableForImportantUsage, total: v.totalCapacity, health: DiskHealth(volume: v))
    }

    static func healthPhrase(_ h: DiskHealth) -> String {
        switch h.level {
        case .healthy: return String(localized: "The disk has plenty of room.")
        case .fine: return String(localized: "The disk is in good shape.")
        case .caution: return String(localized: "It's starting to get tight.")
        case .warning: return String(localized: "It's running low on space.")
        case .critical: return String(localized: "The disk is almost full.")
        }
    }

    // MARK: Cleanup (saved when the Cleanup screen finishes scanning)

    struct Cleanup: Codable {
        let suggested: Int64
        let reclaimable: Int64
        let date: Date
    }

    private static let cleanupKey = "siri.cleanup.v1"

    static func saveCleanup(suggested: Int64, reclaimable: Int64) {
        guard let data = try? JSONEncoder().encode(Cleanup(suggested: suggested, reclaimable: reclaimable, date: Date())) else { return }
        UserDefaults.standard.set(data, forKey: cleanupKey)
    }

    static var cleanup: Cleanup? {
        UserDefaults.standard.data(forKey: cleanupKey).flatMap { try? JSONDecoder().decode(Cleanup.self, from: $0) }
    }

    /// "today", "yesterday", "3 days ago" (or in Portuguese).
    static func when(_ d: Date, now: Date = Date()) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: d), to: Calendar.current.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<1: return String(localized: "today")
        case 1: return String(localized: "yesterday")
        default: return String(localized: "\(days) days ago")
        }
    }

    // MARK: Unused apps (Spotlight)

    struct UnusedApp {
        let name: String
        let size: Int64
        let lastUsed: Date?
    }

    /// Third-party apps in /Applications and ~/Applications unused for `days` days.
    /// Apple apps are left out: they come with the system and can't be removed.
    static func unusedApps(days: Int = 90, now: Date = Date()) -> [UnusedApp] {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        let fm = FileManager.default
        let dirs = ["/Applications", NSHomeDirectory() + "/Applications"]
        var out: [UnusedApp] = []
        for dir in dirs {
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for name in names where name.hasSuffix(".app") {
                let path = dir + "/" + name
                if let id = Bundle(path: path)?.bundleIdentifier, id.hasPrefix("com.apple.") { continue }
                guard let item = MDItemCreate(nil, path as CFString) else { continue }
                let last = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
                let added = (MDItemCopyAttribute(item, kMDItemDateAdded) as? Date)
                    ?? (try? fm.attributesOfItem(atPath: path)[.creationDate] as? Date)
                // never opened: only counts if it has been installed for longer than the limit
                let idle = last.map { $0 < cutoff } ?? (added.map { $0 < cutoff } ?? false)
                guard idle else { continue }
                let size = (MDItemCopyAttribute(item, "kMDItemPhysicalSize" as CFString) as? NSNumber)?.int64Value ?? 0
                out.append(UnusedApp(name: (name as NSString).deletingPathExtension, size: size, lastUsed: last))
            }
        }
        return out.sorted { $0.size > $1.size }
    }

    /// "A, B and C" / "A, B e C".
    static func list(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        let head = items.dropLast().joined(separator: ", ")
        return String(localized: "\(head) and \(items.last!)")
    }
}
