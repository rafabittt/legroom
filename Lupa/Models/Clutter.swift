import Foundation
import CryptoKit

/// Kinds of clutter the "Clutter" tab looks for. They all live in the user's
/// folders (Downloads, Desktop, Documents…), never inside the Library.
enum ClutterKind: String, CaseIterable, Identifiable {
    case duplicates, oldDownloads, installers, screenshots
    var id: String { rawValue }

    var title: String {
        switch self {
        case .duplicates: return String(localized: "Duplicates")
        case .oldDownloads: return String(localized: "Old downloads")
        case .installers: return String(localized: "Installers")
        case .screenshots: return String(localized: "Screenshots")
        }
    }
    var symbol: String {
        switch self {
        case .duplicates: return "doc.on.doc"
        case .oldDownloads: return "arrow.down.circle"
        case .installers: return "opticaldisc"
        case .screenshots: return "camera.viewfinder"
        }
    }
    var explanation: String {
        switch self {
        case .duplicates: return String(localized: "Files with identical content (same size and same signature) in your folders, outside the Library. Choose which copies go to the Trash; one always stays.")
        case .oldDownloads: return String(localized: "Items in Downloads unused for more than 90 days. Many were opened once and forgotten.")
        case .installers: return String(localized: "Disk images and installer packages (.dmg, .pkg, .xip, .iso) in your folders. Once the app is installed, they're no longer needed.")
        case .screenshots: return String(localized: "Screenshots and screen recordings on the Desktop and in Downloads. They're usually disposable once shared.")
        }
    }
}

struct DuplicateGroup: Identifiable {
    let id: String
    /// From most recent to oldest (last use).
    let files: [FileNode]
    var size: Int64 { files.first?.allocatedSize ?? 0 }
    var wasted: Int64 { size * Int64(max(0, files.count - 1)) }
}

struct ClutterReport {
    var duplicates: [DuplicateGroup] = []
    var oldDownloads: [FileNode] = []
    var installers: [FileNode] = []
    var screenshots: [FileNode] = []
    /// Duplicate candidates not yet compared (phase 2).
    var duplicateCandidates: [[FileNode]] = []
    /// Did the scan find Downloads, Desktop, or Documents?
    var coversHome = false

    func items(for kind: ClutterKind) -> [FileNode] {
        switch kind {
        case .duplicates: return duplicates.flatMap(\.files)
        case .oldDownloads: return oldDownloads
        case .installers: return installers
        case .screenshots: return screenshots
        }
    }
    func total(for kind: ClutterKind) -> Int64 {
        kind == .duplicates ? duplicates.reduce(0) { $0 + $1.wasted } : items(for: kind).reduce(0) { $0 + $1.allocatedSize }
    }
}

extension Array where Element == FileNode {
    private static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "xip", "iso"]
    private static let screenshotPrefixes = ["Captura de Tela", "Captura de Ecrã", "Screenshot", "Screen Shot", "Gravação de Tela", "Screen Recording", "CleanShot", "SCR-"]
    private static let skippedDirectories: Set<String> = ["Library", "node_modules", ".git", "Applications"]

    /// Phase 1, fast and synchronous: everything except confirming duplicates.
    func clutterReport(now: Date = Date()) -> ClutterReport {
        var r = ClutterReport()
        let home = NSHomeDirectory()
        let downloads = locate(home + "/Downloads")
        let desktop = locate(home + "/Desktop")
        let documents = locate(home + "/Documents")
        guard !isEmpty else { return r }
        r.coversHome = true
        let cutoff = now.addingTimeInterval(-90 * 86_400)

        // Old downloads: top-level items (file or package) unused for 90 days
        if let downloads {
            r.oldDownloads = downloads.children.filter { c in
                !c.isHidden && (!c.isDirectory || c.isPackage) && c.allocatedSize > 0 && (c.lastUsed.map { $0 < cutoff } ?? false)
            }
        }
        // Installers and screenshots: recursive search through the user's visible folders
        func walk(_ n: FileNode, depth: Int, into visit: (FileNode) -> Void) {
            for c in n.children where !c.isHidden {
                if c.isDirectory && !c.isPackage {
                    if depth < 6 && !Self.skippedDirectories.contains(c.name) { walk(c, depth: depth + 1, into: visit) }
                } else {
                    visit(c)
                }
            }
        }
        for folder in self {
            walk(folder, depth: 0) { f in
                let ext = (f.name as NSString).pathExtension.lowercased()
                if Self.installerExtensions.contains(ext) { r.installers.append(f) }
            }
        }
        for folder in [desktop, downloads].compactMap({ $0 }) {
            for f in folder.children where !f.isDirectory && !f.isHidden {
                if Self.screenshotPrefixes.contains(where: { f.name.hasPrefix($0) }) { r.screenshots.append(f) }
            }
        }
        r.installers.sort { $0.allocatedSize > $1.allocatedSize }
        r.screenshots.sort { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
        r.oldDownloads.sort { $0.allocatedSize > $1.allocatedSize }

        // Duplicates: files ≥ 1 MB with the same logical size, across all roots, outside packages
        var bySize: [Int64: [FileNode]] = [:]
        for folder in self {
            walk(folder, depth: 0) { f in
                guard !f.isSymlink, f.logicalSize >= 1_000_000 else { return }
                bySize[f.logicalSize, default: []].append(f)
            }
        }
        r.duplicateCandidates = bySize.values.filter { $0.count > 1 }.sorted { ($0.first?.logicalSize ?? 0) > ($1.first?.logicalSize ?? 0) }
        return r
    }
}

/// Duplicates phase 2: content signature, off the main thread.
enum Duplicates {
    private struct CacheKey: Hashable { let path: String; let size: Int64; let modified: Date? }
    private static var cache: [CacheKey: String] = [:]
    private static let lock = NSLock()

    /// Files up to this size are read in full; above it, the signature uses the
    /// start, middle, and end (8 MiB each), which is enough in practice.
    static let fullHashLimit: Int64 = 1_000_000_000

    /// Resolves candidate groups into confirmed groups. `progress` receives
    /// how many files have been read so far.
    static func resolve(_ candidates: [[FileNode]], progress: @escaping @Sendable (Int) -> Void) async -> [DuplicateGroup] {
        struct Ref: Sendable { let group: Int; let index: Int; let path: String; let size: Int64; let modified: Date? }
        var refs: [Ref] = []
        for (g, files) in candidates.enumerated() {
            for (i, f) in files.enumerated() { refs.append(Ref(group: g, index: i, path: f.path, size: f.logicalSize, modified: f.modified)) }
        }
        let work = refs
        let signatures: [String?] = await Task.detached(priority: .utility) {
            var out: [String?] = Array(repeating: nil, count: work.count)
            for (n, r) in work.enumerated() {
                out[n] = signature(path: r.path, size: r.size, modified: r.modified)
                if n % 8 == 0 { progress(n + 1) }
            }
            return out
        }.value

        var groups: [DuplicateGroup] = []
        for (g, files) in candidates.enumerated() {
            var bySig: [String: [FileNode]] = [:]
            for (n, r) in refs.enumerated() where r.group == g {
                guard let sig = signatures[n] else { continue }
                bySig[sig, default: []].append(files[r.index])
            }
            for (sig, dup) in bySig where dup.count > 1 {
                let sorted = dup.sorted { ($0.lastUsed ?? .distantPast) > ($1.lastUsed ?? .distantPast) }
                groups.append(DuplicateGroup(id: sig, files: sorted))
            }
        }
        groups.sort { $0.wasted > $1.wasted }
        return groups
    }

    private static func signature(path: String, size: Int64, modified: Date?) -> String? {
        let key = CacheKey(path: path, size: size, modified: modified)
        lock.lock(); let hit = cache[key]; lock.unlock()
        if let hit { return hit }
        guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? fh.close() }
        var hasher = SHA256()
        let chunk = 1 << 20
        func feed(_ offset: UInt64, _ bytes: Int) -> Bool {
            do {
                try fh.seek(toOffset: offset)
                var remaining = bytes
                while remaining > 0 {
                    guard let d = try fh.read(upToCount: min(chunk, remaining)), !d.isEmpty else { break }
                    hasher.update(data: d); remaining -= d.count
                }
                return true
            } catch { return false }
        }
        if size <= fullHashLimit {
            guard feed(0, Int(size)) else { return nil }
        } else {
            let sample = 8 << 20
            guard feed(0, sample), feed(UInt64(size / 2), sample), feed(UInt64(size) - UInt64(sample), sample) else { return nil }
        }
        let sig = "\(size):" + hasher.finalize().map { String(format: "%02x", $0) }.joined()
        lock.lock(); cache[key] = sig; lock.unlock()
        return sig
    }
}
