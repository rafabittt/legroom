import Foundation
import Darwin

struct ScanProgress {
    var files: Int = 0
    var directories: Int = 0
    var allocatedBytes: Int64 = 0
    var deniedDirectories: Int = 0
    var currentPath: String = ""
}

/// Cancellation signal shared between the scan thread and the UI.
final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
}

enum ScanError: LocalizedError {
    case cannotOpen(String)
    case cancelled
    var errorDescription: String? {
        switch self {
        case .cannotOpen(let p): return String(localized: "Couldn't open \(p).")
        case .cancelled: return String(localized: "Scan canceled.")
        }
    }
}

/// Walks a tree with fts(3), as Finder and the Unix tools do.
///
/// Decisions:
/// - FTS_PHYSICAL: doesn't follow symlinks, so nothing is counted twice or
///   escapes to another place on the disk.
/// - FTS_NOCHDIR: doesn't change the process's working directory.
/// - No FTS_XDEV: on APFS the /Users folder lives on another volume (Data) linked
///   by a firmlink; cutting at device boundaries would leave the whole disk out.
///   Instead, we explicitly skip /Volumes, /dev, and /System/Volumes.
/// - Hard links (st_nlink > 1) are counted only once, by the (dev, inode) pair.
/// - The size shown is the allocated size (st_blocks * 512), which is what actually
///   comes back as free space when deleted. The logical size (st_size) is kept too.
struct FTSScanner {
    static let skippedPaths: Set<String> = ["/Volumes", "/dev", "/System/Volumes", "/Network", "/.vol", "/cores"]

    let root: URL
    let token: CancelToken
    let progressInterval: TimeInterval = 0.15
    let onProgress: @Sendable (ScanProgress) -> Void

    func run() throws -> FileNode {
        let rootPath = root.path
        let rootNode = FileNode(name: rootPath, isDirectory: true, isHidden: false)
        var argv: [UnsafeMutablePointer<CChar>?] = [strdup(rootPath), nil]
        defer { free(argv[0]) }
        guard let fts = fts_open(&argv, FTS_PHYSICAL | FTS_NOCHDIR, nil) else {
            throw ScanError.cannotOpen(rootPath)
        }
        defer { fts_close(fts) }

        var stack: [FileNode] = []
        var seenHardLinks: [UInt64: Set<UInt64>] = [:]   // dev -> inodes
        var progress = ScanProgress()
        var lastReport = Date()
        var counter = 0

        func report(_ path: String, force: Bool = false) {
            counter += 1
            if force || counter % 512 == 0 {
                let now = Date()
                if force || now.timeIntervalSince(lastReport) >= progressInterval {
                    progress.currentPath = path
                    onProgress(progress)
                    lastReport = now
                }
            }
        }

        while let ent = fts_read(fts) {
            if token.isCancelled { throw ScanError.cancelled }
            let info = Int32(ent.pointee.fts_info)
            let path = String(cString: ent.pointee.fts_path)
            // fts_name is a flexible array at the end of the struct; we read it by offset.
            let name: String = {
                guard let off = MemoryLayout<FTSENT>.offset(of: \.fts_name) else {
                    return (path as NSString).lastPathComponent
                }
                return String(cString: UnsafeRawPointer(ent).advanced(by: off).assumingMemoryBound(to: CChar.self))
            }()
            let level = ent.pointee.fts_level

            switch info {
            case FTS_D:
                if level == 0 {
                    stack = [rootNode]
                    if let st = ent.pointee.fts_statp { apply(stat: st, to: rootNode) }
                    continue
                }
                if Self.skippedPaths.contains(path) {
                    fts_set(fts, ent, FTS_SKIP)
                    continue
                }
                let node = FileNode(name: name, isDirectory: true, isHidden: name.hasPrefix("."),
                                    parent: stack.last)
                if let st = ent.pointee.fts_statp { apply(stat: st, to: node) }
                stack.last?.children.append(node)
                stack.append(node)
                progress.directories += 1
                report(path)

            case FTS_DP:
                // A folder skipped with FTS_SKIP (e.g. /System/Volumes) comes back as FTS_DP
                // without ever being pushed. Only close the folder at the top of the stack
                // (same level); otherwise its parent would be closed too early and everything
                // that follows (/Users, /Applications…) would be left out of the tree.
                guard level > 0, stack.count - 1 == Int(level), stack.last?.name == name else { continue }
                guard let node = stack.popLast(), let parent = stack.last else { continue }
                parent.allocatedSize += node.allocatedSize
                parent.logicalSize += node.logicalSize
                parent.fileCount += node.fileCount

            case FTS_DNR, FTS_ERR, FTS_NS:
                // For an unreadable directory fts returns FTS_D (pre-order) and, on the
                // next read, the SAME entry as FTS_DNR/FTS_ERR, with no FTS_DP
                // afterwards. So the node is already at the top of the stack: we mark it
                // and pop it here, otherwise every following sibling becomes its child.
                if info != FTS_NS, let top = stack.last, stack.count - 1 == Int(level), top.name == name || level == 0 {
                    top.accessDenied = true
                    if level > 0, stack.count > 1 {
                        stack.removeLast()
                        if let parent = stack.last {
                            parent.allocatedSize += top.allocatedSize
                            parent.logicalSize += top.logicalSize
                            parent.fileCount += top.fileCount
                        }
                    }
                    progress.deniedDirectories += 1
                } else if info == FTS_DNR, let parent = stack.last {
                    let node = FileNode(name: name, isDirectory: true, isHidden: name.hasPrefix("."), parent: parent)
                    node.accessDenied = true
                    parent.children.append(node)
                    progress.deniedDirectories += 1
                }
                // FTS_NS (stat failed) on a file: no known size, so we ignore it.

            case FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT:
                guard let parent = stack.last, let st = ent.pointee.fts_statp else { continue }
                let s = st.pointee
                var allocated = Int64(s.st_blocks) * 512
                let logical = Int64(s.st_size)
                if s.st_nlink > 1 {
                    let dev = UInt64(bitPattern: Int64(s.st_dev))
                    if seenHardLinks[dev, default: []].insert(UInt64(s.st_ino)).inserted == false {
                        allocated = 0
                    }
                }
                let node = FileNode(name: name, isDirectory: false, isHidden: name.hasPrefix("."),
                                    isSymlink: info == FTS_SL || info == FTS_SLNONE,
                                    allocatedSize: allocated, logicalSize: logical, fileCount: 1,
                                    modified: date(s.st_mtimespec), accessed: date(s.st_atimespec),
                                    parent: parent)
                parent.children.append(node)
                parent.allocatedSize += allocated
                parent.logicalSize += logical
                parent.fileCount += 1
                progress.files += 1
                progress.allocatedBytes += allocated
                report(path)

            default:
                continue
            }
        }
        // Closes directories left open if fts ended unexpectedly.
        while stack.count > 1, let node = stack.popLast(), let parent = stack.last {
            parent.allocatedSize += node.allocatedSize
            parent.logicalSize += node.logicalSize
            parent.fileCount += node.fileCount
        }
        progress.allocatedBytes = rootNode.allocatedSize
        report(rootPath, force: true)
        rootNode.sortChildrenRecursively()
        return rootNode
    }

    private func apply(stat st: UnsafeMutablePointer<stat>, to node: FileNode) {
        node.modified = date(st.pointee.st_mtimespec)
        node.accessed = date(st.pointee.st_atimespec)
    }

    private func date(_ ts: timespec) -> Date? {
        guard ts.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(ts.tv_sec) + TimeInterval(ts.tv_nsec) / 1e9)
    }
}
