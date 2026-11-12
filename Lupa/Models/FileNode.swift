import Foundation
import UniformTypeIdentifiers

enum FileCategory: String, CaseIterable {
    case directory, application, bundle, image, video, audio, archive, document, code, diskImage, other

    var label: String {
        switch self {
        case .directory: return String(localized: "Folder")
        case .application: return String(localized: "Application")
        case .bundle: return String(localized: "Package")
        case .image: return String(localized: "Image")
        case .video: return String(localized: "Video")
        case .audio: return String(localized: "Audio")
        case .archive: return String(localized: "Archive")
        case .document: return String(localized: "Document")
        case .code: return String(localized: "Code")
        case .diskImage: return String(localized: "Disk image")
        case .other: return String(localized: "File")
        }
    }

    static func classify(name: String, isDirectory: Bool) -> FileCategory {
        let ext = (name as NSString).pathExtension.lowercased()
        if isDirectory {
            switch ext {
            case "app": return .application
            case "framework", "bundle", "plugin", "appex", "xpc", "kext", "qlgenerator", "photoslibrary", "xcarchive": return .bundle
            default: return .directory
            }
        }
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .diskImage) || ext == "dmg" || ext == "iso" { return .diskImage }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .archive) || ["zip", "gz", "tgz", "xz", "bz2", "7z", "rar", "pkg"].contains(ext) { return .archive }
        if type.conforms(to: .sourceCode) || ["swift", "m", "h", "c", "cpp", "js", "ts", "py", "rb", "go", "rs", "json", "yml", "yaml", "plist"].contains(ext) { return .code }
        if type.conforms(to: .text) || type.conforms(to: .pdf) || type.conforms(to: .presentation) || type.conforms(to: .spreadsheet) || type.conforms(to: .compositeContent) { return .document }
        return .other
    }
}

/// A node in the file tree. Built in the background by the scanner and treated
/// as immutable afterwards, except for removals made by the user.
final class FileNode: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let isDirectory: Bool
    let isHidden: Bool
    let isSymlink: Bool
    /// Bytes actually allocated on disk (st_blocks * 512). This is what Finder
    /// calls "on disk" and what really frees space when deleted.
    var allocatedSize: Int64
    /// Logical size (st_size). Can be larger than the allocated size for sparse
    /// or compressed files, and smaller for shared APFS clones.
    var logicalSize: Int64
    var fileCount: Int
    var modified: Date?
    var accessed: Date?
    /// True when the directory couldn't be read (missing permission).
    var accessDenied = false
    weak var parent: FileNode?
    var children: [FileNode] = []
    private(set) lazy var category: FileCategory = FileCategory.classify(name: name, isDirectory: isDirectory)

    init(name: String, isDirectory: Bool, isHidden: Bool, isSymlink: Bool = false,
         allocatedSize: Int64 = 0, logicalSize: Int64 = 0, fileCount: Int = 0,
         modified: Date? = nil, accessed: Date? = nil, parent: FileNode? = nil) {
        self.name = name
        self.isDirectory = isDirectory
        self.isHidden = isHidden
        self.isSymlink = isSymlink
        self.allocatedSize = allocatedSize
        self.logicalSize = logicalSize
        self.fileCount = fileCount
        self.modified = modified
        self.accessed = accessed
        self.parent = parent
    }

    /// Full path, rebuilt from the parents to save memory.
    var path: String {
        guard let parent else { return name }
        let base = parent.path
        return base.hasSuffix("/") ? base + name : base + "/" + name
    }

    var url: URL { URL(fileURLWithPath: path, isDirectory: isDirectory) }

    var ancestors: [FileNode] {
        var out: [FileNode] = []
        var cur = parent
        while let c = cur { out.insert(c, at: 0); cur = c.parent }
        return out
    }

    var isPackage: Bool { category == .application || category == .bundle }

    func sortChildrenRecursively() {
        children.sort { $0.allocatedSize > $1.allocatedSize }
        for c in children where c.isDirectory { c.sortChildrenRecursively() }
    }

    /// Removes this node from the tree and subtracts its sizes from every ancestor.
    func detachFromParent() {
        guard let parent else { return }
        parent.children.removeAll { $0 === self }
        var cur: FileNode? = parent
        while let c = cur {
            c.allocatedSize -= allocatedSize
            c.logicalSize -= logicalSize
            c.fileCount -= fileCount
            cur = c.parent
        }
        self.parent = nil
    }

    static func == (a: FileNode, b: FileNode) -> Bool { a === b }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}
