import Foundation
import Security

/// The Check-up: a transparent look at what's running on the Mac and who signed
/// it. It is not an antivirus and never claims something is malware on its own:
///
/// - **Defenses**: whether macOS's own protections are on (SIP, Gatekeeper,
///   FileVault, firewall, XProtect and automatic security updates).
/// - **Apple's own scans**: the results XProtect Remediator leaves in the system
///   log every time it runs (Apple's verdict, not ours).
/// - **What starts by itself**: launch agents and daemons, with the code signature
///   of what each one runs, so unsigned scripts, leftovers and look-alikes stand out.
///
/// Everything here runs without an administrator password and without network.
struct SecurityReport {
    var date: Date
    var defenses: [Defense]
    var appleScan: AppleScan?
    var startup: [StartupItem]

    var reviewCount: Int { startup.filter { $0.verdict.isReview }.count }
    var leftoverCount: Int { startup.filter { if case .leftover = $0.verdict { return true } else { return false } }.count }
    var defensesOff: [Defense] { defenses.filter { $0.state == .off } }
}

// MARK: Defenses

struct Defense: Identifiable {
    enum Kind: String { case sip, gatekeeper, fileVault, firewall, xprotect, securityUpdates }
    enum State { case on, off, unknown }
    let kind: Kind
    var state: State
    /// Extra fact, e.g. the XProtect version and when it was updated.
    var detail: String?
    var id: String { kind.rawValue }

    var title: String {
        switch kind {
        case .sip: return String(localized: "System Integrity")
        case .gatekeeper: return String(localized: "Gatekeeper")
        case .fileVault: return String(localized: "FileVault")
        case .firewall: return String(localized: "Firewall")
        case .xprotect: return String(localized: "XProtect")
        case .securityUpdates: return String(localized: "Security updates")
        }
    }
    var symbol: String {
        switch kind {
        case .sip: return "lock.shield"
        case .gatekeeper: return "checkmark.seal"
        case .fileVault: return "externaldrive.badge.checkmark"
        case .firewall: return "network.badge.shield.half.filled"
        case .xprotect: return "magnifyingglass"
        case .securityUpdates: return "arrow.triangle.2.circlepath"
        }
    }
    /// What it is, in one sentence.
    var explanation: String {
        switch kind {
        case .sip: return String(localized: "Keeps the system files of macOS read-only, even for apps with administrator rights.")
        case .gatekeeper: return String(localized: "Only opens apps that are signed and checked by Apple, unless you allow an exception.")
        case .fileVault: return String(localized: "Encrypts the disk, so nobody can read it if the Mac is lost or stolen.")
        case .firewall: return String(localized: "Blocks incoming connections to apps you haven't allowed. Most useful on public Wi‑Fi.")
        case .xprotect: return String(localized: "Apple's built-in malware check. Runs when apps open and in the background, and updates on its own.")
        case .securityUpdates: return String(localized: "Installs Apple's security responses and XProtect updates as soon as they're released.")
        }
    }
    /// What to do when it's off.
    var advice: String? {
        guard state == .off else { return nil }
        switch kind {
        case .sip: return String(localized: "It can only be turned back on from macOS Recovery (csrutil enable).")
        case .gatekeeper: return String(localized: "Turn it back on in Privacy & Security, under “Allow applications from”.")
        case .fileVault: return String(localized: "Turn it on in Privacy & Security › FileVault.")
        case .firewall: return String(localized: "Turn it on in Network › Firewall.")
        case .xprotect: return nil
        case .securityUpdates: return String(localized: "Turn on “Install Security Responses and system files” in Software Update › Automatic Updates.")
        }
    }
    var settingsURL: URL? {
        switch kind {
        case .gatekeeper: return URL(string: "x-apple.systempreferences:com.apple.preference.security?Security")
        case .fileVault: return URL(string: "x-apple.systempreferences:com.apple.preference.security?FileVault")
        case .firewall: return URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension?Firewall")
        case .securityUpdates: return URL(string: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension")
        case .sip, .xprotect: return nil
        }
    }
}

// MARK: Apple's own scans

/// The last run of XProtect Remediator: one scanner per malware family.
struct AppleScan {
    var date: Date
    var scanners: Int
    /// Families where Apple reported something other than "nothing found".
    var findings: [Finding]
    struct Finding: Identifiable, Hashable {
        let family: String
        let status: String
        var id: String { family + status }
    }
}

// MARK: What starts by itself

struct StartupItem: Identifiable {
    enum Domain: String {
        case user       // ~/Library/LaunchAgents: runs as you, at login
        case allUsers   // /Library/LaunchAgents: runs as each user who logs in
        case system     // /Library/LaunchDaemons: runs as root, at startup
        var title: String {
            switch self {
            case .user: return String(localized: "At your login")
            case .allUsers: return String(localized: "At every user's login")
            case .system: return String(localized: "At startup, as the system")
            }
        }
    }
    enum Reason: Hashable {
        case unsigned, adHoc, invalidSignature, notNotarized, script, inlineCommand
        case hiddenFolder, temporaryFolder, looksLikeApple, recent(days: Int)
        var text: String {
            switch self {
            case .unsigned: return String(localized: "not signed")
            case .adHoc: return String(localized: "signed ad hoc (no developer)")
            case .invalidSignature: return String(localized: "signature doesn't check out")
            case .notNotarized: return String(localized: "not notarized by Apple")
            case .script: return String(localized: "runs a script")
            case .inlineCommand: return String(localized: "runs an inline command")
            case .hiddenFolder: return String(localized: "lives in a hidden folder")
            case .temporaryFolder: return String(localized: "lives in a temporary or shared folder")
            case .looksLikeApple: return String(localized: "named like an Apple item, but isn't Apple's")
            case .recent(let d): return d <= 1 ? String(localized: "added today") : String(localized: "added \(d) days ago")
            }
        }
    }
    enum Verdict {
        case apple
        case developer(name: String, team: String)
        case review([Reason])
        case leftover
        var isReview: Bool { if case .review = self { return true } else { return false } }
        var order: Int {
            switch self { case .review: return 0; case .leftover: return 1; case .developer: return 2; case .apple: return 3 }
        }
    }

    let plist: URL
    let label: String
    let domain: Domain
    /// What it runs (the interpreter's script for scripts), or nil if the plist names nothing.
    let program: String?
    let arguments: [String]
    let verdict: Verdict
    /// Extra notes that don't make it suspicious (e.g. "added 2 days ago" on a signed item).
    let notes: [Reason]
    /// The app this belongs to, when the program lives inside one.
    let ownerApp: URL?
    let added: Date?
    var id: String { plist.path }

    /// Friendlier name: the owning app, else the label.
    var displayName: String {
        if let app = ownerApp { return app.deletingPathExtension().lastPathComponent }
        return label
    }
}

// MARK: - Running the check

enum SecurityCheck {
    static func run() -> SecurityReport {
        // the three parts are independent; the log query is the slowest
        var defenses: [Defense] = [], scan: AppleScan?, startup: [StartupItem] = []
        let group = DispatchGroup()
        DispatchQueue.global(qos: .userInitiated).async(group: group) { defenses = readDefenses() }
        DispatchQueue.global(qos: .userInitiated).async(group: group) { scan = readAppleScan() }
        DispatchQueue.global(qos: .userInitiated).async(group: group) { startup = readStartupItems() }
        group.wait()
        return SecurityReport(date: Date(), defenses: defenses, appleScan: scan, startup: startup)
    }

    // MARK: Defenses

    static func readDefenses() -> [Defense] {
        var out: [Defense] = []
        let sip = shell("/usr/bin/csrutil", ["status"])
        out.append(Defense(kind: .sip, state: sip.contains("enabled") ? .on : sip.contains("disabled") ? .off : .unknown))
        let gk = shell("/usr/sbin/spctl", ["--status"])
        out.append(Defense(kind: .gatekeeper, state: gk.contains("enabled") ? .on : gk.contains("disabled") ? .off : .unknown))
        let fv = shell("/usr/bin/fdesetup", ["status"])
        out.append(Defense(kind: .fileVault, state: fv.contains("is On") ? .on : fv.contains("is Off") ? .off : .unknown))
        let fw = shell("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"])
        out.append(Defense(kind: .firewall, state: fw.contains("enabled") ? .on : fw.contains("disabled") ? .off : .unknown))
        out.append(xprotect())
        // CriticalUpdateInstall = security responses and system data files (XProtect included)
        let su = UserDefaults(suiteName: "/Library/Preferences/com.apple.SoftwareUpdate")
        let critical = su?.object(forKey: "CriticalUpdateInstall") as? Bool
        let config = su?.object(forKey: "ConfigDataInstall") as? Bool
        let updatesOn = (critical ?? true) && (config ?? true)
        out.append(Defense(kind: .securityUpdates, state: updatesOn ? .on : .off))
        return out
    }

    private static func xprotect() -> Defense {
        var version: String?, installed: Date?
        let out = shell("/usr/bin/xprotect", ["version"])
        if let v = out.firstMatch(of: /Version:\s*(\S+)/) { version = String(v.1) }
        if let d = out.firstMatch(of: /Installed:\s*(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [+-]\d{4})/) {
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
            installed = f.date(from: String(d.1))
        }
        // macOS 14 has no `xprotect` tool: read the bundle instead
        if version == nil {
            for path in ["/var/protected/xprotect/XProtect.bundle", "/Library/Apple/System/Library/CoreServices/XProtect.bundle"] {
                let info = URL(fileURLWithPath: path + "/Contents/Info.plist")
                if let d = NSDictionary(contentsOf: info), let v = d["CFBundleShortVersionString"] as? String {
                    version = v
                    installed = (try? info.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    break
                }
            }
        }
        let detail = version.map { v in
            installed.map { String(localized: "Version \(v), updated \(Format.relative($0))") } ?? String(localized: "Version \(v)")
        }
        return Defense(kind: .xprotect, state: version == nil ? .unknown : .on, detail: detail)
    }

    // MARK: Apple's scans (XProtect Remediator's structured events in the unified log)

    static func readAppleScan() -> AppleScan? {
        let out = shell("/usr/bin/log", ["show", "--last", "4d", "--style", "ndjson", "--predicate",
                                         #"subsystem == "com.apple.XProtectFramework.PluginAPI" AND category == "XPEvent.structured""#],
                        timeout: 60)
        struct Event { let date: Date; let family: String; let status: String; let code: Int }
        var events: [Event] = []
        let iso = DateFormatter(); iso.locale = Locale(identifier: "en_US_POSIX"); iso.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZ"
        for line in out.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let msg = obj["eventMessage"] as? String, let mdata = msg.data(using: .utf8),
                  let m = try? JSONSerialization.jsonObject(with: mdata) as? [String: Any],
                  let ts = obj["timestamp"] as? String, let date = iso.date(from: ts) else { continue }
            let image = (obj["processImagePath"] as? String).map { ($0 as NSString).lastPathComponent } ?? ""
            let family = image.replacingOccurrences(of: "XProtectRemediator", with: "")
            events.append(Event(date: date, family: family.isEmpty ? image : family,
                                status: m["status_message"] as? String ?? "", code: m["status_code"] as? Int ?? -1))
        }
        guard let last = events.map(\.date).max() else { return nil }
        // one run = the scanners that ran within 30 minutes of the newest event
        let run = events.filter { last.timeIntervalSince($0.date) < 1800 }
        var latestPerFamily: [String: Event] = [:]
        for e in run where (latestPerFamily[e.family]?.date ?? .distantPast) <= e.date { latestPerFamily[e.family] = e }
        // 0 = ran fine, 20 = nothing found; anything else is worth showing as Apple reported it
        let findings = latestPerFamily.values.filter { ![0, 20].contains($0.code) }
            .map { AppleScan.Finding(family: $0.family, status: $0.status) }
            .sorted { $0.family < $1.family }
        return AppleScan(date: last, scanners: latestPerFamily.count, findings: findings)
    }

    // MARK: Startup items

    static func readStartupItems() -> [StartupItem] {
        let fm = FileManager.default
        let dirs: [(String, StartupItem.Domain)] = [
            (NSHomeDirectory() + "/Library/LaunchAgents", .user),
            ("/Library/LaunchAgents", .allUsers),
            ("/Library/LaunchDaemons", .system),
        ]
        var out: [StartupItem] = []
        for (dir, domain) in dirs {
            guard let names = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for name in names where name.hasSuffix(".plist") {
                let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
                if let item = inspect(plist: url, domain: domain) { out.append(item) }
            }
        }
        return out.sorted { ($0.verdict.order, $0.displayName.lowercased()) < ($1.verdict.order, $1.displayName.lowercased()) }
    }

    private static let interpreters: Set<String> = ["sh", "bash", "zsh", "dash", "ksh", "csh", "tcsh", "fish",
                                                    "python", "python3", "perl", "ruby", "node", "osascript", "env", "php", "deno", "bun"]

    static func inspect(plist url: URL, domain: StartupItem.Domain) -> StartupItem? {
        guard let dict = NSDictionary(contentsOf: url) as? [String: Any] else { return nil }
        let label = dict["Label"] as? String ?? url.deletingPathExtension().lastPathComponent
        var args = dict["ProgramArguments"] as? [String] ?? []
        var program = dict["Program"] as? String ?? args.first
        if dict["Program"] != nil, args.first == program { args.removeFirst() } else if !args.isEmpty { args.removeFirst() }
        let added = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
        let recentDays = added.map { Int(Date().timeIntervalSince($0) / 86_400) }

        var reasons: [StartupItem.Reason] = []
        var notes: [StartupItem.Reason] = []
        var target = program

        // scripts: look at what the interpreter runs
        if let p = program, interpreters.contains((p as NSString).lastPathComponent.lowercased().replacingOccurrences(of: #"\d+(\.\d+)?$"#, with: "", options: .regularExpression)) {
            var rest = args
            if (p as NSString).lastPathComponent == "env", !rest.isEmpty { rest.removeFirst() }   // env python3 script.py
            if rest.contains("-c") || rest.contains("-e") {
                reasons.append(.inlineCommand)
                target = nil
            } else if let script = rest.first(where: { !$0.hasPrefix("-") }) {
                reasons.append(.script)
                target = (script as NSString).expandingTildeInPath
            }
        }

        // nothing to run, or it points to something that's gone: a leftover
        if let t = target, !t.isEmpty, !FileManager.default.fileExists(atPath: t) {
            return StartupItem(plist: url, label: label, domain: domain, program: t, arguments: args,
                               verdict: .leftover, notes: [], ownerApp: owningApp(of: t), added: added)
        }
        if program == nil {
            return StartupItem(plist: url, label: label, domain: domain, program: nil, arguments: args,
                               verdict: .leftover, notes: [], ownerApp: nil, added: added)
        }

        // where it lives
        if let t = target {
            let comps = t.split(separator: "/")
            if comps.contains(where: { $0.hasPrefix(".") }) { reasons.append(.hiddenFolder) }
            if ["/tmp/", "/private/tmp/", "/var/tmp/", "/private/var/folders/", "/Users/Shared/"].contains(where: { t.hasPrefix($0) }) {
                reasons.append(.temporaryFolder)
            }
        }

        // who signed it (scripts: the script file itself is never signed; the interpreter is Apple's)
        var verdict: StartupItem.Verdict
        let signed = target.flatMap { reasons.contains(.script) ? nil : signature(of: owningApp(of: $0)?.path ?? $0) }
        if reasons.contains(.script) || reasons.contains(.inlineCommand) {
            verdict = .review(reasons)
        } else if let s = signed {
            switch s {
            case .apple:
                verdict = .apple
            case .developer(let name, let team, let notarized):
                // signed by an identified developer: fine even in a hidden folder (many tools
                // install to ~/.something), and notarization is only required for downloaded apps
                reasons.removeAll { $0 == .hiddenFolder }
                if !notarized { notes.append(.notNotarized) }
                verdict = reasons.isEmpty ? .developer(name: name, team: team) : .review(reasons)
            case .adHoc: reasons.append(.adHoc); verdict = .review(reasons)
            case .unsigned: reasons.append(.unsigned); verdict = .review(reasons)
            case .invalid: reasons.append(.invalidSignature); verdict = .review(reasons)
            }
        } else {
            reasons.append(.unsigned); verdict = .review(reasons)
        }

        // Apple's own items live in /System; a com.apple.* plist elsewhere is unusual
        if label.hasPrefix("com.apple."), case .apple = verdict {} else if label.hasPrefix("com.apple.") {
            if case .review(var r) = verdict { r.append(.looksLikeApple); verdict = .review(r) } else { verdict = .review([.looksLikeApple]) }
        }
        if let d = recentDays, d < 7 {
            if case .review(var r) = verdict { r.append(.recent(days: max(1, d))); verdict = .review(r) } else { notes.append(.recent(days: max(1, d))) }
        }
        return StartupItem(plist: url, label: label, domain: domain, program: target ?? program, arguments: args,
                           verdict: verdict, notes: notes, ownerApp: target.flatMap(owningApp(of:)), added: added)
    }

    /// The .app that contains a path (…/Foo.app/Contents/MacOS/foo → …/Foo.app).
    static func owningApp(of path: String) -> URL? {
        // the outermost app, so helpers inside apps point to the app people know
        if let r = path.range(of: ".app/") { return URL(fileURLWithPath: String(path[..<r.lowerBound]) + ".app") }
        return path.hasSuffix(".app") ? URL(fileURLWithPath: path) : nil
    }

    // MARK: Code signature

    enum Signature {
        case apple
        case developer(name: String, team: String, notarized: Bool)
        case adHoc, unsigned, invalid
    }

    static func signature(of path: String) -> Signature? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var infoCF: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &infoCF) == errSecSuccess,
              let info = infoCF as? [String: Any] else { return .unsigned }
        if info[kSecCodeInfoIdentifier as String] == nil { return .unsigned }
        let flags = (info[kSecCodeInfoFlags as String] as? UInt32) ?? 0
        if flags & 0x2 != 0 { return .adHoc }   // kSecCodeSignatureAdhoc
        if SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), nil) != errSecSuccess { return .invalid }
        if satisfies(code, "anchor apple") { return .apple }
        let team = info[kSecCodeInfoTeamIdentifier as String] as? String ?? ""
        var name = team
        if let certs = info[kSecCodeInfoCertificates as String] as? [SecCertificate], let leaf = certs.first,
           let summary = SecCertificateCopySubjectSummary(leaf) as String? {
            // "Developer ID Application: Google LLC (EQHXZ8M8AV)" → "Google LLC"
            name = summary.replacingOccurrences(of: #"^(Developer ID Application|Apple Development|Apple Distribution|Mac Developer|3rd Party Mac Developer Application): "#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #" \([A-Z0-9]{10}\)$"#, with: "", options: .regularExpression)
        }
        return .developer(name: name, team: team, notarized: satisfies(code, "notarized"))
    }

    private static func satisfies(_ code: SecStaticCode, _ requirement: String) -> Bool {
        var req: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess, let req else { return false }
        return SecStaticCodeCheckValidity(code, [], req) == errSecSuccess
    }

    // MARK: Helpers

    /// Runs a system tool and returns stdout + stderr (empty on failure or timeout).
    static func shell(_ path: String, _ args: [String], timeout: TimeInterval = 10) -> String {
        guard FileManager.default.isExecutableFile(atPath: path) else { return "" }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return "" }
        var data = Data()
        let reader = DispatchQueue(label: "legroom.shell")
        let done = DispatchSemaphore(value: 0)
        reader.async { data = pipe.fileHandleForReading.readDataToEndOfFile(); done.signal() }
        if done.wait(timeout: .now() + timeout) == .timedOut { p.terminate(); return "" }
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Actions

    /// Stops a launch agent for this session and moves its plist to the Trash
    /// (reversible: put it back and log in again). System items need Finder
    /// (administrator password) and stop at the next restart.
    @MainActor static func turnOff(_ item: StartupItem) async -> Bool {
        if item.domain == .user {
            _ = shell("/bin/launchctl", ["bootout", "gui/\(getuid())", item.plist.path])
        }
        do {
            try FileManager.default.trashItem(at: item.plist, resultingItemURL: nil)
            return true
        } catch {
            guard TrashMover.isPermissionError(error) else { return false }
            await TrashMover.trashWithFinder([item.plist])
            return !FileManager.default.fileExists(atPath: item.plist.path)
        }
    }
}
