import Foundation

/// The user's goals, one per tab. They all read the same scan tree; what changes
/// is the slice they look at and the question they answer.
enum Goal: String, Hashable, CaseIterable, Identifiable {
    case home, map, cleanup, large, apps, clutter

    /// Goals that read the disk (Home only summarizes).
    static let scanning: [Goal] = [.map, .cleanup, .large, .apps, .clutter]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return String(localized: "Overview")
        case .map: return String(localized: "Map")
        case .cleanup: return String(localized: "Cleanup")
        case .large: return String(localized: "Large & Forgotten")
        case .apps: return String(localized: "Apps")
        case .clutter: return String(localized: "Clutter")
        }
    }

    var symbol: String {
        switch self {
        case .home: return "chart.bar.doc.horizontal"
        case .map: return "square.grid.3x3.topleft.filled"
        case .cleanup: return "sparkles"
        case .large: return "shippingbox"
        case .apps: return "app.badge"
        case .clutter: return "tray.2"
        }
    }

    /// The one-line promise of what this view delivers.
    var promise: String {
        switch self {
        case .home: return String(localized: "At a glance: disk, memory, processor, network, and what Legroom has freed.")
        case .map: return String(localized: "See the whole disk at once and dive into what takes up space.")
        case .cleanup: return String(localized: "Caches, logs, and tool leftovers your Mac recreates on its own. You choose what goes to the Trash.")
        case .large: return String(localized: "Large files you haven't opened in months. Decide what goes to the Trash.")
        case .apps: return String(localized: "How much space each app really takes, and which ones you haven't opened in a while.")
        case .clutter: return String(localized: "Duplicates, old downloads, used installers, and piled-up screenshots.")
        }
    }

    /// Short question the home screen card asks the user.
    var question: String {
        switch self {
        case .home: return String(localized: "How is my Mac doing?")
        case .map: return String(localized: "What's taking up my disk?")
        case .cleanup: return String(localized: "What can I safely clean up?")
        case .large: return String(localized: "What's large and forgotten?")
        case .apps: return String(localized: "Which apps do I no longer use?")
        case .clutter: return String(localized: "Where's the clutter?")
        }
    }

    /// Each goal's own color (the home screen cards and the goal strip).
    var colors: (UInt32, UInt32) {
        switch self {
        case .home: return (0x9A9AA3, 0x6E6E76)
        case .map: return (0x818CF8, 0xA78BFA)      // indigo → violet
        case .cleanup: return (0x2DD4BF, 0x22C55E)  // teal → green
        case .large: return (0xFB923C, 0xF59E0B)    // orange → amber
        case .apps: return (0x60A5FA, 0x3B82F6)     // blue
        case .clutter: return (0xF472B6, 0xC084FC)  // pink → lilac
        }
    }
}

/// Filters for the "Large & Forgotten" view.
struct LargeFilesFilter: Equatable {
    enum MinSize: Int64, CaseIterable, Identifiable {
        case mb50 = 52_428_800, mb250 = 262_144_000, gb1 = 1_073_741_824, gb5 = 5_368_709_120
        var id: Int64 { rawValue }
        var label: String {
            switch self {
            case .mb50: return "≥ 50 MB"
            case .mb250: return "≥ 250 MB"
            case .gb1: return "≥ 1 GB"
            case .gb5: return "≥ 5 GB"
            }
        }
    }
    enum Age: Int, CaseIterable, Identifiable {
        case any = 0, month = 30, halfYear = 182, year = 365
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .any: return String(localized: "Any age")
            case .month: return String(localized: "Unused for 1 month")
            case .halfYear: return String(localized: "Unused for 6 months")
            case .year: return String(localized: "Unused for 1 year")
            }
        }
    }
    enum Kind: String, CaseIterable, Identifiable {
        case all, media, documents, archives, diskImages, bundles, other
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return String(localized: "All")
            case .media: return String(localized: "Photos, videos & audio")
            case .documents: return String(localized: "Documents")
            case .archives: return String(localized: "Archives & installers")
            case .diskImages: return String(localized: "Disk images")
            case .bundles: return String(localized: "Packages & project files")
            case .other: return String(localized: "Other")
            }
        }
        func matches(_ c: FileCategory) -> Bool {
            switch self {
            case .all: return true
            case .media: return c == .image || c == .video || c == .audio
            case .documents: return c == .document || c == .code
            case .archives: return c == .archive
            case .diskImages: return c == .diskImage
            case .bundles: return c == .bundle || c == .application || c == .directory
            case .other: return c == .other
            }
        }
    }

    var minSize: MinSize = .mb50
    var age: Age = .any
    var kind: Kind = .all
}

extension FileNode {
    /// Last known use: the more recent of access and modification.
    var lastUsed: Date? {
        switch (accessed, modified) {
        case let (a?, m?): return max(a, m)
        case let (a?, nil): return a
        case let (nil, m?): return m
        default: return nil
        }
    }

    /// "Large" items: files and packages (it never descends into .app, .photoslibrary,
    /// etc.) with allocated size above the threshold. Sorted by size, descending.
    func largeItems(filter: LargeFilesFilter, includeHidden: Bool, now: Date = Date()) -> [FileNode] {
        var out: [FileNode] = []
        let cutoff = filter.age == .any ? nil : now.addingTimeInterval(-Double(filter.age.rawValue) * 86_400)
        func visit(_ n: FileNode) {
            for c in n.children {
                if c.allocatedSize < filter.minSize.rawValue { continue }   // children are sorted by size
                if !includeHidden && c.isHidden { continue }
                let leaf = !c.isDirectory || c.isPackage
                if leaf {
                    if !filter.kind.matches(c.category) { continue }
                    if let cutoff, let used = c.lastUsed, used > cutoff { continue }
                    if cutoff != nil && c.lastUsed == nil { continue }
                    out.append(c)
                } else {
                    visit(c)
                }
            }
        }
        visit(self)
        out.sort { $0.allocatedSize > $1.allocatedSize }
        return out
    }

    /// Node at an absolute path within this subtree, or nil if it lies outside it.
    func node(atPath target: String) -> FileNode? {
        let base = path
        let prefix = base.hasSuffix("/") ? base : base + "/"
        if target == base { return self }
        guard target.hasPrefix(prefix) else { return nil }
        var cur = self
        for comp in target.dropFirst(prefix.count).split(separator: "/") {
            guard let next = cur.children.first(where: { $0.name == comp }) else { return nil }
            cur = next
        }
        return cur
    }

    /// All applications (.app) found in the tree, without descending into other .app bundles.
    func applications() -> [FileNode] {
        var out: [FileNode] = []
        func visit(_ n: FileNode) {
            for c in n.children where c.isDirectory {
                if c.category == .application { out.append(c) }
                else if !c.isPackage { visit(c) }
            }
        }
        visit(self)
        out.sort { $0.allocatedSize > $1.allocatedSize }
        return out
    }
}

extension Array where Element == FileNode {
    func largeItems(filter: LargeFilesFilter, includeHidden: Bool, now: Date = Date()) -> [FileNode] {
        var out = flatMap { $0.largeItems(filter: filter, includeHidden: includeHidden, now: now) }
        // the scope itself may be a package (e.g. an .app in ~/Applications)
        for r in self where r.isPackage && r.allocatedSize >= filter.minSize.rawValue && filter.kind.matches(r.category) { out.append(r) }
        out.sort { $0.allocatedSize > $1.allocatedSize }
        return out
    }
    func applications() -> [FileNode] {
        var out = flatMap { $0.applications() }
        for r in self where r.category == .application { out.append(r) }
        out.sort { $0.allocatedSize > $1.allocatedSize }
        return out
    }
}
