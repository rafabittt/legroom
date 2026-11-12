import Foundation
import AppKit

/// A rule for the "Cleanup" tab: a known place on disk, what it holds, and what
/// happens if it goes to the Trash. The rules live openly in Resources/cleanup-rules.json
/// so they can be read, fixed, and extended without recompiling the logic.
struct CleanupRule: Decodable, Identifiable, Hashable {
    enum Mode: String, Decodable {
        /// each child of the folder is an item that can go to the Trash
        case children
        /// the whole folder is a single item
        case `self`
        /// only reports size and how to deal with it; Legroom moves nothing from here
        case info
    }
    enum Safety: String, Decodable { case safe, review }

    /// Criteria for Legroom to check items on its own. Only applies to `safe` rules, and
    /// each criterion only narrows: what fails stays unchecked, never the other way around.
    struct Preselect: Decodable, Hashable {
        var minAgeDays: Int?
        var skipRunningApps: Bool?
        var skipPrefixes: [String]?
        var skipNames: [String]?
        var minBytes: Int64?
    }

    let id: String
    let title: String
    let symbol: String
    let paths: [String]
    let mode: Mode
    let safety: Safety?
    let why: String
    let preselect: Preselect?

    var expandedPaths: [String] {
        let home = NSHomeDirectory()
        return paths.map { $0.hasPrefix("~") ? home + $0.dropFirst() : $0 }
    }

    static let all: [CleanupRule] = {
        guard let url = Bundle.main.url(forResource: "cleanup-rules", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        do {
            // the first entry may be a comment ({"_comment": …}); rules have an "id"
            guard let raw = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
            let onlyRules = raw.filter { $0["id"] != nil }
            let clean = try JSONSerialization.data(withJSONObject: onlyRules)
            // title and why come from the JSON in English; look them up in the string catalog
            return try JSONDecoder().decode([CleanupRule].self, from: clean).map { r in
                CleanupRule(id: r.id, title: CleanupRule.localized(r.title), symbol: r.symbol, paths: r.paths,
                            mode: r.mode, safety: r.safety, why: CleanupRule.localized(r.why), preselect: r.preselect)
            }
        } catch { NSLog("cleanup-rules.json is invalid: %@", "\(error)"); return [] }
    }()

    private static func localized(_ s: String) -> String {
        Bundle.main.localizedString(forKey: s, value: s, table: nil)
    }
}

/// A rule applied to the scan tree.
struct CleanupGroup: Identifiable {
    let rule: CleanupRule
    /// The rule's root folders that exist within the scan.
    let locations: [FileNode]
    /// What can go to the Trash, largest to smallest (empty in info mode).
    let items: [FileNode]
    /// Items Legroom checks on its own, with the age (days without changes) of each.
    let suggested: [UUID: Int]
    var id: String { rule.id }
    var suggestedBytes: Int64 { items.filter { suggested[$0.id] != nil }.reduce(0) { $0 + $1.allocatedSize } }
    var total: Int64 {
        rule.mode == .info ? locations.reduce(0) { $0 + $1.allocatedSize } : items.reduce(0) { $0 + $1.allocatedSize }
    }
}

extension Array where Element == FileNode {
    /// Applies every rule to the scanned roots. Rules whose folders aren't in the
    /// scan (or are empty) are left out.
    func cleanupGroups(rules: [CleanupRule] = CleanupRule.all, now: Date = Date()) -> [CleanupGroup] {
        var out: [CleanupGroup] = []
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        for rule in rules {
            let locations = rule.expandedPaths.compactMap { locate($0) }.filter { $0.isDirectory }
            guard !locations.isEmpty else { continue }
            var items: [FileNode] = []
            switch rule.mode {
            case .children: items = locations.flatMap(\.children).filter { $0.allocatedSize > 0 }
            case .self: items = locations.filter { $0.allocatedSize > 0 }
            case .info: items = []
            }
            items.sort { $0.allocatedSize > $1.allocatedSize }
            let group = CleanupGroup(rule: rule, locations: locations, items: items,
                                     suggested: Self.suggest(items, rule: rule, running: running, now: now))
            if group.total > 0 { out.append(group) }
        }
        return out
    }

    /// Conservative selection: only `safe` rules with preselection criteria, and only
    /// items that pass all of them.
    private static func suggest(_ items: [FileNode], rule: CleanupRule, running: Set<String>, now: Date) -> [UUID: Int] {
        guard rule.safety == .safe, let p = rule.preselect else { return [:] }
        var out: [UUID: Int] = [:]
        for item in items {
            if let min = p.minBytes, item.allocatedSize < min { continue }
            if let names = p.skipNames, names.contains(item.name) { continue }
            if let prefixes = p.skipPrefixes, prefixes.contains(where: { item.name.hasPrefix($0) }) { continue }
            if p.skipRunningApps == true, running.contains(where: { item.name == $0 || item.name.hasPrefix($0 + ".") || item.name.hasPrefix($0 + "-") }) { continue }
            // age from the newest file inside the item, not from the folder itself
            let newest = item.newestModification() ?? item.lastUsed
            let days = newest.map { Int(now.timeIntervalSince($0) / 86_400) } ?? Int.max
            if let minAge = p.minAgeDays, days < minAge { continue }
            out[item.id] = days == Int.max ? 0 : days
        }
        return out
    }
}

extension FileNode {
    /// Most recent modification date in the whole subtree (including the node itself).
    func newestModification() -> Date? {
        var best = modified
        for c in children {
            if let d = c.isDirectory ? c.newestModification() : c.modified, best == nil || d > best! { best = d }
        }
        return best
    }
}
