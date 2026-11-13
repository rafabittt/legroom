import Foundation

/// Each goal scans only the folders it needs, in parallel, instead of the whole
/// disk. The Map is still the full scan; if it already exists and covers a scope,
/// the goal reuses that subtree without scanning again.
extension Goal {
    /// Folders to scan for this goal. Only those that exist.
    func scopes(source: ScanSource?) -> [URL] {
        let fm = FileManager.default
        let home = URL(fileURLWithPath: NSHomeDirectory())
        func existing(_ urls: [URL]) -> [URL] {
            urls.filter { fm.fileExists(atPath: $0.path) }
        }
        switch self {
        case .home, .security:
            return []
        case .map:
            return source.map { [$0.url] } ?? []
        case .cleanup:
            // the rules' folders, skipping any already inside another
            let paths = CleanupRule.all.flatMap(\.expandedPaths).filter { fm.fileExists(atPath: $0) }
            let sorted = Array(Set(paths)).sorted()
            var out: [String] = []
            for p in sorted where !out.contains(where: { p.hasPrefix($0 + "/") }) { out.append(p) }
            return out.map { URL(fileURLWithPath: $0) }
        case .apps:
            return existing([URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")])
        case .clutter:
            // every visible folder in the home folder except Library: duplicates
            // tend to live in project folders, not just in Downloads
            return homeFolders(except: ["Library", "Applications"])
        case .large:
            // another volume or a folder outside the home folder: scan the chosen target
            if let source, !source.url.path.hasPrefix(home.path), source.url.path != "/" {
                return [source.url]
            }
            // the home folder without Library, plus the heavy places inside it
            var urls = homeFolders(except: ["Library"])
            urls += existing(["Library/Developer", "Library/Application Support", "Library/Containers",
                              "Library/Group Containers", "Library/Mobile Documents"].map { home.appendingPathComponent($0) })
            return urls
        }
    }

    /// Visible top-level folders in the home folder.
    private func homeFolders(except skipped: Set<String>) -> [URL] {
        let fm = FileManager.default
        let home = URL(fileURLWithPath: NSHomeDirectory())
        guard let kids = try? fm.contentsOfDirectory(at: home, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        return kids.filter { !skipped.contains($0.lastPathComponent) && ((try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// What the sidebar shows while scanning.
    var scanningLabel: String {
        switch self {
        case .home: return ""
        case .map: return String(localized: "Scanning the disk")
        case .cleanup: return String(localized: "Scanning caches and logs")
        case .large: return String(localized: "Looking for large files")
        case .apps: return String(localized: "Scanning apps")
        case .clutter: return String(localized: "Scanning your home folder")
        case .security: return String(localized: "Checking your Mac")
        }
    }
}

/// A goal's result: one root per scope (parentless nodes, name = path).
struct GoalResult {
    var roots: [FileNode]
    let duration: TimeInterval
    let finished: Date
    /// Came from the Map's full scan (rather than a scan for this tab only).
    var fromMap = false
    /// Key that changes when something is moved to the Trash (fileCount is decremented).
    var key: Int {
        var h = Hasher()
        for r in roots { h.combine(ObjectIdentifier(r)); h.combine(r.fileCount) }
        return h.finalize()
    }
}

extension Array where Element == FileNode {
    /// Node at an absolute path, in any of the roots.
    func locate(_ path: String) -> FileNode? {
        for r in self { if let n = r.node(atPath: path) { return n } }
        return nil
    }
    var totalAllocated: Int64 { reduce(0) { $0 + $1.allocatedSize } }
}
