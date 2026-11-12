import Foundation
import CryptoKit

/// The Map's latest scan, saved per volume in
/// ~/Library/Application Support/Legroom/maps. Two files per volume:
///
/// - `<id>.json`: date, totals, and the tab summaries. It's small and read when the
///   app opens, so the Overview can show the scan without loading the tree.
/// - `<id>.lgmap`: the whole tree, compact and compressed. It's only loaded when
///   you open the Map or a tab that depends on it.
///
/// Opening a saved scan doesn't read the disk: it shows what was read on that date.
/// Anything moved to the Trash afterwards is recorded in `removed` and dropped from
/// the tree on load.
struct SavedMapInfo: Codable, Equatable {
    var sourceID: String
    var rootPath: String
    var date: Date
    var duration: TimeInterval
    var allocatedSize: Int64
    var fileCount: Int
    var nodeCount: Int
    var summaries: [String: String]
    /// Language the summaries were written in (nil: saved before the app was
    /// localized, so Portuguese). They're only shown in that same language.
    var language: String? = SavedMapInfo.currentLanguage
    static var currentLanguage: String { Bundle.main.preferredLocalizations.first ?? "en" }
    var summariesForCurrentLanguage: [String: String] {
        (language ?? "pt-BR") == Self.currentLanguage ? summaries : [:]
    }
    var removed: [String] = []
}

enum MapStore {
    /// Lock shared between whoever writes the tree (in the background) and whoever
    /// modifies it (moving to the Trash, on the main thread).
    static let treeLock = NSLock()

    private static let savingLock = NSLock()
    nonisolated(unsafe) private static var savingCount = 0
    /// A save is in progress (the app waits for it to finish before quitting).
    static var isSaving: Bool { savingLock.withLock { savingCount > 0 } }
    /// Marks the save as soon as it's scheduled (before the task starts running).
    static func markSaving() { savingLock.withLock { savingCount += 1 } }
    static func doneSaving() { savingLock.withLock { savingCount -= 1 } }

    private static let magic: [UInt8] = Array("LGMAP1".utf8)

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Legroom/maps", isDirectory: true)
    }

    private static func fileID(_ sourceID: String) -> String {
        SHA256.hash(data: Data(sourceID.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
    private static func infoURL(_ sourceID: String) -> URL { directory.appendingPathComponent(fileID(sourceID) + ".json") }
    private static func treeURL(_ sourceID: String) -> URL { directory.appendingPathComponent(fileID(sourceID) + ".lgmap") }

    // MARK: Index

    static func loadIndex() -> [String: SavedMapInfo] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [:] }
        var out: [String: SavedMapInfo] = [:]
        let dec = JSONDecoder()
        for f in files where f.pathExtension == "json" {
            guard let d = try? Data(contentsOf: f), let info = try? dec.decode(SavedMapInfo.self, from: d),
                  fm.fileExists(atPath: treeURL(info.sourceID).path) else { continue }
            out[info.sourceID] = info
        }
        return out
    }

    static func writeInfo(_ info: SavedMapInfo) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(info) { try? d.write(to: infoURL(info.sourceID), options: .atomic) }
    }

    static func delete(_ sourceID: String) {
        try? FileManager.default.removeItem(at: infoURL(sourceID))
        try? FileManager.default.removeItem(at: treeURL(sourceID))
    }

    // MARK: Save

    /// Saves the tree and the summary. Call off the main thread.
    static func save(root: FileNode, info: SavedMapInfo) throws {
        var w = Writer()
        w.bytes(magic)
        treeLock.lock()
        w.node(root)
        treeLock.unlock()
        let raw = Data(w.buf)
        let packed = try (raw as NSData).compressed(using: .lzfse) as Data
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try packed.write(to: treeURL(info.sourceID), options: .atomic)
        var info = info
        info.nodeCount = w.count
        writeInfo(info)
    }

    // MARK: Load

    /// Reads the saved tree. Call off the main thread.
    static func load(_ info: SavedMapInfo) throws -> FileNode {
        let packed = try Data(contentsOf: treeURL(info.sourceID))
        let raw = try (packed as NSData).decompressed(using: .lzfse) as Data
        return try raw.withUnsafeBytes { (p: UnsafeRawBufferPointer) -> FileNode in
            var r = Reader(p: p)
            guard r.bytes(magic.count) == magic else { throw CocoaError(.fileReadCorruptFile) }
            let root = try r.node(parent: nil)
            // what went to the Trash after the scan
            for path in info.removed {
                if let n = root.node(atPath: path), n !== root { n.detachFromParent() }
            }
            return root
        }
    }

    // MARK: Format
    //
    // Pre-order. Each node: flags (1 byte), name (varint + UTF-8), allocated and logical
    // (varint), dates in seconds (zigzag, if present) and, for folders, the file count
    // and child count (varint), followed by the children.

    private struct Flags {
        static let dir: UInt8 = 1, hidden: UInt8 = 2, symlink: UInt8 = 4, denied: UInt8 = 8, mod: UInt8 = 16, acc: UInt8 = 32
    }

    private struct Writer {
        var buf: [UInt8] = []
        var count = 0
        init() { buf.reserveCapacity(1 << 24) }

        mutating func bytes(_ b: [UInt8]) { buf.append(contentsOf: b) }
        mutating func varint(_ v: UInt64) {
            var v = v
            while v >= 0x80 { buf.append(UInt8(v & 0x7F) | 0x80); v >>= 7 }
            buf.append(UInt8(v))
        }
        mutating func signed(_ v: Int64) { varint(UInt64(bitPattern: (v << 1) ^ (v >> 63))) }
        mutating func size(_ v: Int64) { varint(UInt64(max(0, v))) }

        mutating func node(_ n: FileNode) {
            count += 1
            var f: UInt8 = 0
            if n.isDirectory { f |= Flags.dir }
            if n.isHidden { f |= Flags.hidden }
            if n.isSymlink { f |= Flags.symlink }
            if n.accessDenied { f |= Flags.denied }
            if n.modified != nil { f |= Flags.mod }
            if n.accessed != nil { f |= Flags.acc }
            buf.append(f)
            let name = Array(n.name.utf8)
            varint(UInt64(name.count))
            buf.append(contentsOf: name)
            size(n.allocatedSize)
            size(n.logicalSize)
            if let m = n.modified { signed(Int64(m.timeIntervalSince1970.rounded())) }
            if let a = n.accessed { signed(Int64(a.timeIntervalSince1970.rounded())) }
            if n.isDirectory {
                size(Int64(n.fileCount))
                let kids = n.children
                varint(UInt64(kids.count))
                for c in kids { node(c) }
            }
        }
    }

    private struct Reader {
        let p: UnsafeRawBufferPointer
        var i = 0

        mutating func bytes(_ n: Int) -> [UInt8] {
            guard i + n <= p.count else { i = p.count; return [] }
            defer { i += n }
            return Array(p[i..<(i + n)])
        }
        mutating func byte() throws -> UInt8 {
            guard i < p.count else { throw CocoaError(.fileReadCorruptFile) }
            defer { i += 1 }
            return p[i]
        }
        mutating func varint() throws -> UInt64 {
            var out: UInt64 = 0, shift: UInt64 = 0
            while true {
                let b = try byte()
                out |= UInt64(b & 0x7F) << shift
                if b < 0x80 { return out }
                shift += 7
                if shift > 63 { throw CocoaError(.fileReadCorruptFile) }
            }
        }
        mutating func signed() throws -> Int64 {
            let u = try varint()
            return Int64(bitPattern: (u >> 1) ^ (0 &- (u & 1)))
        }
        mutating func int() throws -> Int64 { Int64(clamping: try varint()) }

        mutating func node(parent: FileNode?) throws -> FileNode {
            let f = try byte()
            let len = Int(try varint())
            guard i + len <= p.count else { throw CocoaError(.fileReadCorruptFile) }
            let name = String(decoding: UnsafeRawBufferPointer(rebasing: p[i..<(i + len)]), as: UTF8.self)
            i += len
            let allocated = try int()
            let logical = try int()
            let mod = f & Flags.mod != 0 ? Date(timeIntervalSince1970: TimeInterval(try signed())) : nil
            let acc = f & Flags.acc != 0 ? Date(timeIntervalSince1970: TimeInterval(try signed())) : nil
            let dir = f & Flags.dir != 0
            let n = FileNode(name: name, isDirectory: dir, isHidden: f & Flags.hidden != 0, isSymlink: f & Flags.symlink != 0,
                             allocatedSize: allocated, logicalSize: logical, fileCount: dir ? 0 : 1,
                             modified: mod, accessed: acc, parent: parent)
            n.accessDenied = f & Flags.denied != 0
            if dir {
                n.fileCount = Int(clamping: try int())
                let k = Int(try varint())
                var kids: [FileNode] = []
                kids.reserveCapacity(k)
                for _ in 0..<k { kids.append(try node(parent: n)) }
                n.children = kids
            }
            return n
        }
    }
}
