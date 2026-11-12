import AppKit

/// An app leftover found outside the .app bundle: data, caches, preferences,
/// login agents, hidden folders in the home folder, and the downloaded installer.
struct Leftover: Identifiable, Hashable {
    enum Kind: String, CaseIterable {
        case data = "data"
        case caches = "caches"
        case prefs = "prefs"
        case logs = "logs"
        case launch = "launch"
        case installer = "installer"

        var title: String {
            switch self {
            case .data: return String(localized: "App data")
            case .caches: return String(localized: "Caches & temporary files")
            case .prefs: return String(localized: "Preferences & state")
            case .logs: return String(localized: "Logs & crash reports")
            case .launch: return String(localized: "Launch at login")
            case .installer: return String(localized: "Downloaded installer")
            }
        }
    }
    let url: URL
    let kind: Kind
    var bytes: Int64
    /// Comes checked in the review. Hidden folders with the app's exact name (~/.claude)
    /// often belong to a terminal tool with the same name: they come unchecked.
    var suggested = true
    var id: String { url.path }
    var displayPath: String { (url.path as NSString).abbreviatingWithTildeInPath }
}

/// Finds an app's leftovers by bundle id (its own and those of the apps and extensions
/// it carries inside) and by exact name. No "contains": `nod` finds
/// `~/Library/Application Support/nod`, `~/.nod-desktop`, and `nod-arm64.dmg`, but
/// not `chronod` or `claude-cli-nodejs`. Items from Apple and from other installed
/// apps are never included.
enum AppLeftovers {
    struct Identity {
        var ids: Set<String> = []       // lowercased
        var names: Set<String> = []     // lowercased, 3+ letters
    }

    static func identity(of app: URL) -> Identity {
        var out = Identity()
        func add(bundle url: URL) {
            guard let b = Bundle(url: url) else { return }
            if let id = b.bundleIdentifier?.lowercased(), !id.hasPrefix("com.apple.") { out.ids.insert(id) }
        }
        add(bundle: app)
        // helper apps, extensions, and XPC services bundled inside the app
        let contents = app.appendingPathComponent("Contents")
        for sub in ["Library/LoginItems", "Library/LaunchServices", "PlugIns", "XPCServices", "Frameworks", "Helpers", "MacOS", "Library/SystemExtensions"] {
            let dir = contents.appendingPathComponent(sub)
            guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for i in items where ["app", "appex", "xpc", "systemextension"].contains(i.pathExtension) { add(bundle: i) }
        }
        // Only the app's name, never the executable's: it tends to be generic
        // ("Electron") or point to another program (Claude Code's URL Handler
        // has a "claude" executable that is a shortcut to the CLI).
        out.names = nameVariants(of: app)
        return out
    }

    private static func nameVariants(of app: URL) -> Set<String> {
        let b = Bundle(url: app)
        let names = [app.deletingPathExtension().lastPathComponent,
                     b?.object(forInfoDictionaryKey: "CFBundleName") as? String,
                     b?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String]
        var out: Set<String> = []
        for n in names.compactMap({ $0?.lowercased() }) where n.count >= 3 {
            out.insert(n)
            out.insert(n.replacingOccurrences(of: " ", with: ""))
            out.insert(n.replacingOccurrences(of: " ", with: "-"))
        }
        return out
    }

    /// Bundle ids and names of every other installed app, so we don't take what's
    /// theirs (e.g. "Claude" belongs to Claude.app, not to an app with a similar name).
    private static func otherApps(excluding mine: [URL]) -> (ids: Set<String>, names: Set<String>) {
        var ids: Set<String> = [], names: Set<String> = []
        let fm = FileManager.default
        let minePaths = Set(mine.map { $0.standardizedFileURL.path })
        var dirs = ["/Applications", "/Applications/Utilities", NSHomeDirectory() + "/Applications", "/System/Applications", "/System/Applications/Utilities"]
        // apps inside a folder in /Applications (e.g. /Applications/Blackmagic RAW)
        for base in ["/Applications", NSHomeDirectory() + "/Applications"] {
            for sub in (try? fm.contentsOfDirectory(atPath: base)) ?? [] where !sub.hasSuffix(".app") && !sub.hasPrefix(".") {
                dirs.append(base + "/" + sub)
            }
        }
        for dir in dirs {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for i in items where i.hasSuffix(".app") {
                let url = URL(fileURLWithPath: dir + "/" + i)
                guard !minePaths.contains(url.standardizedFileURL.path) else { continue }
                if let id = Bundle(url: url)?.bundleIdentifier?.lowercased() { ids.insert(id) }
                names.formUnion(nameVariants(of: url))
            }
        }
        return (ids, names)
    }

    private enum Rule { case id, idOrName, nameOnly, installer }

    /// Where to look, what counts as a match, and which group it goes into.
    private static func locations() -> [(String, Rule, Leftover.Kind)] {
        let h = NSHomeDirectory(), L = h + "/Library"
        var out: [(String, Rule, Leftover.Kind)] = [
            (L + "/Application Support", .idOrName, .data),
            (L + "/Containers", .id, .data),
            (L + "/Group Containers", .id, .data),
            (L + "/Application Scripts", .id, .data),
            (L + "/Caches", .idOrName, .caches),
            (L + "/HTTPStorages", .id, .caches),
            (L + "/WebKit", .id, .caches),
            (L + "/Preferences", .id, .prefs),
            (L + "/Preferences/ByHost", .id, .prefs),
            (L + "/Saved Application State", .id, .prefs),
            (L + "/Cookies", .id, .prefs),
            (L + "/Logs", .idOrName, .logs),
            (L + "/Logs/DiagnosticReports", .nameOnly, .logs),
            (L + "/LaunchAgents", .id, .launch),
            (h, .nameOnly, .data),                 // ~/.nod-desktop, ~/.app
            (h + "/.config", .nameOnly, .data),
            (h + "/.local/share", .nameOnly, .data),
            (h + "/.cache", .nameOnly, .caches),
            (h + "/Downloads", .installer, .installer),
            ("/Library/Application Support", .idOrName, .data),
            ("/Library/Caches", .idOrName, .caches),
            ("/Library/Preferences", .id, .prefs),
            ("/Library/LaunchAgents", .id, .launch),
            ("/Library/LaunchDaemons", .id, .launch),
            ("/Library/PrivilegedHelperTools", .id, .launch),
            ("/Library/Logs", .idOrName, .logs),
        ]
        // per-user caches and temporary files in /var/folders/…/C and …/T
        for key in [_CS_DARWIN_USER_CACHE_DIR, _CS_DARWIN_USER_TEMP_DIR] {
            var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
            if confstr(key, &buf, buf.count) > 0 {
                let dir = String(cString: buf)
                if dir.count > 1 { out.append((dir.hasSuffix("/") ? String(dir.dropLast()) : dir, .id, .caches)) }
            }
        }
        return out
    }

    /// Name without the extension or a leading dot, lowercased.
    private static func stem(_ name: String) -> String {
        var s = name.lowercased()
        if s.hasPrefix(".") { s.removeFirst() }
        for ext in [".plist", ".savedstate", ".binarycookies", ".log", ".ips", ".crash", ".diag", ".dmg", ".zip", ".pkg"] where s.hasSuffix(ext) {
            s.removeLast(ext.count)
        }
        return s
    }

    private static func matchesID(_ entry: String, _ ids: Set<String>) -> Bool {
        let e = stem(entry)
        return ids.contains { id in
            e == id || e.hasPrefix(id + ".") || e.hasSuffix("." + id) || e.hasPrefix(id + "_") || e.hasPrefix(id + "-")
                || e.contains("." + id + ".")   // TEAMID.id.something
        }
    }

    /// Exact name, or the name followed by "-"/"_" (nod-desktop, nod-updater,
    /// nod-2026-11-12-…ips), never the name in the middle of another word.
    private static func matchesName(_ entry: String, _ names: Set<String>) -> Bool {
        let e = stem(entry)
        return names.contains { n in
            if e == n { return true }
            for sep in ["-", "_"] where e.hasPrefix(n + sep) {
                if appSuffix(String(e.dropFirst(n.count + 1))) { return true }
            }
            return false
        }
    }

    /// What comes after "name-" has to look like part of the app itself
    /// (nod-desktop, code-updater, blender-5.3.0-macos-arm64, nod-2026-…ips),
    /// not like another tool named after it (blender-mcp).
    private static func appSuffix(_ rest: String) -> Bool {
        if rest.first?.isNumber == true { return true }   // version or date
        let first = rest.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == "." }).first.map(String.init) ?? rest
        return ["desktop", "app", "updater", "update", "helper", "data", "cache", "caches", "electron", "shipit",
                "arm64", "x64", "x86_64", "universal", "mac", "macos", "osx", "darwin", "setup", "installer",
                "beta", "nightly", "canary", "insiders", "dev", "logs", "crashpad"].contains(first)
    }

    /// Searches in the background; measures each item's allocated size.
    static func find(for apps: [URL]) -> [Leftover] {
        var ident = Identity()
        for a in apps { let i = identity(of: a); ident.ids.formUnion(i.ids); ident.names.formUnion(i.names) }
        let other = otherApps(excluding: apps)
        let others = other.ids.subtracting(ident.ids)
        // a name that also belongs to another installed app can't be used to find leftovers
        ident.names.subtract(other.names)
        let appPaths = Set(apps.map(\.path))
        let fm = FileManager.default
        var seen: Set<String> = []
        var out: [Leftover] = []
        for (dir, rule, kind) in locations() {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for e in entries {
                let lower = e.lowercased()
                if lower.hasPrefix("com.apple.") || lower.hasPrefix("group.com.apple.") { continue }
                // in the home folder only hidden items count (~/.nod-desktop), never ~/Documents etc.
                if dir == NSHomeDirectory() && !e.hasPrefix(".") { continue }
                let ok: Bool
                switch rule {
                case .id: ok = matchesID(e, ident.ids)
                case .idOrName: ok = matchesID(e, ident.ids) || matchesName(e, ident.names)
                case .nameOnly: ok = matchesName(e, ident.names) || (dir.hasSuffix("DiagnosticReports") && matchesID(e, ident.ids))
                case .installer:
                    ok = [".dmg", ".zip", ".pkg"].contains { lower.hasSuffix($0) } && matchesName(e, ident.names)
                }
                guard ok else { continue }
                // does it belong to another installed app (same id or same name)?
                if matchesID(e, others) && !matchesID(e, ident.ids) { continue }
                if !matchesID(e, ident.ids) && matchesName(e, other.names) { continue }
                let path = (dir as NSString).appendingPathComponent(e)
                guard !appPaths.contains(path), seen.insert(path).inserted else { continue }
                let url = URL(fileURLWithPath: path)
                var item = Leftover(url: url, kind: kind, bytes: allocatedSize(url))
                let h = NSHomeDirectory()
                let homeArea = [h, h + "/.config", h + "/.local/share", h + "/.cache"].contains(dir)
                if homeArea && !matchesID(e, ident.ids) && ident.names.contains(stem(e)) { item.suggested = false }
                out.append(item)
            }
        }
        // a folder inside another one already listed isn't counted twice
        let paths = out.map(\.url.path)
        out.removeAll { l in paths.contains { $0 != l.url.path && l.url.path.hasPrefix($0 + "/") } }
        return out.sorted { $0.bytes > $1.bytes }
    }

    static func allocatedSize(_ url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isDirectoryKey, .isSymbolicLinkKey]
        guard let v = try? url.resourceValues(forKeys: keys) else { return 0 }
        if v.isDirectory != true || v.isSymbolicLink == true { return Int64(v.totalFileAllocatedSize ?? 0) }
        var total: Int64 = 0
        let en = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true })
        while let f = en?.nextObject() as? URL {
            total += Int64((try? f.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    /// For the user's login agents: unloads them from the session before they go to
    /// the Trash, otherwise they keep running until logout.
    static func unloadIfLaunchAgent(_ url: URL) {
        guard url.path.hasPrefix(NSHomeDirectory() + "/Library/LaunchAgents/"), url.pathExtension == "plist" else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["bootout", "gui/\(getuid())", url.path]
        p.standardError = FileHandle.nullDevice; p.standardOutput = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
    }
}
